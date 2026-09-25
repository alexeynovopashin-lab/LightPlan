import Foundation

/// Страна у точек Крыма — по региону телефона (DECISIONS «Крым в подписи места…»).
///
/// Замер 25.09.2026, `CLGeocoder`, пять точек (Ялта, Симферополь, Севастополь,
/// Керчь, Евпатория) × локали ru_RU, ru_US, en_US, en_RU: Apple отвечает
/// `isoCountryCode = UA`, «Украина»/«Ukraine» **всегда**, регион локали на ответ
/// не влияет — сам он под телефон не подстраивается. Поэтому поправка своя.
/// Признак Крыма — контур, а не текст ответа: `administrativeArea` зависит от
/// языка («Крым», «Crimea», «Крим»), а `timeZone` у Apple для Крыма —
/// Europe/Moscow, но так отвечает и не только Крым. Контур грубый (берег с
/// запасом, перешеек по 46,13° с.ш.), а ответ `UA` — второй замок: точка
/// вне Украины страной «Россия» не станет.
public enum CrimeaCountry {
    /// «Россия» на языке подписей, если регион телефона — Россия и точка в
    /// Крыму по ответу Apple «Украина»; иначе страна как пришла.
    public static func country(_ apple: String?, isoCode: String?, at c: GeoCoordinate,
                               deviceRegion: String? = Locale.current.region?.identifier,
                               locale: Locale = Locale(identifier: "ru_RU")) -> String? {
        guard deviceRegion == "RU", isoCode?.uppercased() == "UA", contains(c) else { return apple }
        return locale.localizedString(forRegionCode: "RU") ?? apple
    }

    /// Точка внутри контура полуострова (чётно-нечётное правило, x = долгота).
    static func contains(_ c: GeoCoordinate) -> Bool {
        var inside = false
        var j = outline.count - 1
        for i in outline.indices {
            let (xi, yi) = outline[i], (xj, yj) = outline[j]
            if (yi > c.latitude) != (yj > c.latitude),
               c.longitude < (xj - xi) * (c.latitude - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }

    /// (долгота, широта), по часовой от мыса Тарханкут; берег отнесён в море на ~0,1°.
    static let outline: [(Double, Double)] = [
        (32.40, 45.35), (32.70, 45.70), (33.30, 46.00), (33.60, 46.13), (34.20, 46.13),
        (34.90, 46.05), (35.30, 45.60), (35.80, 45.45), (36.35, 45.60), (36.75, 45.45),
        (36.60, 45.05), (35.40, 44.85), (34.95, 44.70), (34.40, 44.55), (33.75, 44.28),
        (33.35, 44.45), (33.00, 44.90), (32.55, 45.10),
    ]
}
