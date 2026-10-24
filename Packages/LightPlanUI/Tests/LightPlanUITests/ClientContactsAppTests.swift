import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Клиенты в Контактах iPhone в приложении (шаг К7): три защиты Алексея (тестовая сборка не пишет; прошлые — по «Да»;
/// «Убрать всё»), тумблер по умолчанию вкл, право при первом открытии «Клиентов», частичный доступ = «выкл».
/// Книга — подставка `InMemoryContactsStore`.
@MainActor
struct ClientContactsAppTests {

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

    private static func person(_ id: String, _ name: String, _ tel: String) -> Client {
        var c = Client(id: id, kind: .person)
        c.people = [ClientPerson(name: name, phone: tel)]
        return c
    }

    private func model(_ clients: [Client]) -> AppModel {
        var s = Snapshot()
        s.clients = clients
        let now = ISO8601DateFormatter().date(from: "2026-10-24T10:00:00+03:00")!
        return AppModel(snapshot: s, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: DryWeather(), now: { now })
    }

    private func settle(_ app: AppModel) async {
        for _ in 0..<8 {
            await app.contactsChain?.value
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func written(_ s: InMemoryContactsStore) -> [String] { s.entries.compactMap { $0.card?.phone }.sorted() }

    private let past = person("old", "Сергей Прошлый", "8 999 555-66-77")

    // MARK: Защита 1

    @Test func testBuildNeverWritesAndNeverAsks() async {
        let store = InMemoryContactsStore(auth: .full)
        let app = model([past])
        app.attachContacts(store: store, memory: InMemoryContactsMemory(), writes: false)
        app.contactsOpened()
        app.setContactsWanted(true)
        app.answerPastClients(true)
        app.snapshot.clients.append(Self.person("new", "Ольга", "8 916 123-45-67"))
        app.persist()
        app.syncContacts(force: true)
        await settle(app)
        #expect(store.writes == 0 && store.entries.isEmpty)
        #expect(!app.contactsOn)
        #expect(app.contactsPastAsk == nil)
        let ask = InMemoryContactsStore(auth: .notDetermined)
        let app2 = model([past])
        app2.attachContacts(store: ask, memory: InMemoryContactsMemory(), writes: false)
        app2.contactsOpened()
        await settle(app2)
        #expect(ask.asked == 0)
    }

    // MARK: Защита 2

    @Test func pastClientsWaitForYesNewOnesGoByThemselves() async {
        let store = InMemoryContactsStore(auth: .full)
        let memory = InMemoryContactsMemory()
        let app = model([past])
        app.attachContacts(store: store, memory: memory, writes: true)
        await settle(app)
        #expect(app.contactsOn)                               // тумблер по умолчанию вкл
        #expect(store.entries.isEmpty)                        // прошлый сам не пишется
        app.contactsOpened()
        await settle(app)
        #expect(app.contactsPastAsk == 1)
        // Новый клиент после отметки — пишется сам.
        app.snapshot.clients.append(Self.person("new", "Ольга", "8 916 123-45-67"))
        app.syncContacts(force: true)
        await settle(app)
        #expect(written(store) == ["+79161234567"])
        app.answerPastClients(true)
        await settle(app)
        #expect(written(store) == ["+79161234567", "+79995556677"])
        #expect(app.contactsPastAsk == nil)
    }

    @Test func noKeepsPastInTheAppAndTheLineAsksAgain() async {
        let store = InMemoryContactsStore(auth: .full)
        let app = model([past])
        app.attachContacts(store: store, memory: InMemoryContactsMemory(), writes: true)
        app.contactsOpened()
        await settle(app)
        app.answerPastClients(false)
        await settle(app)
        #expect(store.entries.isEmpty)
        #expect(app.contactsPastAsk == nil && app.contactsPastAnswer == false && app.contactsPastWaiting == 1)
        app.contactsOpened()                                   // второй раз сам не спрашивает
        await settle(app)
        #expect(app.contactsPastAsk == nil)
        app.askPastClientsAgain()
        #expect(app.contactsPastAsk == 1)
    }

    // MARK: Защита 3

    @Test func removeAllTakesOnlyOwnTurnsOffAndAsksAgainBeforeMassWrite() async {
        let store = InMemoryContactsStore(auth: .full)
        let theirs = FoundContact(name: "Нина Своя", phones: ["+79130000001"])
        let own = store.addOwn(theirs)
        let memory = InMemoryContactsMemory()
        let app = model([])
        app.attachContacts(store: store, memory: memory, writes: true)
        app.snapshot.clients = [Self.person("a", "Ольга", "8 916 123-45-67"), Self.person("b", "Олег", "8 916 765-43-21")]
        app.syncContacts(force: true)
        await settle(app)
        #expect(written(store).count == 2 && app.contactsOwnCount == 2)
        app.removeAppContacts()
        await settle(app)
        #expect(store.entries.map(\.id) == [own])
        #expect(app.contactsRemoved == 2 && !app.contactsOn && app.contactsOwnCount == 0)
        // Включил снова — массовая запись снова только по «Да».
        app.setContactsWanted(true)
        await settle(app)
        #expect(store.entries.map(\.id) == [own])
        #expect(app.contactsPastAsk == 2)
    }

    // MARK: Право

    @Test func permissionIsAskedWhenClientsOpenNotAtLaunch() async {
        let store = InMemoryContactsStore(auth: .notDetermined, answer: .full)
        let app = model([])
        app.attachContacts(store: store, memory: InMemoryContactsMemory(), writes: true)
        await settle(app)
        #expect(store.asked == 0)
        app.contactsOpened()
        await settle(app)
        #expect(store.asked == 1 && app.contactsOn)
    }

    @Test func partialAccessShowsOffAndWritesNothing() async {
        let store = InMemoryContactsStore(auth: .notDetermined, answer: .limited)
        let app = model([])
        app.attachContacts(store: store, memory: InMemoryContactsMemory(), writes: true)
        app.contactsOpened()
        app.snapshot.clients = [Self.person("a", "Ольга", "8 916 123-45-67")]
        app.syncContacts(force: true)
        await settle(app)
        #expect(app.contactsAuth == .limited && app.contactsWanted)
        #expect(!app.contactsOn && app.contactsNeedsSettings)
        #expect(store.writes == 0)
    }

    @Test func toggleOffStopsNewWritesKeepsWritten() async {
        let store = InMemoryContactsStore(auth: .full)
        let app = model([])
        app.attachContacts(store: store, memory: InMemoryContactsMemory(), writes: true)
        app.snapshot.clients = [Self.person("a", "Ольга", "8 916 123-45-67")]
        app.syncContacts(force: true)
        await settle(app)
        app.setContactsWanted(false)
        app.snapshot.clients.append(Self.person("b", "Олег", "8 916 765-43-21"))
        app.syncContacts(force: true)
        await settle(app)
        #expect(written(store) == ["+79161234567"])
    }

    // MARK: Чтение из «твоего» контакта и «Из Контактов»

    @Test func theirContactFillsMissingBirthdayAndMessenger() async {
        let store = InMemoryContactsStore(auth: .full)
        store.addOwn(FoundContact(name: "Нина Своя", phones: ["8 (913) 000-00-01"], birthday: "1960-03-08",
                                  messengers: [ClientMessenger(kind: "telegram", value: "nina")]))
        let app = model([])
        app.attachContacts(store: store, memory: InMemoryContactsMemory(), writes: true)
        app.snapshot.clients = [Self.person("n", "Нина", "+7 913 000-00-01")]
        app.syncContacts(force: true)
        await settle(app)
        let p = app.snapshot.clients[0].people[0]
        #expect(p.birthday == "1960-03-08" && p.messengers == [ClientMessenger(kind: "telegram", value: "nina")])
        #expect(store.writes == 0)
    }

    /// Ревью GPT к 3e34cb3: сдвинули свадьбу — годовщина в Контактах тоже сдвигается, хотя карточка клиента та же.
    @Test func weddingMovedUpdatesTheAnniversary() async {
        let store = InMemoryContactsStore(auth: .full)
        var pair = Client(id: "p", kind: .couple)
        pair.people = [ClientPerson(name: "Анна", phone: "+7 903 111-22-33")]
        let app = model([])
        app.attachContacts(store: store, memory: InMemoryContactsMemory(), writes: true)
        var w = Session(id: "w", kind: .shoot, day: CivilDate(year: 2025, month: 6, day: 14), start: 600, end: 840, genre: .wedding)
        w.clientId = "p"
        app.snapshot.clients = [pair]
        app.snapshot.sessions = [w]
        app.syncContacts(force: true)
        await settle(app)
        #expect(store.entries.first?.card?.anniversary == CivilDate(year: 2025, month: 6, day: 14))
        app.snapshot.sessions[0].day = CivilDate(year: 2025, month: 6, day: 21)
        app.syncContacts()
        await settle(app)
        #expect(store.entries.first?.card?.anniversary == CivilDate(year: 2025, month: 6, day: 21))
    }

    @Test func pickedContactFillsTheCardPerson() {
        let app = model([Self.person("c", "", "")])
        app.takeClientContact("c", at: 0, FoundContact(name: "Ольга Смирнова", phones: ["+7 (903) 111-22-33", "8 916 123-45-67"],
                                                       birthday: "05-02", messengers: [ClientMessenger(kind: "vk", value: "olga")]))
        let p = app.snapshot.clients[0].people[0]
        #expect(p.name == "Ольга Смирнова" && ClientContacts.phoneKey(p.phone, country: app.telCountry) == "79031112233")
        #expect(p.birthday == "05-02" && p.messengers.map(\.kind) == ["vk"])
    }
}
