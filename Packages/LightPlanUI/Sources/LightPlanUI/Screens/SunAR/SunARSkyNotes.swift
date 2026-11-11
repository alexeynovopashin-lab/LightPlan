import Foundation
import LightPlanCore

/// Справка о видимости глазом под словами «Звёзды», «Созвездия», «Планеты» в списке «Слоёв» (шаг 29.8в.18): слои
/// рисуются всегда, а строка говорит, виден ли этот рисунок настоящему небу, с числом и причиной. Слова — те же, что у
/// строки Млечного Пути (`SunARMilkyWayNotes.eyeLine`).
enum SunARSkyNotes {
    /// «днём не видно: солнце +35°» / «сумерки, солнце −9° · город, засветка 12». Ничто не мешает — `nil`.
    /// `look` — переключатели «Азимуты» и «Термины» (30г.10): без них градусов и слова «сумерки» нет.
    static func eyeLine(_ causes: [SkyEyeNote.Cause], _ t: Lexicon, look: SunARNoteLook = .full) -> String? {
        let parts: [String] = causes.map { cause in
            switch cause {
            case .daylight(let sun): return look.day(sun, t)
            case .twilight(let sun): return look.twilight(sun, t)
            case .glow(let level, let value):
                let n = value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
                return t.t(level == .faint ? "ar.mwEyeGlowFaint" : "ar.mwEyeGlowCity", ["n": n])
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Как справки AR под слоями говорят о солнце (30г.10, расхождение 2 сверки): без «Азимутов» — без градусов высоты
/// («днём не видно: солнце +24°» → «днём не видно»), без «Терминов» — вместо «сумерки» то слово, что купол «Просто» и «Про»
/// показывает при этой высоте солнца (`LightTelemetry.phaseKey(_:terms: false)`; при солнце от −6° до −18° это
/// «Глубокие сумерки»). Луна здесь не читается: в справке Млечного Пути она — причина невидимости (решение 11.11).
struct SunARNoteLook: Equatable {
    /// `AppSettings.sees(.azimuths)`.
    var azimuths: Bool
    /// `AppSettings.sees(.terms)`.
    var terms: Bool
    /// Солнце поднимается: утро у купола (рассвет, «Светает»), иначе вечер.
    var morning: Bool = false

    /// Всё видно — справки как до 30г.10 (Астро со всеми переключателями).
    static let full = SunARNoteLook(azimuths: true, terms: true)

    func day(_ sun: Double, _ t: Lexicon) -> String {
        azimuths ? t.t("ar.mwEyeDay", ["alt": SunARMilkyWayNotes.signed(sun)]) : t.t("ar.mwEyeDayPlain")
    }

    func twilight(_ sun: Double, _ t: Lexicon) -> String {
        if terms {
            return azimuths ? t.t("ar.mwEyeTwilight", ["alt": SunARMilkyWayNotes.signed(sun)]) : t.t("ar.mwEyeTwilightPlain")
        }
        let phase = Self.lowerFirst(t.t(LightTelemetry.phaseKey(LightState(elevation: sun, morning: morning).code, terms: false)))
        return azimuths ? t.t("ar.mwEyePhase", ["phase": phase, "alt": SunARMilkyWayNotes.signed(sun)]) : phase
    }

    /// Слово купола стоит с заглавной («Глубокие сумерки»), в строке справки — со строчной, как «сумерки».
    static func lowerFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.lowercased() + s.dropFirst()
    }
}
