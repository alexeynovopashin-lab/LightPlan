import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// «Поздравлять» в приложении (шаг К6): поля карточки, тумблер сам, право уведомлять, расписание 10:00 по часам
/// телефона, общий потолок со студийным часом, нажатие на уведомление. Система уведомлений — пустышка.
@MainActor
struct GreetAlertsTests {

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
        func greets() -> [String: ScheduledAlert] { table.filter { $0.key.hasPrefix("lp.greet.") } }
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

    private static func person(_ id: String, _ name: String, bd: String? = nil, greet: Bool = false) -> Client {
        var c = Client(id: id, kind: .person)
        var p = ClientPerson(name: name)
        p.birthday = bd
        c.people = [p]
        c.greet = greet
        return c
    }

    private func model(_ snap: Snapshot, center: Fake?, at iso: String = "2026-10-19T10:00:00+03:00",
                       zone: String = "Europe/Moscow") -> AppModel {
        let now = ISO8601DateFormatter().date(from: iso)!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: zone)!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: DryWeather(), now: { now })
        app.alertCenter = center
        return app
    }

    private func settle(_ app: AppModel) async {
        for _ in 0..<6 {
            await app.alertChain?.value
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func snap(_ clients: [Client], sessions: [Session] = []) -> Snapshot {
        var s = Snapshot()
        s.clients = clients
        s.sessions = sessions
        return s
    }

    // MARK: - Расписание

    @Test func birthdayTomorrowIsOneRequestAtTenByThePhonesClock() async {
        let fake = Fake(.allowed)
        let app = model(snap([Self.person("c1", "Ольга Смирнова", bd: "1990-10-20", greet: true)]), center: fake)
        app.syncAlerts(force: true)
        await settle(app)
        let g = await fake.greets()
        #expect(g.keys.sorted() == ["lp.greet.2026-10-20"])
        let a = g["lp.greet.2026-10-20"]
        #expect(a?.wall == WallTime(day: CivilDate(year: 2026, month: 10, day: 20), minutes: 600))
        #expect(a?.fire == Moment(ISO8601DateFormatter().date(from: "2026-10-20T10:00:00+03:00")!))
        #expect(a?.title == "Поздравить клиентов")
        #expect(a?.body == "Сегодня: день рождения — Ольга Смирнова")
        #expect(a?.clientId == "c1")
    }

    @Test func todayIsStillOnBeforeTenAndGoneAfter() async {
        let c = Self.person("c1", "Ольга", bd: "10-19", greet: true)
        let early = Fake(.allowed)
        let a1 = model(snap([c]), center: early, at: "2026-10-19T09:59:00+03:00")
        a1.syncAlerts(force: true)
        await settle(a1)
        #expect(await early.greets().keys.sorted() == ["lp.greet.2026-10-19"])
        let late = Fake(.allowed)
        let a2 = model(snap([c]), center: late, at: "2026-10-19T10:00:00+03:00")
        a2.syncAlerts(force: true)
        await settle(a2)
        #expect(await late.greets().keys.sorted() == ["lp.greet.2027-10-19"])
    }

    @Test func severalOccasionsOneDayOneRequestThatOpensTheList() async {
        var couple = Client(id: "c2", kind: .couple)
        couple.people = [ClientPerson(name: "Анна"), ClientPerson(name: "Иван")]
        couple.greet = true
        var w = Session(id: "w", kind: .shoot, day: CivilDate(year: 2024, month: 10, day: 20), start: 600, end: 1200,
                        duration: 600, genre: .wedding)
        w.clientId = "c2"
        let fake = Fake(.allowed)
        let app = model(snap([Self.person("c1", "Ольга", bd: "10-20", greet: true), couple], sessions: [w]), center: fake)
        app.syncAlerts(force: true)
        await settle(app)
        let g = await fake.greets()
        #expect(g.count == 1)
        #expect(g["lp.greet.2026-10-20"]?.body == "Сегодня: годовщина — Анна и Иван; день рождения — Ольга")
        #expect(g["lp.greet.2026-10-20"]?.clientId == nil)
    }

    @Test func studioHourAndGreetingsShareTheSixtyFour() async {
        var snap = snap((0..<60).map { i in
            let d = CivilDate(year: 2026, month: 10, day: 20).adding(days: i)
            return Self.person("c\(i)", "Человек \(i)", bd: String(format: "%02d-%02d", d.month, d.day), greet: true)
        })
        var st = Studio(id: "st1", name: "Томсон", latitude: nil, longitude: nil)
        st.halls = [Studio.Hall(id: "h1", name: "Эдисон")]
        snap.studios = [st]
        snap.sessions = (0..<40).map { i in
            var s = Session(id: "s\(i)", kind: .shoot, day: CivilDate(year: 2026, month: 10, day: 20).adding(days: i),
                            start: 720, end: 780, duration: 60, genre: .portrait)
            s.route = [RoutePoint(start: 720, end: 780, name: "Студия", studioId: "st1", hallId: "h1")]
            return s
        }
        let fake = Fake(.allowed)
        let app = model(snap, center: fake)
        app.syncAlerts(force: true)
        await settle(app)
        let t = await fake.table
        #expect(t.keys.filter { $0.hasPrefix("lp.greet.") }.count == 40)
        #expect(t.keys.filter { $0.hasPrefix("lp.studio.") }.count == 24)
        // Поздравления выключили у всех — студийный час забирает места обратно.
        for c in app.snapshot.clients { app.setClientGreet(c.id, false) }
        await settle(app)
        let t2 = await fake.table
        #expect(t2.keys.filter { $0.hasPrefix("lp.greet.") }.isEmpty && t2.count == 64)
    }

    // MARK: - Карточка

    @Test func firstBirthdayTurnsGreetOnAndAsksPermissionOnce() async {
        let fake = Fake(.notDetermined)
        let app = model(snap([Self.person("c1", "Ольга")]), center: fake)
        app.syncAlerts(force: true)
        await settle(app)
        #expect(await fake.asked == 0, "на запуске не спрашиваем")
        app.setClientBirthday("c1", at: 0, Birthday(month: 10, day: 25))
        await settle(app)
        #expect(app.clientRecord("c1")?.people[0].birthday == "10-25")
        #expect(app.clientRecord("c1")?.greet == true)
        #expect(await fake.asked == 1)
        #expect(await fake.greets().keys.sorted() == ["lp.greet.2026-10-25"])
        // Правка даты не спрашивает снова и переставляет запрос.
        app.setClientBirthday("c1", at: 0, Birthday(year: 1990, month: 10, day: 26))
        await settle(app)
        #expect(await fake.asked == 1)
        #expect(await fake.greets().keys.sorted() == ["lp.greet.2026-10-26"])
        // Выключили руками — запрос снят; правка той же даты тумблер не включает.
        app.setClientGreet("c1", false)
        await settle(app)
        #expect(await fake.greets().isEmpty)
        app.setClientBirthday("c1", at: 0, Birthday(month: 10, day: 27))
        #expect(app.clientRecord("c1")?.greet == false)
        // Убрали дату.
        app.setClientBirthday("c1", at: 0, nil)
        #expect(app.clientRecord("c1")?.people[0].birthday == nil)
    }

    @Test func refusalBreaksNothing() async {
        let fake = Fake(.notDetermined, grant: false)
        let app = model(snap([Self.person("c1", "Ольга")]), center: fake)
        app.setClientBirthday("c1", at: 0, Birthday(month: 10, day: 25))
        await settle(app)
        let c = app.clientRecord("c1")!
        #expect(c.greet && c.people[0].birthday == "10-25", "дата и тумблер на месте")
        #expect(app.greetNeedsSettings(c))
        #expect(await fake.table.isEmpty)
        app.setClientPersonName("c1", at: 0, "Ольга С.")
        await settle(app)
        #expect(await fake.asked == 1 && app.clientRecord("c1")?.people[0].name == "Ольга С.")
    }

    @Test func anniversaryFromTheWeddingThenByHand() async {
        var couple = Client(id: "c2", kind: .couple)
        couple.people = [ClientPerson(name: "Анна"), ClientPerson(name: "Иван")]
        var w = Session(id: "w", kind: .shoot, day: CivilDate(year: 2025, month: 6, day: 14), start: 600, end: 1200,
                        duration: 600, genre: .wedding)
        w.clientId = "c2"
        let fake = Fake(.allowed)
        let app = model(snap([couple], sessions: [w]), center: fake)
        let c = app.clientRecord("c2")!
        #expect(app.clientAnniversary(c) == CivilDate(year: 2025, month: 6, day: 14) && app.clientAnniversaryFromWedding(c))
        #expect(c.greet == false, "годовщина из свадьбы тумблер сама не включает")
        app.setClientAnniversary("c2", CivilDate(year: 2019, month: 9, day: 1))
        let edited = app.clientRecord("c2")!
        #expect(app.clientAnniversary(edited) == CivilDate(year: 2019, month: 9, day: 1) && !app.clientAnniversaryFromWedding(edited))
        #expect(edited.greet, "вписанная руками дата включает «Поздравлять»")
        app.setClientAnniversary("c2", nil)
        #expect(app.clientAnniversary(app.clientRecord("c2")!) == nil, "убрали — свадьба не возвращает")
    }

    @Test func draftClientIsKeptOnceABirthdayIsWritten() {
        let app = model(snap([]), center: Fake(.allowed))
        app.newClient()
        let id = app.org.clientCardId!
        #expect(app.snapshot.clients.isEmpty)
        app.setClientBirthday(id, at: 0, Birthday(month: 3, day: 7))
        #expect(app.snapshot.clients.first?.id == id && app.snapshot.clients.first?.greet == true)
    }

    @Test func launchWritesTheWeddingAnniversaryIntoTheSnapshot() {
        var couple = Client(id: "c2", kind: .couple)
        couple.people = [ClientPerson(name: "Анна"), ClientPerson(name: "Иван")]
        var w = Session(id: "w", kind: .shoot, day: CivilDate(year: 2025, month: 6, day: 14), start: 600, end: 1200,
                        duration: 600, genre: .wedding)
        w.clientId = "c2"
        var s = snap([couple], sessions: [w])
        #expect(AppModel.settleAnniversaries(in: &s, now: Date()))
        #expect(s.clients[0].anniversary == CivilDate(year: 2025, month: 6, day: 14) && !s.clients[0].anniversaryManual)
        #expect(!AppModel.settleAnniversaries(in: &s, now: Date()))
    }

    // MARK: - Свадьба после обновления (К6б, вариант 3)

    private static func wedding(_ id: String, _ d: CivilDate, client: String? = nil) -> Session {
        var s = Session(id: id, kind: .shoot, day: d, start: 600, end: 1200, duration: 600, genre: .wedding)
        s.contact = "Аня и Марк"
        s.clientPhone = "+7 913 555-66-77"
        s.persons = [Person(name: "Аня", phone: "+7 913 555-66-77"), Person(name: "Марк", phone: "+7 913 555-66-78")]
        s.clientId = client
        return s
    }

    private static func pastCouple() -> Client {
        var c = Client(id: "c1", kind: .couple)
        c.people = [ClientPerson(name: "Аня", phone: "+7 913 555-66-77"), ClientPerson(name: "Марк", phone: "+7 913 555-66-78")]
        return c
    }

    @Test func pastWeddingStaysOffOnLaunchAndOnResave() async {
        // Пара, собранная до обновления: свадьба уже за клиентом, тумблер выключен.
        let fake = Fake(.notDetermined)
        let app = model(snap([Self.pastCouple()], sessions: [Self.wedding("w", CivilDate(year: 2025, month: 6, day: 14), client: "c1")]),
                        center: fake)
        app.syncAlerts(force: true)
        await settle(app)
        app.openForm(editing: "w"); app.saveForm()
        await settle(app)
        #expect(app.clientRecord("c1")?.greet == false, "старая свадьба тумблер не включает")
        let asked = await fake.asked, table = await fake.table
        #expect(asked == 0 && table.isEmpty)
        // И разовый проход по старым съёмкам (первый запуск сборки с клиентами) — тоже нет.
        var old = snap([], sessions: [Self.wedding("w", CivilDate(year: 2025, month: 6, day: 14))])
        old.clientsAssembled = false
        AppModel.assembleClients(into: &old, language: "ru", now: Date())
        #expect(old.clients.count == 1 && old.clients[0].kind == .couple && old.clients[0].greet == false)
    }

    @Test func newWeddingTurnsGreetOnWithoutTheSystemQuestion() async {
        let fake = Fake(.notDetermined)
        let app = model(snap([], sessions: [Self.wedding("w", CivilDate(year: 2026, month: 11, day: 7))]), center: fake)
        app.openForm(editing: "w"); app.saveForm()
        await settle(app)
        let c = app.clients.first { $0.kind == .couple }
        #expect(c?.greet == true, "свадьба впервые встала к клиенту — «Поздравлять» включено")
        #expect(c?.greetHand == false)
        #expect(await fake.asked == 0, "системный вопрос сам не задаётся")
        #expect(c.map(app.greetNeedsAsk) == true, "карточка предлагает разрешить уведомления")
        // Нажали строку — тот же вопрос, что у тумблера.
        app.askGreetPermission()
        await settle(app)
        #expect(await fake.asked == 1)
    }

    @Test func weddingAddedToAPastCoupleTurnsItOn() {
        // Новая свадьба склеилась по номеру с парой, собранной раньше.
        let app = model(snap([Self.pastCouple()], sessions: [Self.wedding("w2", CivilDate(year: 2026, month: 11, day: 7))]), center: nil)
        app.openForm(editing: "w2"); app.saveForm()
        #expect(app.sessions.first { $0.id == "w2" }?.clientId == "c1")
        #expect(app.clientRecord("c1")?.greet == true)
    }

    @Test func turnedOffByHandStaysOffAfterResaveAndAnotherWedding() {
        let app = model(snap([], sessions: [Self.wedding("w", CivilDate(year: 2026, month: 11, day: 7)),
                                            Self.wedding("w2", CivilDate(year: 2026, month: 11, day: 8))]), center: nil)
        app.openForm(editing: "w"); app.saveForm()
        let id = app.clients.first { $0.kind == .couple }!.id
        #expect(app.clientRecord(id)?.greet == true)
        app.setClientGreet(id, false)
        app.openForm(editing: "w"); app.saveForm()
        #expect(app.clientRecord(id)?.greet == false, "пересохранили ту же свадьбу — выключено")
        app.openForm(editing: "w2"); app.saveForm()
        #expect(app.sessions.first { $0.id == "w2" }?.clientId == id)
        #expect(app.clientRecord(id)?.greet == false, "ещё одна свадьба той же пары — выключено")
        app.setClientBirthday(id, at: 0, Birthday(month: 5, day: 5))
        #expect(app.clientRecord(id)?.greet == false, "и первая вписанная дата — тоже")
    }

    // MARK: - Нажатие

    @Test func tapOpensTheClientCardOrTheClientsList() {
        let app = model(snap([Self.person("c1", "Ольга", bd: "10-20", greet: true)]), center: nil)
        app.openGreetClient("c1")
        #expect(app.org.listOpen && app.org.clientsTab == .privates && app.org.clientCardId == "c1")
        app.closeClientCard()
        app.closeOrgs()
        app.openGreetClient(nil)
        #expect(app.org.listOpen && app.org.clientsTab == .privates && app.org.clientCardId == nil)
        app.closeOrgs()
        app.openGreetClient("gone")
        #expect(app.org.listOpen && app.org.clientCardId == nil, "клиента удалили — открывается список")
    }
}
