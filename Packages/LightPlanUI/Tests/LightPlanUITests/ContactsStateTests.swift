import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 28, шаг 7: «Контакты» в хозяине приложения, запись ушедшего номера (карточка организации, форма,
/// уход в фон), «Встреча» и «Назначить съёмку».
@MainActor
struct ContactsStateTests {

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

    private func session(_ id: String, _ d: CivilDate, kind: RecordKind = .shoot, client: String = "", tel: String = "",
                         org: String? = nil) -> Session {
        var s = Session(id: id, kind: kind, day: d, start: 840, end: 900, duration: 60, genre: .wedding)
        s.contact = client
        s.clientPhone = tel
        s.orgId = org
        return s
    }

    private func model(orgs: [Org] = [], sessions: [Session] = []) -> AppModel {
        var snap = Snapshot()
        snap.orgs = orgs
        snap.sessions = sessions
        let now = ISO8601DateFormatter().date(from: "2026-09-30T09:00:00+03:00")!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func org(_ id: String, _ name: String, phone: String = "", person: String = "") -> Org {
        var o = Org(id: id, name: name); o.phone = phone; o.person = person; return o
    }

    // MARK: список

    @Test func settingsValueIsCountOrNone() {
        #expect(model().contactsValue == model().lexicon.t("card.none"))
        let app = model(sessions: [session("a", day(9, 5), client: "Ирина", tel: "8 916 123-45-67"),
                                   session("b", day(9, 6), client: "Ирина", tel: "+7 916 123-45-67"),
                                   session("c", day(9, 7), client: "Пётр", tel: "8 900 000-00-01")])
        #expect(app.contactsValue == "2", "один номер в двух записях — одна строка")
    }

    @Test func rolesAreWordsNotTheFieldHint() {
        var s = session("a", day(9, 5), client: "Настя", tel: "8 923 898-08-18")
        s.persons = [Person(name: "Настя", phone: "+7 923 898-08-18"), Person(name: "Ваня", phone: "8 900 000-00-02")]
        s.orderPerson = "Мария"; s.orderPhone = "8 900 000-00-03"
        let app = model(orgs: [org("o", "Агентство", phone: "8 900 000-00-04", person: "Ольга")], sessions: [s])
        let rows = app.contacts.flatMap(\.rows)
        let words = rows.map { app.contactWho($0) }
        #expect(words.contains("Невеста · Настя") && words.contains("Жених · Ваня"), "роли пары — слова жанра: \(words)")
        #expect(words.contains("Контактное лицо · Мария") && words.contains("Организация · Ольга"))
        #expect(!words.contains { $0.contains("Имя клиента") }, "подсказка поля — не роль (ошибка веба 25)")
        #expect(rows.filter { app.contactWho($0).contains("Настя") }.count == 1, "клиент = невеста — одна строка (ошибка 26)")
    }

    @Test func clientRoleIsCustomerWord() {
        let app = model(sessions: [session("a", day(9, 5), client: "Ирина", tel: "8 916 123-45-67")])
        #expect(app.contactWho(app.contacts[0].rows[0]) == "Заказчик · Ирина")
    }

    @Test func rowTitleIsShootAndDateOrOrgName() {
        let app = model(orgs: [org("o", "Агентство", phone: "8 900 000-00-04")],
                        sessions: [session("a", day(9, 5), client: "Ирина", tel: "8 916 123-45-67")])
        let titles = app.contacts.flatMap(\.rows).map { app.contactTitle($0) }
        #expect(titles.contains("Агентство") && titles.contains { $0.hasPrefix("Свадьба · 5 сентября") && $0.hasSuffix("2026") }, "\(titles)")
    }

    @Test func myNumberIsMarkedAndPastIdsToo() {
        let app = model(sessions: [session("a", day(9, 5), client: "Я", tel: "+7 916 123-45-67")])
        app.setMyPhone("8 916 123-45-67")
        #expect(app.contacts[0].mine, "мой номер помечен, не убран")
    }

    @Test func tapOnRowsOpensCardOrOrg() {
        let app = model(orgs: [org("o", "Агентство", phone: "8 900 000-00-04")],
                        sessions: [session("a", day(9, 5), client: "Ирина", tel: "8 916 123-45-67")])
        app.openContacts()
        #expect(app.org.contactsOpen && app.org.isOpen)
        let shootRow = app.contacts.flatMap(\.rows).first { if case .shoot = $0.card { true } else { false } }!
        app.openContact(shootRow)
        #expect(!app.org.contactsOpen && app.cardId == "a")
        app.closeCard(); app.openContacts()
        let orgRow = app.contacts.flatMap(\.rows).first { if case .org = $0.card { true } else { false } }!
        app.openContact(orgRow)
        #expect(!app.org.contactsOpen && app.org.listOpen && app.org.cardId == "o")
    }

    // MARK: ушедший номер

    @Test func orgNumberChangedInTheCardGoesIntoItsLogOnClose() {
        let app = model(orgs: [org("o", "Агентство", phone: "8 916 123-45-67", person: "Ирина")])
        app.openOrgCard(id: "o")
        app.setOrgPhone("o", "8 900 111-22-33")
        app.closeOrgCard()
        let log = app.orgs[0].telLog
        #expect(log.count == 1 && log[0].phone == "8 916 123-45-67" && log[0].name == "Ирина" && log[0].field == "org")
        #expect(log[0].retiredAt != nil && app.orgs[0].modifiedAt != nil)
        #expect(app.contacts.first { !$0.live }?.rows[0].past == true, "ушедший номер виден в списке прежним")
    }

    @Test func orgNumberIsLoggedWhenTheAppGoesToBackgroundWithTheCardOpen() {
        let app = model(orgs: [org("o", "Агентство", phone: "8 916 123-45-67", person: "Ирина")])
        app.openOrgCard(id: "o")
        app.setOrgPhone("o", "8 900 111-22-33")
        app.commitOrgTels()                      // ушли в фон, «Назад» не нажимали (ошибка веба 29)
        #expect(app.orgs[0].telLog.count == 1)
        app.commitOrgTels(); app.closeOrgCard()
        #expect(app.orgs[0].telLog.count == 1, "повторная сверка не пишет второй раз")
    }

    @Test func retypingTheSameNumberInAnotherWayIsNotALeave() {
        let app = model(orgs: [org("o", "А", phone: "8 916 123-45-67")])
        app.openOrgCard(id: "o")
        app.setOrgPhone("o", "+7 916 123-45-67")
        app.closeOrgCard()
        #expect(app.orgs[0].telLog.isEmpty)
    }

    @Test func formSaveMovesTheGoneClientNumberIntoTheShootLog() {
        let app = model(sessions: [session("a", day(10, 5), client: "Ирина", tel: "8 916 123-45-67")])
        app.openForm(editing: "a")
        app.form?.clientPhone = "8 900 111-22-33"
        app.saveForm()
        let s = app.sessions[0]
        #expect(s.clientPhone == "8 900 111-22-33")
        #expect(s.telLog.map(\.phone) == ["8 916 123-45-67"] && s.telLog[0].name == "Ирина" && s.telLog[0].field == "client")
        // Ещё одна правка сохраняет архив.
        app.openForm(editing: "a"); app.saveForm()
        #expect(app.sessions[0].telLog.count == 1)
    }

    @Test func formSaveWithMovedNumberWritesNothing() {
        var s = session("a", day(10, 5), client: "Настя", tel: "8 923 898-08-18")
        s.persons = [Person(name: "", phone: "")]
        let app = model(sessions: [s])
        app.openForm(editing: "a")
        app.form?.clientPhone = ""
        app.form?.persons = [Person(name: "Настя", phone: "+7 923 898-08-18")]
        app.saveForm()
        #expect(app.sessions[0].telLog.isEmpty, "номер переехал внутри записи — не смена")
    }

    // MARK: вход «Встреча»

    @Test func meetTileOpensTheMeetFormAtTwoInTheAfternoonForAnHour() {
        let app = model()
        app.openForm(day: day(10, 12), start: 14 * 60, fromLight: false, mode: .meet)
        #expect(app.form?.mode == .meet && app.form?.day == day(10, 12))
        #expect(app.form?.start == 840 && app.form?.duration == 60, "14:00 на час")
    }

    // MARK: «Назначить съёмку»

    private func meet() -> Session {
        var m = session("m1", day(10, 5), kind: .meet, client: "Ирина", tel: "8 916 123-45-67", org: nil)
        m.notes = "обсудить свет"; m.place = "Кафе"
        return m
    }

    @Test func growMakesAShootKeepsTheMeetAndOpensTheForm() {
        let app = model(sessions: [meet()])
        app.openCard(id: "m1")
        app.growMeet("m1")
        #expect(app.sessions.count == 2)
        let m = app.sessions.first { $0.id == "m1" }!, s = app.sessions.first { $0.kind == .shoot }!
        #expect(m.kind == .meet && m.grewOn == s.day && m.grewToId == s.id, "встреча остаётся с пометкой")
        #expect(s.day == day(11, 4), "подсказка: встреча + 30 дней")
        #expect(s.contact == "Ирина" && s.clientPhone == "8 916 123-45-67" && s.place == "Кафе" && s.notes == "обсудить свет")
        #expect(s.fromMeetId == "m1")
        #expect(app.cardId == nil && app.form?.id == s.id && app.form?.isNew == false, "форма новой съёмки открыта, дату называет фотограф")
        #expect(app.planner.selected == s.day)
        #expect(app.grownLine(m) == "Съёмка назначена на 4 ноября.")
    }

    @Test func noteFollowsTheShootWhenThePhotographerMovesItsDate() {
        let app = model(sessions: [meet()])
        app.growMeet("m1")
        app.form?.day = day(12, 1)
        app.saveForm()
        #expect(app.grownLine(app.sessions.first { $0.id == "m1" }!) == "Съёмка назначена на 1 декабря.", "дата взята у съёмки, не записана при назначении")
        let shootId = app.sessions.first { $0.kind == .shoot }!.id
        app.snapshot.sessions.removeAll { $0.id == shootId }
        #expect(app.grownLine(app.sessions[0]) == "Съёмка назначена на 4 ноября.", "съёмки нет — остаётся записанный день")
    }

    @Test func secondGrowCreatesNoSecondShoot() {
        let app = model(sessions: [meet()])
        app.growMeet("m1")
        app.closeForm()
        app.growMeet("m1")
        #expect(app.sessions.filter { $0.kind == .shoot }.count == 1)
    }

    @Test func shootHasNoGrowLine() {
        let app = model(sessions: [session("s", day(10, 5))])
        app.growMeet("s")
        #expect(app.sessions.count == 1 && app.grownLine(app.sessions[0]) == nil)
    }
}
