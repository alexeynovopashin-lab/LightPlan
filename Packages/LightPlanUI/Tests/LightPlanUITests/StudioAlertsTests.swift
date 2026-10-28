import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Студийный час по расписанию (шаг 30а): тексты сигналов, право уведомлять,
/// переписывание при правках данных. Система уведомлений — пустышка.
@MainActor
struct StudioAlertsTests {

    private actor Fake: NotificationCentering {
        var status: NotificationAuthorization
        var table: [String: ScheduledAlert] = [:]
        private(set) var asked = 0
        let grant: Bool
        init(_ status: NotificationAuthorization = .notDetermined, grant: Bool = true) {
            self.status = status; self.grant = grant
        }
        func authorization() -> NotificationAuthorization { status }
        func requestAuthorization() -> Bool {
            asked += 1
            status = grant ? .allowed : .denied
            return grant
        }
        func pending() -> [PendingAlert] { table.values.map { PendingAlert(id: $0.id, signature: $0.signature) } }
        func add(_ alert: ScheduledAlert) -> Bool { table[alert.id] = alert; return true }
        func remove(ids: [String]) { ids.forEach { table[$0] = nil } }
        func foreignOne() { table["lp.other.1"] = ScheduledAlert(id: "lp.other.1", sessionId: "", fire: Moment(milliseconds: 0),
                                                              offsetHours: 0, title: "", body: "") }
    }

    private struct DryWeather: WeatherSource {
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            HourlyWeather(time: [], cloud: [], temperature: [], windSpeed: [], precipitation: [], weatherCode: [])
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

    /// Студия «Томсон» с двумя залами; запись 20.10 с одной ячейкой.
    private static func snapshot(cell: (Int, Int) = (720, 780), extra: [String: JSONValue] = [:]) -> Snapshot {
        var snap = Snapshot()
        var st = Studio(id: "st1", name: "Томсон", latitude: nil, longitude: nil)
        st.halls = [Studio.Hall(id: "h1", name: "Эдисон")]
        snap.studios = [st]
        var s = Session(id: "s1", kind: .shoot, day: CivilDate(year: 2026, month: 10, day: 20), start: cell.0, end: cell.1,
                        duration: cell.1 - cell.0, genre: .portrait)
        s.route = [RoutePoint(start: cell.0, end: cell.1, name: "Студия", studioId: "st1", hallId: "h1")]
        snap.sessions = [s]
        snap.extra = extra
        // Напоминание о съёмке — своя полоса со своими тестами (`ShootReminderTests`); здесь мерим студийный час.
        var notif: [String: JSONValue] = [:]
        if case .object(let o)? = extra["notif"] { notif = o }
        notif["remind"] = .number(0)
        snap.extra["notif"] = .object(notif)
        return snap
    }

    private func model(_ snap: Snapshot, center: Fake?, at iso: String = "2026-10-19T10:00:00+03:00") -> AppModel {
        let now = ISO8601DateFormatter().date(from: iso)!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: DryWeather(), now: { now })
        app.alertCenter = center
        return app
    }

    private func settle(_ app: AppModel) async {
        // Задача расписания и задача включения: ждём обе.
        for _ in 0..<5 {
            await app.alertChain?.value
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func iso(_ s: String) -> Moment { Moment(ISO8601DateFormatter().date(from: s)!) }

    // MARK: - Слова

    @Test func bodyAndTitleAreTheBetasWords() {
        let t = Lexicon("ru")
        let clock = ClockText(language: "ru", preference: .h24)
        let n = StudioSchedule.Notice(id: "x", sessionId: "s", stage: 1, fire: Moment(milliseconds: 0), minutesLeft: 10,
                                      deadline: 12 * 60 + 55, offsetHours: 3, studioName: "Томсон", hallName: "Эдисон")
        let a = StudioAlertText.alert(n, lexicon: t, clock: clock)
        #expect(a.title == "12:55 · студийный час")
        #expect(a.body == "Выйти из зала через 10 минут. Томсон, Эдисон.")
        let five = StudioSchedule.Notice(id: "y", sessionId: "s", stage: 2, fire: Moment(milliseconds: 0), minutesLeft: 5,
                                         deadline: 775, offsetHours: 3, studioName: "Томсон", hallName: nil)
        #expect(StudioAlertText.alert(five, lexicon: t, clock: clock).body == "Выйти из зала через 5 минут. Томсон.")
        let zero = StudioSchedule.Notice(id: "z", sessionId: "s", stage: 2, fire: Moment(milliseconds: 0), minutesLeft: 0,
                                         deadline: 775, offsetHours: 3, studioName: "Томсон", hallName: nil)
        #expect(StudioAlertText.alert(zero, lexicon: t, clock: clock).body == "Пора выходить из зала. Томсон.")
    }

    // MARK: - Разрешение

    @Test func permissionIsNotAskedAtLaunchOnlyWhenTheToggleTurnsOn() async {
        let fake = Fake(.notDetermined)
        let app = model(Self.snapshot(), center: fake)
        app.syncAlerts(force: true)      // запуск, возврат в приложение
        await settle(app)
        #expect(await fake.asked == 0)
        #expect(await fake.table.isEmpty)
        #expect(app.studioAlertsOn == false)   // хочет, но ничего не придёт — тумблер честен
        app.setStudioAlerts(true)
        await settle(app)
        #expect(await fake.asked == 1)
        #expect(app.studioAlertsOn)
        #expect(await fake.table.count == 2)
    }

    @Test func refusalBreaksNothing() async {
        let fake = Fake(.notDetermined, grant: false)
        var snap = Self.snapshot()
        snap.extra["studioTold"] = .object(["s1": .object(["to": .number(775), "n": .number(1)])])
        let app = model(snap, center: fake)
        app.setStudioAlerts(true)
        await settle(app)
        #expect(await fake.asked == 1)
        #expect(await fake.table.isEmpty)
        #expect(app.studioAlertsOn == false)
        #expect(app.studioAlertsNeedSettings)
        // Память баннеров при открытии нетронута.
        #expect(app.snapshotForTests.extra["studioTold"] == snap.extra["studioTold"])
        // Приложение живёт: правка данных проходит, без расписания.
        app.snapshot.sessions[0].route[0].end = 840
        app.persist()
        await settle(app)
        #expect(await fake.table.isEmpty)
        #expect(await fake.asked == 1)
    }

    @Test func lastTapWinsWhenTheAnswerComesLate() async {
        let fake = Fake(.notDetermined)
        let app = model(Self.snapshot(), center: fake)
        app.setStudioAlerts(true)
        app.setStudioAlerts(false)       // нажали снова, пока шёл системный вопрос
        await settle(app)
        #expect(app.studioAlertsWanted == false)
        #expect(await fake.table.isEmpty)
    }

    @Test func switchingOffRemovesAllOursAndLeavesForeignAlone() async {
        let fake = Fake(.allowed)
        let app = model(Self.snapshot(), center: fake)
        await fake.foreignOne()
        app.syncAlerts(force: true)
        await settle(app)
        #expect(await fake.table.count == 3)
        app.setStudioAlerts(false)
        await settle(app)
        #expect(await fake.table.keys.sorted() == ["lp.other.1"])
        #expect(app.studioAlertsOn == false)
    }

    // MARK: - Расписание по данным

    @Test func scheduleLandsOnTheBetasNumbersInThePlacesZone() async {
        let fake = Fake(.allowed)
        let app = model(Self.snapshot(), center: fake)
        app.syncAlerts(force: true)
        await settle(app)
        let t = await fake.table
        #expect(t.keys.sorted() == ["lp.studio.s1.0.1", "lp.studio.s1.0.2"])
        // 12:00–13:00 по Москве: дедлайн 12:55, сигналы 12:45 и 12:50.
        #expect(t["lp.studio.s1.0.1"]?.fire == iso("2026-10-20T12:45:00+03:00"))
        #expect(t["lp.studio.s1.0.2"]?.fire == iso("2026-10-20T12:50:00+03:00"))
        #expect(t["lp.studio.s1.0.1"]?.body == "Выйти из зала через 10 минут. Томсон, Эдисон.")
        #expect(t["lp.studio.s1.0.2"]?.body == "Выйти из зала через 5 минут. Томсон, Эдисон.")
    }

    @Test func editingHoursAndExtendingRewriteTheSameRequests() async {
        let fake = Fake(.allowed)
        let app = model(Self.snapshot(), center: fake)
        app.syncAlerts(force: true)
        await settle(app)
        // Подтверждённое продление: конец ячейки уехал на час.
        app.snapshot.sessions[0].route[0].end = 840
        app.persist()
        await settle(app)
        var t = await fake.table
        #expect(t.count == 2)
        #expect(t["lp.studio.s1.0.1"]?.fire == iso("2026-10-20T13:45:00+03:00"))
        #expect(t["lp.studio.s1.0.2"]?.fire == iso("2026-10-20T13:50:00+03:00"))
        // Правка часов: ячейка уехала на вечер целиком.
        app.snapshot.sessions[0].route[0].start = 1080
        app.snapshot.sessions[0].route[0].end = 1140
        app.persist()
        await settle(app)
        t = await fake.table
        #expect(t.count == 2)
        #expect(t["lp.studio.s1.0.1"]?.fire == iso("2026-10-20T18:45:00+03:00"))
    }

    @Test func removingTheCellOrTheShootRemovesTheirRequests() async {
        let fake = Fake(.allowed)
        let app = model(Self.snapshot(), center: fake)
        app.syncAlerts(force: true)
        await settle(app)
        #expect(await fake.table.count == 2)
        app.snapshot.sessions[0].route = []
        app.persist()
        await settle(app)
        #expect(await fake.table.isEmpty)
        // И запись целиком — в корзину.
        let app2 = model(Self.snapshot(), center: fake)
        app2.syncAlerts(force: true)
        await settle(app2)
        #expect(await fake.table.count == 2)
        app2.trashSession(id: "s1")
        await settle(app2)
        #expect(await fake.table.isEmpty)
    }

    @Test func reopeningFindsAMovedScheduleAndFixesIt() async {
        let fake = Fake(.allowed)
        let app = model(Self.snapshot(), center: fake)
        app.syncAlerts(force: true)
        await settle(app)
        // Расписание разошлось с данными (запрос потерян): возврат в приложение чинит.
        await fake.remove(ids: ["lp.studio.s1.0.2"])
        #expect(await fake.table.count == 1)
        app.syncAlerts(force: true)
        await settle(app)
        #expect(await fake.table.count == 2)
    }

    @Test func passedStagesAreNotScheduled() async {
        let fake = Fake(.allowed)
        // 12:47 — первая ступень (12:45) прошла.
        let app = model(Self.snapshot(), center: fake, at: "2026-10-20T12:47:00+03:00")
        app.syncAlerts(force: true)
        await settle(app)
        #expect(await fake.table.keys.sorted() == ["lp.studio.s1.0.2"])
    }

    @Test func sixtyFourCeilingKeepsTheNearest() async {
        let fake = Fake(.allowed)
        var snap = Self.snapshot()
        let first = snap.sessions[0]
        snap.sessions = (0..<40).map { i in
            var s = first
            s.id = "s\(i)"
            s.day = first.day.adding(days: i)
            return s
        }
        let app = model(snap, center: fake)
        app.syncAlerts(force: true)
        await settle(app)
        #expect(await fake.table.count == 64)
        #expect(await fake.table["lp.studio.s31.0.2"] != nil)
        #expect(await fake.table["lp.studio.s32.0.1"] == nil)
    }

    @Test func notifFlagsAreTheWebsKeysAndOtherKeysSurvive() async {
        let fake = Fake(.allowed)
        let snap = Self.snapshot(extra: ["notif": .object(["all": .bool(true), "wx": .bool(false), "srv": .bool(true),
                                                          "clash": .bool(true), "studio": .bool(false)])])
        let app = model(snap, center: fake)
        #expect(app.studioAlertsWanted == false)
        app.syncAlerts(force: true)
        await settle(app)
        #expect(await fake.table.isEmpty)
        app.setStudioAlerts(true)
        await settle(app)
        guard case .object(let o)? = app.snapshotForTests.extra["notif"] else { Issue.record("notif пропал"); return }
        #expect(o["studio"] == .bool(true) && o["all"] == .bool(true))
        #expect(o["wx"] == .bool(false), "чужие ключи не тронуты")
        #expect(await fake.table.count == 2)
    }

    @Test func scheduleDoesNotDependOnThePhonesZone() async {
        // Запись с точкой: пояс её, а не телефона. Телефон в Токио и в Нью-Йорке — расписание одно.
        var snap = Self.snapshot()
        snap.studios[0].latitude = 55.75
        snap.studios[0].longitude = 37.62
        func table(zone: String) async -> [String: Moment] {
            let fake = Fake(.allowed)
            let now = ISO8601DateFormatter().date(from: "2026-10-19T10:00:00+03:00")!
            let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: zone)!,
                               locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                               weatherSource: DryWeather(), now: { now })
            app.alertCenter = fake
            app.syncAlerts(force: true)
            await settle(app)
            return await fake.table.mapValues(\.fire)
        }
        let a = await table(zone: "Asia/Tokyo"), b = await table(zone: "America/New_York")
        #expect(a.count == 2 && a == b)
    }
}
