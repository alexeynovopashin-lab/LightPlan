import Testing
import Foundation
@testable import LightPlanUI
import LightPlanMapCanvas
import LightPlanCore
import LightPlanData
import LightPlanDomain
import LightPlanTimeline

/// 28ж, слово Алексея 02.10: «без имитации». Пока настоящего прогноза нет — на всех экранах, что читают
/// погоду, её нет совсем (ни облачности, ни градусов, ни знака, ни оценки заката); астрономия остаётся.
/// Смотрим на данные, не на строки экрана.
@MainActor
struct NoMadeUpWeatherTests {

    private struct Offline: Error {}
    private struct NoWeather: WeatherSource {
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }

    /// Прогноз на 5 суток назад и 16 вперёд от «сейчас» (окно Open-Meteo) — ровно этот набор дней.
    private struct Window: WeatherSource {
        let first: Date, days: Int
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Barnaul")!
            var time: [String] = []
            for d in 0..<days {
                let day = cal.date(byAdding: .day, value: d, to: first)!
                let c = cal.dateComponents([.year, .month, .day], from: day)
                for h in 0..<24 { time.append(String(format: "%04d-%02d-%02dT%02d:00", c.year!, c.month!, c.day!, h)) }
            }
            let n = time.count
            return HourlyWeather(time: time, cloud: Array(repeating: 30, count: n), temperature: Array(repeating: 12, count: n),
                                 windSpeed: Array(repeating: 2, count: n), precipitation: Array(repeating: 0, count: n),
                                 weatherCode: Array(repeating: 0, count: n))
        }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { [:] }
    }

    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup { func cities(matching query: String) async throws -> [CityHit] { [] } }
    private final class Locator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    private let barnaul = TimeZone(identifier: "Asia/Barnaul")!
    private let now = ISO8601DateFormatter().date(from: "2026-09-23T13:00:00+07:00")!

    private func app(_ source: any WeatherSource) -> AppModel {
        var snap = Snapshot()
        snap.extra["me"] = .object(["city": .string("Барнаул"), "cityLat": .number(53.3548), "cityLon": .number(83.7698), "met": .bool(true)])
        snap.extra["zones"] = .object(["53.5,84.0": .string("Asia/Barnaul")])
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: barnaul, locator: Locator(),
                        geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: source, now: { [now] in now })
    }

    private func facts(_ app: AppModel) -> PlannerFacts { PlannerFacts(app: app, dark: false) }

    // MARK: - Прогноза нет вовсе

    @Test func withoutAForecastEveryReaderGetsNothing() async {
        let app = app(NoWeather())
        await app.light.weather.settled()
        let today = app.today
        #expect(app.light.weather.status == .unavailable)
        let f = facts(app)
        for offset in -8...25 {
            let d = today.adding(days: offset)
            #expect(app.light.weather.day(for: d) == nil, "\(offset): хранилище отдало день")
            #expect(f.weather(d) == nil, "\(offset): планировщик получил погоду")
            #expect(f.temp(d) == nil, "\(offset): планировщик получил градусы")
            #expect(app.light.timebar.weatherSignName(offset: offset) == nil, "\(offset): барабан нарисовал знак")
        }
        #expect(f.forecastNote == "Прогноз недоступен")
    }

    @Test func theFormWindowIsAstronomicalAndTheWishesAreSilentWithoutAForecast() async {
        let app = app(NoWeather())
        await app.light.weather.settled()
        let day = app.today.adding(days: 1)
        let sun = SolarDay(date: day, place: app.place.place)
        let window = app.formLight(on: day)
        #expect(window?.poor != true, "«плохо» — это суждение о погоде, а погоды нет")
        #expect(window?.dawn != true)
        #expect(window?.start == sun.goldenB && window?.end == sun.blueB, "окно — вечернее золотой час…синий, по солнцу")
        #expect(app.wishSky(day).quality == nil)
        #expect(app.wishSky(day).sunsetScore == nil)
    }

    // MARK: - Прогноз есть: свой день виден, чужой — нет

    @Test func aForecastShowsItsOwnDaysAndNothingBeyondTheWindow() async {
        let first = Calendar(identifier: .gregorian).date(byAdding: .day, value: -5, to: now)!
        let app = app(Window(first: first, days: 21))        // 5 назад + сегодня + 15 вперёд = 21 суток
        await app.light.weather.settled()
        let today = app.today
        #expect(app.light.weather.status == .live(.direct))
        let f = facts(app)
        for offset in -5...15 {
            let d = today.adding(days: offset)
            #expect(app.light.weather.day(for: d) != nil, "\(offset): день из прогноза пропал")
            #expect(f.temp(d) != nil)
            #expect(app.light.timebar.weatherSignName(offset: offset) != nil)
        }
        for offset in [-6, -9, 16, 17, 40] {
            let d = today.adding(days: offset)
            #expect(app.light.weather.day(for: d) == nil, "\(offset): день вне окна получил погоду")
            #expect(f.weather(d) == nil && f.temp(d) == nil)
            #expect(app.light.timebar.weatherSignName(offset: offset) == nil)
        }
    }
}
