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

/// `CLGeocoder` вместо Nominatim с `featuretype=settlement` (веб): у Apple нет фильтра «только населённые
/// пункты». Улица, кофейня, гора отбрасываются; метка без `locality` проходит, только если названа как набрано
/// (Токио, Бали, остров: у Apple у них нет города, замер 14.11.2026, 30и.1).
///
/// 30и.12: спрашивает тем же путём, что «Где снимаем» (`ApplePlaceSearch.marks`): запасной вопрос латиницей,
/// названные как набрано — первыми, лечение смешанных букв, два знака для 東京.
public struct AppleCityLookup: CityLookup {
    public let locale: Locale

    public let deviceRegion: String?

    public init(locale: Locale = Locale(identifier: "ru_RU"),
                deviceRegion: String? = Locale.current.region?.identifier) {
        self.locale = locale; self.deviceRegion = deviceRegion
    }

    public func cities(matching query: String) async throws -> [CityHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard PlaceQuery.isAskable(q) else { return [] }
        let marks = try await ApplePlaceSearch.marks(matching: q, locale: locale)
        return Self.hits(marks, query: q, deviceRegion: deviceRegion, locale: locale)
    }

    /// Разбор меток отдельно от геокодера — его проверяют тесты.
    static func hits(_ marks: [PlaceMark], query: String, deviceRegion: String?, locale: Locale) -> [CityHit] {
        var seen = Set<String>()
        var out: [CityHit] = []
        let latin = PlaceQuery.transliteration(of: query)
        for m in marks {
            let locality = m.locality.map(PlaceQuery.cleaned)
            // Без города метка — город, только если её имя и есть набранное (или его латиница).
            let named = m.name.map(PlaceQuery.cleaned)
            // …или если она сама область/остров: имя равно региону («Tokyo» отвечает именем «Токио», 30и.12).
            let asked = named.map { n in
                PlaceQuery.folded(n) == PlaceQuery.folded(query)
                    || latin.map { PlaceQuery.folded(n) == PlaceQuery.folded($0) } == true
                    || m.region.map { PlaceQuery.folded($0) == PlaceQuery.folded(n) } == true
            } ?? false
            guard let name = locality ?? (asked ? named : nil), !name.isEmpty else { continue }
            let coord = m.coordinate
            let country = CrimeaCountry.country(m.country, isoCode: m.isoCode, at: coord,
                                                deviceRegion: deviceRegion, locale: locale)
            let area = [m.region.map(PlaceQuery.cleaned), country].compactMap { $0 }.filter { $0 != name }.joined(separator: ", ")
            guard seen.insert(name + "|" + area).inserted else { continue }
            out.append(CityHit(name: name, area: area, countryCode: m.isoCode?.lowercased(), coordinate: coord))
            if out.count == 5 { break }
        }
        return out
    }
}
