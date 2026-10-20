import Foundation
import LightPlanCore

/// Справка о видимости глазом под словами «Звёзды», «Созвездия», «Планеты» в списке «Слоёв» (шаг 29.8в.18): слои
/// рисуются всегда, а строка говорит, виден ли этот рисунок настоящему небу, с числом и причиной. Слова — те же, что у
/// строки Млечного Пути (`SunARMilkyWayNotes.eyeLine`).
enum SunARSkyNotes {
    /// «днём не видно: солнце +35°» / «сумерки, солнце −9° · город, засветка 12». Ничто не мешает — `nil`.
    static func eyeLine(_ causes: [SkyEyeNote.Cause], _ t: Lexicon) -> String? {
        let parts: [String] = causes.map { cause in
            switch cause {
            case .daylight(let sun): return t.t("ar.mwEyeDay", ["alt": SunARMilkyWayNotes.signed(sun)])
            case .twilight(let sun): return t.t("ar.mwEyeTwilight", ["alt": SunARMilkyWayNotes.signed(sun)])
            case .glow(let level, let value):
                let n = value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
                return t.t(level == .faint ? "ar.mwEyeGlowFaint" : "ar.mwEyeGlowCity", ["n": n])
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
