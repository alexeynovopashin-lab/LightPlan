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

/// Память режима на телефоне. Файл данных общий с вебом и теряет ключ, память — нет. С 30г.4 в ней же переключатели «Астро».
public protocol AppModeMemory: AnyObject, Sendable {
    var mode: AppMode? { get set }
    var astro: AstroSwitches? { get set }
    /// Человек уже входил в «Астро» на этом телефоне (30г.7а): первый вход включает слои неба (опись, вопрос 4, вариант А),
    /// повторный — нет. Кто был в «Астро» до обновления, отмечен при запуске, его слои не трогаются.
    var astroEntered: Bool { get set }
}

/// Память на время запуска: тесты и снимки, где режим задаёт только файл.
public final class InMemoryAppModeMemory: AppModeMemory, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AppMode?
    private var storedAstro: AstroSwitches?
    private var storedEntered: Bool
    public init(_ mode: AppMode? = nil, astro: AstroSwitches? = nil, astroEntered: Bool = false) {
        stored = mode; storedAstro = astro; storedEntered = astroEntered
    }
    public var astroEntered: Bool {
        get { lock.withLock { storedEntered } }
        set { lock.withLock { storedEntered = newValue } }
    }
    public var mode: AppMode? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
    public var astro: AstroSwitches? {
        get { lock.withLock { storedAstro } }
        set { lock.withLock { storedAstro = newValue } }
    }
}

/// Память телефона: строка режима и список выключенных переключателей в `UserDefaults`.
public final class DeviceAppModeMemory: AppModeMemory, @unchecked Sendable {
    public static let key = "lightplan.native.app.mode"
    public static let astroKey = "lightplan.native.app.astroOff"
    public static let astroEnteredKey = "lightplan.native.app.astroEntered"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var mode: AppMode? {
        get { defaults.string(forKey: Self.key).flatMap(AppMode.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: Self.key) }
    }

    /// Нет записи — `nil` (памяти нет), пустой список — все пять включены.
    public var astro: AstroSwitches? {
        get { (defaults.array(forKey: Self.astroKey) as? [String]).map { AstroSwitches.read(file: $0, remembered: nil) } }
        set { defaults.set(newValue?.offNames, forKey: Self.astroKey) }
    }

    public var astroEntered: Bool {
        get { defaults.bool(forKey: Self.astroEnteredKey) }
        set { defaults.set(newValue, forKey: Self.astroEnteredKey) }
    }
}
