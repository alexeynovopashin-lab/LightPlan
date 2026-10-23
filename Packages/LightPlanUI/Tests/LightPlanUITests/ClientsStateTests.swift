import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Шаг К1 «Клиенты»: склейка при «Сохранить» формы, разовый проход на старте, экран «Клиенты» в хозяине приложения.
@MainActor
struct ClientsStateTests {

    private struct NoWeather: WeatherSource {
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

    private func day(_ m: Int, _ d: Int) -> CivilDate { CivilDate(year: 2026, month: m, day: d) }

    private func session(_ id: String, _ d: CivilDate, genre: Genre = .portrait, client: String = "", tel: String = "",
                         persons: [Person] = [], org: String? = nil, rate: Decimal? = nil) -> Session {
        var s = Session(id: id, kind: .shoot, day: d, start: 840, end: 930, duration: 90, genre: genre)
        s.contact = client
        s.clientPhone = tel
        s.persons = persons
        s.orgId = org
        s.pay = rate == nil ? nil : .flat
        s.rate = rate
        return s
    }

    private func model(snapshot: Snapshot = Snapshot(), language: String = "ru") -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-09-30T09:00:00+03:00")!
        return AppModel(snapshot: snapshot, store: nil, language: language, zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func model(sessions: [Session], orgs: [Org] = []) -> AppModel {
        var snap = Snapshot()
        snap.sessions = sessions
        snap.orgs = orgs
        return model(snapshot: snap)
    }

    // MARK: склейка при «Сохранить»

    @Test func savingTheFormCreatesAClientAndTheNextShootWithTheSameNumberJoinsIt() {
        let app = model(sessions: [session("a", day(9, 5), client: "Ирина", tel: "8 916 123-45-67"),
                                   session("b", day(9, 20), client: "Ира", tel: "8 916 123-45-67")])
        #expect(app.clients.isEmpty, "пока не сохраняли — клиентов нет")
        app.openForm(editing: "a"); app.saveForm()
        app.openForm(editing: "b"); app.saveForm()
        #expect(app.clients.count == 1)
        let a = app.sessions.first { $0.id == "a" }!, b = app.sessions.first { $0.id == "b" }!
        #expect(a.clientId != nil && a.clientId == b.clientId && a.clientId == app.clients[0].id)
        #expect(app.clients[0].kind == .person && app.clients[0].people.map(\.name) == ["Ирина"])
    }

    @Test func aWeddingFormMakesOneCoupleWithTwoPeople() {
        let wed = session("w", day(9, 12), genre: .wedding, client: "Аня и Марк", tel: "+7 913 555-66-77",
                          persons: [Person(name: "Аня", phone: "+7 913 555-66-77"), Person(name: "Марк", phone: "+7 913 555-66-78")])
        let app = model(sessions: [wed])
        app.openForm(editing: "w"); app.saveForm()
        #expect(app.clients.count == 1 && app.clients[0].kind == .couple && app.clients[0].people.count == 2)
    }

    @Test func aRepeatedShootsCopiesShareTheClient() {
        let app = model(sessions: [session("a", day(9, 5), client: "Ольга", tel: "8 913 787-97-07")])
        app.openForm(editing: "a")
        app.setFormRepeat(.week)
        app.setFormRepeatCount(3)
        app.saveForm()
        #expect(app.sessions.count >= 2 && app.clients.count == 1)
        #expect(Set(app.sessions.compactMap(\.clientId)) == [app.clients[0].id] && app.sessions.allSatisfy { $0.clientId != nil })
    }

    @Test func aCompanyShootGetsNoPrivateClient() {
        var o = Org(id: "o1", name: "Форум")
        o.phone = "+7 383 200-10-10"
        let app = model(sessions: [session("a", day(9, 5), genre: .report, client: "Форум", tel: "+7 383 200-10-10", org: "o1")], orgs: [o])
        app.openForm(editing: "a"); app.saveForm()
        #expect(app.clients.isEmpty && app.sessions[0].clientId == nil)
    }

    @Test func myOwnNumberIsNeverAClient() {
        let app = model(sessions: [session("a", day(9, 5), client: "Я", tel: "8 916 123-45-67")])
        app.setMyPhone("+7 916 123-45-67")
        app.openForm(editing: "a"); app.saveForm()
        #expect(app.clients.isEmpty)
    }

    @Test func savingWithoutChangesDoesNotTouchTheClientsStamp() {
        let app = model(sessions: [session("a", day(9, 5), client: "Ирина", tel: "8 916 123-45-67")])
        app.openForm(editing: "a"); app.saveForm()
        let first = app.clients
        app.openForm(editing: "a"); app.saveForm()
        #expect(app.clients == first)
    }

    // MARK: разовый проход на старте

    @Test func theOneTimePassBuildsClientsAndRunsOnlyOnce() {
        var snap = Snapshot()
        snap.sessions = [session("a", day(9, 5), client: "Ирина", tel: "8 916 123-45-67"),
                         session("b", day(9, 6), client: "Ира", tel: "+7 916 123-45-67"),
                         session("c", day(9, 7), genre: .wedding, client: "Аня и Марк",
                                 persons: [Person(name: "Аня", phone: "+7 913 555-66-77"), Person(name: "Марк", phone: "+7 913 555-66-78")])]
        let now = ISO8601DateFormatter().date(from: "2026-09-30T09:00:00+03:00")!
        #expect(AppModel.assembleClients(into: &snap, language: "ru", now: now))
        #expect(snap.clientsAssembled && snap.clients.count == 2 && snap.sessions.allSatisfy { $0.clientId != nil })
        let again = snap
        #expect(!AppModel.assembleClients(into: &snap, language: "ru", now: now) && snap == again, "второй раз проход молчит")
    }

    @Test func theSeedBecomesClientsWithTwoPersonCouples() throws {
        var snap = try #require(TestSeed.snapshot())
        let now = ISO8601DateFormatter().date(from: "2026-09-30T09:00:00+03:00")!
        AppModel.assembleClients(into: &snap, language: "ru", now: now)
        let couples = snap.clients.filter { $0.kind == .couple }
        #expect(couples.count >= 3 && couples.contains { $0.people.count == 2 }, "свадьбы засева — пары с двумя людьми")
        for s in snap.sessions where ClientBook.kind(for: s) != nil && !s.contact.isEmpty {
            #expect(s.clientId != nil, Comment(rawValue: s.id))
        }
        #expect(snap.sessions.filter { $0.genre == .landscape || $0.genre == .street }.allSatisfy { $0.clientId == nil })
    }

    // MARK: экран «Клиенты»

    @Test func openingClientsShowsPrivateAndOrgsOpenCompanies() {
        let app = model()
        app.org.clientsTab = .companies
        app.openClients()
        #expect(app.org.listOpen && app.org.clientsTab == .privates)
        app.closeOrgs()
        app.openOrgs()
        #expect(app.org.listOpen && app.org.clientsTab == .companies, "организации открываются вкладкой «Компании»")
    }

    @Test func settingsValueIsTheCountOrNone() {
        let app = model(sessions: [session("a", day(9, 5), client: "Ирина", tel: "8 916 123-45-67")])
        #expect(app.clientsValue == app.lexicon.t("card.none"))
        app.openForm(editing: "a"); app.saveForm()
        #expect(app.clientsValue == "1")
    }

    @Test func rowsAreNewestFirstWithShootsAndSumsAndFilterable() {
        var s1 = session("a", day(9, 5), client: "Ирина", tel: "8 916 123-45-67", rate: 8_000)
        var s2 = session("b", day(9, 25), client: "Ирина", tel: "8 916 123-45-67", rate: 12_000)
        let wed = session("w", day(9, 10), genre: .wedding, client: "Аня и Марк",
                          persons: [Person(name: "Аня Петрова", phone: "+7 913 555-66-77"), Person(name: "Марк Петров", phone: "+7 913 555-66-78")])
        s1.pay = .flat; s2.pay = .flat
        let app = model(sessions: [s1, wed, s2])
        for id in ["a", "w", "b"] { app.openForm(editing: id); app.saveForm() }
        let rows = app.clientRows()
        #expect(rows.map(\.title) == ["Ирина", "Аня и Марк"], "свежие сверху; пара — имена без фамилий")
        #expect(rows[0].subtitle.hasPrefix("2 съёмки · ") && rows[0].subtitle.contains("20"), "съёмки и сумма считаются из съёмок: \(rows[0].subtitle)")
        #expect(rows[0].icon == "partner" && rows[1].icon == "couple")
        app.org.clientsFilter = .couples
        #expect(app.clientRows().map(\.title) == ["Аня и Марк"])
        app.org.clientsFilter = .families
        #expect(app.clientRows().isEmpty)
    }

    @Test func aClientRowOpensItsLatestShootAndClosesTheLayer() {
        let app = model(sessions: [session("a", day(9, 5), client: "Ирина", tel: "8 916 123-45-67"),
                                   session("b", day(9, 25), client: "Ирина", tel: "8 916 123-45-67")])
        app.openForm(editing: "a"); app.saveForm()
        app.openForm(editing: "b"); app.saveForm()
        app.openClients()
        let row = app.clientRows()[0]
        #expect(row.latestShoot == "b")
        app.openClient(row)
        #expect(!app.org.listOpen && app.cardId == "b")
    }

    @Test func aClientWithoutShootsHasNowhereToGoYet() {
        var snap = Snapshot()
        snap.clients = [Client(id: "c1")]
        let app = model(snapshot: snap)
        app.openClients()
        let row = app.clientRows()[0]
        #expect(row.latestShoot == nil && row.title == app.lexicon.t("cl.noName") && row.subtitle == app.lexicon.t("cl.noShoots"))
        app.openClient(row)
        #expect(app.org.listOpen && app.cardId == nil)
    }
}
