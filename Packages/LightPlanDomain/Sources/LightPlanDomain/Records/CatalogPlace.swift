import Foundation

/// Место из общего списка студий (30е.1): запись отдаваемого файла ядра Event OS,
/// формат версии 1 (`event_os:16_Place_Registry.md`, «Отдаваемый файл»). Приложение
/// только читает её: карточка фотографа — копия, сделанная при выборе, и живёт сама
/// (DECISIONS 05.11 «Каталог и фантомы»). Людей, телефонов, цен в файле нет.
public struct CatalogPlace: Sendable, Hashable, Identifiable {
    /// Степень проверки (`verification`). Непроверенное не выдаётся за подтверждённое.
    public enum Check: String, Sendable, Hashable {
        /// «проверена человеком».
        case verified
        /// «из сбора».
        case collected
        /// «спорная» — возможный дубль или спорный адрес; показываем, не прячем.
        case disputed
    }

    /// Зал места: номер внутри места и название (`halls[]`).
    public struct Hall: Sendable, Hashable {
        public var number: Int
        public var name: String
        public init(number: Int, name: String) { self.number = number; self.name = name }
    }

    /// `placeId` — номер места `pl…`; ложится в `Studio.catalogId`.
    public var id: String
    /// `name` — текущее название.
    public var name: String
    /// `address`; пусто — адрес при сборе не найден.
    public var address: String
    /// `city`.
    public var city: String
    /// `timezone` (IANA) или `nil`.
    public var timezone: String?
    /// `halls` без архивных. Пусто — один зал с названием студии (правило 04.11).
    public var halls: [Hall]
    /// `life == "закрыта"`: в выборе новой студии скрыта.
    public var closed: Bool
    public var check: Check
    /// `mergedInto` — склеенный дубль: живой номер места.
    public var mergedInto: String?

    public init(id: String, name: String, address: String = "", city: String, timezone: String? = nil,
                halls: [Hall] = [], closed: Bool = false, check: Check = .collected, mergedInto: String? = nil) {
        self.id = id; self.name = name; self.address = address; self.city = city; self.timezone = timezone
        self.halls = halls; self.closed = closed; self.check = check; self.mergedInto = mergedInto
    }
}

/// Весь общий список: шапка файла и места по возрастанию номера.
public struct PlaceCatalog: Sendable, Equatable {
    /// `etag` — растёт с каждым изменением реестра.
    public var etag: Int
    /// `asOf` — день сборки файла.
    public var asOf: String
    public var places: [CatalogPlace]

    public init(etag: Int, asOf: String, places: [CatalogPlace]) {
        self.etag = etag; self.asOf = asOf; self.places = places
    }

    /// Место по номеру; склеенный дубль ведёт на живой номер (не дальше пяти шагов).
    public func place(_ id: String) -> CatalogPlace? {
        var key = id
        for _ in 0..<5 {
            guard let p = places.first(where: { $0.id == key }) else { return nil }
            guard let next = p.mergedInto, next != key else { return p }
            key = next
        }
        return nil
    }
}
