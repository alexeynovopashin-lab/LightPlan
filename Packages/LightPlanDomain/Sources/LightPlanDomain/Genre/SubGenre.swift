import Foundation

/// Уточнение жанра (веб `SUBGENRE`): меняет у съёмки имя и знак, и больше
/// ничего — ни поля, ни сроки, ни оплата, ни папка референсов о нём не знают.
///
/// Ключ общий, а не свой у каждого жанра: беременность снимают и портретисты,
/// и семейные, и это одно слово (`sub.<код>` в словаре). Какие уточнения есть
/// у жанра — `Genre.subGenres`.
public enum SubGenre: String, CaseIterable, Sendable {
    case newborn, pregnancy, kids, boudoir, business
    case engagement, registry, church
    case birthday, jubilee, newyear, graduation, christening, barmitzvah
    case anniversary
    case baby, generations
    case dogs, cats, horses
    case stars
    case interior, realty
    case sport, races, olympics, football, basketball, volleyball, swimming, ski, concert, conference
    case food, macro, cars, moto
    case fashion, lookbook, catalog, beauty

    /// Имя знака в общей библиотеке (`icons.js`).
    public var iconName: String {
        switch self {
        case .newborn: "infant"
        case .pregnancy: "pregnant"
        case .kids: "child"
        case .boudoir: "boudoir"
        case .business: "briefcase"
        case .engagement: "ring_stone"
        case .registry: "hall"
        case .church: "church"
        case .birthday: "cake_bd"
        case .jubilee: "feast"
        case .newyear: "tree"
        case .graduation: "graduation"
        case .christening: "chapel"
        case .barmitzvah: "star_david"
        case .anniversary: "rings"
        case .baby: "stroller"
        case .generations: "generations"
        case .dogs: "dog"
        case .cats: "cat"
        case .horses: "horse"
        case .stars: "stars"
        case .interior: "interior"
        case .realty: "home"
        case .sport: "runner"
        case .races: "flag_finish"
        case .olympics: "olympics"
        case .football: "ball"
        case .basketball: "basketball"
        case .volleyball: "volleyball"
        case .swimming: "swimmer"
        case .ski: "ski"
        case .concert: "mic"
        case .conference: "speaker"
        case .food: "croissant"
        case .macro: "macro"
        case .cars: "car"
        case .moto: "moto"
        case .fashion: "hanger"
        case .lookbook: "album"
        case .catalog: "doc"
        case .beauty: "makeup"
        }
    }
}

/// Папка набора референсов (веб `GENRE_TAGS`, `REF_TAGS_DEFAULT`). Свои папки,
/// набранные руками, остаются строками и в этот список не входят: чужое слово
/// честнее пустоты (итерация 28, мудборд).
public enum RefTag: String, CaseIterable, Sendable {
    case gathering, couple, bride, groom, walk, evening, details
    case celebrant, guests, table, dancing
    case allTogether, kids, parents, play
    case face, fullLength, hands, light
    case object, angles, texture, composition
    case campaign, model, product, scene
    case facade, interior, detail, wideShot
    case hero, wide, closeUp, moment
    case foreground, sky
    case frame, geometry

    /// Папки жанра, которого нет в таблице (`REF_TAGS_DEFAULT`).
    public static let defaults: [RefTag] = [.wide, .closeUp, .light, .details]

    /// Русские имена прежнего формата (`TAG_CODE`): кадр хранил папку словом,
    /// «Сборы» — это `gathering`. Порядок — порядок таблицы веба.
    public static let russianNames: [(name: String, tag: RefTag)] = [
        ("Сборы", .gathering), ("Пара", .couple), ("Невеста", .bride), ("Жених", .groom),
        ("Прогулка", .walk), ("Вечер", .evening), ("Детали", .details),
        ("Виновник", .celebrant), ("Гости", .guests), ("Стол", .table), ("Танцы", .dancing),
        ("Все вместе", .allTogether), ("Дети", .kids), ("Родители", .parents), ("Игра", .play),
        ("Лицо", .face), ("В рост", .fullLength), ("Руки", .hands), ("Свет", .light),
        ("Предмет", .object), ("Ракурсы", .angles), ("Фактура", .texture), ("Композиция", .composition),
        ("Кампания", .campaign), ("Модель", .model), ("Продукт", .product), ("Сцена", .scene),
        ("Фасад", .facade), ("Интерьер", .interior), ("Деталь", .detail), ("Общий план", .wideShot),
        ("Герой", .hero), ("Общий", .wide), ("Крупный", .closeUp), ("Момент", .moment),
        ("Передний план", .foreground), ("Небо", .sky), ("Кадр", .frame), ("Геометрия", .geometry),
    ]
}
