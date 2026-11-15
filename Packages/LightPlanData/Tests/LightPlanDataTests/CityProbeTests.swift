import Foundation
import Testing
import CoreLocation
@testable import LightPlanData

/// 30и.12: живой замер таблицы запросов (сеть, Apple). Только при LP_CITY_PROBE=1.
struct CityProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LP_CITY_PROBE"] != nil))
    func table() async throws {
        let loc = Locale(identifier: "ru_RU")
        var before = 0, after = 0
        let qs = ["Токио", "Tokyo", "東京", "Бали", "Bali", "Нью-Йорк", "Барнаул", "Томск", "Париж", "Санкт-Петербург"]
        for q in qs {
            let old = try? await CLGeocoder().geocodeAddressString(q, in: nil, preferredLocale: loc).compactMap { $0.locality }
            let marks = (try? await ApplePlaceSearch.marks(matching: q, locale: loc)) ?? []
            let new = AppleCityLookup.hits(marks, query: q, deviceRegion: "RU", locale: loc)
            if !(old ?? []).isEmpty { before += 1 }
            if !new.isEmpty { after += 1 }
            print("PROBE \(q): before=\(old ?? []) after=\(new.map { $0.name + " / " + $0.area })")
        }
        print("PROBE found before=\(before) after=\(after) of \(qs.count)")
    }
}
