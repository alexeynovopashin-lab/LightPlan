import Foundation

/// Градусы в AR — переключатель «Азимуты» (30г.5; опись `docs/30g2_modes_table.md` № 102, 107, 108 и § 2). Каждая подпись
/// с градусами положения берётся отсюда: без переключателя её нет, а стрелка к солнцу, время и слова остаются.
/// `shown` — `AppSettings.sees(.azimuths)` (через `LightScreenModel.azimuths`).
enum SunARDegrees {
    /// Подпись стрелки за краем кадра «320° · +12°». Без «Азимутов» пусто: стрелка без плашки.
    static func pointer(azimuth: Double, altitude: Double, shown: Bool) -> String {
        guard shown else { return "" }
        let a = azimuth.rounded() == 360 ? 0 : azimuth.rounded()
        return String(format: "%.0f° · %+.0f°", a, altitude.rounded())
    }

    /// Чип курса «N°» — куда смотрит телефон. `nil` — чипа нет.
    static func heading(_ azimuth: Double, shown: Bool) -> String? {
        guard shown else { return nil }
        return String(format: "%.0f°", azimuth.rounded() == 360 ? 0 : azimuth.rounded())
    }

    /// «Азимут N° · Высота +M°» над ползунком. `nil` — строки нет.
    static func sunPosition(azimuth: Double, altitude: Double, shown: Bool, lexicon: Lexicon) -> String? {
        guard shown else { return nil }
        return String(format: "%@ %.0f° · %@ %+.0f°", lexicon.t("pro.azimuth"), azimuth, lexicon.t("pro.altitude"), altitude)
    }

    /// «ядро восходит 22:40 · 195°» / «заходит 04:10 · 262°»; без «Азимутов» — только время.
    static func coreEvent(rise: Bool, time: String, azimuth: Double, shown: Bool, lexicon: Lexicon) -> String {
        guard shown else { return lexicon.t(rise ? "ar.coreRisesAt" : "ar.coreSetsAt", ["t": time]) }
        return lexicon.t(rise ? "ar.coreRises" : "ar.coreSets", ["t": time, "a": String(Int(azimuth.rounded()) % 360)])
    }
}
