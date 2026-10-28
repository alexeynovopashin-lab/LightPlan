import Testing
import Foundation
@testable import LightPlanCore

/// Шаг 30б.2в-6: рассветный балл — та же формула, что закатная (`SunsetScore.score`), на ярусах облаков и влажности в час восхода
/// (слова Алексея 27.10: «та же формула в час рассвета»). Нет прогноза на этот час — `nil`, число не выдумывается.
struct SunriseScoreTests {

    private let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    private let day = CivilDate(year: 2026, month: 10, day: 25)

    /// Сутки по часам; `special` — ярусы в нужных часах, остальное — глухая облачность (балл заведомо низкий).
    private func hourly(on date: CivilDate, special: [Int: (low: Double, mid: Double, high: Double, hum: Double)], hours: ClosedRange<Int> = 0...23) -> HourlyWeather {
        let hs = Array(hours)
        func stamp(_ h: Int) -> String { String(format: "%04d-%02d-%02dT%02d:00", date.year, date.month, date.day, h) }
        let n = hs.count
        return HourlyWeather(
            time: hs.map(stamp), cloud: Array(repeating: 60, count: n),
            cloudLow: hs.map { special[$0]?.low ?? 90 }, cloudMid: hs.map { special[$0]?.mid ?? 0 }, cloudHigh: hs.map { special[$0]?.high ?? 0 },
            humidity: hs.map { special[$0]?.hum ?? 80 }, temperature: Array(repeating: 5, count: n),
            windSpeed: Array(repeating: 3, count: n), precipitation: Array(repeating: 0, count: n), weatherCode: Array(repeating: 3, count: n))
    }

    private func hours(_ date: CivilDate, _ place: Place) throws -> (rise: Int, set: Int) {
        let sun = SolarDay(date: date, place: place, time: .web)
        let r = try #require(sun.rise), s = try #require(sun.set)
        return (Int(min(23, max(0, Sky.jsRound(r / 60)))), Int(min(23, max(0, Sky.jsRound(s / 60)))))
    }

    @Test func theSunriseScoreIsTheSunsetFormulaAtTheSunriseHour() throws {
        let (rh, sh) = try hours(day, tomsk)
        let clear = (low: 0.0, mid: 45.0, high: 50.0, hum: 40.0)
        let h = hourly(on: day, special: [rh: clear])
        let d = try #require(WeatherDay.buildDays(from: h, place: tomsk).days[day])
        #expect(d.sunrise == SunsetScore.score(low: 0, mid: 45, high: 50, humidity: 40) && d.sunrise == 100, "ясный рассвет: \(String(describing: d.sunrise))")
        #expect(d.sunset == SunsetScore.score(low: 90, mid: 0, high: 0, humidity: 80), "закат — на своём часе, глухом: \(String(describing: d.sunset))")
        #expect(d.sunrise != d.sunset && rh != sh)
    }

    @Test func theAirOfTheSunriseHourCorrectsItLikeTheSunsets() throws {
        let (rh, _) = try hours(day, tomsk)
        let h = hourly(on: day, special: [rh: (low: 0, mid: 45, high: 50, hum: 40)])
        let clean = try #require(WeatherDay.buildDays(from: h, place: tomsk).days[day]?.sunrise)
        let smoky = [day: [rh: AirSample(aod: 0.8, dust: nil)]]
        let withAir = try #require(WeatherDay.buildDays(from: h, place: tomsk, air: smoky).days[day]?.sunrise)
        #expect(withAir == SunsetScore.score(low: 0, mid: 45, high: 50, humidity: 40, air: AirSample(aod: 0.8, dust: nil)) && withAir < clean, "дымка гасит рассвет: \(withAir) против \(clean)")
    }

    @Test func noForecastForTheHourMeansNoNumber() throws {
        // Прогноз только с 12 часов: до восхода (8–9) дальше трёх часов — часа нет, числа нет; закат при этом есть.
        let h = hourly(on: day, special: [:], hours: 12...23)
        let d = try #require(WeatherDay.buildDays(from: h, place: tomsk).days[day])
        #expect(d.sunrise == nil, "часа восхода в прогнозе нет: \(String(describing: d.sunrise))")
        #expect(d.sunset != nil)
    }

    @Test func polarDaysHaveNoSunrise() throws {
        let tromso = Place(latitude: 69.6496, longitude: 18.956, zone: ZoneID("Europe/Oslo")!)
        let june = CivilDate(year: 2026, month: 6, day: 21), dec = CivilDate(year: 2026, month: 12, day: 21)
        for date in [june, dec] {
            let d = try #require(WeatherDay.buildDays(from: hourly(on: date, special: [:]), place: tromso).days[date])
            #expect(d.sunrise == nil, "\(date): полярные сутки — восхода нет")
        }
    }

    @Test func aMockDayCarriesNoSunriseNumber() {
        // Выдумка (`MockWeather`) закатного балла не несёт, рассветного — тем более.
        let mock = MockWeather.day(for: day)
        #expect(mock.sunrise == nil && mock.sunset == nil && !mock.real)
    }
}
