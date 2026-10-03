import Foundation
import LightPlanCore

/// Сроки жизни ответа и предел, до которого старый прогноз ещё показывается
/// при сбое обновления. Прогноз и воздух — как у сервера (1 ч и 3 ч).
public struct WeatherLifetime: Sendable, Equatable {
    public var hourly: TimeInterval
    public var air: TimeInterval
    /// Сколько старый прогноз терпим, если новый не приходит (слово ТЗ 28ж).
    public var staleLimit: TimeInterval

    public init(hourly: TimeInterval = 3600, air: TimeInterval = 3 * 3600, staleLimit: TimeInterval = 6 * 3600) {
        self.hourly = hourly
        self.air = air
        self.staleLimit = staleLimit
    }

    public static let standard = WeatherLifetime()
}

/// Прогноз и воздух по месту — с кэшем, чтобы то же место дважды не шло в
/// сеть (веб `wxKey === key && wxLive`, `airKey === key`). Ключ — три знака
/// после запятой, как везде в продукте (`GeoCoordinate.nameKey`), но здесь
/// свой: слой Data не тянет `Place` в `LightPlanCore` ради строки.
/// Кэш с сроком: ответ старше срока (ровно срок — уже старый) не отдаётся,
/// спрашивается заново. Часы приходят снаружи.
/// Сбой в кэш не попадает: повтор дойдёт до сети.
public actor WeatherFetcher {
    private let source: any WeatherSource
    private let now: @Sendable () -> Date
    private let lifetime: WeatherLifetime
    private var hourlyCache: [String: (value: HourlyWeather, origin: WeatherOrigin, at: Date)] = [:]
    private var airCache: [String: (value: [CivilDate: [Int: AirSample]], at: Date)] = [:]

    public init(source: any WeatherSource, lifetime: WeatherLifetime = .standard,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.lifetime = lifetime
        self.now = now
    }

    static func key(for place: Place) -> String {
        String(format: "%.3f,%.3f", place.latitude, place.longitude)
    }

    /// Часовой прогноз; тот же адрес и не старше срока — из кэша, без сети.
    public func hourly(at place: Place) async throws -> HourlyWeather {
        try await hourlyWithOrigin(at: place).0
    }

    /// То же и каким путём он получен (источник без путей — прямой).
    public func hourlyWithOrigin(at place: Place) async throws -> (HourlyWeather, WeatherOrigin) {
        let got = try await hourlyStamped(at: place)
        return (got.value, got.origin)
    }

    /// То же и когда ответ получен: по этому времени хранитель считает свой срок.
    public func hourlyStamped(at place: Place) async throws -> (value: HourlyWeather, origin: WeatherOrigin, at: Date) {
        let key = Self.key(for: place)
        if let hit = hourlyCache[key], now().timeIntervalSince(hit.at) < lifetime.hourly { return hit }
        let fetched: (HourlyWeather, WeatherOrigin)
        if let routed = source as? any OriginReportingWeatherSource {
            fetched = try await routed.fetchHourlyWithOrigin(at: place)
        } else {
            fetched = (try await source.fetchHourly(at: place), .direct)
        }
        try Task.checkCancellation()
        let got = (value: fetched.0, origin: fetched.1, at: now())
        hourlyCache[key] = got
        return got
    }

    /// Воздух; тот же адрес и не старше срока — из кэша, без сети.
    public func air(at place: Place) async throws -> [CivilDate: [Int: AirSample]] {
        try await airStamped(at: place).value
    }

    public func airStamped(at place: Place) async throws -> (value: [CivilDate: [Int: AirSample]], at: Date) {
        let key = Self.key(for: place)
        if let hit = airCache[key], now().timeIntervalSince(hit.at) < lifetime.air { return hit }
        let fetched = try await source.fetchAir(at: place)
        try Task.checkCancellation()
        let got = (value: fetched, at: now())
        airCache[key] = got
        return got
    }
}
