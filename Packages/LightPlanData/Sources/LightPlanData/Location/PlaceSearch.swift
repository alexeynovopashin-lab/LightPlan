import Foundation
import CoreLocation

/// Ответ поиска места по названию (`searchPlace` веба): имя, где оно, точка.
public struct PlaceHit: Sendable, Hashable {
    public let name: String
    /// «Томск, Томская область» — две части адреса после имени, как у веба.
    public let area: String
    public let coordinate: GeoCoordinate

    public init(name: String, area: String, coordinate: GeoCoordinate) {
        self.name = name; self.area = area; self.coordinate = coordinate
    }
}

/// Поиск места листа «Где снимаем», путь «Место»: человек думает «Лагерный
/// сад», а не координатами. В отличие от `CityLookup`, отвечает чем угодно —
/// сквер, улица, дом, — а не только городом.
public protocol PlaceSearch: Sendable {
    /// До шести мест по набранной строке. Пустой ответ — не сбой.
    func places(matching query: String) async throws -> [PlaceHit]
}

/// `CLGeocoder` вместо Nominatim `search` веба — тот же геокодер, что у
/// `AppleCityLookup`, без фильтра «только город». Имя — `name` метки (у
/// сквера — его название, у дома — улица и номер), область — город и регион.
public struct ApplePlaceSearch: PlaceSearch {
    public let locale: Locale

    public init(locale: Locale = Locale(identifier: "ru_RU")) { self.locale = locale }

    public func places(matching query: String) async throws -> [PlaceHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { return [] }
        let marks = try await CLGeocoder().geocodeAddressString(q, in: nil, preferredLocale: locale)
        return Self.hits(marks.compactMap { p in
            p.location.map { (name: p.name, locality: p.locality, region: p.administrativeArea,
                              coordinate: GeoCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) }
        })
    }

    /// Разбор меток отдельно от геокодера — его проверяют тесты.
    static func hits(_ marks: [(name: String?, locality: String?, region: String?, coordinate: GeoCoordinate)]) -> [PlaceHit] {
        var seen = Set<String>()
        var out: [PlaceHit] = []
        for m in marks {
            guard let name = (m.name ?? m.locality)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
            let area = [m.locality, m.region].compactMap { $0 }.filter { !$0.isEmpty && $0 != name }.joined(separator: ", ")
            guard seen.insert(name + "|" + area).inserted else { continue }
            out.append(PlaceHit(name: name, area: area, coordinate: m.coordinate))
            if out.count == 6 { break }
        }
        return out
    }
}
