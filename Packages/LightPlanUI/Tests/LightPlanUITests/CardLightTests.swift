import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 26, шаг 3: блоки условий карточки — свет (золотой час только у
/// «Заката», своя строка у «Звёзд» и «Луны»), погода по прогнозу точки
/// съёмки, честная строка без прогноза, строка под листом, сдвиг времени,
/// «Золотой» на ленте.
@MainActor
struct CardLightTests {

    /// Небо суток одно на все часы: дождь (код 61, облачность 95) или ясно.
    private struct SkySource: WeatherSource {
        let rain: Bool
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            var time: [String] = []
            let d0 = CivilDate(year: 2026, month: 9, day: 15)
            for k in 0..<21 {
                let d = d0.adding(days: k)
                for h in 0..<24 { time.append(String(format: "%04d-%02d-%02dT%02d:00", d.year, d.month, d.day, h)) }
            }
            let n = time.count
            return HourlyWeather(time: time, cloud: Array(repeating: rain ? 95 : 5, count: n),
                                 temperature: Array(repeating: 12, count: n), windSpeed: Array(repeating: 2, count: n),
                                 precipitation: Array(repeating: rain ? 3 : 0, count: n),
                                 weatherCode: Array(repeating: rain ? 61 : 0, count: n))
        }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { [:] }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    /// Москва, 21.09 18:00–20:00 (закат около 18:50), с местом.
    private static func shoot(_ id: String, wishes: [Wish], day: Int = 21, month: Int = 9,
                              start: Int = 1080, end: Int = 1200, place: Bool = true) -> Session {
        var s = Session(id: id, kind: .shoot, day: CivilDate(year: 2026, month: month, day: day),
                        start: start, end: end, duration: end - start, genre: .portrait)
        s.wishes = wishes
        if place { s.latitude = 55.75; s.longitude = 37.62 }
        return s
    }

    private func model(_ sessions: [Session], rain: Bool) -> AppModel {
        var snap = Snapshot()
        snap.sessions = sessions
        let now = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00+03:00")!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: SkySource(rain: rain), now: { now })
    }

    private func open(_ app: AppModel, _ id: String) async -> Session {
        app.openCard(id: id)
        await app.pointWeather.settled()
        return app.sessions.first { $0.id == id }!
    }

    // MARK: - Свет

    /// Закат под дождём: терракотовая реплика по прогнозу точки съёмки и
    /// строка под листом.
    @Test func sunsetUnderRainSaysBadSkyAndWarns() async {
        let app = model([Self.shoot("a", wishes: [.sunset])], rain: true)
        let s = await open(app, "a")
        let says = app.cardSays(s, phase: .before)
        #expect(says.first?.kind == .golden && says.first?.bad == true)
        #expect(says.first?.text.contains("дождь") == true)
        #expect(app.cardBlocks(s, phase: .before).contains(.light))
        #expect(app.cardWishMissed(s, phase: .before) == "Ожидался закат. Прогноз на этот день — дождь.")
    }

    /// «Звёзды» без «Заката»: о золотом часе ни слова, своя строка есть.
    @Test func starsGetOwnLineNotGolden() async {
        let app = model([Self.shoot("a", wishes: [.stars], start: 1320, end: 1500)], rain: false)
        let s = await open(app, "a")
        let says = app.cardSays(s, phase: .before)
        #expect(!says.contains { $0.kind == .golden })
        #expect(says.contains { $0.kind == .stars && $0.icon == "stars" })
        #expect(!says.contains { $0.text.contains("Золотой час") })
    }

    @Test func moonGetsOwnLine() async {
        let app = model([Self.shoot("a", wishes: [.moon])], rain: false)
        let s = await open(app, "a")
        let moon = app.cardSays(s, phase: .before).first { $0.kind == .moon }
        #expect(moon != nil)
        #expect(moon?.text.contains("Луна") == true || moon?.text.contains("луна") == true)
    }

    /// После съёмки свет молчит.
    @Test func lightSilentAfter() async {
        let app = model([Self.shoot("a", wishes: [.sunset, .stars, .moon])], rain: false)
        let s = await open(app, "a")
        #expect(app.cardSays(s, phase: .after).isEmpty)
        #expect(!app.cardBlocks(s, phase: .after).contains(.light))
    }

    // MARK: - Погода

    /// Портрет 18:00–20:00: две колонки часов → по краям час до и после.
    @Test func weatherColumnsFromPointForecast() async {
        let app = model([Self.shoot("a", wishes: [])], rain: true)
        let s = await open(app, "a")
        guard case .columns(let cols)? = app.cardWeather(s, phase: .before) else {
            Issue.record("ждали колонки"); return
        }
        #expect(cols.map(\.minute) == [1020, 1080, 1200, 1260])
        #expect(cols.map(\.aside) == [true, false, false, true])
        #expect(cols.allSatisfy { $0.sky == "rain" && $0.temp == "12°" && $0.cloud == "95%" })
    }

    /// До съёмки дальше, чем видит прогноз: честная строка, погода не
    /// выдумывается, свет не говорит «прогноз обещает дождь».
    @Test func farShootHasNoWeatherAndNoRainClaims() async {
        let app = model([Self.shoot("a", wishes: [.sunset], day: 20, month: 10)], rain: true)
        let s = await open(app, "a")
        #expect(app.cardWeather(s, phase: .before) == .noData)
        #expect(!app.cardSays(s, phase: .before).contains { $0.bad })
        #expect(app.cardWishMissed(s, phase: .before) == nil)
        #expect(app.pointWeather.states.isEmpty, "вне окна прогноза сеть не спрашивается")
    }

    /// Запись без места прогноза не ждёт: блока погоды нет.
    @Test func noPlaceNoWeatherBlock() async {
        let app = model([Self.shoot("a", wishes: [], place: false)], rain: true)
        let s = await open(app, "a")
        #expect(app.cardWeather(s, phase: .before) == nil)
        #expect(!app.cardBlocks(s, phase: .before).contains(.weather))
    }

    /// Пожелание совпало с прогнозом — строка под листом молчит.
    @Test func wishMatchingForecastIsSilent() async {
        let app = model([Self.shoot("a", wishes: [.rain])], rain: true)
        let s = await open(app, "a")
        #expect(app.cardWishMissed(s, phase: .before) == nil)
    }

    // MARK: - Сдвиг времени и «Золотой»

    @Test func movedLineAndCross() async {
        var r = Self.shoot("a", wishes: [])
        r.dayMoved = DayMoved(start: 1050, end: 1170)
        let app = model([r], rain: false)
        let s = await open(app, "a")
        let m = app.cardMoved(s)
        // Между временем и тире — неразрывные пробелы, как у веба (`fmtRange`).
        #expect(m?.from == "17:30\u{00A0}–\u{00A0}19:30" && m?.to == "18:00\u{00A0}–\u{00A0}20:00")
        app.clearDayMoved(id: "a")
        #expect(app.cardMoved(app.sessions.first { $0.id == "a" }!) == nil)
    }

    /// Прогулка 16:00 и ужин 20:30, закат в пожеланиях: начало золотого часа
    /// между ними, ни одна точка не ближе 20 минут — на ленте «Золотой».
    @Test func goldenOnLane() async {
        var r = Self.shoot("a", wishes: [.sunset], start: 960, end: 1260)
        r.route = [RoutePoint(start: 960, name: "Прогулка"), RoutePoint(start: 1230, name: "Ужин")]
        let app = model([r], rain: false)
        let s = await open(app, "a")
        let g = app.laneGolden(s, route: s.timedRoute, phase: .before)
        #expect(g != nil)
        #expect((g ?? 0) > 960 && (g ?? 0) < 1230)
        // Без «Заката» — нет.
        var noSun = s
        noSun.wishes = [.stars]
        #expect(app.laneGolden(noSun, route: noSun.timedRoute, phase: .before) == nil)
    }
}
