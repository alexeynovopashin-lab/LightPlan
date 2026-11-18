import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// 31.6 «Рассвет — остальные места» (Алексей 18.11: «закаты и рассветы равнозначны по значению»), экраны. Москва 21.09.2026:
/// восход ≈ 06:17, закат ≈ 18:27; окна неба ±2 ч у часа события. Прогноз — дождь в одном окне, другое сухое.
/// Только API, что было и на `c7b1256b`: на старом коде набор падает проверками, не сборкой. Новое API — в `DawnRestNewTests`.
@MainActor
@Suite(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
struct DawnRestTests {

    /// Дождь часы `wet` каждый день; аэрозоль 0,7 («дым») в часы `smoky`, остальные 0,1.
    struct Rain: WeatherSource {
        let wet: ClosedRange<Int>
        var smoky: ClosedRange<Int>? = nil
        let first = CivilDate(year: 2026, month: 9, day: 15)
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            var time: [String] = [], rain: [Double] = [], code: [Int] = []
            for k in 0..<21 {
                let d = first.adding(days: k)
                for h in 0..<24 {
                    time.append(String(format: "%04d-%02d-%02dT%02d:00", d.year, d.month, d.day, h))
                    let w = wet.contains(h)
                    rain.append(w ? 1.2 : 0); code.append(w ? 61 : 0)
                }
            }
            let n = time.count
            return HourlyWeather(time: time, cloud: Array(repeating: 30, count: n), temperature: Array(repeating: 12, count: n),
                                 windSpeed: Array(repeating: 2, count: n), precipitation: rain, weatherCode: code)
        }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] {
            guard let smoky else { return [:] }
            var out: [CivilDate: [Int: AirSample]] = [:]
            for k in 0..<21 {
                var day: [Int: AirSample] = [:]
                for h in 0..<24 { day[h] = AirSample(aod: smoky.contains(h) ? 0.7 : 0.1, dust: nil) }
                out[first.adding(days: k)] = day
            }
            return out
        }
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

    static let day = CivilDate(year: 2026, month: 9, day: 21)
    static let moscow = Place(latitude: 55.75, longitude: 37.62, zone: ZoneID("Europe/Moscow")!)
    static var sun: SolarDay { SolarDay(date: day, place: moscow) }

    /// Москва, 20.09.2026 12:00; съёмка «am» 21.09 в `start` с пожеланиями `wishes`.
    static func app(_ source: Rain, start: Int = 360, wishes: [Wish] = []) -> AppModel {
        var snap = Snapshot()
        snap.extra["me"] = .object(["city": .string("Москва"), "cityLat": .number(55.75), "cityLon": .number(37.62), "met": .bool(true)])
        snap.extra["zones"] = .object(["56.0,37.5": .string("Europe/Moscow")])
        var s = Session(id: "am", kind: .shoot, day: day, start: start, end: start + 60, duration: 60, genre: .portrait)
        s.latitude = 55.75; s.longitude = 37.62
        s.wishes = wishes
        snap.sessions = [s]
        let now = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!, locator: Locator(),
                           geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: source, now: { now })
        app.draftStore = MemoryDraftStore()   // черновик формы — свой у каждого теста, не общий UserDefaults
        return app
    }

    static let morningRain = Rain(wet: 3...9)
    static let eveningRain = Rain(wet: 15...21)
    static let lexicon = Lexicon("ru")

    // MARK: - П. 2: «Воздух»

    @Test("«Воздух» утром — аэрозоль часа восхода, после утреннего золотого часа — заката")
    func airIsAtTheEventHour() async throws {
        let app = Self.app(Rain(wet: 0...0, smoky: 5...7))
        await app.light.weather.settled()
        let goldenA = try #require(Self.sun.goldenA)
        app.light.timebar.show(day: Self.day, minute: goldenA - 20)
        #expect(app.light.telemetry.air == Self.lexicon.t("air.smoke"), "утром: дым у восхода")
        app.light.timebar.show(day: Self.day, minute: 15 * 60)
        #expect(app.light.telemetry.air == nil, "днём: у заката чисто")
    }

    // MARK: - П. 3: тренд облаков

    /// Томск 18.11 (архив Open-Meteo): утром тренд — часы вокруг восхода (09:05 → 06…11 ч), днём — 16…21, как было.
    @Test("тренд под отсчётом утром — к рассвету, днём — к закату")
    func trendFollowsTheEvent() async throws {
        let w = try await DawnEqualTests.weather()
        let morning = DawnEqualTests.light(at: 9 * 60 + 21, w).next.trend
        let dawnHours = (6...11).map { w.hours[$0]?.cloud ?? Double(w.cloud) }
        #expect(dawnHours != w.trend, "окна разные — иначе тест ничего не докажет")
        #expect(morning == dawnHours)
        #expect(DawnEqualTests.light(at: 12 * 60, w).next.trend == w.trend)
    }

    // MARK: - П. 4: подсказка времени формы

    @Test("подсказка формы: дождь у заката и ясный рассвет — утреннее окно, а не «окна нет»")
    func formWindowTakesTheDawnWhenTheEveningIsWet() async throws {
        let wet = Self.app(Self.eveningRain)
        await wet.light.weather.settled()
        let w = try #require(wet.formLight(on: Self.day))
        #expect(!w.poor && w.dawn, "утреннее окно")
        #expect(w.start == Self.sun.blueA && w.end == Self.sun.goldenA)
        // Дождь у рассвета, сухой вечер — вечернее окно, как было.
        let dry = Self.app(Self.morningRain)
        await dry.light.weather.settled()
        let e = try #require(dry.formLight(on: Self.day))
        #expect(!e.poor && !e.dawn && e.start == Self.sun.goldenB)
        // Дождь в обоих окнах — окна нет.
        let both = Self.app(Rain(wet: 3...21))
        await both.light.weather.settled()
        #expect(both.formLight(on: Self.day)?.poor == true)
    }

    // MARK: - П. 5: пожелания формы и строка карточки — одним небом

    @Test("утренняя съёмка с «Дождём» при дожде на рассвете: форма молчит, карточка молчит")
    func rainWishAgreesForTheMorningShoot() async throws {
        let app = Self.app(Self.morningRain, wishes: [.rain])
        await app.light.weather.settled()
        app.openForm(day: Self.day, start: 360, fromLight: false)
        app.form?.wishes = [.rain]   // пресет жанра кладёт свои пожелания — здесь только одно
        await app.pointWeather.settled()
        let f = try #require(app.form)
        #expect(f.wishes.contains(.rain))
        #expect(app.pointWeather.states.values.contains { if case .ready = $0 { true } else { false } },
                "прогноз места пришёл — иначе «молчит» ничего не доказывает")
        #expect(app.formWishWarning(f) == nil, "\(String(describing: app.formWishWarning(f)))")
        app.closeForm()
        app.openCard(id: "am")
        await app.pointWeather.settled()
        let s = try #require(app.sessions.first { $0.id == "am" })
        #expect(app.cardWishMissed(s, phase: .before) == nil)
    }

    @Test("утренняя съёмка с «Ясно» при дожде на рассвете: и форма, и карточка говорят о дожде")
    func clearWishAgreesForTheMorningShoot() async throws {
        let app = Self.app(Self.morningRain, wishes: [.clear])
        await app.light.weather.settled()
        app.openForm(day: Self.day, start: 360, fromLight: false)
        app.form?.wishes = [.clear]   // пресет жанра кладёт свои пожелания — здесь только одно
        await app.pointWeather.settled()   // 31.6б: форма судит погодой места съёмки и ждёт её, как карточка
        let f = try #require(app.form)
        let warn = try #require(app.formWishWarning(f))
        #expect(warn.message.contains(Self.lexicon.t("qualSky.poor").lowercased()), "\(warn.message)")
        app.closeForm()
        app.openCard(id: "am")
        await app.pointWeather.settled()
        let s = try #require(app.sessions.first { $0.id == "am" })
        #expect(app.cardWishMissed(s, phase: .before) != nil)
        // Вечерняя съёмка в тот же день — сухой закат: «Ясно» не спорит с дождём утра.
        let evening = Self.app(Self.morningRain)
        await evening.light.weather.settled()
        evening.openForm(day: Self.day, start: 17 * 60, fromLight: false)
        evening.form?.wishes = [.clear]
        await evening.pointWeather.settled()
        let ef = try #require(evening.form)
        #expect(evening.formWishWarning(ef)?.message.contains(Self.lexicon.t("qualSky.poor").lowercased()) != true)
    }

    // MARK: - П. 7: синий час утром на точках карточки

    @Test("утренний синий час у точки — знак рассвета, вечерний — заката")
    func morningBlueHourSignIsTheSunrise() throws {
        let app = Self.app(Self.morningRain)
        let s = try #require(app.sessions.first { $0.id == "am" })
        let sun = Self.sun
        let morning = Int(((try #require(sun.civilA)) + (try #require(sun.blueA))) / 2)
        let evening = Int(((try #require(sun.blueB)) + (try #require(sun.civilB))) / 2)
        #expect(app.pointLightCode(s, app.anchor(s), morning) == .blue)
        #expect(app.pointLight(s, app.anchor(s), morning)?.icon == "sunrise")
        #expect(app.pointLight(s, app.anchor(s), morning)?.blue == true)
        #expect(app.pointLight(s, app.anchor(s), evening)?.icon == "sunset")
    }

    // MARK: - П. 9: строка золотого часа карточки для «Рассвета»

    @Test("«Рассвет» в карточке: точка в утреннем золотом часе — «попадает в золотой час» с утренним окном")
    func dawnWishSaysTheMorningGoldenHour() async throws {
        let sun = Self.sun
        let blueA = try #require(sun.blueA), goldenA = try #require(sun.goldenA)
        let app = Self.app(Self.eveningRain, start: Int(blueA) + 10, wishes: [.sunrise])
        app.openCard(id: "am")
        await app.pointWeather.settled()
        let s = try #require(app.sessions.first { $0.id == "am" })
        let golden = try #require(app.cardSays(s, phase: .before).first { $0.kind == .golden })
        #expect(!golden.bad)
        #expect(golden.text.contains(PlannerFacts(app: app, dark: false).range(blueA, goldenA)), "\(golden.text)")
    }

    @Test("«Рассвет» в карточке при дожде на рассвете: «Ожидался рассвет, а прогноз обещает …»")
    func dawnWishSaysTheWetDawn() async throws {
        let app = Self.app(Self.morningRain, start: 360, wishes: [.sunrise])
        app.openCard(id: "am")
        await app.pointWeather.settled()
        let s = try #require(app.sessions.first { $0.id == "am" })
        let golden = try #require(app.cardSays(s, phase: .before).first { $0.kind == .golden })
        #expect(golden.bad)
        #expect(golden.text.hasPrefix("Ожидался рассвет, а прогноз обещает"), "\(golden.text)")
    }

    // MARK: - П. 14: свод «Карты»

    @Test("свод «Карты»: золотой и синий час утром и вечером, подписи «Подробно»")
    func mapFoldHasMorningWindows() {
        let sun = Self.sun
        let clock = ClockText(language: "ru")
        let s = MapSummary.build(date: Self.day, t: 13 * 60, sun: sun, place: Self.moscow, utcOffset: 3, pro: false, glow: nil, mw: nil,
                                 dateShort: { "\($0.day).\($0.month)" }, lexicon: Self.lexicon, clock: clock)
        let am = s.rows.first { $0.label == "pro.goldenAM" }
        #expect(am?.text.hasPrefix(clock.range(sun.blueA, sun.goldenA)) == true, "\(String(describing: am))")
        #expect(s.rows.first { $0.label == "pro.goldenPM" }?.text.hasPrefix(clock.range(sun.goldenB, sun.blueB)) == true)
        #expect(s.rows.first { $0.label == "pro.blueAM" }?.text.hasPrefix(clock.range(sun.civilA, sun.blueA)) == true)
        #expect(s.rows.first { $0.label == "pro.bluePM" }?.text.hasPrefix(clock.range(sun.blueB, sun.civilB)) == true)
    }

    // MARK: - Слова

    @Test("новые слова есть на всех пяти языках")
    func newWordsInFiveLanguages() {
        for lang in ["ru", "en", "es", "ja", "zh"] {
            let l = Lexicon(lang)
            for k in ["next.toBlue", "light.waitedSunrise", "clash.bothSunriseT", "clash.bothSunriseM", "ar.afterSunrise"] {
                #expect(l.t(k) != k, "\(lang): \(k)")
            }
        }
    }
}
