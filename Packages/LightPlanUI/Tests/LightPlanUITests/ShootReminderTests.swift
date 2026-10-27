import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// «Напоминать о съёмке» (шаг «Напоминание-1») на модели приложения: слова карточки, номер шапки, настройка,
/// корзина снимает напоминание. Система уведомлений — пустышка.
@MainActor
struct ShootReminderTests {

    private actor Fake: NotificationCentering {
        var status: NotificationAuthorization
        var table: [String: ScheduledAlert] = [:]
        init(_ status: NotificationAuthorization = .allowed) { self.status = status }
        func authorization() -> NotificationAuthorization { status }
        func requestAuthorization() -> Bool { status = .allowed; return true }
        func pending() -> [PendingAlert] { table.values.map { PendingAlert(id: $0.id, signature: $0.signature) } }
        func add(_ alert: ScheduledAlert) -> Bool { table[alert.id] = alert; return true }
        func remove(ids: [String]) { ids.forEach { table[$0] = nil } }
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

    static let day = CivilDate(year: 2026, month: 10, day: 20)

    /// Портрет Кирилла 20.10 в 12:00, «Студия Томсон», номер в строке клиента.
    private static func shoot(_ id: String = "s1", kind: RecordKind = .shoot) -> Session {
        var s = Session(id: id, kind: kind, day: day, start: 720, end: 810, duration: 90, genre: .portrait)
        s.contact = "Кирилл"
        s.clientPhone = "+79618878078"
        s.place = "Студия Томсон"
        return s
    }

    private func model(_ sessions: [Session], notif: [String: JSONValue]? = nil, center: Fake) -> AppModel {
        var snap = Snapshot()
        snap.sessions = sessions
        if let notif { snap.extra["notif"] = .object(notif) }
        let now = ISO8601DateFormatter().date(from: "2026-10-19T10:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: DryWeather(), now: { now })
        app.alertCenter = center
        return app
    }

    private func settle(_ app: AppModel) async {
        for _ in 0..<5 {
            await app.alertChain?.value
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func defaultIsFifteenMinutesWithTheCardsWords() async {
        let fake = Fake()
        let app = model([Self.shoot()], center: fake)
        #expect(app.remindMinutes == 15)
        app.syncAlerts(force: true)
        await settle(app)
        let a = await fake.table["lp.remind.s1"]
        #expect(a?.title == "Кирилл · 12:00")
        #expect(a?.body == "Портрет · Студия Томсон\n+7 961 887-80-78")
        // 12:00 в Москве минус 15 минут.
        #expect(a?.fire == Moment(ISO8601DateFormatter().date(from: "2026-10-20T11:45:00+03:00")!))
        #expect(a?.urgent == true)
    }

    @Test func meetingSaysMeetingAndTheFriendsNumberWins() async {
        var meet = Self.shoot("m1", kind: .meet)
        meet.via = ContactVia(relation: .girlfriend, name: "Алёна", phone: "+79131234567")
        let fake = Fake()
        let app = model([meet], center: fake)
        app.syncAlerts(force: true)
        await settle(app)
        let a = await fake.table["lp.remind.m1"]
        #expect(a?.body == "Встреча · портрет · Студия Томсон\nна связи: Алёна, подруга · +7 913 123-45-67")
    }

    @Test func noClientNameNoRepeatedGenre() async {
        var s = Self.shoot()
        s.contact = ""
        s.clientPhone = ""
        let fake = Fake()
        let app = model([s], center: fake)
        app.syncAlerts(force: true)
        await settle(app)
        let a = await fake.table["lp.remind.s1"]
        #expect(a?.title == "Портрет · 12:00" && a?.body == "Студия Томсон")
    }

    @Test func choosingOffClearsAndThirtyMovesTheMoment() async {
        let fake = Fake()
        let app = model([Self.shoot()], center: fake)
        app.syncAlerts(force: true)
        await settle(app)
        app.setRemindMinutes(30)
        await settle(app)
        #expect(await fake.table["lp.remind.s1"]?.fire == Moment(ISO8601DateFormatter().date(from: "2026-10-20T11:30:00+03:00")!))
        app.setRemindMinutes(0)
        await settle(app)
        #expect(await fake.table.isEmpty)
        guard case .object(let o)? = app.snapshotForTests.extra["notif"] else { Issue.record("notif пропал"); return }
        #expect(o["remind"] == .number(0))
    }

    @Test func webMasterSwitchOffMeansNoReminder() async {
        let fake = Fake()
        let app = model([Self.shoot()], notif: ["all": .bool(false)], center: fake)
        app.syncAlerts(force: true)
        await settle(app)
        #expect(await fake.table.isEmpty)
    }

    @Test func trashingTheShootCancelsItsReminder() async {
        let fake = Fake()
        let app = model([Self.shoot("s1"), Self.shoot("s2")], center: fake)
        app.syncAlerts(force: true)
        await settle(app)
        #expect(await fake.table.keys.sorted() == ["lp.remind.s1", "lp.remind.s2"])
        app.trashSession(id: "s1")
        await settle(app)
        #expect(await fake.table.keys.sorted() == ["lp.remind.s2"])
    }
}
