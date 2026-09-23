import Foundation
import LightPlanDomain

/// Настройки приложения, которые делает экран «Настройки» (итерация 19а).
///
/// Хранятся не отдельно, а полями того же снимка, что и съёмки (`Snapshot`):
/// веб пишет их в один объект с записями, копия данных несёт их вместе, и
/// импорт архива веба приносит их без перевода. Имена значений — строки веба
/// (`"dark"`, `"paper"`, `"24"`), умолчания — его же правила чтения
/// (`themePref`, `timeStep`, `travelMin`… в `beta/index.html`).
public struct AppSettings: Sendable, Equatable {

    public enum Theme: String, Sendable, CaseIterable { case dark, light, auto }
    public enum DrumSlot: String, Sendable, CaseIterable { case paper, graphite, window }
    public enum RibbonMode: String, Sendable, CaseIterable { case drum, lane }
    public enum TempUnit: String, Sendable, CaseIterable { case c, f }
    public enum Clock: String, Sendable, CaseIterable { case auto, h24 = "24", h12 = "12" }
    public enum Practice: String, Sendable, CaseIterable { case ru, us, uk, eu }

    /// Шаги барабана времени в форме (`STEPS`).
    public static let steps = [5, 10, 30]
    /// Пороги дороги между площадками, минуты (`#travelSeg`).
    public static let travelChoices = [20, 40, 60, 90]

    public var pro: Bool
    public var theme: Theme
    public var ribbonMode: RibbonMode
    public var drumSlot: DrumSlot
    public var timeStep: Int
    public var travelMin: Int
    public var tempUnit: TempUnit
    public var clock: Clock
    public var currency: Currency
    public var practice: Practice
    /// Выбрал ли практику сам человек (`practicePicked` веба): город меняет
    /// её только тому, кто не выбирал. Веб выводит признак из того, что
    /// практика записана, — так же и здесь.
    public var practicePicked: Bool
    public var home: HomeCity

    public init(pro: Bool = false, theme: Theme = .dark, ribbonMode: RibbonMode = .drum,
                drumSlot: DrumSlot = .paper, timeStep: Int = 5, travelMin: Int = 40,
                tempUnit: TempUnit = .c, clock: Clock = .auto, currency: Currency = .rub,
                practice: Practice = .ru, practicePicked: Bool = false, home: HomeCity = HomeCity()) {
        self.pro = pro; self.theme = theme; self.ribbonMode = ribbonMode; self.drumSlot = drumSlot
        self.timeStep = timeStep; self.travelMin = travelMin; self.tempUnit = tempUnit
        self.clock = clock; self.currency = currency; self.practice = practice
        self.practicePicked = practicePicked; self.home = home
    }

    /// Прочитать из снимка по правилам веба. `zone` — пояс телефона, по
    /// нему угадывается практика, пока её не выбрали (`guessPractice`).
    public init(snapshot s: Snapshot, zone: TimeZone = .current) {
        pro = s.pro
        // Старые записи знали только «dark» и «light»: всё прочее — тёмная.
        theme = s.theme.flatMap(Theme.init(rawValue:)) ?? .dark
        ribbonMode = s.ribbonMode == "lane" ? .lane : .drum
        drumSlot = s.drumSlot.flatMap(DrumSlot.init(rawValue:)) ?? .paper
        timeStep = s.timeStep.flatMap { Self.steps.contains($0) ? $0 : nil } ?? 5
        // Веб: `+saved.travelMin || 40` — любое положительное число, ноль и пусто дают 40.
        travelMin = s.travelMin.flatMap { $0 > 0 ? $0 : nil } ?? 40
        tempUnit = s.tempUnit == "f" ? .f : .c
        clock = s.clock.flatMap(Clock.init(rawValue:)) ?? .auto
        currency = s.currency ?? .rub
        if let p = s.practice.flatMap(Practice.init(rawValue:)) {
            practice = p; practicePicked = true
        } else {
            practice = Self.guessPractice(zone: zone.identifier) ?? .ru; practicePicked = false
        }
        home = HomeCity(me: s.extra["me"])
    }

    /// Записать в снимок. Прочие поля снимка и прочие ключи `me` (номер,
    /// «знакомство пройдено») не трогаются.
    public func apply(to s: inout Snapshot) {
        s.pro = pro
        s.theme = theme.rawValue
        s.ribbonMode = ribbonMode.rawValue
        s.drumSlot = drumSlot.rawValue
        s.timeStep = timeStep
        s.travelMin = travelMin
        s.tempUnit = tempUnit.rawValue
        s.clock = clock.rawValue
        s.currency = currency
        // Невыбранная практика не пишется: иначе догадка по поясу стала бы
        // выбором после первого же сохранения (веб пишет `practice` всегда,
        // но читает признак выбора отдельно — здесь его нести негде).
        s.practice = practicePicked ? practice.rawValue : nil
        s.extra["me"] = home.merged(into: s.extra["me"])
    }

    /// Практика по часовому поясу — порт `guessPractice` веба: пояс — это
    /// география, то есть то, чем юрисдикция и определяется.
    public static func guessPractice(zone tz: String) -> Practice? {
        if tz.hasPrefix("America/") { return .us }
        if tz == "Europe/London" || ["Europe/Belfast", "Europe/Guernsey", "Europe/Isle_of_Man", "Europe/Jersey"].contains(tz) { return .uk }
        let ru = ["Europe/Moscow", "Europe/Kaliningrad", "Europe/Samara", "Europe/Volgograd", "Europe/Saratov",
                  "Europe/Astrakhan", "Europe/Ulyanovsk", "Europe/Kirov", "Europe/Minsk", "Europe/Kiev",
                  "Europe/Simferopol", "Asia/Yekaterinburg", "Asia/Omsk", "Asia/Novosibirsk", "Asia/Krasnoyarsk",
                  "Asia/Irkutsk", "Asia/Yakutsk", "Asia/Vladivostok", "Asia/Magadan", "Asia/Kamchatka",
                  "Asia/Almaty", "Asia/Tashkent", "Asia/Tbilisi", "Asia/Yerevan", "Asia/Baku", "Asia/Bishkek"]
        if ru.contains(tz) { return .ru }
        if tz.hasPrefix("Europe/") { return .eu }
        return nil
    }

    /// Практика по стране города (`practiceFromCC`): СНГ ведёт дела
    /// российским порядком, ЕС и соседи — европейским.
    public static func practice(countryCode cc: String) -> Practice? {
        let cc = cc.lowercased()
        let map: [String: Practice] = [
            "ru": .ru, "by": .ru, "kz": .ru, "ua": .ru, "uz": .ru, "kg": .ru, "am": .ru,
            "az": .ru, "ge": .ru, "md": .ru, "tj": .ru, "tm": .ru,
            "us": .us, "ca": .us, "gb": .uk, "ie": .eu,
        ]
        if let p = map[cc] { return p }
        let eu = ["at", "be", "bg", "hr", "cy", "cz", "dk", "ee", "fi", "fr", "de", "gr", "hu", "is",
                  "it", "lv", "li", "lt", "lu", "mt", "nl", "no", "pl", "pt", "ro", "sk", "si", "es", "se", "ch"]
        return eu.contains(cc) ? .eu : nil
    }

    /// Выбран город из справочника (`takeCity`): имя, координаты, страна.
    /// Страна меняет практику, только пока человек не выбрал её сам.
    public mutating func takeCity(_ hit: CityHit) {
        home = HomeCity(name: HomeCity.cap(hit.name), coordinate: hit.coordinate, countryCode: hit.countryCode)
        if !practicePicked, let cc = hit.countryCode, let p = Self.practice(countryCode: cc) { practice = p }
    }
}
