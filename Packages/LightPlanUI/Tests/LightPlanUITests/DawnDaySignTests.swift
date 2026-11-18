import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// 31.5б (Алексей 18.11 «Да, все «б»», DECISIONS 18.11): знак дня до полудня — по небу рассвета, после — по небу заката;
/// тревога «прогноз сменился» у утренней съёмки следит за рассветом. Прогноз: каждое утро дождь 03–09 ч (окно рассвета ±2 ч у
/// восхода ≈ 06 ч), вечер сухой, облачность 30 %. Только API, что было на `eeb05848`: на старом коде набор падает проверками.
@MainActor
struct DawnDaySignTests {

    struct MorningRain: WeatherSource {
        let first: CivilDate
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            var time: [String] = [], rain: [Double] = [], code: [Int] = []
            for k in 0..<21 {
                let d = first.adding(days: k)
                for h in 0..<24 {
                    time.append(String(format: "%04d-%02d-%02dT%02d:00", d.year, d.month, d.day, h))
                    let wet = (3...9).contains(h)
                    rain.append(wet ? 1.2 : 0); code.append(wet ? 61 : 0)
                }
            }
            let n = time.count
            return HourlyWeather(time: time, cloud: Array(repeating: 30, count: n), temperature: Array(repeating: 12, count: n),
                                 windSpeed: Array(repeating: 2, count: n), precipitation: rain, weatherCode: code)
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

    /// Москва, 20.09.2026 в `hh:mm`; съёмки 21.09 — утренняя в 06:00 (до конца утреннего золотого часа) и вечерняя в 18:00.
    static func app(at hh: Int, _ mm: Int = 0, seen: JSONValue? = nil) -> AppModel {
        var snap = Snapshot()
        snap.extra["me"] = .object(["city": .string("Москва"), "cityLat": .number(55.75), "cityLon": .number(37.62), "met": .bool(true)])
        snap.extra["zones"] = .object(["56.0,37.5": .string("Europe/Moscow")])
        func shoot(_ id: String, _ start: Int) -> Session {
            var s = Session(id: id, kind: .shoot, day: CivilDate(year: 2026, month: 9, day: 21), start: start, end: start + 120,
                            duration: 120, genre: .portrait)
            s.latitude = 55.75; s.longitude = 37.62
            return s
        }
        snap.sessions = [shoot("am", 360), shoot("pm", 1080)]
        if let seen { snap.extra["wxSeen"] = seen }
        let now = ISO8601DateFormatter().date(from: String(format: "2026-09-20T%02d:%02d:00+03:00", hh, mm))!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!, locator: Locator(),
                        geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: MorningRain(first: CivilDate(year: 2026, month: 9, day: 15)), now: { now })
    }

    @Test("лента «Света»: в 09:00 знак дня — дождь рассвета, в 15:00 — сухой закат; у всех дней разом")
    func ribbonSignFollowsNoon() async {
        let am = Self.app(at: 9), pm = Self.app(at: 15)
        await am.light.weather.settled(); await pm.light.weather.settled()
        for offset in 0...3 {
            #expect(am.light.timebar.weatherSignName(offset: offset) == "rain", "\(offset): утром знак дня — небо рассвета")
            let evening = pm.light.timebar.weatherSignName(offset: offset)
            #expect(evening != nil && evening != "rain", "\(offset): после полудня — небо заката (\(evening ?? "nil"))")
        }
        // Граница — полдень по часам места.
        let before = Self.app(at: 11, 59), after = Self.app(at: 12)
        await before.light.weather.settled(); await after.light.weather.settled()
        #expect(before.light.timebar.weatherSignName(offset: 1) == "rain")
        #expect(after.light.timebar.weatherSignName(offset: 1) != "rain")
    }

    @Test("тревога: утренняя съёмка сравнивает небо рассвета, вечерняя — заката")
    func morningShootWatchesTheDawn() async throws {
        let app = Self.app(at: 12)
        app.openCard(id: "am")
        await app.pointWeather.settled()
        let am = try #require(app.sessions.first { $0.id == "am" }), pm = try #require(app.sessions.first { $0.id == "pm" })
        let dawn = try #require(app.cardSkySnap(am)), dusk = try #require(app.cardSkySnap(pm))
        #expect(dawn.quality == .poor, "в окне рассвета дождь")
        #expect(dusk.quality != .poor, "вечер сухой")
    }

    @Test("строка тревоги утренней съёмки говорит о балле рассвета")
    func morningShootShiftSaysTheDawnScore() async throws {
        let probe = Self.app(at: 12)
        probe.openCard(id: "am")
        await probe.pointWeather.settled()
        let shoot = try #require(probe.sessions.first { $0.id == "am" })
        let now = try #require(probe.cardSkySnap(shoot))
        let score = try #require(now.sunset)
        let was = score < 50 ? score + 40 : score - 40
        let app = Self.app(at: 12, seen: .object(["am": .object(["q": .string(now.quality.rawValue), "sc": .number(Double(was))])]))
        app.openCard(id: "am")
        await app.pointWeather.settled()
        let s = try #require(app.sessions.first { $0.id == "am" })
        let line = try #require(app.cardShift(s, phase: .before))
        #expect(line.text == "Балл рассвета был \(was) из 100, стал \(score).")
    }
}

/// Новое API 31.5б: событие и небо знака дня в планировщике, правило утренней съёмки.
@MainActor
struct DawnDaySignPlannerTests {

    @Test("неделя и месяц планировщика: небо дня — рассвета до полудня, заката после")
    func plannerDaySky() async {
        let am = DawnDaySignTests.app(at: 9), pm = DawnDaySignTests.app(at: 15)
        await am.light.weather.settled(); await pm.light.weather.settled()
        let d = CivilDate(year: 2026, month: 9, day: 21)
        let fa = PlannerFacts(app: am, dark: false), fp = PlannerFacts(app: pm, dark: false)
        #expect(fa.dayEvent == .dawn && fp.dayEvent == .sunset)
        #expect(fa.daySky(d)?.quality == .poor && fa.daySky(d)?.precip == .rain)
        #expect(fa.daySky(d)?.quality.weekSignName(fa.daySky(d)?.precip) == "rain")
        #expect(fp.daySky(d)?.quality != .poor && fp.daySky(d)?.precip == nil)
        #expect(fa.daySky(d)?.quality.dot == DayQuality.poor.dot)
        #expect(fp.weather(d)?.signIconName(.sunset) == fp.weather(d)?.signIconName)
    }

    @Test("утренняя съёмка — до конца утреннего золотого часа у своего якоря")
    func shootsAtDawnRule() async throws {
        let app = DawnDaySignTests.app(at: 12)
        let am = try #require(app.sessions.first { $0.id == "am" }), pm = try #require(app.sessions.first { $0.id == "pm" })
        #expect(app.shootsAtDawn(am) && !app.shootsAtDawn(pm))
    }
}
