import Foundation
import Testing
import LightPlanCore
@testable import LightPlanData

/// Ответы `CLGeocoder` 25.09.2026: у всех пяти точек Крыма `UA` / «Украина» при любой
/// локали (ru_RU, ru_US, en_US, en_RU) — снимок замера, а не эталон Apple.
private let crimea: [(String, Double, Double)] = [
    ("Ялта", 44.4952, 34.1663), ("Симферополь", 44.9521, 34.1024), ("Севастополь", 44.6166, 33.5254),
    ("Керчь", 45.3562, 36.4674), ("Евпатория", 45.1904, 33.3672),
]

struct CrimeaCountryTests {
    private func c(_ p: (String, Double, Double)) -> GeoCoordinate { GeoCoordinate(latitude: p.1, longitude: p.2) }

    @Test func russianRegionSeesRussiaInCrimea() {
        for p in crimea {
            #expect(CrimeaCountry.country("Украина", isoCode: "UA", at: c(p), deviceRegion: "RU") == "Россия", "\(p.0)")
        }
    }

    @Test func otherRegionsKeepApplesAnswer() {
        for region in ["US", "DE", nil] as [String?] {
            for p in crimea {
                #expect(CrimeaCountry.country("Украина", isoCode: "UA", at: c(p), deviceRegion: region) == "Украина", "\(p.0) \(region ?? "nil")")
            }
        }
    }

    @Test func answerLanguageFollowsTheLocale() {
        let yalta = GeoCoordinate(latitude: 44.4952, longitude: 34.1663)
        #expect(CrimeaCountry.country("Ukraine", isoCode: "UA", at: yalta, deviceRegion: "RU",
                                      locale: Locale(identifier: "en_US")) == "Russia")
    }

    @Test func outsideCrimeaNothingChanges() {
        let outside: [(String, Double, Double, String, String)] = [
            ("Киев", 50.4501, 30.5234, "UA", "Украина"),
            ("Геническ", 46.17, 34.80, "UA", "Украина"),          // за перешейком, Херсонская область
            ("Херсон", 46.6354, 32.6169, "UA", "Украина"),
            ("Тамань", 45.21, 36.72, "RU", "Россия"),             // за проливом
            ("Краснодар", 45.0355, 38.9753, "RU", "Россия"),
        ]
        for p in outside {
            let got = CrimeaCountry.country(p.4, isoCode: p.3, at: GeoCoordinate(latitude: p.1, longitude: p.2), deviceRegion: "RU")
            #expect(got == p.4, "\(p.0)")
        }
    }

    @Test func onlyWithUkrainianAnswer() {
        // Второй замок: точка в контуре, но Apple ответил не «UA» — не трогаем.
        let yalta = GeoCoordinate(latitude: 44.4952, longitude: 34.1663)
        #expect(CrimeaCountry.country("Россия", isoCode: "RU", at: yalta, deviceRegion: "RU") == "Россия")
        #expect(CrimeaCountry.country("Турция", isoCode: "TR", at: yalta, deviceRegion: "RU") == "Турция")
    }
}
