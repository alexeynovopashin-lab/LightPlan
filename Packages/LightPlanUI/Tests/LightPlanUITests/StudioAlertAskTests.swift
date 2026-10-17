import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Плашка перед системным окном уведомлений (шаг 30а.2). Система уведомлений — подставной центр: настоящего окна
/// в тестах нет, считается, сколько раз его позвали.
@MainActor
struct StudioAlertAskTests {

    private actor Fake: NotificationCentering {
        var status: NotificationAuthorization
        private(set) var asked = 0
        let grant: Bool
        init(_ status: NotificationAuthorization, grant: Bool = true) { self.status = status; self.grant = grant }
        func authorization() -> NotificationAuthorization { status }
        func requestAuthorization() -> Bool {
            asked += 1
            status = grant ? .allowed : .denied
            return grant
        }
        func pending() -> [PendingAlert] { [] }
        func add(_ alert: ScheduledAlert) -> Bool { true }
        func remove(ids: [String]) {}
    }

    /// Центр с управляемой задержкой: `authorization()` стоит, пока тест не вызовет `release()`. Без sleep.
    private actor Gated: NotificationCentering {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var open = false
        var waiting: Int { waiters.count }
        func release() { open = true; waiters.forEach { $0.resume() }; waiters = [] }
        func authorization() async -> NotificationAuthorization {
            if !open { await withCheckedContinuation { waiters.append($0) } }
            return .notDetermined
        }
        func requestAuthorization() -> Bool { true }
        func pending() -> [PendingAlert] { [] }
        func add(_ alert: ScheduledAlert) -> Bool { true }
        func remove(ids: [String]) {}
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

    /// Запись 20.10 с точкой «Томсон / Эдисон» и часами; `withStudio: false` — съёмка без студии.
    private static func snapshot(withStudio: Bool = true, extra: [String: JSONValue] = [:]) -> Snapshot {
        var snap = Snapshot()
        var st = Studio(id: "st1", name: "Томсон", latitude: nil, longitude: nil)
        st.halls = [Studio.Hall(id: "h1", name: "Эдисон")]
        snap.studios = [st]
        var s = Session(id: "s1", kind: .shoot, day: CivilDate(year: 2026, month: 10, day: 20), start: 720, end: 780,
                        duration: 60, genre: .portrait)
        s.route = [RoutePoint(start: 720, end: 780, name: withStudio ? "Студия" : "Двор",
                              studioId: withStudio ? "st1" : nil, hallId: withStudio ? "h1" : nil)]
        snap.sessions = [s]
        snap.extra = extra
        return snap
    }

    private func model(_ snap: Snapshot, center: Fake?) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-10-19T10:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: DryWeather(), now: { now })
        app.alertCenter = center
        return app
    }

    private func modelGated(_ snap: Snapshot, center: Gated) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-10-19T10:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: DryWeather(), now: { now })
        app.alertCenter = center
        return app
    }

    private func settle(_ app: AppModel) async {
        for _ in 0..<5 {
            await app.alertOfferTask?.value
            await app.alertChain?.value
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Сохранить запись так, как это делает галочка формы.
    private func save(_ app: AppModel) async {
        app.openForm(editing: "s1")
        #expect(app.saveForm() != nil)
        await settle(app)
    }

    // MARK: - Показ

    @Test func firstSaveWithStudioShowsThePlateAndAsksNothing() async {
        let fake = Fake(.notDetermined)
        let app = model(Self.snapshot(), center: fake)
        await save(app)
        #expect(app.studioAlertAsk)
        #expect(await fake.asked == 0, "системное окно не зовётся до «Да»")
        #expect(app.studioAlertsOn == false)
    }

    @Test func yesAsksTheSystemAndTurnsTheToggleOn() async {
        let fake = Fake(.notDetermined)
        let app = model(Self.snapshot(), center: fake)
        await save(app)
        app.answerStudioAlertAsk(yes: true)
        await settle(app)
        #expect(app.studioAlertAsk == false)
        #expect(await fake.asked == 1)
        #expect(app.studioAlertsOn)
    }

    @Test func yesWithSystemRefusalLeavesTheToggleOff() async {
        let fake = Fake(.notDetermined, grant: false)
        let app = model(Self.snapshot(), center: fake)
        await save(app)
        app.answerStudioAlertAsk(yes: true)
        await settle(app)
        #expect(await fake.asked == 1)
        #expect(app.studioAlertsOn == false)
    }

    @Test func noClosesThePlateWithoutTheSystemWindow() async {
        let fake = Fake(.notDetermined)
        let app = model(Self.snapshot(), center: fake)
        await save(app)
        app.answerStudioAlertAsk(yes: false)
        await settle(app)
        #expect(app.studioAlertAsk == false)
        #expect(await fake.asked == 0)
        #expect(app.studioAlertsOn == false)
    }

    @Test func plateNeverComesBackAfterNoAndNotAfterARelaunch() async {
        let fake = Fake(.notDetermined)
        let app = model(Self.snapshot(), center: fake)
        await save(app)
        app.answerStudioAlertAsk(yes: false)
        await save(app)
        #expect(app.studioAlertAsk == false, "второе сохранение в том же запуске")
        // Новый запуск: память — в снимке.
        let relaunched = model(app.snapshotForTests, center: Fake(.notDetermined))
        await save(relaunched)
        #expect(relaunched.studioAlertAsk == false, "после перезапуска")
    }

    // MARK: - Когда плашки нет

    @Test func alreadyAllowedInTheSystemNoPlate() async {
        let fake = Fake(.allowed)
        let app = model(Self.snapshot(), center: fake)
        await save(app)
        #expect(app.studioAlertAsk == false)
        #expect(await fake.asked == 0)
        #expect(app.studioAlertsOn, "тумблер включается сам по правилу 30а")
    }

    @Test func deniedInTheSystemNoPlateAndTheRowLeadsToSettings() async {
        let fake = Fake(.denied)
        let app = model(Self.snapshot(), center: fake)
        await save(app)
        #expect(app.studioAlertAsk == false)
        #expect(await fake.asked == 0)
        #expect(app.studioAlertsNeedSettings)
    }

    @Test func toggleAlreadyOnNoPlate() async {
        let fake = Fake(.notDetermined)
        let app = model(Self.snapshot(), center: fake)
        app.setStudioAlerts(true)
        await settle(app)
        #expect(app.studioAlertsOn)
        await save(app)
        #expect(app.studioAlertAsk == false)
        #expect(await fake.asked == 1, "только то нажатие на тумблер")
    }

    @Test func shootWithoutStudioNoPlate() async {
        let fake = Fake(.notDetermined)
        let app = model(Self.snapshot(withStudio: false), center: fake)
        await save(app)
        #expect(app.studioAlertAsk == false)
        #expect(await fake.asked == 0)
    }

    @Test func studioAlertsTurnedOffByThePersonNoPlate() async {
        let fake = Fake(.notDetermined)
        let app = model(Self.snapshot(extra: ["notif": .object(["studio": .bool(false)])]), center: fake)
        await save(app)
        #expect(app.studioAlertAsk == false)
    }

    // MARK: - Гонки и память

    @Test func toggleTurnedOffWhileTheSystemAnswersNoPlate() async {
        let gate = Gated()
        let app = modelGated(Self.snapshot(), center: gate)
        app.openForm(editing: "s1")
        #expect(app.saveForm() != nil)
        for _ in 0..<10_000 where await gate.waiting == 0 { await Task.yield() }
        #expect(await gate.waiting >= 1, "предложение ждёт ответа системы")
        app.setStudioAlerts(false)
        for _ in 0..<10_000 where app.studioAlertsWanted { await Task.yield() }
        #expect(app.studioAlertsWanted == false)
        await gate.release()
        await app.alertOfferTask?.value
        #expect(app.studioAlertAsk == false, "за время ожидания тумблер выключили")
    }

    @Test func closingTheAppWithThePlateOpenDoesNotSpendTheOffer() async {
        let app = model(Self.snapshot(), center: Fake(.notDetermined))
        await save(app)
        #expect(app.studioAlertAsk)
        // Приложение закрыли, не ответив: в памяти отметки нет, новый запуск спросит снова.
        let relaunched = model(app.snapshotForTests, center: Fake(.notDetermined))
        await save(relaunched)
        #expect(relaunched.studioAlertAsk, "ответа не было — плашка вернётся")
    }

    @Test func plateTextIsTheStudioHourWording() {
        let app = model(Self.snapshot(), center: nil)
        #expect(app.lexicon.t("studio.askT") == "Предупреждать за 10 и 5 минут до конца студийного часа?")
    }
}
