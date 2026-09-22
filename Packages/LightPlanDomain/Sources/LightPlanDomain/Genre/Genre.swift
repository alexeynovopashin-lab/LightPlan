import Foundation

/// Жанр съёмки — пресет формы, а не профиль фотографа: свадебщик снимает и
/// семью тоже (веб `GENRE`, `docs/12_CARD_ARCHITECTURE.md`).
///
/// Сырое значение — код, который веб пишет в запись (`type`). Порядок
/// `allCases` — `ALL_GENRES`, список «Моих жанров»; порядок самой таблицы
/// `GENRE` другой (`specOrder`), и он тоже значим: по нему идёт поиск жанра в
/// названии чужого события при ввозе календаря — выигрывает первый.
public enum Genre: String, CaseIterable, Sendable {
    case portrait, wedding, party, lovestory, family, animals
    case landscape, architecture, street, report, product, ad

    /// Порядок ключей таблицы `GENRE` веба: животные стоят перед семьёй.
    public static let specOrder: [Genre] = [
        .portrait, .wedding, .party, .lovestory, .animals, .family,
        .landscape, .architecture, .street, .report, .product, .ad,
    ]

    /// Строка таблицы `GENRE`.
    public var spec: GenreSpec {
        switch self {
        case .portrait:     GenreSpec(delivery: true, client: true, duration: 60, pay: [.hourly, .flat, .pack])
        case .wedding:      GenreSpec(delivery: true, client: true, duration: 480, pay: [.hourly, .pack], explicitRoute: true)
        case .party:        GenreSpec(delivery: true, client: true, duration: 240, pay: [.hourly, .pack], explicitRoute: true)
        case .lovestory:    GenreSpec(delivery: true, client: true, duration: 90, pay: [.hourly, .flat, .pack])
        case .animals:      GenreSpec(delivery: true, client: true, duration: 60, pay: [.hourly, .flat, .pack], breed: true)
        case .family:       GenreSpec(delivery: true, client: true, duration: 90, pay: [.hourly, .flat, .pack])
        case .landscape:    GenreSpec(delivery: false, client: false, duration: nil, pay: [.flat])
        case .architecture: GenreSpec(delivery: true, client: true, duration: 120, pay: [.object])
        case .street:       GenreSpec(delivery: false, client: false, duration: 180, pay: [.flat])
        case .report:       GenreSpec(delivery: true, client: true, duration: 180, pay: [.hourly, .flat])
        case .product:      GenreSpec(delivery: true, client: true, duration: 180, pay: [.flat, .hourly, .item], models: true)
        case .ad:           GenreSpec(delivery: true, client: true, duration: 240, pay: [.flat, .hourly], models: true)
        }
    }

    /// Группа жанра (`GENRE_GROUP`): она задаёт состав и подписи, жанр правит поверх.
    public var group: GenreGroup {
        switch self {
        case .wedding, .party: .event
        case .portrait, .lovestory, .family, .animals: .people
        case .product, .ad, .architecture, .report: .client
        case .landscape, .street: .own
        }
    }

    /// Порядок ключей `GENRE_GROUP`.
    public static let groupOrder: [Genre] = [
        .wedding, .party, .portrait, .lovestory, .family, .animals,
        .product, .ad, .architecture, .report, .landscape, .street,
    ]

    /// Кого снимаем поимённо (`GENRE_PERSONS`): у свадьбы двое, у праздника
    /// герой один, у остальных пары нет — клиент остаётся строкой.
    public var persons: [PersonRole] {
        switch self {
        case .wedding: [.bride, .groom]
        case .party: [.celebrant]
        default: []
        }
    }

    /// Срок сдачи по жанру в днях (`GENRE_DEADLINE`).
    public var deliveryDays: Int {
        switch self {
        case .wedding: 90
        case .party, .lovestory, .family, .landscape, .street: 14
        case .portrait, .animals: 7
        case .architecture, .product: 5
        case .report: 3
        case .ad: 10
        }
    }

    /// Порядок ключей `GENRE_DEADLINE`.
    public static let deadlineOrder: [Genre] = [
        .wedding, .party, .lovestory, .family, .portrait, .animals,
        .landscape, .architecture, .street, .report, .product, .ad,
    ]

    /// Папки набора референсов (`GENRE_TAGS`): называют предмет съёмки, поэтому
    /// идут от жанра, а не от группы.
    public var refTags: [RefTag] {
        switch self {
        case .wedding:      [.gathering, .couple, .bride, .groom, .walk, .evening, .details]
        case .party:        [.celebrant, .guests, .table, .dancing, .details]
        case .lovestory:    [.couple, .walk, .evening, .details]
        case .family:       [.allTogether, .kids, .parents, .play, .details]
        case .portrait:     [.face, .fullLength, .hands, .light, .details]
        case .animals:      [.face, .fullLength, .play, .light, .details]
        case .product:      [.object, .angles, .texture, .composition]
        case .ad:           [.campaign, .model, .product, .scene]
        case .architecture: [.facade, .interior, .detail, .wideShot]
        case .report:       [.hero, .wide, .closeUp, .moment]
        case .landscape:    [.wide, .foreground, .sky, .light]
        case .street:       [.frame, .hero, .light, .geometry]
        }
    }

    /// Порядок ключей `GENRE_TAGS`.
    public static let refTagsOrder: [Genre] = [
        .wedding, .party, .lovestory, .family, .portrait, .animals,
        .product, .ad, .architecture, .report, .landscape, .street,
    ]

    /// Уточнения жанра в порядке панели (`SUBGENRE`): меняют у съёмки имя и
    /// знак, и больше ничего. У стрита их нет намеренно.
    public var subGenres: [SubGenre] {
        switch self {
        case .portrait:     [.newborn, .pregnancy, .kids, .boudoir, .business]
        case .wedding:      [.engagement, .registry, .church]
        case .party:        [.birthday, .jubilee, .newyear, .graduation, .christening, .barmitzvah]
        case .lovestory:    [.anniversary]
        case .family:       [.baby, .pregnancy, .generations]
        case .animals:      [.dogs, .cats, .horses]
        case .landscape:    [.stars]
        case .architecture: [.interior, .realty]
        case .street:       []
        case .report:       [.sport, .races, .olympics, .football, .basketball, .volleyball, .swimming, .ski, .concert, .conference]
        case .product:      [.food, .macro, .cars, .moto]
        case .ad:           [.fashion, .lookbook, .catalog, .beauty]
        }
    }

    /// Порядок ключей `SUBGENRE` (стрита в таблице нет).
    public static let subGenreOrder: [Genre] = [
        .portrait, .wedding, .party, .lovestory, .family, .animals,
        .landscape, .architecture, .report, .product, .ad,
    ]

    /// Уточнение принадлежит жанру (веб `subOk`): сменили жанр — чужое
    /// уточнение молча забыто, «Ньюборн» на свадьбе не показывается.
    public func allows(_ sub: SubGenre?) -> Bool {
        guard let sub else { return false }
        return subGenres.contains(sub)
    }
}

/// Строка таблицы `GENRE`: что жанр подставляет в форму.
public struct GenreSpec: Sendable, Hashable {
    /// Есть ли кому сдавать материал (`delivery`).
    public let delivery: Bool
    /// Есть ли заказчик (`client`).
    public let client: Bool
    /// Обычная длительность в минутах; `nil` — «сколько длится свет» (`dur: null`).
    public let duration: Int?
    /// Способы оплаты по приоритету, первый — по умолчанию (`pay`).
    public let pay: [PayKind]
    /// Маршрут записан у самого жанра (`route: true` у свадьбы и праздника);
    /// `nil` — решает группа.
    public let explicitRoute: Bool?
    /// Графа «порода или вид» (`breed`): снимают питомца, договаривается хозяин.
    public let breed: Bool
    /// Модели и кампания поверх группы (`models`): у рекламы и предметки в кадре чужие люди.
    public let models: Bool

    public init(delivery: Bool, client: Bool, duration: Int?, pay: [PayKind],
                explicitRoute: Bool? = nil, breed: Bool = false, models: Bool = false) {
        self.delivery = delivery
        self.client = client
        self.duration = duration
        self.pay = pay
        self.explicitRoute = explicitRoute
        self.breed = breed
        self.models = models
    }

    /// Пресет незнакомого жанра — тот, что веб отдаёт вместо пустоты
    /// (`GENRE[g] || {…}` в `genreSpec`).
    public static let fallback = GenreSpec(delivery: true, client: true, duration: 90, pay: [.hourly, .flat])
}

/// Группа жанров по типу рабочего процесса, а не по предмету съёмки
/// (`docs/12_CARD_ARCHITECTURE.md`, веб `GROUP`). Девять описаний сжимаются в четыре.
public enum GenreGroup: String, CaseIterable, Sendable {
    /// Событие дня: свадьба, праздник — день из точек.
    case event
    /// Люди: портрет, лавстори, семья, животные.
    case people
    /// Заказчик-организация: платит не тот, кого снимают.
    case client
    /// Свои съёмки: пейзаж, стрит.
    case own

    /// Строка таблицы `GROUP`.
    public var spec: GroupSpec {
        switch self {
        case .event:  GroupSpec(route: .always, pack: true, guests: true, prepay: true, org: true, order: false)
        case .people: GroupSpec(route: .optional, pack: true, guests: false, prepay: true, org: false, order: false)
        case .client: GroupSpec(route: .optional, pack: false, guests: false, prepay: true, org: true, order: true)
        case .own:    GroupSpec(route: .off, pack: false, guests: false, prepay: true, org: false, order: false)
        }
    }
}

/// Маршрут дня у группы (`route` в `GROUP`).
public enum RouteMode: String, Sendable {
    /// У события маршрут есть всегда.
    case always
    /// Доступен и молчит, пока точек не завели.
    case optional = "opt"
    /// Нет вовсе.
    case off
}

/// Строка таблицы `GROUP`.
public struct GroupSpec: Sendable, Hashable {
    public let route: RouteMode
    /// Пакеты — именованные продукты группы.
    public let pack: Bool
    /// Гости — мерка события дня.
    public let guests: Bool
    /// Предоплата — везде, где за съёмку платят.
    public let prepay: Bool
    /// Организатор у события, заказчик у заказа — одна строка, разные слова.
    public let org: Bool
    /// Заказ: ТЗ, документы, контактное лицо вместо клиента строкой.
    public let order: Bool
}

/// Жанр вместе со всем, что из него выводится, — с правилами веба для
/// незнакомого или пустого жанра: группа «люди», пресет «ставка или сдельно»,
/// срок 7 дней, папки по умолчанию, пары нет (`genreSpec`, `groupOf`,
/// `genreDeadline`, `refTagsFor`, `personsOf`).
public struct GenreProfile: Sendable, Hashable {
    public let genre: Genre?

    public init(_ genre: Genre?) { self.genre = genre }

    public var spec: GenreSpec { genre?.spec ?? .fallback }
    public var group: GenreGroup { genre?.group ?? .people }
    public var groupSpec: GroupSpec { group.spec }

    /// Маршрут у жанра есть по определению (`genreSpec(type).route === true`,
    /// веб `hasRoute`): записан у жанра или группа говорит «всегда».
    public var hasRoute: Bool { spec.explicitRoute ?? (groupSpec.route == .always) }
    /// Маршрут доступен и молчит (`routeOpt`).
    public var routeOptional: Bool { groupSpec.route == .optional }

    public var persons: [PersonRole] { genre?.persons ?? [] }
    public var deliveryDays: Int { genre?.deliveryDays ?? 7 }
    public var refTags: [RefTag] { genre?.refTags ?? RefTag.defaults }
    public var subGenres: [SubGenre] { genre?.subGenres ?? [] }
}

/// Роль человека в паре (`GENRE_PERSONS`); слово — `person.<код>` в словаре.
public enum PersonRole: String, CaseIterable, Sendable {
    case bride, groom, celebrant
}
