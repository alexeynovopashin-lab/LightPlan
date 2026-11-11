import Foundation

/// Выбор студии из общего списка в листе «Где снимаем» → «Фотостудия» (30е.1;
/// схема `docs/30e1_studio_list/index.html`, ответ Алексея «Да, A везде», DECISIONS 07.11).
///
/// - Поиск в том же листе: по набранным буквам (с двух), по названию, адресу,
///   городу и залам; город съёмки первым, потом другие города. Закрытые скрыты.
/// - У каждой строки пометка проверки; «проверена человеком» — без «не проверена».
/// - Выбор делает **свою** карточку фотографа с номером места; карточку, заведённую
///   руками, со списком не склеиваем (хаб Q-045 п. 4). Место, уже взятое в свои
///   студии, второй карточки не даёт.
public enum StudioCatalog {

    /// Строка выдачи: место и своя карточка с этим номером, если она уже есть.
    public struct Row: Sendable, Hashable {
        public var place: CatalogPlace
        /// `Studio.id` своей карточки с этим номером места.
        public var mine: String?

        public init(place: CatalogPlace, mine: String? = nil) { self.place = place; self.mine = mine }
    }

    /// Выдача: город съёмки и другие города, по `cap` строк; остаток — числом.
    public struct Hits: Sendable, Hashable {
        public var here: [Row] = []
        public var other: [Row] = []
        public var moreHere = 0
        public var moreOther = 0
        public var isEmpty: Bool { here.isEmpty && other.isEmpty }

        public init(here: [Row] = [], other: [Row] = [], moreHere: Int = 0, moreOther: Int = 0) {
            self.here = here; self.other = other; self.moreHere = moreHere; self.moreOther = moreOther
        }
    }

    /// Пометка у строки.
    public enum Mark: Sendable, Hashable {
        /// Место уже в своих студиях.
        case yours
        /// «проверена человеком».
        case verified
        /// «из сбора»: «не проверена».
        case unverified
        /// «спорная»: «возможно, дубль — сверьте адрес». Пометка сборщика (`note`) не показывается.
        case disputed
    }

    /// Что ложится в черновик карточки при выборе.
    public struct Card: Sendable, Hashable {
        public var catalogId: String
        public var name: String
        public var address: String
        public var town: String
        /// Залы: `id` = «n» + номер зала в месте.
        public var halls: [Studio.Hall]
        /// Центр города, пока адрес не найден на карте; `nil` — город не из таблицы.
        public var latitude: Double?
        public var longitude: Double?
        /// Пояс места: из файла, иначе пояс города из таблицы.
        public var zone: String?
    }

    /// Строк в разделе, пока поиск не сужен.
    public static let cap = 30
    /// Поиск начинается с двух знаков: одна буква в Москве — сотни строк.
    public static let minQuery = 2
    /// Найденный адрес дальше этого от центра города — чужой дом с тем же названием улицы.
    public static let cityRadiusKm = 60.0

    /// Строчные, «ё» = «е», знаки препинания — пробелы.
    public static func fold(_ s: String) -> String {
        EventForm.cityNorm(s)
    }

    /// Один город: по названию в любом виде или по таблице (русское и английское имя).
    public static func sameCity(_ a: String, _ b: String) -> Bool {
        let x = fold(a), y = fold(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        if x == y { return true }
        guard let ca = CatalogCities.find(a), let cb = CatalogCities.find(b) else { return false }
        return ca.ru == cb.ru
    }

    /// Номер места, если студия взята из общего списка.
    public static func placeId(of st: Studio) -> String? {
        guard let id = st.catalogId, id.hasPrefix("pl") else { return nil }
        return id
    }

    /// Своя карточка с этим номером места.
    public static func mine(_ placeId: String, in studios: [Studio]) -> Studio? {
        studios.first { $0.catalogId == placeId }
    }

    /// Действующих мест в городе — для строки «N студий города» до набора.
    public static func count(town: String, in catalog: PlaceCatalog) -> Int {
        guard !fold(town).isEmpty else { return 0 }
        return catalog.places.filter { !$0.closed && $0.mergedInto == nil && sameCity($0.city, town) }.count
    }

    /// Поиск по набранной строке. Каждое слово запроса должно встретиться в названии,
    /// адресе, городе или залах. Порядок: название начинается с запроса, название
    /// содержит запрос, остальное; внутри — как в файле (по номеру места).
    public static func search(_ query: String, in catalog: PlaceCatalog, town: String, mine studios: [Studio],
                              cap: Int = cap) -> Hits {
        let q = fold(query)
        guard q.count >= minQuery else { return Hits() }
        let words = q.split(separator: " ").map(String.init)
        var found: [(rank: Int, row: Row)] = []
        for p in catalog.places where !p.closed && p.mergedInto == nil {
            let name = fold(p.name)
            let hay = [name, fold(p.address), fold(p.city), p.halls.map { fold($0.name) }.joined(separator: " ")]
                .joined(separator: " ")
            guard words.allSatisfy({ hay.contains($0) }) else { continue }
            let rank = name.hasPrefix(q) ? 0 : name.contains(q) ? 1 : 2
            found.append((rank, Row(place: p, mine: mine(p.id, in: studios)?.id)))
        }
        let rows = found.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map(\.element.row)
        let local = fold(town).isEmpty
        let here = rows.filter { local || sameCity($0.place.city, town) }
        let other = local ? [] : rows.filter { !sameCity($0.place.city, town) }
        return Hits(here: Array(here.prefix(cap)), other: Array(other.prefix(cap)),
                    moreHere: max(0, here.count - cap), moreOther: max(0, other.count - cap))
    }

    public static func mark(_ row: Row) -> Mark {
        if row.mine != nil { return .yours }
        switch row.place.check {
        case .verified: return .verified
        case .collected: return .unverified
        case .disputed: return .disputed
        }
    }

    /// Черновик карточки из места: название, адрес целиком, город, залы с номерами,
    /// центр города и пояс. Телефона в списке нет, ключа брони — тоже.
    public static func card(_ p: CatalogPlace) -> Card {
        let city = CatalogCities.find(p.city)
        return Card(catalogId: p.id, name: p.name, address: p.address, town: p.city,
                    halls: p.halls.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                        .map { Studio.Hall(id: "n\($0.number)", name: $0.name) },
                    latitude: city?.latitude, longitude: city?.longitude,
                    zone: p.timezone ?? city?.zone)
    }

    /// Найденный на карте адрес годится, если он в городе места (≤ `cityRadiusKm`
    /// от центра); город не из таблицы — сверять не с чем, годится.
    public static func accepts(latitude: Double, longitude: Double, for p: CatalogPlace) -> Bool {
        guard let c = CatalogCities.find(p.city) else { return true }
        return km(latitude, longitude, c.latitude, c.longitude) <= cityRadiusKm
    }

    static func km(_ la1: Double, _ lo1: Double, _ la2: Double, _ lo2: Double) -> Double {
        let r = 6371.0, d = Double.pi / 180
        let a = sin((la2 - la1) * d / 2), b = sin((lo2 - lo1) * d / 2)
        let h = a * a + cos(la1 * d) * cos(la2 * d) * b * b
        return 2 * r * asin(min(1, h.squareRoot()))
    }
}

/// Центры и пояса городов общего списка (39 городов файла 06.11): студия встаёт в
/// центр своего города, пока её адрес не найден на карте (развилка 2, вариант А).
/// Координаты сверены 07.11 с геокодером Apple: расхождение 0–9 км, в пределах
/// города; пояса — из его ответов (Севастополь геокодер не нашёл: значения по памяти).
public enum CatalogCities {
    public struct City: Sendable, Hashable {
        public let ru: String
        public let en: String
        public let latitude: Double
        public let longitude: Double
        public let zone: String
    }

    public static let all: [City] = [
        City(ru: "Москва", en: "Moscow", latitude: 55.7558, longitude: 37.6173, zone: "Europe/Moscow"),
        City(ru: "Санкт-Петербург", en: "Saint Petersburg", latitude: 59.9386, longitude: 30.3141, zone: "Europe/Moscow"),
        City(ru: "Астана", en: "Astana", latitude: 51.1282, longitude: 71.4307, zone: "Asia/Almaty"),
        City(ru: "Краснодар", en: "Krasnodar", latitude: 45.0355, longitude: 38.9753, zone: "Europe/Moscow"),
        City(ru: "Томск", en: "Tomsk", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk"),
        City(ru: "Челябинск", en: "Chelyabinsk", latitude: 55.1644, longitude: 61.4368, zone: "Asia/Yekaterinburg"),
        City(ru: "Воронеж", en: "Voronezh", latitude: 51.6608, longitude: 39.2003, zone: "Europe/Moscow"),
        City(ru: "Тольятти", en: "Tolyatti", latitude: 53.5078, longitude: 49.4204, zone: "Europe/Samara"),
        City(ru: "Омск", en: "Omsk", latitude: 54.9885, longitude: 73.3242, zone: "Asia/Omsk"),
        City(ru: "Нижний Новгород", en: "Nizhny Novgorod", latitude: 56.3269, longitude: 44.0059, zone: "Europe/Moscow"),
        City(ru: "Тюмень", en: "Tyumen", latitude: 57.1530, longitude: 65.5343, zone: "Asia/Yekaterinburg"),
        City(ru: "Ульяновск", en: "Ulyanovsk", latitude: 54.3142, longitude: 48.4031, zone: "Europe/Ulyanovsk"),
        City(ru: "Кемерово", en: "Kemerovo", latitude: 55.3547, longitude: 86.0873, zone: "Asia/Novokuznetsk"),
        City(ru: "Рязань", en: "Ryazan", latitude: 54.6292, longitude: 39.7364, zone: "Europe/Moscow"),
        City(ru: "Екатеринбург", en: "Yekaterinburg", latitude: 56.8389, longitude: 60.6057, zone: "Asia/Yekaterinburg"),
        City(ru: "Хабаровск", en: "Khabarovsk", latitude: 48.4802, longitude: 135.0719, zone: "Asia/Vladivostok"),
        City(ru: "Ижевск", en: "Izhevsk", latitude: 56.8526, longitude: 53.2045, zone: "Europe/Samara"),
        City(ru: "Махачкала", en: "Makhachkala", latitude: 42.9849, longitude: 47.5047, zone: "Europe/Moscow"),
        City(ru: "Новосибирск", en: "Novosibirsk", latitude: 55.0302, longitude: 82.9204, zone: "Asia/Novosibirsk"),
        City(ru: "Казань", en: "Kazan", latitude: 55.7963, longitude: 49.1088, zone: "Europe/Moscow"),
        City(ru: "Красноярск", en: "Krasnoyarsk", latitude: 56.0153, longitude: 92.8932, zone: "Asia/Krasnoyarsk"),
        City(ru: "Ростов-на-Дону", en: "Rostov-on-Don", latitude: 47.2357, longitude: 39.7015, zone: "Europe/Moscow"),
        City(ru: "Иркутск", en: "Irkutsk", latitude: 52.2870, longitude: 104.3050, zone: "Asia/Irkutsk"),
        City(ru: "Владивосток", en: "Vladivostok", latitude: 43.1155, longitude: 131.8855, zone: "Asia/Vladivostok"),
        City(ru: "Пермь", en: "Perm", latitude: 58.0105, longitude: 56.2502, zone: "Asia/Yekaterinburg"),
        City(ru: "Ставрополь", en: "Stavropol", latitude: 45.0428, longitude: 41.9734, zone: "Europe/Moscow"),
        City(ru: "Барнаул", en: "Barnaul", latitude: 53.3474, longitude: 83.7784, zone: "Asia/Barnaul"),
        City(ru: "Балашиха", en: "Balashikha", latitude: 55.7963, longitude: 37.9381, zone: "Europe/Moscow"),
        City(ru: "Новокузнецк", en: "Novokuznetsk", latitude: 53.7596, longitude: 87.1216, zone: "Asia/Novokuznetsk"),
        City(ru: "Минск", en: "Minsk", latitude: 53.9006, longitude: 27.5590, zone: "Europe/Minsk"),
        City(ru: "Саратов", en: "Saratov", latitude: 51.5331, longitude: 46.0342, zone: "Europe/Saratov"),
        City(ru: "Алматы", en: "Almaty", latitude: 43.2220, longitude: 76.8512, zone: "Asia/Almaty"),
        City(ru: "Волгоград", en: "Volgograd", latitude: 48.7080, longitude: 44.5133, zone: "Europe/Volgograd"),
        City(ru: "Оренбург", en: "Orenburg", latitude: 51.7682, longitude: 55.0969, zone: "Asia/Yekaterinburg"),
        City(ru: "Самара", en: "Samara", latitude: 53.1959, longitude: 50.1002, zone: "Europe/Samara"),
        City(ru: "Севастополь", en: "Sevastopol", latitude: 44.6167, longitude: 33.5254, zone: "Europe/Simferopol"),
        City(ru: "Набережные Челны", en: "Naberezhnye Chelny", latitude: 55.7436, longitude: 52.3958, zone: "Europe/Moscow"),
        City(ru: "Уфа", en: "Ufa", latitude: 54.7388, longitude: 55.9721, zone: "Asia/Yekaterinburg"),
        City(ru: "Ярославль", en: "Yaroslavl", latitude: 57.6261, longitude: 39.8845, zone: "Europe/Moscow"),
    ]

    private static let index: [String: City] = {
        var d: [String: City] = [:]
        for c in all {
            d[EventForm.cityNorm(c.ru)] = c
            d[EventForm.cityNorm(c.en)] = c
        }
        return d
    }()

    /// Город по русскому или английскому названию; регистр, «ё» и дефисы не важны.
    public static func find(_ name: String) -> City? { index[EventForm.cityNorm(name)] }
}
