import Testing
import Foundation
import SwiftUI
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Поле-2 (слова Алексея 25.10): «На связи через» в форме, оба человека в досье, звонок и «написать» из шапки карточки идут
/// тому, кто на связи. Правила склейки — в `PoleTwoTests` (Domain); здесь — то, что видит экран. Смотрим на данные, не на
/// строки экрана; слова проверяются по ключам словаря на всех языках.
@MainActor
struct PoleTwoScreensTests {

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

    private let alyona = "+7 913 555-66-77"

    private func model(clients: [Client] = [], sessions: [Session] = [], lang: String = "ru") -> AppModel {
        var snap = Snapshot()
        snap.clients = clients
        snap.sessions = sessions
        snap.clientsAssembled = true
        let now = ISO8601DateFormatter().date(from: "2026-10-26T09:00:00+03:00")!
        return AppModel(snapshot: snap, store: nil, language: lang, zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func party(_ id: String = "p1", hero: String = "Ольга", heroPhone: String = "", via: ContactVia? = nil,
                       day: Int = 24) -> Session {
        var s = Session(id: id, kind: .shoot, day: CivilDate(year: 2026, month: 10, day: day), start: 840, end: 1080,
                        duration: 240, genre: .party)
        s.persons = [Person(name: hero, phone: heroPhone)]
        s.contact = hero
        s.via = via
        return s
    }

    private func friend(_ name: String = "Алёна", _ phone: String, msg: [(MessengerKind, String)] = []) -> ClientPerson {
        var p = ClientPerson(name: name, phone: phone)
        p.relation = .girlfriend
        p.messengers = msg.map { ClientMessenger(kind: $0.0.rawValue, value: $0.1) }
        p.preferred = msg.first?.0.rawValue
        return p
    }

    // MARK: слова

    @Test func theWordsExistInEveryLanguage() {
        for lang in ["ru", "en", "es", "ja", "zh"] {
            let t = model(lang: lang).lexicon
            for key in ["via.title", "via.namePh", "via.organizer", "via.girlfriend", "via.friend", "via.relative"] {
                #expect(t.t(key) != key && !t.t(key).isEmpty, Comment(rawValue: "\(lang) \(key)"))
            }
            #expect(t.t("via.label", ["rel": "X"]).contains("X") && t.t("via.head", ["name": "N", "rel": "X"]).contains("N"))
        }
        let ru = model().lexicon
        #expect(ru.t("via.title") == "На связи через")
        #expect(ViaRelation.allCases.map { ru.t("via." + $0.rawValue) } == ["Организатор", "Подруга", "Друг", "Родственник"], "порядок и слова — как сказал Алексей")
        #expect(Set(["en", "es", "ja", "zh"].flatMap { l in ViaRelation.allCases.map { model(lang: l).lexicon.t("via." + $0.rawValue) } }).count == 16,
                "ни одно отношение не слилось с другим ни в одном языке")
    }

    // MARK: форма и досье

    @Test func savingOlgaViaAlyonaMakesOneCardWithBothAndRemembersTheRelation() throws {
        let app = model(sessions: [party(via: nil)])
        app.openForm(editing: "p1")
        #expect(app.form?.showsVia == true && app.form?.viaName.isEmpty == true)
        app.form?.viaRelation = .girlfriend; app.form?.viaName = "Алёна"; app.form?.viaPhone = alyona
        app.saveForm()
        let s = try #require(app.sessions.first { $0.id == "p1" })
        #expect(s.via == ContactVia(relation: .girlfriend, name: "Алёна", phone: alyona) && s.persons == [Person(name: "Ольга", phone: "")])
        let c = try #require(app.clients.first)
        #expect(app.clients.count == 1 && c.people.map(\.name) == ["Ольга", "Алёна"] && c.people.map(\.relation) == [nil, .girlfriend])
        #expect(app.clientTitle(c) == "Ольга")
        // и снова открытая форма показывает то же
        app.openForm(editing: "p1")
        #expect(app.form?.viaRelation == .girlfriend && app.form?.viaName == "Алёна" && app.form?.viaPhone == alyona)
    }

    @Test func aFormWithAnEmptyRowSavesLikeBeforeAndLeavesNoKey() throws {
        let app = model(sessions: [party(heroPhone: "+7 913 000-11-22")])
        app.openForm(editing: "p1"); app.saveForm()
        #expect(app.sessions[0].via == nil && app.clients.first?.people.map(\.relation) == [nil])
    }

    @Test func alyonasOwnPortraitMonthLaterIsHerOwnClient() throws {
        var portrait = Session(id: "q", kind: .shoot, day: CivilDate(year: 2026, month: 11, day: 20), start: 600, end: 690,
                               duration: 90, genre: .portrait)
        portrait.contact = "Алёна"; portrait.clientPhone = alyona
        let app = model(sessions: [party(via: ContactVia(relation: .girlfriend, name: "Алёна", phone: alyona)), portrait])
        app.openForm(editing: "p1"); app.saveForm()
        app.openForm(editing: "q")
        let form = try #require(app.form)
        #expect(app.formClientPlate(form) == nil, "в форме её портрета нет плашки про карточку Ольги")
        app.saveForm()
        #expect(app.clients.count == 2 && app.sessions.first { $0.id == "q" }?.clientId != app.sessions.first { $0.id == "p1" }?.clientId)
        #expect(app.clients[0].people.count == 2, "карточка Ольги не тронута")
    }

    // MARK: шапка карточки: звонок и «написать»

    @Test func theHeadCallsAndWritesToWhoIsOnTheLine() throws {
        let s = party(heroPhone: "+7 913 000-11-22",
                      via: ContactVia(relation: .girlfriend, name: "Алёна", phone: alyona))
        var c = Client(id: "c1")
        var olga = ClientPerson(name: "Ольга", phone: "+7 913 000-11-22")
        olga.messengers = [ClientMessenger(kind: MessengerKind.vk.rawValue, value: "olga")]
        c.people = [olga, friend("Алёна", alyona, msg: [(.telegram, "alyona_t")])]
        var shoot = s
        shoot.clientId = "c1"
        let app = model(clients: [c], sessions: [shoot])
        let h = CardHeadText(shoot, phase: app.phase(of: shoot), app: app)
        #expect(h.tel?.dial == "+79135556677", "звонок — подруге, хотя у героя тоже есть номер")
        #expect(h.via == "на связи: Алёна, подруга")
        let plan = try #require(app.shootReach(shoot))
        #expect(plan.primary.messenger == .telegram, "«написать» — её основным способом, не мессенджером Ольги")
        #expect(plan.sections.count == 1, "в меню только её способы")
    }

    @Test func withoutAFriendTheHeadIsAsBefore() throws {
        var s = party(heroPhone: "+7 913 000-11-22")
        s.clientId = "c1"
        var c = Client(id: "c1")
        c.people = [ClientPerson(name: "Ольга", phone: "+7 913 000-11-22")]
        let app = model(clients: [c], sessions: [s])
        let h = CardHeadText(s, phase: app.phase(of: s), app: app)
        #expect(h.tel?.dial == "+79130001122" && h.via == nil)
        #expect(app.shootReach(s)?.primary.messenger == nil, "SMS на номер героя, как раньше")
    }

    @Test func aFriendWithoutANumberDoesNotTakeTheCallAway() throws {
        var s = party(heroPhone: "+7 913 000-11-22", via: ContactVia(relation: .organizer, name: "Вера", phone: ""))
        s.clientId = nil
        let app = model(sessions: [s])
        let h = CardHeadText(s, phase: app.phase(of: s), app: app)
        #expect(h.tel?.dial == "+79130001122", "у организатора номера нет — звонок герою")
        #expect(h.via == "на связи: Вера, организатор")
        #expect(app.shootReach(s) != nil)
    }

    @Test func aFriendWithOnlyARelationLineHasNoName() {
        var s = party(via: ContactVia(relation: .relative, name: "", phone: alyona))
        s.clientId = nil
        let app = model(sessions: [s])
        let h = CardHeadText(s, phase: app.phase(of: s), app: app)
        #expect(h.via == "На связи · родственник" && h.tel?.dial == "+79135556677")
    }

    // MARK: ревью GPT к ab89487

    @Test func anUnfinishedFriendNumberDoesNotTakeTheCallFromTheHero() {
        var s = party(heroPhone: "+7 913 000-11-22", via: ContactVia(relation: .friend, name: "Лида", phone: "89"))
        s.clientId = nil
        let app = model(sessions: [s])
        let h = CardHeadText(s, phase: app.phase(of: s), app: app)
        #expect(h.tel?.dial == "+79130001122" && h.via == "на связи: Лида, друг", "недописанный номер — звонок герою, строка про Лиду остаётся")
    }

    @Test func theHeadFollowsTheFriendNumberCorrectedInTheDossier() throws {
        var s = party(via: ContactVia(relation: .girlfriend, name: "Алёна", phone: alyona))
        s.clientId = "c1"
        var c = Client(id: "c1")
        c.people = [ClientPerson(name: "Ольга"), friend("Алёна", "+7 913 777-00-00", msg: [(.telegram, "alyona_t")])]
        c.telLog = [TelLogEntry(field: PhoneBook.Field.via, phone: alyona, name: "Алёна", retiredAt: "2026-10-26T00:00:00Z")]
        let app = model(clients: [c], sessions: [s])
        let h = CardHeadText(s, phase: app.phase(of: s), app: app)
        #expect(h.tel?.dial == "+79137770000", "звонок — на новый номер из досье, не на старый из съёмки")
        #expect(app.shootReach(s)?.primary.messenger == .telegram, "и её мессенджеры не пропали из меню")
    }

    @Test func aRetiredNumberOfAnUnrecognisedFriendIsNotOfferedForTheCall() {
        var s = party(heroPhone: "+7 913 000-11-22", via: ContactVia(relation: .friend, name: "Лида", phone: alyona))
        s.clientId = "c1"
        var c = Client(id: "c1")
        c.people = [ClientPerson(name: "Ольга", phone: "+7 913 000-11-22"), friend("Алёна", "+7 913 777-00-00")]
        c.telLog = [TelLogEntry(field: PhoneBook.Field.via, phone: alyona, name: "Тамара", retiredAt: "2026-10-26T00:00:00Z")]
        let app = model(clients: [c], sessions: [s])
        let h = CardHeadText(s, phase: app.phase(of: s), app: app)
        #expect(h.tel?.dial == "+79130001122", "номер, который в досье заменили, не предлагается: звонок герою")
    }

    // MARK: книга номеров

    @Test func theNumberListNamesTheFriendByTheRelationOfThatShoot() throws {
        let app = model(sessions: [party(via: ContactVia(relation: .girlfriend, name: "Алёна", phone: alyona))])
        let row = try #require(app.contacts.flatMap(\.rows).first { $0.field == PhoneBook.Field.via })
        #expect(app.contactRole(row) == "На связи · подруга")
    }
}
