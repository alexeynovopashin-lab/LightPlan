import Foundation

/// Город, по которому живут «Свет», карта и календарь после запуска.
///
/// Решение Алексея 19 сентября 2026 (ROADMAP, «Город по умолчанию»):
/// город в настройках → место пользователя, если доступ к геолокации уже
/// дан → ближайшая по часовому поясу столица среди стран языка телефона
/// («для Испанского языка в GMT+2 — Мадрид, для UTC-6 — Мехико»). Лобни из
/// кода больше нет. Новых запросов разрешения правило не делает: место
/// пользователя берётся, только если доступ уже был.
public enum DefaultCity {

    public enum Source: Sendable, Equatable { case settings, device, capital }

    public struct Resolved: Sendable, Equatable {
        public let coordinate: GeoCoordinate
        /// Имя, если оно известно без геокодера (город настроек, столица).
        public let name: String?
        public let source: Source
    }

    public struct Capital: Sendable, Equatable {
        public let zone: String
        public let coordinate: GeoCoordinate
        public let names: [String: String]

        public func name(in language: String) -> String {
            names[language] ?? names["en"] ?? ""
        }
    }

    /// Столицы стран, где язык — основной. Порядок внутри языка решает
    /// ничью по поясу: первой стоит страна, которую Алексей назвал сам
    /// («для английского Лондон, для русского Москва»). Страны, где язык
    /// лишь второй государственный (русский в Казахстане и Киргизии),
    /// не берутся: иначе фотограф из Новосибирска получил бы Бишкек.
    public static let capitals: [String: [Capital]] = [
        "ru": [
            cap("Europe/Moscow", 55.7558, 37.6173, ru: "Москва", en: "Moscow"),
            cap("Europe/Minsk", 53.9006, 27.5590, ru: "Минск", en: "Minsk"),
        ],
        "en": [
            cap("Europe/London", 51.5074, -0.1278, ru: "Лондон", en: "London"),
            cap("America/New_York", 38.8951, -77.0364, ru: "Вашингтон", en: "Washington"),
            cap("America/Toronto", 45.4215, -75.6972, ru: "Оттава", en: "Ottawa"),
            cap("Europe/Dublin", 53.3498, -6.2603, ru: "Дублин", en: "Dublin"),
            cap("Australia/Sydney", -35.2809, 149.1300, ru: "Канберра", en: "Canberra"),
            cap("Pacific/Auckland", -41.2865, 174.7762, ru: "Веллингтон", en: "Wellington"),
        ],
        "es": [
            cap("Europe/Madrid", 40.4168, -3.7038, ru: "Мадрид", en: "Madrid", es: "Madrid"),
            cap("America/Mexico_City", 19.4326, -99.1332, ru: "Мехико", en: "Mexico City", es: "Ciudad de México"),
            cap("America/Bogota", 4.7110, -74.0721, ru: "Богота", en: "Bogotá", es: "Bogotá"),
            cap("America/Lima", -12.0464, -77.0428, ru: "Лима", en: "Lima", es: "Lima"),
            cap("America/Caracas", 10.4806, -66.9036, ru: "Каракас", en: "Caracas", es: "Caracas"),
            cap("America/Santiago", -33.4489, -70.6693, ru: "Сантьяго", en: "Santiago", es: "Santiago"),
            cap("America/Argentina/Buenos_Aires", -34.6037, -58.3816, ru: "Буэнос-Айрес", en: "Buenos Aires", es: "Buenos Aires"),
        ],
        "ja": [
            cap("Asia/Tokyo", 35.6762, 139.6503, ru: "Токио", en: "Tokyo", ja: "東京"),
        ],
        "zh": [
            cap("Asia/Shanghai", 39.9042, 116.4074, ru: "Пекин", en: "Beijing", zh: "北京"),
            cap("Asia/Taipei", 25.0330, 121.5654, ru: "Тайбэй", en: "Taipei", zh: "臺北"),
        ],
    ]

    /// - Parameters:
    ///   - home: «Мой город» из настроек; без координат он не в счёт.
    ///   - device: точка телефона — только если доступ уже был дан.
    ///   - language: язык телефона (`ru`, `en-GB`, `es`…); незнакомый — английский.
    ///   - zone: пояс телефона; `now` — момент, на который берётся смещение
    ///     (летнее время меняет ответ: Лондон зимой +0, летом +1).
    public static func resolve(home: HomeCity, device: GeoCoordinate?, language: String,
                               zone: TimeZone, now: Date = Date()) -> Resolved {
        if let c = home.coordinate, !home.isEmpty {
            return Resolved(coordinate: c, name: home.name, source: .settings)
        }
        if let d = device { return Resolved(coordinate: d, name: nil, source: .device) }
        let base = String(language.prefix { $0 != "-" && $0 != "_" }).lowercased()
        let c = capital(language: base, zone: zone, now: now)
        return Resolved(coordinate: c.coordinate, name: c.name(in: base), source: .capital)
    }

    /// Ближайшая по смещению от UTC столица языка; ничья — первая в списке.
    public static func capital(language base: String, zone: TimeZone, now: Date = Date()) -> Capital {
        let list = capitals[base] ?? capitals["en"]!
        let mine = zone.secondsFromGMT(for: now)
        func gap(_ c: Capital) -> Int {
            abs((TimeZone(identifier: c.zone)?.secondsFromGMT(for: now) ?? 0) - mine)
        }
        var best = list[0]
        for c in list.dropFirst() where gap(c) < gap(best) { best = c }
        return best
    }

    private static func cap(_ zone: String, _ lat: Double, _ lon: Double,
                            ru: String, en: String, es: String? = nil, ja: String? = nil, zh: String? = nil) -> Capital {
        var n = ["ru": ru, "en": en]
        if let es { n["es"] = es }
        if let ja { n["ja"] = ja }
        if let zh { n["zh"] = zh }
        return Capital(zone: zone, coordinate: GeoCoordinate(latitude: lat, longitude: lon), names: n)
    }
}
