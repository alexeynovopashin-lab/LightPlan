import Foundation

/// Ключ CARTO (28л.3): свой бесплатный, без него плитки идут как раньше. Лежит не в репозитории
/// (он публичный): фаза сборки `Tools/carto_key.sh` кладёт его в `carto.plist` рядом с приложением
/// из `~/.config/lightplan/carto_key`. Нет файла или он пуст — `nil`, приложение не падает.
public enum CartoKey {
    public static func load(bundle: Bundle = .main) -> String? {
        guard let file = bundle.url(forResource: "carto", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: file) as? [String: Any] else { return nil }
        let key = (dict["LPCartoKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return key.isEmpty ? nil : key
    }

    /// Ключ этой сборки — читается раз за запуск.
    public static let current: String? = load()
}

/// Часы сторожа: `now` — монотонное «сейчас», `sleep(until:)` — ждать до этого момента. Выносятся наружу,
/// чтобы тест решал, когда «проходит время»: окна в 60–250 мс на настоящих таймерах краснели в полном наборе
/// (замер: задача сторожа взлетала через 1,7 с после `start()` — очередь главного актора стояла за долгими тестами).
public struct GateClock: Sendable {
    public var now: @Sendable () -> Duration
    public var sleep: @Sendable (_ until: Duration) async throws -> Void

    public init(now: @escaping @Sendable () -> Duration, sleep: @escaping @Sendable (_ until: Duration) async throws -> Void) {
        self.now = now
        self.sleep = sleep
    }

    /// Боевые часы: `ContinuousClock`, отсчёт от первого обращения.
    public static let real: GateClock = {
        let clock = ContinuousClock()
        let origin = clock.now
        return GateClock(now: { origin.duration(to: clock.now) },
                         sleep: { until in try await clock.sleep(until: origin.advanced(by: until)) })
    }()
}

/// Сторож первой плитки CARTO (28л.3): за `timeout` плитка не пришла — `onSilent` один раз, и приложение
/// переходит на карту Apple. Плитка пришла — сторож гаснет, `firstTileMs` хранит, сколько ждали.
/// Он ничего не знает ни о карте, ни о сети: «молчащий источник» в тесте — тот, кто не зовёт `tileArrived`.
/// Срок считается от `start()`, а не от момента, когда задача сторожа добралась до очереди: `deadline` фиксируется
/// сразу в `start()`.
@MainActor
public final class MapFallbackGate {
    public static let timeout: Duration = .seconds(4)

    public enum Outcome: Equatable, Sendable { case waiting, arrived, silent }

    public private(set) var outcome: Outcome = .waiting
    /// Мс от `start()` до первой плитки; `nil`, пока не пришла.
    public private(set) var firstTileMs: Int?
    private let timeout: Duration
    private let clock: GateClock
    private let onSilent: @MainActor () -> Void
    private var task: Task<Void, Never>?
    /// Последняя задача сторожа — остаётся и после отмены: тест ждёт её конца, а не «сколько-то мс».
    private var lastTask: Task<Void, Never>?
    private var startedAt: Duration?

    public init(timeout: Duration = MapFallbackGate.timeout, clock: GateClock = .real,
                onSilent: @escaping @MainActor () -> Void) {
        self.timeout = timeout
        self.clock = clock
        self.onSilent = onSilent
    }

    /// Отсчёт с нуля; повторный вызов отсчёт не сбрасывает.
    public func start() {
        guard outcome == .waiting, task == nil else { return }
        let begun = clock.now()
        startedAt = begun
        let deadline = begun + timeout, sleep = clock.sleep
        let running = Task { [weak self] in
            try? await sleep(deadline)
            guard !Task.isCancelled else { return }
            self?.expire()
        }
        task = running
        lastTask = running
    }

    /// Дождаться, пока задача сторожа закончит (срок вышел либо отмена). Для тестов: ждать не «сколько-то мс»,
    /// а конкретное событие (ничего не запущено — вернётся сразу).
    func settled() async { await lastTask?.value }

    /// Что сторож понимает о загрузке карты. Приходом данных считается только `.mapLoaded`: ни загруженный
    /// стиль (он локальный и встаёт без сети), ни неполные кадры о плитках не говорят.
    public enum Event: Equatable, Sendable { case styleLoaded, partialFrame, mapLoaded }

    public func receive(_ event: Event) {
        if event == .mapLoaded { tileArrived() }
    }

    public func tileArrived() {
        guard outcome == .waiting, let startedAt else { return }
        let d = clock.now() - startedAt
        firstTileMs = Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
        outcome = .arrived
        cancel()
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    private func expire() {
        guard outcome == .waiting else { return }
        outcome = .silent
        task = nil
        onSilent()
    }
}
