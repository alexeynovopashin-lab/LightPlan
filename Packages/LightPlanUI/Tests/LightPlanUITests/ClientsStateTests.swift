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

    @Test func aClientRowOpensItsCardOverTheList() {
        let app = model(sessions: [session("a", day(9, 5), client: "Ирина", tel: "8 916 123-45-67"),
                                   session("b", day(9, 25), client: "Ирина", tel: "8 916 123-45-67")])
        app.openForm(editing: "a"); app.saveForm()
        app.openForm(editing: "b"); app.saveForm()
        app.openClients()
        let row = app.clientRows()[0]
        app.openClient(row)
        #expect(app.org.listOpen && app.org.clientCardId == row.id && app.cardId == nil, "карточка клиента слоем поверх списка (К2)")
        app.closeClientCard()
        #expect(app.org.listOpen && app.org.clientCardId == nil, "«Назад» — в список")
    }

    @Test func aClientWithoutShootsOpensItsCardToo() {
        var snap = Snapshot()
        var c = Client(id: "c1")
        c.people = [ClientPerson(name: "", phone: "8 913 787-97-07")]
        snap.clients = [c]
        let app = model(snapshot: snap)
        app.openClients()
        let row = app.clientRows()[0]
        #expect(row.title == "8 913 787-97-07" && row.subtitle == app.lexicon.t("cl.noShoots"))
        app.openClient(row)
        #expect(app.org.clientCardId == "c1")
    }

    // MARK: карточка клиента (К2)

    /// Два клиента: Ирина (две съёмки по 8 000) и Ира с другим номером (одна съёмка 12 000).
    private func twoIrinas() -> AppModel {
        let app = model(sessions: [session("a", day(9, 5), client: "Ирина", tel: "8 916 123-45-67", rate: 8_000),
                                   session("b", day(9, 20), client: "Ирина", tel: "8 916 123-45-67", rate: 8_000),
                                   session("c", day(9, 25), client: "Ира", tel: "8 903 000-11-22", rate: 12_000)])
        for id in ["a", "b", "c"] { app.openForm(editing: id); app.saveForm() }
        return app
    }

    private func clientId(_ app: AppModel, of session: String) -> String { app.sessions.first { $0.id == session }!.clientId! }

    @Test func editingTheNameWritesAtOnceAndTheListShowsIt() {
        let app = twoIrinas()
        let id = clientId(app, of: "a")
        app.openClients()
        app.openClientCard(id: id)
        app.setClientPersonName(id, at: 0, "Ирина Смирнова")
        #expect(app.clientRecord(id)?.people[0].name == "Ирина Смирнова" && app.clientRecord(id)?.modifiedAt != nil)
        app.closeClientCard()
        #expect(app.clientRows().contains { $0.title == "Ирина Смирнова" })
        #expect(app.sessions.first { $0.id == "a" }?.contact == "Ирина", "прошлая съёмка своё имя не переписывает")
    }

    @Test func shootsAndSumsOfTheCardAreComputed() {
        let app = twoIrinas()
        let id = clientId(app, of: "a")
        let line = app.clientLine(id)
        #expect(line.hasPrefix("2 съёмки · ") && line.contains("16"), Comment(rawValue: line))
        #expect(ClientBook.shoots(of: id, in: app.sessions).map(\.id) == ["b", "a"])
        app.openForm(editing: "a"); app.setFormRate(20_000); app.saveForm()
        #expect(app.clientLine(id).contains("28"), "сумма — из съёмок, не копия: \(app.clientLine(id))")
    }

    @Test func aChangedPhoneGoesToTheArchiveOnBackAndStillFindsTheClient() {
        let app = twoIrinas()
        let id = clientId(app, of: "a")
        app.openClientCard(id: id)
        app.setClientPersonPhone(id, at: 0, "+7 916 999-88-77")
        app.closeClientCard()
        let c = app.clientRecord(id)!
        #expect(c.telLog.map { TelFormat.full($0.phone, country: app.telCountry) } == [TelFormat.full("8 916 123-45-67", country: app.telCountry)])
        app.openForm(editing: "b"); app.saveForm()
        #expect(app.sessions.first { $0.id == "b" }?.clientId == id && app.clients.count == 2, "по старому номеру клиент узнаётся")
    }

    @Test func mergeMovesTheShootsAndBuriesTheSecondClient() {
        let app = twoIrinas()
        let ira = clientId(app, of: "c"), irina = clientId(app, of: "a")
        app.openClients()
        app.openClientCard(id: irina)
        #expect(app.clientMergeCandidates(irina).map(\.id) == [ira])
        app.mergeClient(ira, into: irina)
        #expect(app.clients.map(\.id) == [irina])
        #expect(app.sessions.allSatisfy { $0.clientId == irina })
        #expect(app.clientRecord(irina)?.people.count == 2, "телефоны слились: у Ирины оба номера")
        #expect(app.clientLine(irina).hasPrefix("3 съёмки"))
        guard case .array(let graves)? = app.snapshot.extra["graves"] else { Issue.record("нет могил"); return }
        #expect(graves.contains { if case .object(let o) = $0 { o["id"] == .string(ira) } else { false } }, "второй клиент в могиле")
        app.closeClientCard()
        #expect(app.clientRecord(irina)?.telLog.isEmpty == true, "пришедшие номера при «Назад» не «уходят» в архив")
    }

    @Test func aShootInTheBinFollowsTheMerge() {
        let app = twoIrinas()
        let ira = clientId(app, of: "c"), irina = clientId(app, of: "a")
        app.snapshot.trashed = [TrashedItem(record: app.sessions.first { $0.id == "c" }!, index: 2, deletedAt: 1)]
        app.snapshot.sessions.removeAll { $0.id == "c" }
        app.mergeClient(ira, into: irina)
        #expect(app.snapshot.trashed[0].record.clientId == irina, "вернувшаяся из корзины съёмка не укажет в пустоту")
    }

    @Test func twinPlateNamesTheOtherClientWithTheSameNumber() {
        let app = twoIrinas()
        let ira = clientId(app, of: "c"), irina = clientId(app, of: "a")
        #expect(app.clientTwins(irina).isEmpty)
        app.openClientCard(id: irina)
        app.addClientPerson(irina)
        app.setClientPersonPhone(irina, at: 1, "+7 903 000-11-22")
        #expect(app.clientTwins(irina).map { [$0.clientId, $0.title] } == [[ira, "Ира"]])
    }

    @Test func deleteKeepsTheShootsWithoutAClient() {
        let app = twoIrinas()
        let id = clientId(app, of: "a")
        app.openClients()
        app.openClientCard(id: id)
        #expect(app.clientShootCount(id) == 2)
        app.deleteClient(id)
        #expect(app.org.clientCardId == nil && app.clientRecord(id) == nil)
        #expect(app.sessions.count == 3 && app.sessions.filter { $0.clientId == nil }.map(\.id).sorted() == ["a", "b"])
        #expect(app.sessions.first { $0.id == "a" }?.clientPhone == "8 916 123-45-67", "имя и номер в съёмке остаются")
    }

    @Test func newClientIsADraftUntilSomethingIsWritten() {
        let app = model()
        app.openClients()
        app.newClient()
        let id = app.org.clientCardId!
        #expect(app.clients.isEmpty && app.clientRecord(id)?.people.count == 1)
        app.setClientKind(id, .family)
        #expect(app.clients.isEmpty, "вид — ещё не слово")
        app.setClientPersonName(id, at: 0, "Кузнецовы")
        #expect(app.clients.map(\.id) == [id] && app.clients[0].kind == .family)
        app.closeClientCard()
        #expect(app.clients.count == 1)
    }

    @Test func aBlankDraftOrAnEmptiedClientWithoutShootsIsNotKept() {
        let app = model()
        app.newClient()
        app.closeClientCard()
        #expect(app.clients.isEmpty && app.org.clientDraft == nil, "пустой черновик забыт")
        app.newClient()
        let id = app.org.clientCardId!
        app.setClientPersonName(id, at: 0, "Ольга")
        app.setClientPersonName(id, at: 0, "")
        app.closeClientCard()
        #expect(app.clients.isEmpty, "стёртый до пустоты клиент без съёмок не остаётся")
    }

    @Test func blankPersonRowsArePrunedOnBack() {
        let app = twoIrinas()
        let id = clientId(app, of: "a")
        app.openClientCard(id: id)
        app.setClientKind(id, .family)
        app.addClientPerson(id)
        app.addClientPerson(id)
        #expect(app.clientRecord(id)?.people.count == 3)
        app.closeClientCard()
        #expect(app.clientRecord(id)?.people.count == 1)
    }

    @Test func ownLinksAreKeptAndATapOnAShootOpensIt() {
        let app = twoIrinas()
        let id = clientId(app, of: "a")
        app.openClients()
        app.openClientCard(id: id)
        app.addClientLink(id, "disk.yandex.ru/gallery", title: "Галерея 2025")
        #expect(app.clientRecord(id)?.links.map(\.url) == ["https://disk.yandex.ru/gallery"])
        app.removeClientLink(id, linkId: app.clientRecord(id)!.links[0].id)
        #expect(app.clientRecord(id)?.links.isEmpty == true)
        app.openClientShoot("b")
        #expect(app.org.clientCardId == nil && !app.org.listOpen && app.cardId == "b")
    }

    // MARK: ответ на ревью GPT к 718a182

    @Test func aNumberChangedInTheCardBeforeMergingStillGoesToTheArchive() {
        let app = twoIrinas()
        let ira = clientId(app, of: "c"), irina = clientId(app, of: "a")
        app.openClients()
        app.openClientCard(id: irina)
        app.setClientPersonPhone(irina, at: 0, "+7 916 999-88-77")
        app.mergeClient(ira, into: irina)
        app.closeClientCard()
        let log = app.clientRecord(irina)!.telLog.map { TelFormat.full($0.phone, country: app.telCountry) }
        #expect(log == [TelFormat.full("8 916 123-45-67", country: app.telCountry)], "прежний номер в архиве")
        // Новая съёмка со старым номером, без клиента (ревью GPT к a220859): находится по архиву, не заводит нового.
        app.snapshot.sessions.append(session("d", day(10, 2), client: "Ирина", tel: "8 916 123-45-67"))
        app.openForm(editing: "d"); app.saveForm()
        #expect(app.sessions.first { $0.id == "d" }?.clientId == irina && app.clients.count == 1, "старый номер узнаёт клиента")
    }

    @Test func shootsOnlyInTheBinStillMakeDeleteAsk() {
        let app = twoIrinas()
        let ira = clientId(app, of: "c")
        app.snapshot.trashed = [TrashedItem(record: app.sessions.first { $0.id == "c" }!, index: 2, deletedAt: 1)]
        app.snapshot.sessions.removeAll { $0.id == "c" }
        #expect(app.clientShootCount(ira) == 1, "съёмка в корзине тоже числится — удаление спросит")
    }
}
