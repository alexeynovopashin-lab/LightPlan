import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 25, шаг 3: пояс точки съёмки у геокодера, шапка, плитка дня,
/// студийный час — на записях посева сезона (`Fixtures/shots/seed_planner.json`,
/// телефон в Барнауле).
@MainActor
struct CardHeadTileTests {

    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }
    /// Геокодер, который знает один пояс на всё (`nil` — молчит).
    private struct ZoneGeocoder: ReverseGeocoding {
        let zone: String?
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: zone)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    /// Приложение посева в момент `iso`; `tomsk` — пояс Томска уже в кэше.
    private func app(_ iso: String, tomsk: Bool = true, manualEnd: Bool = false, geocoder: String? = nil,
                     edit: (inout Snapshot) -> Void = { _ in }) -> AppModel {
        var snap = CardPhaseTests.seed
        if tomsk, case .object(var z)? = snap.extra["zones"] {
            z["56.5,85.0"] = .string("Asia/Tomsk")
            snap.extra["zones"] = .object(z)
        }
        snap.manualEnd = manualEnd
        edit(&snap)
        let now = ISO8601DateFormatter().date(from: iso)!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                        locator: NoLocator(), geocoder: ZoneGeocoder(zone: geocoder), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func rec(_ app: AppModel, _ id: String) -> Session { app.sessions.first { $0.id == id }! }

    private func tile(_ app: AppModel, _ id: String) -> DayTileText {
        let s = rec(app, id)
        return DayTileText(s, phase: app.phase(of: s), app: app)
    }

    private func head(_ app: AppModel, _ id: String) -> CardHeadText {
        let s = rec(app, id)
        return CardHeadText(s, phase: app.phase(of: s), app: app)
    }

    private func studio(_ app: AppModel, _ id: String) -> StudioTileState? {
        let s = rec(app, id)
        return StudioTileState.of(s, phase: app.phase(of: s), app: app)
    }

    // MARK: - Пояс точки съёмки

    /// Пояс Томска в посеве не записан: по оценке долготы (+6) в 13:00
    /// телефона портрет в студии ещё впереди. Карточка спросила геокодер —
    /// «Asia/Tomsk» (+7), съёмка идёт, и пояс лёг в снимок под ключом веба.
    @Test func shootPointZoneComesFromGeocoder() async {
        let a = app("2026-09-23T13:00:00+07:00", tomsk: false, geocoder: "Asia/Tomsk")
        #expect(a.phase(of: rec(a, "sd_sep_now")) == .before)
        #expect(a.zoneTag(of: rec(a, "sd_sep_now")) == "UTC+6")
        await a.learnZone(of: rec(a, "sd_sep_now"))
        #expect(a.phase(of: rec(a, "sd_sep_now")) == .during)
        #expect(a.zoneTag(of: rec(a, "sd_sep_now")) == nil)
        guard case .object(let z)? = a.snapshotForTests.extra["zones"] else { Issue.record("нет zones"); return }
        #expect(z["56.5,85.0"] == .string("Asia/Tomsk"))
        #expect(z["53.5,84.0"] == .string("Asia/Barnaul"))      // прежние зоны целы
    }

    /// Геокодер молчит (нет сети) — остаётся оценка, снимок не трогается.
    @Test func silentGeocoderKeepsEstimate() async {
        let a = app("2026-09-23T13:00:00+07:00", tomsk: false, geocoder: nil)
        await a.learnZone(of: rec(a, "sd_sep_now"))
        #expect(a.phase(of: rec(a, "sd_sep_now")) == .before)
        guard case .object(let z)? = a.snapshotForTests.extra["zones"] else { Issue.record("нет zones"); return }
        #expect(z["56.5,85.0"] == nil)
    }

    /// «Завершить» после того, как пояс узнан, пишет минуту по часам Томска.
    @Test func finishUsesLearnedZone() async {
        let a = app("2026-09-23T13:30:00+07:00", tomsk: false, manualEnd: true, geocoder: "Asia/Tomsk")
        await a.learnZone(of: rec(a, "sd_sep_now"))
        a.finishSession(id: "sd_sep_now")
        #expect(rec(a, "sd_sep_now").doneAt == 810)
    }

    // MARK: - Шапка

    @Test func headOfWeddingTheDayBefore() {
        let h = head(app("2026-09-23T13:00:00+07:00"), "sd_sep_wed")
        #expect(h.name == "Лена и Тимур")
        #expect(h.person.isEmpty)
        #expect(h.when == "Свадьба\u{00A0}· 24\u{00A0}сентября,\u{00A0}завтра\u{00A0}· 11:00\u{00A0}–\u{00A0}22:00")
        #expect(h.tel?.shown == "+7 913 343-53-63")
        #expect(h.tel?.dial == "+79133435363")
    }

    /// Заказ: крупно организация, строкой ниже лицо из организации.
    @Test func headOfClientOrderShowsOrgPerson() {
        let h = head(app("2026-09-23T13:00:00+07:00"), "sd_sep_inter")
        #expect(h.name == "Ресторан «Соль»")
        #expect(h.person == "Марат Шаев")
    }

    /// После съёмки — «N дней назад», пока не больше недели.
    @Test func headAfterSaysDaysAgo() {
        let h = head(app("2026-09-23T13:00:00+07:00"), "sd_sep_love")
        #expect(h.when.contains("\u{00A0}· 17\u{00A0}сентября,\u{00A0}6\u{00A0}дней\u{00A0}назад\u{00A0}· 18:00\u{00A0}–\u{00A0}20:00"))
    }

    /// Конец в других сутках называет свою дату.
    @Test func headNamesEndDateAcrossMidnight() {
        let a = app("2026-09-23T13:00:00+07:00") { s in
            var w = Session(id: "late", day: CivilDate(year: 2026, month: 9, day: 24), start: 1150, end: 1630, genre: .wedding)
            w.contact = "Аня и Олег"
            s.sessions.append(w)
        }
        #expect(head(a, "late").when.hasSuffix("03:10\u{00A0}25\u{00A0}сентября"))
    }

    // MARK: - Плитка дня

    /// Свадьба с точками: день до, утро дня, середина, после.
    @Test func dayTileWithRoute() {
        let before = tile(app("2026-09-23T13:00:00+07:00"), "sd_sep_wed")
        #expect(before.now == "11:00\u{00A0}–\u{00A0}22:00")
        #expect(before.plainLeft == "11 часов · 5 точек")
        #expect(before.clock == nil && !before.dot)

        let morning = tile(app("2026-09-24T09:00:00+07:00"), "sd_sep_wed")
        #expect(morning.now == "Скоро: Сборы")
        #expect(morning.plainLeft == "через 2 часа · в 11:00")
        #expect(morning.clock == "09:00")

        let noon = tile(app("2026-09-24T13:30:00+07:00"), "sd_sep_wed")
        #expect(noon.now == "Сейчас: Пара в студии")
        #expect(noon.plainLeft == "осталось 2 часа · дальше Роспись")
        #expect(noon.left.contains("\u{1}2 часа\u{2}"))
        #expect(noon.dot)

        let banquet = tile(app("2026-09-24T21:00:00+07:00"), "sd_sep_wed")
        #expect(banquet.now == "Сейчас: Банкет")
        #expect(banquet.plainLeft == "последняя точка дня")

        let after = tile(app("2026-09-25T09:00:00+07:00"), "sd_sep_wed")
        #expect(after.now == "Съёмка закончена")
        #expect(!after.dot)
    }

    /// Съёмку начали раньше первой точки: «во время», но до неё — «Скоро: …»,
    /// как в тот же день до начала (Алексей, 28.09). Веб здесь пишет «Съёмка
    /// закончена» — ошибку эталона не переносим.
    @Test func duringBeforeFirstPointSaysSoon() {
        let a = app("2026-09-24T10:30:00+07:00") { s in
            var w = Session(id: "early", day: CivilDate(year: 2026, month: 9, day: 24), start: 600, end: 1320, genre: .wedding)
            w.latitude = 53.3548; w.longitude = 83.7698
            w.route = [RoutePoint(start: 660, end: 750, name: "Сборы"), RoutePoint(start: 1170, end: 1320, name: "Банкет")]
            s.sessions.append(w)
        }
        #expect(a.phase(of: rec(a, "early")) == .during)
        let x = tile(a, "early")
        #expect(x.now == "Скоро: Сборы")
        #expect(x.plainLeft == "через 30 мин · в 11:00")
        #expect(x.dot)
    }

    /// Съёмка без точек — отрезок: до, во время, сверх плана, после.
    @Test func dayTileWithoutRoute() {
        let soon = tile(app("2026-09-23T12:00:00+07:00"), "sd_sep_now")
        #expect(soon.now == "12:20\u{00A0}–\u{00A0}13:50")
        #expect(soon.plainLeft == "1,5 часа · через 20 мин")
        let going = tile(app("2026-09-23T13:00:00+07:00"), "sd_sep_now")
        #expect(going.now == "Идёт съёмка")
        #expect(going.plainLeft == "осталось 50 мин · до 13:50")
        let over = tile(app("2026-09-23T14:30:00+07:00", manualEnd: true), "sd_sep_now")
        #expect(over.plainLeft == "сверх плана 40 мин · по записи до 13:50")
        let done = tile(app("2026-09-23T14:30:00+07:00"), "sd_sep_now")
        #expect(done.now == "Съёмка закончена")
        #expect(done.plainLeft == "12:20\u{00A0}–\u{00A0}13:50 · 1,5 часа")
        let meetDone = tile(app("2026-09-23T21:00:00+07:00"), "sd_sep_meet")
        #expect(meetDone.now == "Встреча прошла")
    }

    /// Часы плитки — место съёмки; пояс не телефона — метка рядом.
    @Test func dayTileClockIsShootPlaceClock() {
        let a = app("2026-09-23T18:30:00+03:00") { s in
            var r = Session(id: "msk", day: CivilDate(year: 2026, month: 9, day: 23), start: 1080, end: 1140, genre: .portrait)
            r.latitude = 55.7558; r.longitude = 37.6173
            s.sessions.append(r)
            if case .object(var z)? = s.extra["zones"] { z["56.0,37.5"] = .string("Europe/Moscow"); s.extra["zones"] = .object(z) }
        }
        let x = tile(a, "msk")
        #expect(x.clock == "18:30")
        #expect(x.zone == "UTC+3")
    }

    @Test func laneWordTakesFirstWord() {
        #expect(CardLane.word("Сборы жениха") == "Сборы")
        #expect(CardLane.word("Фотостудийная") == "Фотостудий…")
    }

    // MARK: - Студийный час

    /// Портрет в «Томсоне» 12:20–13:50: выйти в 13:45. В 13:00 — «0:45»,
    /// последние пять минут — по секундам и тревогой, в 13:46 плитки нет, а
    /// номер администратора ещё есть до конца оплаченного.
    @Test func studioHourCountsDownToExit() {
        #expect(studio(app("2026-09-23T12:10:00+07:00"), "sd_sep_now")?.seconds == nil)     // аренда не началась
        let calm = studio(app("2026-09-23T13:00:00+07:00"), "sd_sep_now")!
        #expect(calm.clock == "0:45")
        #expect(calm.exitAt == "13:45")
        #expect(calm.title == "Фотостудия\u{00A0}Томсон. Зал\u{00A0}Эдисон")
        #expect(calm.stage == .calm && calm.note == nil)
        let wrap = studio(app("2026-09-23T13:35:00+07:00"), "sd_sep_now")!
        #expect(wrap.clock == "10:00")
        #expect(wrap.stage == .wrap && wrap.note == "Пора собираться")
        let leave = studio(app("2026-09-23T13:40:30+07:00"), "sd_sep_now")!
        #expect(leave.seconds == 270)
        #expect(leave.clock == "04:30")
        #expect(leave.stage == .leave && leave.note == "Пора выходить")
        #expect(abs(leave.fraction - 0.9) < 1e-9)
        let a = app("2026-09-23T13:46:00+07:00")
        #expect(studio(a, "sd_sep_now")?.seconds == nil)
        #expect(StudioTileState.tel(rec(a, "sd_sep_now"), app: a)?.shown == "+7 961 887-80-78")
        #expect(StudioTileState.tel(rec(app("2026-09-23T13:51:00+07:00"), "sd_sep_now"),
                                    app: app("2026-09-23T13:51:00+07:00")) == nil)
    }

    /// Аренда 23:00 → 02:00: в 00:30 вторых суток до выхода «1:25». Веб берёт
    /// секунды суток и показывает «25:25» — ошибку не переносим.
    @Test func studioHourAfterMidnight() {
        let a = app("2026-09-25T00:30:00+07:00") { s in
            var r = Session(id: "night", day: CivilDate(year: 2026, month: 9, day: 24), start: 1320, end: 1560, genre: .portrait)
            r.studioId = "sd_st_tomson"; r.rentFrom = 1380; r.rentTo = 1560
            s.sessions.append(r)
        }
        let st = studio(a, "night")!
        #expect(st.seconds == 5100)
        #expect(st.clock == "1:25")
        #expect(st.exitAt == "01:55")
    }

    /// У свадьбы студия — точка маршрута: окно — её часы.
    @Test func studioHourFromRoutePoint() {
        let st = studio(app("2026-09-24T13:30:00+07:00"), "sd_sep_wed")!
        #expect(st.window.from == 780 && st.window.to == 900)
        #expect(st.clock == "1:25")
        #expect(st.title == "Фотостудия\u{00A0}Томсон. Зал\u{00A0}Эдисон")   // зал — у точки маршрута
    }
}
