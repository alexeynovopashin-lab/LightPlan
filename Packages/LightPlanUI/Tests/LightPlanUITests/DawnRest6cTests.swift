import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// 31.6в (DECISIONS 18.11, Алексей «1Б, но надо учитывать работу приложения во всех городах, местах», «2А»): «Звёзды» без
/// названного времени — облака окна Млечного Пути, нет окна — часов темноты; строка карточки «Ожидались звёзды» — облаками ночи
/// той же функцией, что форма; темнота и луна формы — у места съёмки. Только API, что было и на `1403a320`.
@MainActor
@Suite(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
struct DawnRest6cTests {

    struct City: Sendable { let name: String; let lat: Double; let lon: Double; let zone: String }
    nonisolated static let moscow = City(name: "Москва", lat: 55.75, lon: 37.62, zone: "Europe/Moscow")
    nonisolated static let tomsk = City(name: "Томск", lat: 56.49, lon: 84.95, zone: "Asia/Tomsk")
    nonisolated static let petersburg = City(name: "Санкт-Петербург", lat: 59.94, lon: 30.31, zone: "Europe/Moscow")
    nonisolated static let almaty = City(name: "Алматы", lat: 43.24, lon: 76.89, zone: "Asia/Almaty")
    nonisolated static let tromso = City(name: "Тромсё", lat: 69.65, lon: 18.96, zone: "Europe/Oslo")
    nonisolated static let sydney = City(name: "Сидней", lat: -33.87, lon: 151.21, zone: "Australia/Sydney")
    nonisolated static let all = [moscow, tomsk, petersburg, almaty, tromso, sydney]

    /// Облачность `dark` в часы, когда в этом месте солнце ниже −18° (по **его настоящему** поясу — не по тому, что передал
    /// запрос: ошибка пояса в приложении сдвинет часы и средняя упадёт ниже 70 %), `light` — в остальные; `sunsetRain` — дождь
    /// 14…18 ч (окно заката Томска в декабре).
    struct NightSky: WeatherSource {
        var dark: Double = 78
        var light: Double = 0
        var sunsetRain = false
        let first = CivilDate(year: 2026, month: 6, day: 1)
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            let city = DawnRest6cTests.all.min { abs($0.lat - place.latitude) + abs($0.lon - place.longitude)
                < abs($1.lat - place.latitude) + abs($1.lon - place.longitude) }!
            let truth = Place(latitude: place.latitude, longitude: place.longitude, zone: ZoneID(city.zone)!)
            var time: [String] = [], cloud: [Double] = [], rain: [Double] = [], code: [Int] = []
            for k in 0..<400 {
                let d = first.adding(days: k)
                let sun = SolarDay(date: d, place: truth)
                for h in 0..<24 {
                    time.append(String(format: "%04d-%02d-%02dT%02d:00", d.year, d.month, d.day, h))
                    let m = Double(h * 60 + 30)
                    let isDark = (sun.astroB.map { m >= $0 } ?? false) || (sun.astroA.map { m <= $0 } ?? false)
                        || (sun.astroA == nil && sun.astroB == nil && sun.elevation(at: m) <= -18)
                    cloud.append(isDark ? dark : light)
                    let w = sunsetRain && (14...18).contains(h)
                    rain.append(w ? 1.2 : 0); code.append(w ? 61 : 0)
                }
            }
            let n = time.count
            return HourlyWeather(time: time, cloud: cloud, humidity: Array(repeating: 50, count: n),
                                 temperature: Array(repeating: -5, count: n), windSpeed: Array(repeating: 2, count: n),
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

    static func cell(_ c: City) -> String { "\((c.lat * 2).rounded() / 2),\((c.lon * 2).rounded() / 2)" }

    /// Город приложения `city`, «сейчас» — накануне `day` в полдень; пояса всех мест — в кэше снимка (как после геокодера).
    static func app(_ source: NightSky, city: City, day: CivilDate, sessions: [Session] = []) -> AppModel {
        var snap = Snapshot()
        snap.extra["me"] = .object(["city": .string(city.name), "cityLat": .number(city.lat), "cityLon": .number(city.lon), "met": .bool(true)])
        var zones: [String: JSONValue] = [:]
        for c in all { zones[cell(c)] = .string(c.zone) }
        snap.extra["zones"] = .object(zones)
        snap.sessions = sessions
        let tz = TimeZone(identifier: city.zone)!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let eve = day.adding(days: -1)
        let now = cal.date(from: DateComponents(year: eve.year, month: eve.month, day: eve.day, hour: 12))!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: tz, locator: Locator(),
                           geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: source, now: { now })
        app.draftStore = MemoryDraftStore()
        app.update { $0.mode = .astro }
        return app
    }

    /// Форма «Звёзд» на `day`: место — `at` (без него — место приложения), время — `start` (nil — предложенное правилом).
    static func starsForm(_ app: AppModel, day: CivilDate, start: Int?, at place: City? = nil) async throws -> EventForm {
        await app.light.weather.settled()
        app.openForm(day: day, start: start, fromLight: false)
        if let place { app.form?.sessionPlace = FormPlace(town: place.name, latitude: place.lat, longitude: place.lon, isCity: false) }
        app.form?.wishes = [.stars]
        await app.pointWeather.settled()
        let f = try #require(app.form)
        if start == nil { #expect(f.timeIsProposed) }
        return f
    }

    static func shoot(_ id: String, _ c: City, day: CivilDate, start: Int, wishes: [Wish]) -> Session {
        var s = Session(id: id, kind: .shoot, day: day, start: start, end: start + 60, duration: 60, genre: .portrait)
        s.latitude = c.lat; s.longitude = c.lon; s.placeIsCity = false
        s.wishes = wishes
        return s
    }

    static let winter = CivilDate(year: 2026, month: 12, day: 21)

    // MARK: - 1Б: без названного времени — окно, нет окна — темнота

    @Test("Томск зимой, время не названо: окна нет — облака часов темноты 19:08–07:28, «по прогнозу затянуто»")
    func tomskWinterUsesTheDarkness() async throws {
        let app = Self.app(NightSky(), city: Self.tomsk, day: Self.winter)
        let f = try await Self.starsForm(app, day: Self.winter, start: nil)
        let w = try #require(app.formWishWarning(f))
        #expect(w.message.lowercased().contains("по прогнозу затянуто"), "\(w.message)")
        let clear = Self.app(NightSky(dark: 0), city: Self.tomsk, day: Self.winter)
        let cf = try await Self.starsForm(clear, day: Self.winter, start: nil)
        #expect(!(clear.formWishWarning(cf)?.message.lowercased().contains("по прогнозу") ?? false), "ясная ночь — облачности нет")
    }

    /// Съёмка в другом поясе: город приложения Москва (+3), место — Томск (+7). Часы ночи — по поясу места: при ошибке на час
    /// и больше облака 78 % в настоящей темноте и 0 % рядом давали бы «местами облачно».
    @Test("съёмка в другом поясе (Москва → Томск): часы темноты — по поясу места, «по прогнозу затянуто»")
    func farZoneShootUsesItsOwnClock() async throws {
        let app = Self.app(NightSky(), city: Self.moscow, day: Self.winter)
        let f = try await Self.starsForm(app, day: Self.winter, start: nil, at: Self.tomsk)
        let w = try #require(app.formWishWarning(f))
        #expect(w.message.lowercased().contains("по прогнозу затянуто"), "\(w.message)")
    }

    @Test("Тромсё в декабре (полярная ночь) и Сидней в декабре (ночь через полночь): облака часов темноты")
    func polarNightAndSouth() async throws {
        for c in [Self.tromso, Self.sydney] {
            let app = Self.app(NightSky(), city: c, day: Self.winter)
            let f = try await Self.starsForm(app, day: Self.winter, start: nil)
            let w = try #require(app.formWishWarning(f), "\(c.name)")
            #expect(w.message.lowercased().contains("по прогнозу затянуто"), "\(c.name): \(w.message)")
        }
    }

    /// Белая ночь у места съёмки, город приложения — Алматы (там темнеет): «недостаточно темно» — по месту съёмки, облака без
    /// часов ночи не называются; карточка той же съёмки говорит то же.
    @Test("Петербург в июне (белая ночь) из Алматы: «Недостаточно темно» у формы и карточки, облака не придумываются")
    func whiteNightAtTheShootPlace() async throws {
        let june = CivilDate(year: 2027, month: 6, day: 21)
        let app = Self.app(NightSky(dark: 95, light: 95), city: Self.almaty, day: june,
                           sessions: [Self.shoot("spb", Self.petersburg, day: june, start: 23 * 60, wishes: [.stars])])
        let f = try await Self.starsForm(app, day: june, start: nil, at: Self.petersburg)
        let w = try #require(app.formWishWarning(f))
        #expect(w.message.hasPrefix("Недостаточно темно"), "\(w.message)")
        #expect(!w.message.contains("по прогнозу"), "без часов ночи облака не называются: \(w.message)")
        app.closeForm()
        app.openCard(id: "spb")
        await app.pointWeather.settled()
        let s = try #require(app.sessions.first { $0.id == "spb" })
        guard case .starsNone(let why)? = app.cardStars(s, phase: .before) else { Issue.record("ждали «не будет видно»"); return }
        #expect(why.first == .notDark)
    }

    // MARK: - 2А: строка карточки «Ожидались звёзды»

    /// Одна съёмка, форма и карточка: со временем человека обе судят облака часов съёмки одной функцией и говорят одно слово.
    @Test("«Звёзды»: форма и карточка одной съёмки говорят одно — затянуто / ясно")
    func formAndCardAgree() async throws {
        for (dark, word) in [(78.0, "затянуто"), (0.0, nil)] as [(Double, String?)] {
            let app = Self.app(NightSky(dark: dark), city: Self.tomsk, day: Self.winter,
                               sessions: [Self.shoot("t", Self.tomsk, day: Self.winter, start: 23 * 60, wishes: [.stars])])
            await app.light.weather.settled()
            app.openCard(id: "t")
            await app.pointWeather.settled()
            let s = try #require(app.sessions.first { $0.id == "t" })
            let card = app.cardWishMissed(s, phase: .before)
            app.openForm(editing: "t")
            await app.pointWeather.settled()
            let f = try #require(app.form)
            let form = app.formWishWarning(f)?.message.lowercased()
            if let word {
                #expect(card == "Ожидались звёзды. Прогноз на эту ночь — \(word).", "\(String(describing: card))")
                #expect(form?.contains("по прогнозу \(word)") == true, "\(String(describing: form))")
            } else {
                #expect(card == nil, "\(String(describing: card))")
                #expect(form?.contains("по прогнозу") != true, "\(String(describing: form))")
            }
        }
    }

    @Test("дождь на закате и затянутая ночь: под листом две строки — закат и звёзды")
    func twoLinesUnderTheSheet() async throws {
        let app = Self.app(NightSky(sunsetRain: true), city: Self.tomsk, day: Self.winter,
                           sessions: [Self.shoot("t", Self.tomsk, day: Self.winter, start: 23 * 60, wishes: [.sunset, .stars])])
        await app.light.weather.settled()
        app.openCard(id: "t")
        await app.pointWeather.settled()
        let s = try #require(app.sessions.first { $0.id == "t" })
        let lines = try #require(app.cardWishMissed(s, phase: .before)).components(separatedBy: "\n")
        #expect(lines.count == 2, "\(lines)")
        #expect(lines.first?.hasPrefix("Ожидался закат.") == true && !(lines.first?.contains("звёзды") ?? true), "\(lines)")
        #expect(lines.last == "Ожидались звёзды. Прогноз на эту ночь — затянуто.", "\(lines)")
    }

    @Test("слова «Ожидались звёзды … на эту ночь» на пяти языках: без сырых слотов")
    func starsMissedWords() {
        for lang in ["ru", "en", "es", "ja", "zh"] {
            let lex = Lexicon(lang)
            let t = lex.t("card.starsMissed", ["wish": lex.t("wish.was.stars"), "cond": lex.t("mwSky.poor").lowercased()])
            #expect(!t.contains("{") && t != "card.starsMissed", "\(lang): «\(t)»")
        }
    }
}
