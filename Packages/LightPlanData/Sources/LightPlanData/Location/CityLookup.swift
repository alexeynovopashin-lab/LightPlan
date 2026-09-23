import Foundation
import CoreLocation

/// Подсказка города: имя, где он, страна и точка (`cityHints` веба).
public struct CityHit: Sendable, Hashable {
    public let name: String
    /// «Томская область, Россия» — чтобы отличить Троицк от Троицка.
    public let area: String
    /// Две буквы ISO, строчными (`country_code` Nominatim).
    public let countryCode: String?
    public let coordinate: GeoCoordinate

    public init(name: String, area: String, countryCode: String?, coordinate: GeoCoordinate) {
        self.name = name; self.area = area; self.countryCode = countryCode; self.coordinate = coordinate
    }
}

/// Прямой геокодер за протоколом: приложение говорит с Apple, тесты — с записью.
public protocol CityLookup: Sendable {
    /// До пяти городов по набранной строке. Пустой ответ — не сбой.
    func cities(matching query: String) async throws -> [CityHit]
}

/// `CLGeocoder` вместо Nominatim с `featuretype=settlement` (веб): у Apple
/// нет фильтра «только населённые пункты», поэтому ответ без `locality`
/// (улица, гора, озеро) отбрасывается — спрашивают город, а не кофейню.
public struct AppleCityLookup: CityLookup {
    public let locale: Locale

    public init(locale: Locale = Locale(identifier: "ru_RU")) { self.locale = locale }

    public func cities(matching query: String) async throws -> [CityHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { return [] }
        let marks = try await CLGeocoder().geocodeAddressString(q, in: nil, preferredLocale: locale)
        var seen = Set<String>()
        return marks.compactMap { p -> CityHit? in
            guard let name = p.locality, let loc = p.location else { return nil }
            let area = [p.administrativeArea, p.country].compactMap { $0 }.filter { $0 != name }.joined(separator: ", ")
            guard seen.insert(name + "|" + area).inserted else { return nil }
            return CityHit(name: name, area: area, countryCode: p.isoCountryCode?.lowercased(),
                           coordinate: GeoCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude))
        }.prefix(5).map { $0 }
    }
}
