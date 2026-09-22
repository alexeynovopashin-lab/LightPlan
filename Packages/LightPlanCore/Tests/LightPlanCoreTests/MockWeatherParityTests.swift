import Testing
import Foundation
@testable import LightPlanCore

/// Сверка выдумки офлайн с вебом (итерация 10): `qualityOf`, `dayWeather` —
/// чистая функция даты, `mulberry32` порт бит в бит. Эталон —
/// `Fixtures/mock_weather.json`.
struct MockWeatherParityTests {

    private static func date(_ iso: String) -> CivilDate {
        let p = iso.split(separator: "-").map { Int($0)! }
        return CivilDate(year: p[0], month: p[1], day: p[2])
    }

    @Test("mock_weather.json: категория, облачность, температура, ветер, тренд — строго")
    func mock() throws {
        let f = try ParityFixtures.load("mock_weather.json", as: ParityFixtures.MockWeatherFile.self)
        var failures = 0
        var realCount = 0
        for row in f.days {
            let day = MockWeather.day(for: Self.date(row.date))
            if day.real { realCount += 1 }
            let sameQuality = day.quality.rawValue == row.q
            let sameCloud = day.cloud == row.cloud
            let sameTemp = day.temperatureBase == row.tempBase
            let sameWind = day.wind == row.wind
            let sameTrend = day.trend == row.trend
            if !(sameQuality && sameCloud && sameTemp && sameWind && sameTrend) {
                failures += 1
                if failures <= 20 {
                    Issue.record("""
                        \(row.date): JS q=\(row.q) cloud=\(row.cloud) temp=\(row.tempBase) wind=\(row.wind) trend=\(row.trend); \
                        Swift q=\(day.quality.rawValue) cloud=\(day.cloud) temp=\(day.temperatureBase) wind=\(day.wind) trend=\(day.trend)
                        """)
                }
            }
        }
        print("mock: \(f.days.count) суток")
        #expect(realCount == 0, "выдумка не должна называть себя настоящим прогнозом")
        #expect(failures == 0, "\(failures) расхождений с вебом")
    }
}
