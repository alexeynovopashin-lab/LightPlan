// Сгенерировано `Tools/bright_stars/gen_swift.js` из `Tools/bright_stars/bright_stars.json` — не править руками.
// Экваториальные координаты эпохи J2000: RA в часах, Dec в градусах, видимая величина V.
// Источник: Yale Bright Star Catalogue, 5-е изд. (VizieR V/50); имена — IAU WGSN. Подробно — Tools/bright_stars/README.md.

/// Яркая звезда (V ≤ 2.5) вне фигур созвездий: координаты как у `CatalogStar`, плюс имя и спектр.
public struct BrightStar: Sendable, Equatable {
    /// Имя по-английски: принятое МАС, иначе обозначение Байера латиницей («Gamma Centauri»).
    public let name: String
    /// Русское имя — только у 30 самых ярких звёзд неба; `nil` — показывать `name`.
    public let nameRu: String?
    /// Обозначение Байера: «α Car».
    public let bayer: String
    /// Прямое восхождение, **часы**.
    public let ra: Double
    /// Склонение, градусы.
    public let dec: Double
    /// Видимая величина V; у слитой пары (α Cen, α Cru) — суммарная.
    public let magnitude: Double
    /// Спектральный класс по V/50 («B1III»); у слитой пары — через «+».
    public let spectralClass: String
    /// Номер в Yale Bright Star Catalogue (HR) — по нему звезда ищется в источнике.
    public let hr: Int
}

/// Яркие звёзды, которых нет среди звёзд `ConstellationCatalog` (сверка по месту, допуск 0.05°): 31 шт., от яркой к слабой.
public enum BrightStarCatalog {
    public static let all: [BrightStar] = [
        BrightStar(name: "Canopus", nameRu: "Канопус", bayer: "α Car",
                   ra: 6.39919, dec: -52.6958, magnitude: -0.72, spectralClass: "F0II", hr: 2326),
        BrightStar(name: "Rigil Kentaurus", nameRu: "Альфа Центавра", bayer: "α Cen",
                   ra: 14.65997, dec: -60.8353, magnitude: -0.29, spectralClass: "G2V+K1V", hr: 5459),
        BrightStar(name: "Achernar", nameRu: "Ахернар", bayer: "α Eri",
                   ra: 1.62858, dec: -57.2367, magnitude: 0.46, spectralClass: "B3Vpe", hr: 472),
        BrightStar(name: "Hadar", nameRu: "Хадар", bayer: "β Cen",
                   ra: 14.06372, dec: -60.3731, magnitude: 0.61, spectralClass: "B1III", hr: 5267),
        BrightStar(name: "Acrux", nameRu: "Акрукс", bayer: "α Cru",
                   ra: 12.44331, dec: -63.0992, magnitude: 0.76, spectralClass: "B0.5IV+B1V", hr: 4730),
        BrightStar(name: "Fomalhaut", nameRu: "Фомальгаут", bayer: "α PsA",
                   ra: 22.96086, dec: -29.6222, magnitude: 1.16, spectralClass: "A3V", hr: 8728),
        BrightStar(name: "Mimosa", nameRu: "Бекрукс", bayer: "β Cru",
                   ra: 12.79533, dec: -59.6886, magnitude: 1.25, spectralClass: "B0.5III", hr: 4853),
        BrightStar(name: "Gacrux", nameRu: "Гакрукс", bayer: "γ Cru",
                   ra: 12.51942, dec: -57.1133, magnitude: 1.63, spectralClass: "M3.5III", hr: 4763),
        BrightStar(name: "Miaplacidus", nameRu: "Бета Киля", bayer: "β Car",
                   ra: 9.22, dec: -69.7172, magnitude: 1.68, spectralClass: "A2IV", hr: 3685),
        BrightStar(name: "Alnair", nameRu: "Альнаир", bayer: "α Gru",
                   ra: 22.13722, dec: -46.9611, magnitude: 1.74, spectralClass: "B7IV", hr: 8425),
        BrightStar(name: "Gamma² Velorum", nameRu: nil, bayer: "γ² Vel",
                   ra: 8.15889, dec: -47.3367, magnitude: 1.78, spectralClass: "WC8+O9I", hr: 3207),
        BrightStar(name: "Avior", nameRu: nil, bayer: "ε Car",
                   ra: 8.37522, dec: -59.5097, magnitude: 1.86, spectralClass: "K3III+B2:V", hr: 3307),
        BrightStar(name: "Atria", nameRu: nil, bayer: "α TrA",
                   ra: 16.81108, dec: -69.0278, magnitude: 1.92, spectralClass: "K2IIb-IIIa", hr: 6217),
        BrightStar(name: "Peacock", nameRu: nil, bayer: "α Pav",
                   ra: 20.42747, dec: -56.735, magnitude: 1.94, spectralClass: "B2IV", hr: 7790),
        BrightStar(name: "Alsephina", nameRu: nil, bayer: "δ Vel",
                   ra: 8.74506, dec: -54.7083, magnitude: 1.96, spectralClass: "A1V", hr: 3485),
        BrightStar(name: "Alphard", nameRu: nil, bayer: "α Hya",
                   ra: 9.45978, dec: -8.6586, magnitude: 1.98, spectralClass: "K3II-III", hr: 3748),
        BrightStar(name: "Hamal", nameRu: nil, bayer: "α Ari",
                   ra: 2.11956, dec: 23.4625, magnitude: 2, spectralClass: "K2-IIICa-1", hr: 617),
        BrightStar(name: "Diphda", nameRu: nil, bayer: "β Cet",
                   ra: 0.7265, dec: -17.9867, magnitude: 2.04, spectralClass: "G9.5IIICH-1", hr: 188),
        BrightStar(name: "Menkent", nameRu: nil, bayer: "θ Cen",
                   ra: 14.11139, dec: -36.37, magnitude: 2.06, spectralClass: "K0-IIIb", hr: 5288),
        BrightStar(name: "Rasalhague", nameRu: nil, bayer: "α Oph",
                   ra: 17.58225, dec: 12.56, magnitude: 2.08, spectralClass: "A5III", hr: 6556),
        BrightStar(name: "Tiaki", nameRu: nil, bayer: "β Gru",
                   ra: 22.71114, dec: -46.8847, magnitude: 2.1, spectralClass: "M5III", hr: 8636),
        BrightStar(name: "Gamma Centauri", nameRu: nil, bayer: "γ Cen",
                   ra: 12.69194, dec: -48.9597, magnitude: 2.17, spectralClass: "A1IV", hr: 4819),
        BrightStar(name: "Suhail", nameRu: nil, bayer: "λ Vel",
                   ra: 9.13328, dec: -43.4325, magnitude: 2.21, spectralClass: "K4.5Ib-II", hr: 3634),
        BrightStar(name: "Naos", nameRu: nil, bayer: "ζ Pup",
                   ra: 8.05975, dec: -40.0033, magnitude: 2.25, spectralClass: "O5f", hr: 3165),
        BrightStar(name: "Aspidiske", nameRu: nil, bayer: "ι Car",
                   ra: 9.28483, dec: -59.2753, magnitude: 2.25, spectralClass: "A8Ib", hr: 3699),
        BrightStar(name: "Epsilon Centauri", nameRu: nil, bayer: "ε Cen",
                   ra: 13.66478, dec: -53.4664, magnitude: 2.3, spectralClass: "B1III", hr: 5132),
        BrightStar(name: "Uridim", nameRu: nil, bayer: "α Lup",
                   ra: 14.69883, dec: -47.3883, magnitude: 2.3, spectralClass: "B1.5III/Vn", hr: 5469),
        BrightStar(name: "Eta Centauri", nameRu: nil, bayer: "η Cen",
                   ra: 14.59178, dec: -42.1578, magnitude: 2.31, spectralClass: "B1.5Vne", hr: 5440),
        BrightStar(name: "Ankaa", nameRu: nil, bayer: "α Phe",
                   ra: 0.43806, dec: -42.3061, magnitude: 2.39, spectralClass: "K0III", hr: 99),
        BrightStar(name: "Sabik", nameRu: nil, bayer: "η Oph",
                   ra: 17.17297, dec: -15.7247, magnitude: 2.43, spectralClass: "A2V", hr: 6378),
        BrightStar(name: "Markeb", nameRu: nil, bayer: "κ Vel",
                   ra: 9.36856, dec: -55.0108, magnitude: 2.5, spectralClass: "B2IV-V", hr: 3734),
    ]
}
