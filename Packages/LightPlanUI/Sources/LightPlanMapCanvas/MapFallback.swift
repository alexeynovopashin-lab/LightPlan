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

/// Сторож первой плитки CARTO (28л.3): за `timeout` плитка не пришла — `onSilent` один раз, и приложение
/// переходит на карту Apple. Плитка пришла — сторож гаснет, `firstTileMs` хранит, сколько ждали.
/// Он ничего не знает ни о карте, ни о сети: «молчащий источник» в тесте — тот, кто не зовёт `tileArrived`.
@MainActor
public final class MapFallbackGate {
    public static let timeout: Duration = .seconds(4)

    public enum Outcome: Equatable, Sendable { case waiting, arrived, silent }

    public private(set) var outcome: Outcome = .waiting
    /// Мс от `start()` до первой плитки; `nil`, пока не пришла.
    public private(set) var firstTileMs: Int?
    private let timeout: Duration
    private let onSilent: @MainActor () -> Void
    private var task: Task<Void, Never>?
    private var startedAt: ContinuousClock.Instant?

    public init(timeout: Duration = MapFallbackGate.timeout, onSilent: @escaping @MainActor () -> Void) {
        self.timeout = timeout
        self.onSilent = onSilent
    }

    /// Отсчёт с нуля; повторный вызов отсчёт не сбрасывает.
    public func start() {
        guard outcome == .waiting, task == nil else { return }
        let clock = ContinuousClock()
        startedAt = clock.now
        let timeout = timeout
        task = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.expire()
        }
    }

    /// Что сторож понимает о загрузке карты. Приходом данных считается только `.mapLoaded`: ни загруженный
    /// стиль (он локальный и встаёт без сети), ни неполные кадры о плитках не говорят.
    public enum Event: Equatable, Sendable { case styleLoaded, partialFrame, mapLoaded }

    public func receive(_ event: Event) {
        if event == .mapLoaded { tileArrived() }
    }

    public func tileArrived() {
        guard outcome == .waiting, let startedAt else { return }
        let d = ContinuousClock().now - startedAt
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
