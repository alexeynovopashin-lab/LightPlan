import Foundation
import LightPlanCore

/// Пять строк Млечного Пути в сводке карты (порт `renderMwRows` веба,
/// итерация 20б): ночь, луна для звёзд, засветка, небо, вердикт. Строки
/// приходят вместе со слоем «Млечный Путь» и уходят вместе с ним; строка без
/// данных не показывается вовсе, а не пишет прочерк.
///
/// Чистая функция: окно, помеха луны, засветка и погода над окном считаются
/// снаружи — окно нужно и группе «Подробно», а стоит оно трёхсот шагов
/// астрономии.
public struct MapMilkyWayRows: Equatable, Sendable {

    /// Цвет значения — переменные веба.
    public enum Tone: Equatable, Sendable {
        /// `--ink-2`: обычное показание.
        case ink2
        /// `--ink-4`: приглушено — темноты нет, окно под луной.
        case ink4
        /// `--terra`: помеха, от которой уезжают или которую ждут.
        case terra
        /// `#C6AAE8`: окно съёмки открыто.
        case violet
    }

    public struct Row: Equatable, Sendable {
        /// Ключ словаря подписи (`map.night` …) — он же имя строки.
        public let label: String
        public let text: String
        public let tone: Tone
    }

    public let rows: [Row]

    /// - Parameters:
    ///   - sun: солнце выбранных суток (`SUN` веба) — границы астрономической ночи.
    ///   - window: окно Млечного Пути этих суток (`mwWindow`).
    ///   - moon: помеха луны звёздам (`moonVsStars`).
    ///   - glow: засветка места (`glowVal`); `nil` — атласа нет или он молчит.
    ///   - sky: погода над окном (`mwSkyAt`); `nil` — на эти часы прогноза нет.
    ///   - nextDark: когда темнота вернётся (`nextAstroNight`); зовётся, только
    ///     если этой ночью её нет.
    ///   - dateShort: короткая дата (`mwDateShort` → `dMonShort`).
    public static func build(
        sun: SolarDay, window w: MilkyWayWindow, moon mg: MoonVsStars, glow: Double?, sky: MilkyWaySky?,
        nextDark: () -> CivilDate?, dateShort: (CivilDate) -> String, lexicon: Lexicon, clock: ClockText
    ) -> MapMilkyWayRows {
        var rows: [Row] = []

        if w.dark {
            let text = sun.astroB != nil && sun.astroA != nil
                ? clock.range(sun.astroB, sun.astroA! + 1440) : lexicon.t("mw.nightYes")
            rows.append(Row(label: "map.night", text: text, tone: .ink2))
        } else {
            let text = nextDark().map { lexicon.t("mw.nightUntil", ["date": dateShort($0)]) } ?? lexicon.t("mw.nightNo")
            rows.append(Row(label: "map.night", text: text, tone: .ink4))
        }

        // Луна своей строкой, а не внутри вердикта: самая частая причина
        // пустой ясной ночи.
        let moonLevel = mg.level?.rawValue ?? 0
        if w.dark, moonLevel > 0 {
            let pct = String(mg.percent ?? 0)
            rows.append(moonLevel == 2
                ? Row(label: "map.moonGlare", text: lexicon.t("mw.glareWash", ["pct": pct]), tone: .terra)
                : Row(label: "map.moonGlare", text: lexicon.t("mw.glareDim", ["pct": pct]), tone: .ink2))
        }

        // Засветка числом рядом со словом: «×0.6» читается без астрономии,
        // mag/arcsec² — в «Подробно».
        let level = Glow.level(glow)
        if let level, let g = glow {
            let n = g < 10 ? String(format: "%.1f", g) : String(Int((g + 0.5).rounded(.down)))
            rows.append(Row(label: "map.glow", text: lexicon.t("glow.\(level.rawValue)") + " · ×" + n,
                            tone: level == .dark || level == .faint ? .ink2 : .terra))
        }

        if let sky {
            let word = sky.word.map { " · " + lexicon.t($0.rawValue) } ?? ""
            rows.append(Row(label: "map.sky", text: lexicon.t("mwSky.\(sky.look.rawValue)") + " · \(sky.cloud)%" + word,
                            tone: sky.score >= 50 ? .ink2 : .terra))
        }

        // Засветка названа раньше луны намеренно: луна уйдёт через неделю,
        // зарево города — никогда, и ответ на него другой — ехать.
        let peak = w.best.altitude
        var verdict: String, dim = true
        if !w.dark { verdict = lexicon.t("mw.noDark") }
        else if peak < MilkyWay.workLow {
            verdict = lexicon.t("mw.coreLow", ["alt": String(format: "%.0f", peak), "need": String(Int(MilkyWay.workLow))])
        }
        else if level == Glow.Level.none { verdict = lexicon.t("mw.glowKills") }
        else if moonLevel == 2 { verdict = lexicon.t("mw.moonWashes") }
        else if let from = w.from {
            verdict = clock.range(from, w.to) + (moonLevel == 1 ? lexicon.t("mw.moonDims") : "")
            dim = moonLevel == 1
        }
        else { verdict = w.moonBlocks ? lexicon.t("mw.moonBlocks") : lexicon.t("mw.noWindow") }
        rows.append(Row(label: "map.verdict", text: verdict, tone: dim ? .ink4 : .violet))

        return MapMilkyWayRows(rows: rows)
    }
}
