import Testing
import Foundation
@testable import LightPlanCore

/// 31.6, ядро — то, что требует нового API (на `c7b1256b` не собирается): тренд облаков к окну рассвета, «после рассвета» AR.
struct DawnRestCoreNewTests {

    /// Облачность часа = 10 × час: тренд рассвета — часы вокруг восхода, у заката — 16…21, как было.
    static func hourly(_ d: CivilDate) -> HourlyWeather {
        var time: [String] = [], cloud: [Double] = []
        for h in 0..<24 {
            time.append(String(format: "%04d-%02d-%02dT%02d:00", d.year, d.month, d.day, h))
            cloud.append(Double(h * 4))
        }
        let n = time.count
        return HourlyWeather(time: time, cloud: cloud, temperature: Array(repeating: 5, count: n), windSpeed: Array(repeating: 2, count: n),
                             precipitation: Array(repeating: 0, count: n), weatherCode: Array(repeating: 0, count: n))
    }

    @Test("п. 3: тренд к рассвету — шесть часов вокруг часа восхода (h − 3 … h + 2), к закату — 16…21")
    func dawnTrendIsAroundTheSunrise() throws {
        let place = DawnRestCoreTests.tomsk, d = DawnRestCoreTests.date
        let w = try #require(WeatherDay.buildDays(from: Self.hourly(d), place: place, time: .iau).days[d])
        let h = Int(Sky.jsRound(try #require(SolarDay(date: d, place: place).rise) / 60))
        #expect(h == 9)
        #expect(w.trend(.dawn) == (6...11).map { Double($0 * 4) })
        #expect(w.trend(.sunset) == (16...21).map { Double($0 * 4) })
        #expect(w.trend == w.trend(.sunset))
    }

    @Test("п. 17: «после рассвета N» до конца утреннего золотого часа, потом «до заката»")
    func arAfterSunrise() throws {
        let s = DawnRestCoreTests.sun
        let rise = try #require(s.rise), goldenA = try #require(s.goldenA)
        #expect(SunTrack.note(at: rise + 20, solar: s) == .afterSunrise(20))
        #expect(SunTrack.note(at: goldenA - 1, solar: s) == .afterSunrise(goldenA - 1 - rise))
        #expect(SunTrack.note(at: rise - 5, solar: s) == .untilSunrise(5))
    }

    @Test("п. 18: ночью — «До синего часа»")
    func nightIsUntilBlueHour() throws {
        let s = DawnRestCoreTests.sun
        #expect(s.nextLight(at: 60).key == .toBlue)
    }
}
