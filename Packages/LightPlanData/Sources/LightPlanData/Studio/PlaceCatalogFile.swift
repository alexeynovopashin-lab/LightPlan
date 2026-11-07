import Foundation
import LightPlanDomain

/// Откуда приходит общий список студий (30е.1). Сейчас — копия файла в сборке
/// (`BundledPlaceCatalog`), на закрытый тест; потом сервер BroniOS (DECISIONS 05.11
/// «С сервера BroniOS»): новый источник отдаёт те же байты формата 1, экран не меняется.
public protocol PlaceCatalogSource: Sendable {
    /// Байты отдаваемого файла или `nil`, если списка нет. Не бросает: без списка
    /// приложение работает как раньше.
    func data() async -> Data?
}

public extension PlaceCatalogSource {
    /// Список, прочитанный из источника; `nil` — нет файла или он не того формата.
    func load() async -> PlaceCatalog? {
        guard let d = await data() else { return nil }
        return PlaceCatalogFile.decode(d)
    }
}

/// Файл `places_served.json` в приложении. Кладёт его шаг сборки
/// (`Tools/places_served.sh` из `build_stamp.sh`): самый свежий
/// `ws:20_shared/places_served_*.json`. В git файла нет (`.gitignore`), так что
/// сборка из чистого репозитория — без списка.
public struct BundledPlaceCatalog: PlaceCatalogSource {
    public static let fileName = "places_served"
    let bundle: Bundle

    public init(bundle: Bundle = .main) { self.bundle = bundle }

    public func data() async -> Data? {
        guard let url = bundle.url(forResource: Self.fileName, withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }
}

/// Готовые байты: тесты и кадры.
public struct FixedPlaceCatalog: PlaceCatalogSource {
    let bytes: Data?
    public init(_ bytes: Data?) { self.bytes = bytes }
    public func data() async -> Data? { bytes }
}

/// Отдаваемый файл ядра, формат версии 1 (`event_os:16_Place_Registry.md`,
/// «Отдаваемый файл: формат версии 1»). Читаем только то, что нужно выбору студии;
/// `names`, `links`, `catalog`, `note`, `movedTo`, `updatedAt` — для 30е.2.
public enum PlaceCatalogFile {
    /// Формат, который приложение понимает. Другой номер — как «списка нет».
    public static let format = 1

    struct Head: Decodable {
        let format: Int
        let etag: Int?
        let asOf: String?
        let places: [Place]
    }

    struct Place: Decodable {
        let placeId: String
        let name: String?
        let address: String?
        let city: String?
        let timezone: String?
        let halls: [Hall]?
        let life: String?
        let verification: String?
        let mergedInto: String?
    }

    struct Hall: Decodable {
        let number: Int?
        let name: String?
        let archived: String?
    }

    /// Только номер формата: чтобы чужой формат не падал на разборе полей.
    struct Version: Decodable { let format: Int? }

    public static func decode(_ data: Data) -> PlaceCatalog? {
        guard (try? JSONDecoder().decode(Version.self, from: data))?.format == format,
              let head = try? JSONDecoder().decode(Head.self, from: data) else { return nil }
        let places = head.places.compactMap(place)
        return PlaceCatalog(etag: head.etag ?? 0, asOf: head.asOf ?? "", places: places)
    }

    /// Запись без номера `pl…` или без названия в выбор не идёт.
    static func place(_ p: Place) -> CatalogPlace? {
        let name = (p.name ?? "").trimmingCharacters(in: .whitespaces)
        guard p.placeId.hasPrefix("pl"), !name.isEmpty else { return nil }
        let halls = (p.halls ?? []).enumerated().compactMap { i, h -> CatalogPlace.Hall? in
            guard h.archived == nil, let n = h.name?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return nil }
            return CatalogPlace.Hall(number: h.number ?? i + 1, name: n)
        }
        let check: CatalogPlace.Check = switch p.verification {
        case "проверена человеком": .verified
        case "спорная": .disputed
        default: .collected
        }
        let tz = p.timezone.flatMap { TimeZone(identifier: $0) != nil ? $0 : nil }
        return CatalogPlace(id: p.placeId, name: name, address: p.address ?? "", city: p.city ?? "",
                            timezone: tz, halls: halls, closed: p.life == "закрыта", check: check,
                            mergedInto: p.mergedInto)
    }
}
