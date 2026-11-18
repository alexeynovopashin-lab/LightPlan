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
    Font(webPlatformFont(size, weight))
}

/// Тот же шрифт, что `webFont`, в виде системного — для замеров по метрикам (положение двоеточия в студийном часе).
#if canImport(UIKit)
func webPlatformFont(_ size: CGFloat, _ weight: Int = 400) -> UIFont {
    UIFont.systemFont(ofSize: size, weight: UIFont.Weight(rawValue: webWeightValue(weight)))
}
#else
func webPlatformFont(_ size: CGFloat, _ weight: Int = 400) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: NSFont.Weight(rawValue: webWeightValue(weight)))
}
#endif

private func webWeightValue(_ weight: Int) -> CGFloat {
    switch weight {
    case ..<450: 0
    case ..<550: 0.23
    case ..<625: 0.3
    case ..<675: 0.35
    default: 0.4
    }
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

    /// Знак погоды строки недели (веб `wxSign`) — не тот, что у сводки дня. `.poor`: капли — только дождь (31.2).
    func weekSignName(_ precip: Precip?) -> String {
        switch self {
        case .poor: signIconName(precip)
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

    /// Настоящий прогноз дня; `nil` — его нет (28ж: выдумка не подставляется).
    func weather(_ d: CivilDate) -> WeatherDay? { app.light.weather.day(for: d) }

    /// Событие знака и цвета дня (31.5б, Алексей 18.11 «Да, все «б»»): до полудня по часам места — рассвет, после — закат.
    var dayEvent: SkyEvent { SkyEvent.ofDay(nowMinute: Double(app.nowMinute)) }

    /// Небо дня для его знака и цвета: категория и осадки окна события `dayEvent`; прогноза нет — `nil`.
    func daySky(_ d: CivilDate) -> (quality: DayQuality, precip: Precip?)? {
        weather(d).map { ($0.quality(dayEvent), $0.precip(dayEvent)) }
    }

    /// Надпись вместо погоды, когда прогноза нет: «Прогноз недоступен» или, пока
    /// первый ответ не пришёл, «Прогноз загружается…».
    var forecastNote: String {
        t.t(app.light.weather.status == .loading ? "wx.loading" : "wx.unavailable")
    }

    /// Градусы дня в 15:00 из часов прогноза (31.2; веб `tempOut(wx.tempBase, 900)` — синус от средней); `nil` — прогноза нет.
    func temp(_ d: CivilDate, at minute: Double = 900) -> Int? {
        weather(d)?.temperature(at: minute).map { LightTelemetry.degrees($0, app.settings.tempUnit == .f) }
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

    /// Подпись занятости в клетке месяца: первое слово заметки, без заметки — слово вида (Алексей 28.10).
    func blockMonthLabel(_ b: Block) -> String {
        BlockMonthLabel.text(note: b.note, kindWord: t.t("blkKind." + b.kind.rawValue), language: app.language)
    }

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
