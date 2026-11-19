import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// 31.8 (DECISIONS 18.11 «Звёзды: остатки — шаг 31.8»): строка карточки «Ожидались звёзды» говорит о тех часах, что судит.
/// Съёмка мимо темноты (днём, в сумерки) судится облаками своих часов — «Прогноз на время съёмки», а не «на эту ночь».
/// Помощники — из `DawnRest6cTests` (облака 78 % в темноте или вне её, пояса мест в снимке).
@MainActor
@Suite(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
struct StarsRest8Tests {
    typealias T = DawnRest6cTests

    func cardLine(_ src: T.NightSky, _ c: T.City, day: CivilDate, start: Int) async throws -> String? {
        let app = T.app(src, city: c, day: day, sessions: [T.shoot("s", c, day: day, start: start, wishes: [.stars])])
        await app.light.weather.settled()
        app.openCard(id: "s")
        await app.pointWeather.settled()
        let s = try #require(app.sessions.first { $0.id == "s" })
        return app.cardWishMissed(s, phase: .before)
    }

    /// Днём облака 78 %, ночью ясно: карточка судит часы съёмки (как форма со временем человека) и так и говорит.
    @Test("«Звёзды» днём (Томск 13:00, Тромсё в полярную ночь 12:00, Сидней 13:00): «Прогноз на время съёмки — затянуто»")
    func daytimeShootSaysShootHours() async throws {
        for c in [T.tomsk, T.tromso, T.sydney] {
            let line = try await cardLine(T.NightSky(dark: 0, light: 78), c, day: T.winter, start: c.name == "Тромсё" ? 12 * 60 : 13 * 60)
            #expect(line == "Ожидались звёзды. Прогноз на время съёмки — затянуто.", "\(c.name): \(String(describing: line))")
        }
    }

    /// Сумерки до темноты: Томск 21.12, темнота с 19:08 — съёмка 17:30–18:30 её не касается.
    @Test("«Звёзды» в сумерки до темноты (Томск 17:30): тоже «на время съёмки»")
    func twilightShootSaysShootHours() async throws {
        let line = try await cardLine(T.NightSky(dark: 0, light: 78), T.tomsk, day: T.winter, start: 17 * 60 + 30)
        #expect(line == "Ожидались звёзды. Прогноз на время съёмки — затянуто.", "\(String(describing: line))")
    }

    /// Ночная съёмка — вечером своих суток и под утро (хвост прошлой ночи): «на эту ночь», как было.
    @Test("«Звёзды» ночью (Томск 23:00 и 02:00, Алматы 23:00 в июле): «Прогноз на эту ночь — затянуто»")
    func nightShootSaysThisNight() async throws {
        let july = CivilDate(year: 2027, month: 7, day: 4)
        for (c, d, start) in [(T.tomsk, T.winter, 23 * 60), (T.tomsk, T.winter, 2 * 60), (T.almaty, july, 23 * 60)] {
            let line = try await cardLine(T.NightSky(), c, day: d, start: start)
            #expect(line == "Ожидались звёзды. Прогноз на эту ночь — затянуто.", "\(c.name) \(start): \(String(describing: line))")
        }
    }

    @Test("слова «… на время съёмки» на пяти языках: без сырых слотов, не те же, что «на эту ночь»")
    func shootHoursWords() {
        for lang in ["ru", "en", "es", "ja", "zh"] {
            let lex = Lexicon(lang)
            let args = ["wish": lex.t("wish.was.stars"), "cond": lex.t("mwSky.poor").lowercased()]
            let t = lex.t("card.starsMissedShoot", args)
            #expect(!t.contains("{") && t != "card.starsMissedShoot", "\(lang): «\(t)»")
            #expect(t != lex.t("card.starsMissed", args), "\(lang)")
        }
    }

    // MARK: - П. 1: ночь, тёмная только после полуночи (Алексей 19.11 «А, с подсветкой»)

    nonisolated static let kyiv = T.City(name: "Киев", lat: 50.45, lon: 30.52, zone: "Europe/Kiev")

    /// Город приложения `city`, «сейчас» — накануне `day`; пояса Киева и мест `DawnRest6cTests` — в снимке (как после геокодера).
    static func app(city: T.City, day: CivilDate) -> AppModel {
        var snap = Snapshot()
        snap.extra["me"] = .object(["city": .string(city.name), "cityLat": .number(city.lat), "cityLon": .number(city.lon), "met": .bool(true)])
        var zones: [String: JSONValue] = [:]
        for c in T.all + [kyiv] { zones[T.cell(c)] = .string(c.zone) }
        snap.extra["zones"] = .object(zones)
        let tz = TimeZone(identifier: city.zone)!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let eve = day.adding(days: -1)
        let now = cal.date(from: DateComponents(year: eve.year, month: eve.month, day: eve.day, hour: 12))!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: tz, locator: T.Locator(),
                           geocoder: T.SilentGeocoder(), cityLookup: T.NoCities(), weatherSource: T.NightSky(dark: 0), now: { now })
        app.draftStore = MemoryDraftStore()
        app.update { $0.mode = .astro }
        return app
    }

    /// Новая форма на `day` без названного времени, нажато «Звёзды».
    func starsForm(_ c: T.City, _ day: CivilDate) async throws -> (AppModel, EventForm) {
        let app = Self.app(city: c, day: day)
        await app.light.weather.settled()
        app.openForm(day: day, start: nil, fromLight: false)
        app.toggleFormWish(.stars)
        return (app, try #require(app.form))
    }

    static func place(_ c: T.City) -> Place { Place(latitude: c.lat, longitude: c.lon, zone: ZoneID(c.zone)!) }

    /// Ожидание — то же правило, что в другие дни (`ShootTime.target`): начало темноты, а съёмка длиннее темноты кончается вместе с ней.
    @Test("Томск 29.04 и Киев 27.05: темно только после полуночи — форма ставит следующую дату и подсвечивает её")
    func lateDarkMovesToTheNextDate() async throws {
        for (c, day) in [(T.tomsk, CivilDate(year: 2027, month: 4, day: 29)), (Self.kyiv, CivilDate(year: 2027, month: 5, day: 27))] {
            let (app, f) = try await starsForm(c, day)
            let dark = try #require(StarNightHours.dark(date: day, place: Self.place(c)))
            let from = Int(dark.lowerBound.rounded()), to = Int(dark.upperBound.rounded())
            let want = f.duration > to - from ? to - f.duration : from
            #expect(f.day == day.adding(days: 1) && f.start == want - 1440, "\(c.name): \(f.day) \(f.start), ждали \(want - 1440) (длительность \(f.duration))")
            #expect(f.dateShifted && f.timeShifted && f.timeIsProposed, "\(c.name): дата и время подсвечены")
            // Повторный пересчёт (закрылось колесо) не уводит дату дальше
            app.formTimeSettled()
            #expect(app.form?.day == day.adding(days: 1) && app.form?.start == want - 1440, "\(c.name): дата не сползла")
            // Сняли «Звёзды» — выбранная дата, подсветка ушла
            app.toggleFormWish(.stars)
            #expect(app.form?.day == day && app.form?.dateShifted == false, "\(c.name): \(String(describing: app.form?.day))")
        }
    }

    @Test("обычный день (Томск 21.12, Киев 15.05): дата та же, время — начало темноты вечером, дата не подсвечена")
    func ordinaryDayKeepsTheDate() async throws {
        for (c, day) in [(T.tomsk, T.winter), (Self.kyiv, CivilDate(year: 2027, month: 5, day: 15))] {
            let (_, f) = try await starsForm(c, day)
            let b = try #require(SolarDay(date: day, place: Self.place(c)).astroB)
            #expect(f.day == day && f.start == Int(b.rounded()) && !f.dateShifted, "\(c.name): \(f.day) \(f.start), темнеет \(b)")
        }
    }

    /// Последний «поздний» день сезона: Киев 28.05 — форма на 29.05, а ночи 29.05 уже нет. Небо пожеланий — ночи 28.05: форма не
    /// говорит «Недостаточно темно» о ночи, которую не судит.
    @Test("Киев 28.05 → 29.05: «Недостаточно темно» не говорится — ночь выбранной даты тёмная")
    func movedFormJudgesTheChosenNight() async throws {
        let day = CivilDate(year: 2027, month: 5, day: 28)
        let (app, f) = try await starsForm(Self.kyiv, day)
        #expect(f.day == day.adding(days: 1) && f.dateShifted)
        #expect(app.wishSky(f.day, form: f).astroNight, "ночь 28.05 тёмная 00:49–01:01")
        #expect(!(app.formWishWarning(f)?.message.hasPrefix("Недостаточно темно") ?? false), "\(String(describing: app.formWishWarning(f)?.message))")
    }
}
