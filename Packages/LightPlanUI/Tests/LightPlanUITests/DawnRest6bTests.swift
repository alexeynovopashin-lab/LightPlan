import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// 31.6б (DECISIONS 18.11, «наша недоработка»): подпись кнопки «Запланировать съёмку» — золотой час события наверху; «Звёзды» в форме —
/// облаками ночи, а не неба заката; форма судит пожелания погодой места съёмки, тем же путём, что карточка. Только API, что было и на
/// `cadfddc0`: на старом коде набор падает проверками, не сборкой.
@MainActor
@Suite(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
struct DawnRest6bTests {

    /// Облачность `night` в часы 21…5, `rest` — в остальные; `southRain` — дождь 15…21 ч там, где широта ниже 52° (место съёмки
    /// южнее Москвы), у Москвы сухо.
    struct Sky: WeatherSource {
        var night: Double = 30
        var rest: Double = 30
        var southRain = false
        let first = CivilDate(year: 2026, month: 8, day: 1)
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            var time: [String] = [], cloud: [Double] = [], rain: [Double] = [], code: [Int] = []
            for k in 0..<60 {
                let d = first.adding(days: k)
                for h in 0..<24 {
                    time.append(String(format: "%04d-%02d-%02dT%02d:00", d.year, d.month, d.day, h))
                    cloud.append(h >= 21 || h <= 5 ? night : rest)
                    let w = southRain && place.latitude < 52 && (15...21).contains(h)
                    rain.append(w ? 1.2 : 0); code.append(w ? 61 : 0)
                }
            }
            let n = time.count
            return HourlyWeather(time: time, cloud: cloud, humidity: Array(repeating: 50, count: n),
                                 temperature: Array(repeating: 12, count: n), windSpeed: Array(repeating: 2, count: n),
                                 precipitation: rain, weatherCode: code)
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

    static let moscowDay = CivilDate(year: 2026, month: 9, day: 21)

    /// Город приложения — `city` (по умолчанию Москва), «сейчас» — `now`; записей нет.
    static func app(_ source: Sky, city: (String, Double, Double, String) = ("Москва", 55.75, 37.62, "Europe/Moscow"),
                    now iso: String = "2026-09-20T12:00:00+03:00") -> AppModel {
        var snap = Snapshot()
        snap.extra["me"] = .object(["city": .string(city.0), "cityLat": .number(city.1), "cityLon": .number(city.2), "met": .bool(true)])
        let cell = "\((city.1 * 2).rounded() / 2),\((city.2 * 2).rounded() / 2)"
        snap.extra["zones"] = .object([cell: .string(city.3)])
        let now = ISO8601DateFormatter().date(from: iso)!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: city.3)!, locator: Locator(),
                           geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: source, now: { now })
        app.draftStore = MemoryDraftStore()
        app.update { $0.mode = .astro }   // «Звёзды» видны и проверяются только в «Астро»
        return app
    }

    /// Форма съёмки на `day` в `start` (время назвал человек) с пожеланиями `wishes`; прогнозы города и места дождались.
    static func form(_ app: AppModel, day: CivilDate, start: Int?, wishes: [Wish]) async throws -> EventForm {
        await app.light.weather.settled()
        app.openForm(day: day, start: start, fromLight: false)
        app.form?.wishes = wishes
        await app.pointWeather.settled()
        return try #require(app.form)
    }

    // MARK: - 1. Подпись под «Запланировать съёмку»

    @Test("подпись кнопки «Запланировать съёмку»: утром — золотой час утра, днём — вечера, как строка сводки")
    func planButtonSubtitleFollowsTheEvent() async throws {
        let app = DawnRestTests.app(DawnRestTests.Rain(wet: 0...0))
        await app.light.weather.settled()
        let sun = DawnRestTests.sun
        func tight(_ s: String) -> String { s.replacingOccurrences(of: "\u{00A0}–\u{00A0}", with: "–") }
        let goldenA = try #require(sun.goldenA)
        app.light.timebar.show(day: DawnRestTests.day, minute: goldenA - 20)
        var tel = app.light.telemetry
        #expect(tel.golden.contains(tight(tel.actionSubtitle)), "утром: подпись «\(tel.actionSubtitle)», сводка «\(tel.golden)»")
        app.light.timebar.show(day: DawnRestTests.day, minute: 15 * 60)
        tel = app.light.telemetry
        #expect(tel.golden.contains(tight(tel.actionSubtitle)), "днём: подпись «\(tel.actionSubtitle)», сводка «\(tel.golden)»")
    }

    // MARK: - 2. «Звёзды» в форме — облака ночи

    @Test("«Звёзды» со временем съёмки: ночью затянуто — «по прогнозу затянуто», даже если закат ясный")
    func starsSeeTheOvercastNight() async throws {
        let app = Self.app(Sky(night: 95, rest: 0))
        let f = try await Self.form(app, day: Self.moscowDay, start: 23 * 60, wishes: [.stars])
        let w = try #require(app.formWishWarning(f))
        #expect(w.message.lowercased().contains("по прогнозу затянуто"), "\(w.message)")
    }

    @Test("«Звёзды» со временем съёмки: ночь ясная — облачность не причина, даже если закат затянут")
    func starsIgnoreTheOvercastSunset() async throws {
        let app = Self.app(Sky(night: 0, rest: 95))
        let f = try await Self.form(app, day: Self.moscowDay, start: 23 * 60, wishes: [.stars])
        let w = app.formWishWarning(f)
        #expect(!(w?.message.lowercased().contains("по прогнозу") ?? false), "\(w?.message ?? "плашки нет")")
    }

    /// Время не называли (предложено правилом) — облака часов окна Млечного Пути, того же окна, что у строки «Звёзды» карточки:
    /// Иерусалим, новолуние 12.08.2026, ядро в окне высоко. Предложенный полдень ясный — его облака не судят.
    @Test("«Звёзды» без названного времени: облака часов окна Млечного Пути, а не предложенного полдня")
    func starsWithoutATimeLookAtTheMilkyWayWindow() async throws {
        let day = CivilDate(year: 2026, month: 8, day: 12)
        let city = ("Иерусалим", 31.78, 35.22, "Asia/Jerusalem")
        let place = Place(latitude: city.1, longitude: city.2, zone: ZoneID(city.3)!)
        #expect(!MilkyWayWindow(date: day, place: place).spans.isEmpty, "окно этой ночи есть — иначе проверять нечего")
        let app = Self.app(Sky(night: 95, rest: 0), city: city, now: "2026-08-11T12:00:00+03:00")
        let f = try await Self.form(app, day: day, start: nil, wishes: [.stars])
        #expect(f.timeIsProposed)
        let w = try #require(app.formWishWarning(f))
        #expect(w.message.lowercased().contains("по прогнозу затянуто"), "\(w.message)")
    }

    // MARK: - 3. Погода места съёмки

    @Test("пожелания формы — погодой места съёмки: дождь там, сухо в городе — «Дождь» сбывается; без места — город")
    func formJudgesTheShootPlace() async throws {
        let app = Self.app(Sky(southRain: true))
        await app.light.weather.settled()
        app.openForm(day: Self.moscowDay, start: 18 * 60, fromLight: false)
        app.form?.wishes = [.rain]
        app.form?.sessionPlace = FormPlace(town: "Киев", latitude: 50.45, longitude: 30.52, isCity: false)
        var f = try #require(app.form)
        // Прогноз места ещё летит — как карточка: о погоде молчит, город не подставляется.
        #expect(app.formWishWarning(f) == nil, "пока прогноза места нет: \(app.formWishWarning(f)?.title ?? "")")
        await app.pointWeather.settled()
        f = try #require(app.form)
        #expect(app.formWishWarning(f) == nil, "у места дождь — пожелание «Дождь» сбывается")
        // Место стёрли — небо города приложения, как раньше: там сухо.
        app.form?.sessionPlace = FormPlace()
        f = try #require(app.form)
        #expect(app.formWishWarning(f)?.title == Lexicon("ru").t("wc.noRainT"))
    }
}
