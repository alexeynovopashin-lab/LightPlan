import Foundation

/// Режим приложения: три равных варианта (Алексей 31.10, «вариант А»). Единственное место, которое знает, как режим
/// хранится и как читается (`docs/30g2_modes_table.md` § 4). Экраны пока спрашивают галочку `AppSettings.pro`.
public enum AppMode: String, Sendable, CaseIterable {
    case simple, pro, astro

    /// Галочка `pro` файла данных: веб знает только её, поэтому она включена и в «Про», и в «Астро».
    public var webPro: Bool { self != .simple }

    /// Какой режим стоит. Свой ключ файла сильнее всего. Веб при пересохранении теряет ключ (пишет только свои, `saveAll`),
    /// тогда решает память телефона, а не галочка: иначе файл из веба превращал бы «Про» в «Астро». Галочка решает, только
    /// если нет ни ключа, ни памяти (первое обновление, новый телефон): `pro` — «Астро», без неё — «Просто».
    public static func read(file: String?, webPro: Bool, remembered: AppMode?) -> AppMode {
        file.flatMap(AppMode.init(rawValue:)) ?? remembered ?? (webPro ? .astro : .simple)
    }

    /// Записать в снимок: ключ и галочка всегда вровень.
    public func write(to s: inout Snapshot) {
        s.appMode = rawValue
        s.pro = webPro
    }
}

/// Память режима на телефоне. Файл данных общий с вебом и теряет ключ, память — нет.
public protocol AppModeMemory: AnyObject, Sendable {
    var mode: AppMode? { get set }
}

/// Память на время запуска: тесты и снимки, где режим задаёт только файл.
public final class InMemoryAppModeMemory: AppModeMemory, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AppMode?
    public init(_ mode: AppMode? = nil) { stored = mode }
    public var mode: AppMode? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Память телефона: одна строка в `UserDefaults`.
public final class DeviceAppModeMemory: AppModeMemory, @unchecked Sendable {
    public static let key = "lightplan.native.app.mode"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var mode: AppMode? {
        get { defaults.string(forKey: Self.key).flatMap(AppMode.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: Self.key) }
    }
}
