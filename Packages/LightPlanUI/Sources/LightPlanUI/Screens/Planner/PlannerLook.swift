import SwiftUI
import LightPlanCore
import LightPlanDomain
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Шрифт с весом CSS. У веба в «Съёмках» есть 650 — между полужирным (600) и
/// жирным (700); `Font.Weight` его не знает, а системный шрифт переменный и
/// берёт любую точку шкалы (0,3 — 600, 0,4 — 700).
func webFont(_ size: CGFloat, _ weight: Int = 400) -> Font {
    let w: CGFloat = switch weight {
    case ..<450: 0
    case ..<550: 0.23
    case ..<625: 0.3
    case ..<675: 0.35
    default: 0.4
    }
    #if canImport(UIKit)
    return Font(UIFont.systemFont(ofSize: size, weight: UIFont.Weight(rawValue: w)))
    #else
    return Font(NSFont.systemFont(ofSize: size, weight: NSFont.Weight(rawValue: w)))
    #endif
}

extension DayQuality {
    /// Точка качества дня (веб `QUAL[q].dot`): у «обычного» точки нет. Туман
    /// берёт цвет хорошего света — это другое окно (рассвет), а не хуже.
    var dot: Color? {
        switch self {
        case .excellent, .fog: Color(hex: 0xE2A44C)
        case .good: Color(hex: 0xA8B49B)
        case .plain: nil
        case .poor: Color(hex: 0x7C9CC4)
        }
    }

    /// Знак погоды строки недели (веб `wxSign`) — не тот, что у сводки дня.
    var weekSignName: String {
        switch self {
        case .poor: "rain"
        case .fog: "cloud"
        case .good: "part"
        case .excellent, .plain: "clear"
        }
    }
}

extension Color {
    init(rgb c: Urgency.RGB, alpha: Double = 1) {
        self.init(.sRGB, red: c.r / 255, green: c.g / 255, blue: c.b / 255, opacity: alpha)
    }
}

/// Что планировщик знает о дне: свет, погоду, записи. Считается из хозяина
/// приложения при каждой отрисовке — у веба так же (`daySky`, `dayWeather`
/// без кэша), а дней на экране не больше сорока двух.
@MainActor
struct PlannerFacts {
    let app: AppModel
    let words: PlannerWords
    let dark: Bool

    init(app: AppModel, dark: Bool) {
        self.app = app
        self.dark = dark
        words = PlannerWords(lexicon: app.lexicon, orgs: app.orgs)
    }

    var t: Lexicon { app.lexicon }
    var clock: ClockText { ClockText(language: app.language, preference: app.light.clockPreference) }
    var today: CivilDate { app.today }

    /// Солнце дня в месте приложения (веб `daySky`).
    func sky(_ d: CivilDate) -> SolarDay { SolarDay(date: d, place: app.place.place) }

    func weather(_ d: CivilDate) -> WeatherDay { app.light.weather.day(for: d) }

    /// Градусы дня в 15:00 (веб `tempOut(wx.tempBase, 900)`).
    func temp(_ d: CivilDate, at minute: Double = 900) -> Int {
        LightTelemetry.tempOut(weather(d).temperatureBase, minute, app.settings.tempUnit == .f)
    }

    /// Записи с частью в этих сутках, видимые в планировщике (веб `onDay` +
    /// `shownRec`), в порядке снимка.
    func shown(on d: CivilDate) -> [Session] {
        app.sessions.filter { $0.part(on: d) != nil && $0.isShown(eventsLayer: app.eventsLayer) }
    }

    func blocks(on d: CivilDate) -> [Block] { app.blocks.filter { $0.covers(d) } }

    func items(on d: CivilDate) -> [DayItem] {
        DayItem.items(on: d, sessions: app.sessions, blocks: app.blocks, eventsLayer: app.eventsLayer)
    }

    func blockLabel(_ b: Block) -> String { b.note.isEmpty ? t.t("blkKind." + b.kind.rawValue) : b.note }

    /// Самая тяжёлая ступень сдачи дня (веб `dayMark`).
    func mark(_ d: CivilDate) -> DeliveryStatus? {
        Urgency.dayMark(d, sessions: app.sessions, status: app.deliveryStatus)
    }

    /// Минуты — «ЧЧ:ММ» по часам настроек (веб `fmt`).
    func fmt(_ m: Double?) -> String { clock.fmt(m) }
    func range(_ a: Double?, _ b: Double?) -> String { clock.range(a, b) }

    /// «1 ч 30 м» (веб `durShort`).
    func durShort(_ m: Int) -> String {
        let m = max(0, m)
        if m < 60 { return t.t("durS.minutes", ["m": "\(m)"]) }
        let h = m / 60, mm = m % 60
        return mm > 0 ? t.t("durS.hoursMins", ["h": "\(h)", "m": "\(mm)"]) : t.t("durS.hours", ["h": "\(h)"])
    }

    /// «2,5 часа», «3 часа», «40 мин» (веб `durLabel`).
    func durLabel(_ m: Int) -> String {
        let h = m / 60, mm = m % 60
        if h == 0 { return t.t("dur.minutes", ["m": "\(mm)"]) }
        if mm == 0 { return t.t("dur.hours", ["h": "\(h)", "hourWord": t.word("unit.hour", h)]) }
        if mm == 30 { return t.t("dur.halfHour", ["h": "\(h)"]) }
        return t.t("dur.hoursMins", ["h": "\(h)", "m": "\(mm)"])
    }

    /// Подпись ступени сдачи (веб `deliveryState().label` и `.short`).
    func deliveryWords(_ st: DeliveryStatus) -> (label: String, short: String?) {
        switch st {
        case .notWork: return ("", nil)
        case .done: return (t.t("delv.done"), nil)
        case .ahead: return (t.t("delv.ahead"), nil)
        case .noTerm: return (t.t("delv.noTerm"), nil)
        case .due(_, let left):
            let n = t.count("unit.dayShort", left)
            return (t.t("delv.dueIn", ["days": n]), n)
        case .overdue(let days):
            let n = t.count("unit.dayShort", days)
            return (t.t("delv.overdue", ["days": n]), n)
        }
    }

    func deliveryColor(_ st: DeliveryStatus) -> Color {
        Color(rgb: Urgency.color(st, dark: dark))
    }

    /// День как `Date` в полдень — для словаря дат, которому нужен момент.
    func date(_ d: CivilDate) -> Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour) = (d.year, d.month, d.day, 12)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: c) ?? Date()
    }

    var dates: DateText { DateText(language: app.language) }
}
