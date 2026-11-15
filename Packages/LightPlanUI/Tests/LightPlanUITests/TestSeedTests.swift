import Testing
import Foundation
@testable import LightPlanUI
import LightPlanData
import LightPlanCore
import LightPlanDomain

/// Тестовый засев копии ветки (Алексей, 29.09): лежит в пакете и читается как снимок.
struct TestSeedTests {
    @Test func seedDecodesAsSnapshot() throws {
        let snap = try #require(TestSeed.snapshot())
        #expect(snap.sessions.count == 24)
        #expect(snap.sessions.contains { $0.id == "sd_sep_inter" })
    }
}

/// Запись «сегодня» тестового засева (27): маршрут и «Референсы» открыты в любое время суток,
/// а не только пока свадьба идёт по записанным рамкам.
@MainActor
struct TestSeedTodayTests {
    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
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

    /// Засев, перенесённый на 29.09 по Томску; часы приложения — `iso`.
    private func app(_ iso: String) throws -> AppModel {
        let launch = ISO8601DateFormatter().date(from: "2026-09-29T12:00:00+07:00")!
        let snap = try #require(TestSeed.snapshot(now: launch))
        let now = ISO8601DateFormatter().date(from: iso)!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Tomsk")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    /// (фаза, есть ли «Маршрут», есть ли «Референсы») записи `sd_today_wed` в момент `iso`.
    private func look(_ iso: String) throws -> (EventPhase, Bool, Bool) {
        let a = try app(iso)
        let s = try #require(a.sessions.first { $0.id == "sd_today_wed" })
        let ph = a.phase(of: s)
        let shown = a.cardBlocks(s, phase: ph)
        return (ph, shown.contains(.route), shown.contains(.refs))
    }

    @Test func routeAndRefsOpenAtAnyTimeOfDay() throws {
        for t in ["00:30", "07:00", "12:00", "21:00", "22:12", "23:59"] {
            let (ph, route, refs) = try look("2026-09-29T\(t):00+07:00")
            #expect(route, "маршрут скрыт в \(t), фаза \(ph)")
            #expect(refs, "«Референсы» скрыты в \(t), фаза \(ph)")
        }
    }

    /// 30и.12: в день первого запуска ничто другое из засева не стоит на свадьбе «сегодня» (08:00–02:00). Раньше «День города»
    /// 12:00–18:00 лежал на 14.11 и форма свадьбы писала «Время пересекается».
    @Test func nothingElseSitsOnTheWeddingOfTodayWhateverTheLaunchDay() throws {
        let zone = TimeZone(identifier: "Asia/Tomsk")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let raw = try #require(TestSeed.rawData())
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for iso in ["2026-11-14T12:00:00+07:00", "2026-09-25T12:00:00+07:00", "2026-10-17T09:00:00+07:00"] {
            let launch = ISO8601DateFormatter().date(from: iso)!
            let root = try #require(try JSONSerialization.jsonObject(with: TestSeed.rebased(raw, now: launch)) as? [String: Any])
            let all = try #require(root["sessions"] as? [[String: Any]])
            func day(_ r: [String: Any]) -> Bool { cal.isDate(f.date(from: r["date"] as! String)!, inSameDayAs: launch) }
            let onWedding = all.filter { ($0["id"] as? String) != "sd_today_wed" && day($0) }.map { $0["id"] as! String }
            #expect(onWedding.isEmpty, "на дне свадьбы \(iso) стоит \(onWedding)")
        }
    }

    /// 30и.9 (Алексей 14.11: «почему у нас свадьба в 00:00 начинается?»): рамки свадьбы «сегодня» — не сутки с нуля. Она начинается с первой
    /// точки маршрута, и строка плашки экрана блокировки читает именно эти рамки: «Сейчас: Букет невесты» над «08:00 – 02:00 · 18 ч».
    /// Код плашки верен (диапазон — рамки самой съёмки, `ActivityFrame.range`), неверной была запись засева: `min 0`, `end 1439`.
    @Test func theWeddingOfTodayStartsWithItsFirstStepNotAtMidnight() throws {
        let snap = try #require(TestSeed.snapshot())
        let s = try #require(snap.sessions.first { $0.id == "sd_today_wed" })
        let first = try #require(s.timedRoute.first?.start)
        #expect(s.start == first, "свадьба начинается в \(s.start), первая точка — в \(first)")
        #expect(s.start > 0, "начало в полночь — заготовка «сутки целиком», не свадьба")
        #expect(s.endMinute - s.start < 20 * 60, "свадьба «23 ч 59 мин» — тоже не свадьба")
        #expect(s.endMinute >= (s.timedRoute.compactMap(\.end).max() ?? 0), "последняя точка выходит за конец съёмки")
    }

    /// Та же запись, как её читает плашка: диапазон под «Сейчас: …» — рамки свадьбы, часы настоящие.
    @Test func theActivityLineOfTheSeedWeddingReadsBelievableHours() throws {
        let a = try app("2026-09-29T20:08:00+07:00")
        let feed = a.makeWidgetFeed()
        let shoot = try #require(feed.shoots.first { $0.id == "sd_today_wed" })
        let frame = a.activityFrame(feed, shoot, at: a.now())
        #expect(frame.status.contains("Букет"), "«сейчас» — \(frame.status)")
        #expect(frame.range == "08:00 – 02:00 · 18 ч", "диапазон — \(frame.range)")
    }

    /// «Заполнить»: в форме столько же строк, сколько точек в записи. Веб (`loadRoute`) ставит
    /// первой строкой место записи, если оно не начало первой точки, — засев держит их согласованными.
    @Test func fillFormShowsExactlyTheRoutePoints() throws {
        let snap = try #require(TestSeed.snapshot())
        let s = try #require(snap.sessions.first { $0.id == "sd_today_wed" })
        #expect(s.route.count == 12)
        #expect(EventForm.editing(s).route.count == s.route.count)
    }
}

/// Свежая установка тестовой сборки (шаг «Свои данные»): город Алексея — Томск, а не Барнаул,
/// и его студия с тремя залами; чужие данные засев не перетирает.
@MainActor
struct TestSeedOwnDataTests {
    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
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

    private func tempStore() -> (Store, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-seed-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (Store(directory: dir), dir)
    }

    /// Телефон Алексея стоит в Москве: город должен прийти из засева, а не из пояса телефона.
    private func app(_ snap: Snapshot) -> AppModel {
        AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                 locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
    }

    @Test func freshInstallStartsInTomskWithOwnStudio() async throws {
        let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
        let snap = await AppModel.startSnapshot(store: store, fresh: true, bundleID: "Novopashin.LightPlan.Test")
        let a = app(snap)

        #expect(a.homeCityName == "Томск")
        #expect(a.citySource == .settings)
        #expect(abs(a.place.place.latitude - 56.4977) < 0.001)
        #expect(abs(a.place.place.longitude - 84.9744) < 0.001)
        #expect(a.place.place.zone.identifier == "Asia/Tomsk")

        let st = try #require(a.studios.first { $0.id == "sd_st_tomson" })
        #expect(st.name == "Томсон")                       // «Фотостудия» дописывает приложение
        #expect(st.address == "Томск, Красноармейская, 101а")
        #expect(st.town == "Томск")
        #expect(TelFormat.e164(st.phone, country: a.telCountry) == "+79234123330")
        #expect(st.halls.map(\.name) == ["Эдисон", "Сфера", "Вегас"])
        // Каждый зал, названный в записях засева, есть у студии.
        for s in snap.sessions where s.studioId == "sd_st_tomson" {
            #expect(st.halls.contains { $0.id == s.hallId }, "зал \(s.hallId ?? "-") вне студии")
        }
    }

    /// Слова Алексея: студия на набережной называется просто «Набережная»; залы Томсона не задеты.
    @Test func embankmentStudioIsNamedNaberezhnaya() async throws {
        let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
        let snap = await AppModel.startSnapshot(store: store, fresh: true, bundleID: "Novopashin.LightPlan.Test")
        let a = app(snap)
        let st = try #require(a.studios.first { $0.id == "sd_st_sfera" })
        #expect(st.name == "Набережная")
        #expect(st.address == "Томск, Набережная реки Ушайки, 12")
        #expect(st.halls.map(\.name) == ["Циклорама", "Лофт"])
        #expect(!a.studios.contains { $0.name.contains("Сфера на Набережной") })
        #expect(a.studios.first { $0.id == "sd_st_tomson" }?.halls.map(\.name) == ["Эдисон", "Сфера", "Вегас"])
        // Записи засева, привязанные к студии, подписаны тем же именем.
        for s in snap.sessions where s.studioId == "sd_st_sfera" { #expect(s.place == "Набережная") }
    }

    @Test func existingUserDataIsNotSeededOver() async throws {
        let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
        var own = Snapshot()
        own.extra["me"] = .object(["city": .string("Казань"), "cityLat": .number(55.79), "cityLon": .number(49.12),
                          "cityAt": .string("Казань"), "cityCC": .string("ru")])
        own.studios = [Studio(id: "mine", name: "Своя", latitude: nil, longitude: nil)]
        try await store.saveNow(own)
        let snap = await AppModel.startSnapshot(store: store, fresh: false, bundleID: "Novopashin.LightPlan.Test")
        #expect(app(snap).homeCityName == "Казань")
        #expect(snap.studios.map(\.id) == ["mine"])
    }

    @Test func mainAppIsNeverSeeded() async {
        let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
        let snap = await AppModel.startSnapshot(store: store, fresh: true, bundleID: "Novopashin.LightPlan")
        #expect(snap.studios.isEmpty)
        #expect(app(snap).homeCityName.isEmpty)
    }
}
