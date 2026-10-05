import Foundation
import LightPlanCore

/// Каким путём пришёл прогноз — для строки «Источник».
public enum WeatherOrigin: Sendable, Equatable { case direct, proxy }

/// Что известно о прогнозе места: ещё спрашиваем, получен (и откуда), или
/// настоящего прогноза нет. Выдумки нет ни в одном из трёх (слово Алексея
/// 02.10: «без имитации»).
public enum WeatherStatus: Sendable, Equatable {
    case loading
    case live(WeatherOrigin)
    case unavailable
}

/// Источник, который знает, каким путём получил ответ. Остальные источники
/// (файл для снимков, сценарии тестов) — прямые.
public protocol OriginReportingWeatherSource: WeatherSource {
    func fetchHourlyWithOrigin(at place: Place) async throws -> (HourlyWeather, WeatherOrigin)
    func fetchAirWithOrigin(at place: Place) async throws -> ([CivilDate: [Int: AirSample]], WeatherOrigin)
}

public enum WeatherRouteError: Error, Equatable { case directTimedOut }

/// Выбор пути (28ж, решение Алексея 03.10): сначала прямой Open-Meteo с коротким
/// ожиданием; не ответил — наш сервер. Сработавший путь запоминается и
/// начинает следующий запрос; прямой перепроверяется раз в 3 часа (VPN
/// включили или выключили). Форма ответа у путей одна, разбор не меняется.
///
/// 28л.6: поверх этого — режим человека и детектор доступности (`NetworkPolicy`).
/// - «Только напрямую»: наш сервер не спрашивается вовсе, прямой — без своего срока (у запроса он свой, 20 с);
///   отказ уходит наверх, экран пишет «Прогноз недоступен».
/// - «Авто» и зарубежное недоступно: сразу наш сервер, без ожидания четырёх секунд; не ответил — прямой с сроком.
/// - «Авто» и зарубежное доступно: прямой; память «ходим через сервер» забывается — детектор свежее, чем отметка
///   о прошлом отказе.
/// - «Авто» и неизвестно (проба ещё идёт, сети нет): как до детектора — отметка о прошлом отказе и 3 часа.
///
/// Ожидание и «сейчас» приходят снаружи — тест не ждёт четыре настоящие секунды.
public actor RoutedWeatherSource: OriginReportingWeatherSource {
    public static let directTimeout: Duration = .seconds(4)
    public static let recheckInterval: TimeInterval = 3 * 3600

    private let direct: any WeatherSource
    private let proxy: any WeatherSource
    private let timeout: Duration
    private let recheck: TimeInterval
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let policy: @Sendable () async -> NetworkPolicy

    /// Путь, с которого начинается следующий запрос.
    public private(set) var preferred: WeatherOrigin = .direct
    /// Когда прямой путь последний раз не ответил: от этого считаются 3 часа.
    private var directFailedAt: Date?

    public init(direct: any WeatherSource, proxy: any WeatherSource,
                timeout: Duration = RoutedWeatherSource.directTimeout,
                recheck: TimeInterval = RoutedWeatherSource.recheckInterval,
                now: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                policy: @escaping @Sendable () async -> NetworkPolicy = { NetworkPolicy() }) {
        self.policy = policy
        self.direct = direct
        self.proxy = proxy
        self.timeout = timeout
        self.recheck = recheck
        self.now = now
        self.sleep = sleep
    }

    /// Боевая сборка: прямой Open-Meteo и наш сервер; без ключа — только прямой
    /// и без ожидания (кроме него идти некуда).
    public static func live(config: WeatherProxyConfig?, hub: NetworkPolicyHub? = nil) -> any WeatherSource {
        guard let config else { return OpenMeteoSource() }
        let policy: @Sendable () async -> NetworkPolicy = { await hub?.policy() ?? NetworkPolicy() }
        return RoutedWeatherSource(direct: OpenMeteoSource(),
                                   proxy: OpenMeteoSource(endpoint: .proxy(config.url, key: config.key)),
                                   policy: policy)
    }

    public func fetchHourly(at place: Place) async throws -> HourlyWeather {
        try await fetchHourlyWithOrigin(at: place).0
    }

    public func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] {
        try await fetchAirWithOrigin(at: place).0
    }

    public func fetchHourlyWithOrigin(at place: Place) async throws -> (HourlyWeather, WeatherOrigin) {
        try await route { try await $0.fetchHourly(at: place) }
    }

    public func fetchAirWithOrigin(at place: Place) async throws -> ([CivilDate: [Int: AirSample]], WeatherOrigin) {
        try await route { try await $0.fetchAir(at: place) }
    }

    private var recheckDue: Bool {
        guard let failed = directFailedAt else { return true }
        return now().timeIntervalSince(failed) >= recheck
    }

    private func route<T: Sendable>(
        _ op: @escaping @Sendable (any WeatherSource) async throws -> T
    ) async throws -> (T, WeatherOrigin) {
        let direct = self.direct, proxy = self.proxy
        let net = await policy()
        if net.mode == .directOnly {
            let got = try await op(direct)
            return (got, .direct)
        }
        if net.foreign == .unreachable || (net.foreign == .unknown && preferred == .proxy && !recheckDue) {
            if let got = try? await op(proxy) {
                preferred = .proxy
                return (got, .proxy)
            }
            try Task.checkCancellation()
            // Наш сервер молчит — остаётся прямой, тоже с ожиданием.
            let got = try await withDirectTimeout { try await op(direct) }
            preferred = .direct
            return (got, .direct)
        }
        do {
            let got = try await withDirectTimeout { try await op(direct) }
            preferred = .direct
            return (got, .direct)
        } catch {
            try Task.checkCancellation()
            directFailedAt = now()
            let got = try await op(proxy)
            preferred = .proxy
            return (got, .proxy)
        }
    }

    /// Прямой запрос против часов. Опоздавший ответ отменяется и выбрасывается.
    /// Опирается на то, что сеть отменяется по отмене задачи (`URLSession` так и
    /// делает); источник, глухой к отмене, держал бы возврат до своего ответа.
    private func withDirectTimeout<T: Sendable>(_ op: @escaping @Sendable () async throws -> T) async throws -> T {
        let timeout = self.timeout, sleep = self.sleep
        return try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await op() }
            group.addTask { try await sleep(timeout); return nil }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let value = first else {
                throw WeatherRouteError.directTimedOut
            }
            return value
        }
    }
}
