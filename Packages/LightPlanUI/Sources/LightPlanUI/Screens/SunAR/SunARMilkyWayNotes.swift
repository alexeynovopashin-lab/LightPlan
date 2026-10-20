import Foundation
import LightPlanCore

/// Строки под словом «Млечный Путь» в списке «Слоёв» (шаг 29.8в.17б). Чистая сборка из чисел ядра и слов словаря:
/// список рисует то, что она вернула, тест проверяет те же строки.
///
/// Порядок: когда ядро над горизонтом и когда темно · справка о видимости глазом · окно съёмки · подпись про формулу.
/// Справка о видимости — справка, а не условие рисования: полоса рисуется всегда (слово Алексея 20.10).
enum SunARMilkyWayNotes {

    /// `pano` — панорама Алексея (29.8в.20): нейтральная подпись «панорама: материалы Алексея», пока источник не подтверждён.
    /// `gaia` — картина из каталога Gaia (29.8в.19): вместо «по формуле, условно» — «по звёздам каталога Gaia» и кредит
    /// данных строкой (лицензия CC BY-NC 3.0 IGO требует его рядом со слоем).
    static func lines(plan: MilkyWayPlan, eye: MilkyWayLook.EyeNote, clock: ClockText, lexicon t: Lexicon,
                      gaia: Bool = false, pano: Bool = false) -> [String] {
        let tail = pano ? [t.t(MilkyWayPano.creditKey)] : gaia ? [t.t("ar.mwGaia"), t.t("ar.mwCredit")] : [t.t("ar.mwFormula")]
        return [above(plan: plan, clock: clock, t), eyeLine(eye, t), window(plan: plan, clock: clock, t)].compactMap { $0 } + tail
    }

    /// «ядро над горизонтом 22:40–04:10 · темно с 20:30». Ядро не восходит или не заходит на этой широте — так и сказано.
    static func above(plan: MilkyWayPlan, clock: ClockText, _ t: Lexicon) -> String {
        let head: String
        switch plan.passage {
        case .neverRises: return t.t("ar.mwNeverRises")
        case .neverSets: return t.t("ar.mwNeverSets")
        case .crossing:
            switch (plan.passage.rise, plan.passage.set) {
            case let (r?, s?): head = t.t("ar.mwAbove", ["range": clock.range(r.minutes, s.minutes)])
            case let (r?, nil): head = t.t("ar.mwAboveFrom", ["t": clock.fmt(r.minutes)])
            case let (nil, s?): head = t.t("ar.mwAboveTo", ["t": clock.fmt(s.minutes)])
            case (nil, nil): head = ""
            }
        }
        let dark: String
        switch plan.dark {
        case .from(let m): dark = t.t("ar.mwDarkFrom", ["t": clock.fmt(m)])
        case .allDay: dark = t.t("ar.mwDarkAll")
        case .never: dark = t.t("mw.noDark")
        }
        return head + " · " + dark
    }

    /// Знак минус — настоящий (U+2212), как у высот в остальных строках.
    static func signed(_ v: Double) -> String {
        let n = Int(v.rounded())
        return n < 0 ? "−\(-n)" : "+\(n)"
    }

    /// «видимость глазом 8 %: город, засветка 12» / «днём не видно: солнце +20°» / «Луна 62 % освещена над горизонтом».
    static func eyeLine(_ eye: MilkyWayLook.EyeNote, _ t: Lexicon) -> String {
        var why: [String] = []
        for cause in eye.causes {
            switch cause {
            case .daylight(let sun): return t.t("ar.mwEyeDay", ["alt": signed(sun)])
            case .moon(let pct): return t.t("ar.mwEyeMoon", ["pct": String(pct)])
            case .twilight(let sun): why.append(t.t("ar.mwEyeTwilight", ["alt": signed(sun)]))
            case .glow(let level, let value):
                let n = value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
                switch level {
                case .dark: why.append(t.t("ar.mwEyeGlowDark"))
                case .faint: why.append(t.t("ar.mwEyeGlowFaint", ["n": n]))
                case .city: why.append(t.t("ar.mwEyeGlowCity", ["n": n]))
                case .none: why.append(t.t("ar.mwEyeGlowNone", ["n": n]))
                }
            case .haze: why.append(t.t("ar.mwEyeHaze"))
            case .belowHorizon: why.append(t.t("ar.mwEyeBelow"))
            }
        }
        return t.t("ar.mwEye", ["pct": String(eye.percent), "why": why.joined(separator: " · ")])
    }

    /// Окно съёмки — отрезки `MilkyWayWindow` (`MilkyWayPlan.shooting`): «окно съёмки 23:40–03:10», не больше трёх
    /// отрезков через запятую; окна нет — причина словами веба.
    static func window(plan: MilkyWayPlan, clock: ClockText, _ t: Lexicon) -> String? {
        let w = plan.window
        if !plan.shooting.isEmpty {
            let ranges = plan.shooting.prefix(3).map { clock.range($0.from, $0.to) }.joined(separator: ", ")
            return t.t("ar.mwWindow", ["range": ranges])
        }
        let why: String
        if !w.dark { why = t.t("mw.noDark") }
        else if w.moonBlocks { why = t.t("mpro.windowMoon") }
        else { why = t.t("mw.coreLow", ["alt": String(Int(w.best.altitude.rounded())), "need": String(Int(MilkyWay.workLow))]) }
        return t.t("ar.mwWindowNone", ["why": why])
    }
}
