import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Шаг «Поле-2» (слова Алексея 25.10): «На связи через» — организатор, подруга, друг, родственник; в досье герой и тот, кто на
/// связи, вместе; звонок из шапки идёт ему; склейка по его номеру не клеит его собственную будущую съёмку с чужим клиентом.
/// Слова, форма и шапка карточки — в тестах интерфейса (`PoleTwoScreensTests`).
@Suite struct PoleTwoTests {
    typealias B = ClientBookTests
    static let alyona = "+7 913 555-66-77"

    static func party(_ id: String, _ d: Int, hero: String = "Ольга", heroPhone: String = "",
                      via: ContactVia? = ContactVia(relation: .girlfriend, name: "Алёна", phone: alyona)) -> Session {
        var s = B.shoot(id, B.day(d, month: 10), genre: .party, persons: hero.isEmpty && heroPhone.isEmpty ? [] : [Person(name: hero, phone: heroPhone)])
        s.via = via
        return s
    }

    // MARK: Запись

    @Test func viaSurvivesTheSnapshotAndAbsentViaWritesNoKey() throws {
        let s = Self.party("a", 24)
        let back = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(s))
        #expect(back.via == ContactVia(relation: .girlfriend, name: "Алёна", phone: Self.alyona))
        let plain = String(decoding: try JSONEncoder().encode(Self.party("b", 24, via: nil)), as: UTF8.self)
        #expect(!plain.contains("\"via\""), "старая запись не получает нового ключа: файл, не знавший «Поле-2», остаётся тем же")
        var blank = Self.party("c", 24)
        blank.via = ContactVia(relation: .friend)
        #expect(!String(decoding: try JSONEncoder().encode(blank), as: UTF8.self).contains("\"via\""), "одно отношение человека не называет")
    }

    @Test func oldRecordsAndUnknownRelationOpenAsBefore() throws {
        let old = try JSONDecoder().decode(Session.self, from: Data(#"{"id":"x","kind":"shoot","date":"2026-10-24","min":600,"type":"party"}"#.utf8))
        #expect(old.via == nil)
        let odd = try JSONDecoder().decode(Session.self, from: Data(#"{"id":"x","kind":"shoot","date":"2026-10-24","min":600,"via":{"r":"neighbour","n":"Лида","tel":"+7 913 555-66-00"}}"#.utf8))
        #expect(odd.via == ContactVia(relation: .organizer, name: "Лида", phone: "+7 913 555-66-00"), "незнакомое отношение не теряет человека")
        let person = try JSONDecoder().decode(ClientPerson.self, from: Data(#"{"n":"Лена","tel":"+7 913 555-66-01"}"#.utf8))
        #expect(person.relation == nil, "клиент без нового поля — герой, как прежде")
        let key = String(decoding: try JSONEncoder().encode(person), as: UTF8.self)
        #expect(!key.contains("rel"))
        var via = person; via.relation = .friend
        #expect(try JSONDecoder().decode(ClientPerson.self, from: JSONEncoder().encode(via)).relation == .friend)
    }

    // MARK: Форма

    @Test func theRowIsOnWhereThereIsAPrivateClient() {
        let on: [Genre] = [.wedding, .party, .portrait, .lovestory, .family, .animals]
        for g in Genre.allCases {
            #expect(FormShape.showsVia(genre: g) == on.contains(g), Comment(rawValue: g.rawValue))
        }
    }

    @Test func formWritesTrimmedViaAndEmptyRowWritesNone() {
        var f = EventForm.editing(Self.party("a", 24, via: nil))
        let s0 = f.session(orgName: nil, and: " и ")
        #expect(s0.via == nil)
        f.viaRelation = .friend; f.viaName = "  Алёна "; f.viaPhone = " +7 913 555-66-77 "
        #expect(f.session(orgName: nil, and: " и ").via == ContactVia(relation: .friend, name: "Алёна", phone: "+7 913 555-66-77"))
        f.viaName = " "; f.viaPhone = ""
        #expect(f.session(orgName: nil, and: " и ").via == nil, "отношение без имени и номера — пустая строка")
    }

    @Test func switchingToAGenreWithoutTheRowDropsItOnSave() {
        var f = EventForm.editing(Self.party("a", 24))
        f.genre = .landscape
        #expect(f.session(orgName: nil, and: " и ").via == nil, "у пейзажа клиента нет — и связи через кого-то нет")
        f.genre = .portrait
        #expect(f.session(orgName: nil, and: " и ").via?.name == "Алёна", "а вернули жанр — набранное на месте")
    }

    @Test func editingOpensTheRowFilledAndKeepsPartyHeroWithoutAPhone() {
        let s = Self.party("a", 24)
        let f = EventForm.editing(s)
        #expect(f.viaRelation == .girlfriend && f.viaName == "Алёна" && f.viaPhone == Self.alyona)
        let back = f.session(orgName: nil, and: " и ")
        #expect(back.via == s.via && back.persons == [Person(name: "Ольга", phone: "")], "герой остаётся без номера")
    }

    @Test func draftKeepsTheRowAndAnOldDraftOpensWithoutIt() throws {
        var f = EventForm.new(id: "n", day: CivilDate(year: 2026, month: 10, day: 24), start: 840, fromLight: false, mode: .shoot,
                              genre: .party, prefs: nil, light: FormLightWindow(start: 1178, end: 1230))
        f.viaRelation = .relative; f.viaName = "Мама"; f.viaPhone = "+7 913 555-66-00"
        #expect(f.hasTypedContent)
        let data = try #require(f.draftData())
        let back = try #require(EventForm.fromDraft(data))
        #expect(back.viaRelation == .relative && back.viaName == "Мама" && back.viaPhone == "+7 913 555-66-00")
        var bare = EventForm.new(id: "n2", day: f.day, start: 840, fromLight: false, mode: .shoot, genre: .party, prefs: nil,
                                 light: FormLightWindow(start: 1178, end: 1230))
        bare.viaRelation = .friend
        let bareData = try #require(bare.draftData())
        let old = try #require(EventForm.fromDraft(bareData))
        #expect(old.viaName.isEmpty && old.viaPhone.isEmpty, "пустая строка в черновик не пишется")
    }

    @Test func aMeetingPassesItsViaToTheShoot() {
        var meet = Self.party("m", 20, via: ContactVia(relation: .organizer, name: "Алёна", phone: Self.alyona))
        meet.kind = .meet
        let shoot = MeetGrow.draft(from: meet, shootId: "s", day: B.day(24, month: 10), start: 840, duration: 240)
        #expect(shoot.via == meet.via)
    }

    // MARK: Досье: оба в одной карточке

    @Test func olgaAndAlyonaShareOneCard() throws {
        var clients: [Client] = [], ids = B.Ids()
        var s = Self.party("a", 24)
        let o = B.save(&s, &clients, ids: ids)
        #expect(o.created && clients.count == 1)
        let c = clients[0]
        #expect(c.kind == .person)
        #expect(c.people.map(\.name) == ["Ольга", "Алёна"] && c.people.map(\.phone) == ["", Self.alyona])
        #expect(c.people.map(\.relation) == [nil, .girlfriend], "Ольга — герой, Алёна — «на связи · подруга»")
        #expect(ClientBook.title(of: c, and: " и ") == "Ольга", "название карточки — герой, а не подруга")
        #expect(!ClientBook.canAddPerson(c), "персона: героев один, подруга места не занимает")
    }

    @Test func aCoupleWithAnOrganizerKeepsBothHeroes() {
        var clients: [Client] = [], ids = B.Ids()
        var s = B.shoot("w", B.day(5, month: 10), genre: .wedding, contact: "Аня и Марк", persons: [B.anya, B.mark])
        s.via = ContactVia(relation: .organizer, name: "Вера", phone: "+7 913 555-00-01")
        B.save(&s, &clients, ids: ids)
        #expect(clients[0].people.count == 3 && clients[0].people[2].relation == .organizer)
        #expect(ClientBook.title(of: clients[0], and: " и ") == "Аня и Марк", "пара называется по героям")
        var again = s
        again.id = "w2"
        B.save(&again, &clients, ids: ids)
        #expect(clients.count == 1 && clients[0].people.count == 3, "тот же человек на связи второй раз не дописывается")
    }

    @Test func onlyTheContactKnownYetStillMakesACardAndTheHeroJoinsLater() {
        var clients: [Client] = [], ids = B.Ids()
        var s = Self.party("a", 24, hero: "")
        let first = B.save(&s, &clients, ids: ids)
        #expect(first.created && clients[0].people.map(\.relation) == [.girlfriend], "имя именинницы узнают на съёмке")
        #expect(ClientBook.title(of: clients[0], and: " и ") == "Алёна", "пока героя нет, карточка названа тем, кто есть")
        s.persons = [Person(name: "Ольга", phone: "")]
        B.save(&s, &clients, ids: ids)
        #expect(clients.count == 1 && clients[0].people.map(\.name) == ["Ольга", "Алёна"], "герой встал перед подругой")
        #expect(ClientBook.title(of: clients[0], and: " и ") == "Ольга")
    }

    @Test func theHeroJoiningLaterKeepsWhoWeWriteTo() {
        var clients: [Client] = [], ids = B.Ids()
        var s = Self.party("a", 24, hero: "")
        B.save(&s, &clients, ids: ids)
        #expect(clients[0].main == 0 && clients[0].people[0].relation == .girlfriend)
        s.persons = [Person(name: "Ольга", phone: "")]
        B.save(&s, &clients, ids: ids)
        #expect(clients[0].people.map(\.name) == ["Ольга", "Алёна"] && clients[0].main == 1, "«Пишем» остался на Алёне, хоть она и сдвинулась в списке")
    }

    // MARK: Склейка по номеру того, кто на связи

    @Test func theSameHeroViaTheSameFriendIsOneClient() {
        var clients: [Client] = [], ids = B.Ids()
        var a = Self.party("a", 24)
        var b = Self.party("b", 25, hero: "ольга петрова", via: ContactVia(relation: .friend, name: "АЛЕНА", phone: "8 913 555-66-77"))
        B.save(&a, &clients, ids: ids)
        let o = B.save(&b, &clients, ids: ids)
        #expect(!o.created && clients.count == 1 && b.clientId == a.clientId, "номер подруги + имя героя: у Ольги нет своего номера, а найти её нужно")
        #expect(clients[0].people.count == 2, "ни второй Ольги, ни второй Алёны")
        #expect(clients[0].people[1].relation == .friend, "отношение берётся из последней съёмки")
    }

    @Test func aFriendOrganizingTwoPartiesGetsTwoClients() {
        var clients: [Client] = [], ids = B.Ids()
        var olga = Self.party("a", 24)
        var maria = Self.party("b", 25, hero: "Мария")
        B.save(&olga, &clients, ids: ids)
        let o = B.save(&maria, &clients, ids: ids)
        #expect(o.created && clients.count == 2 && olga.clientId != maria.clientId, "один номер подруги — не повод слить двух именинниц")
        #expect(clients[1].people.map(\.name) == ["Мария", "Алёна"])
    }

    @Test func twoUnnamedHeroesViaOneFriendAreNotMergedOnTheNumberAlone() {
        var clients: [Client] = [], ids = B.Ids()
        var a = Self.party("a", 24, hero: "")
        var b = Self.party("b", 25, hero: "")
        B.save(&a, &clients, ids: ids)
        B.save(&b, &clients, ids: ids)
        #expect(clients.count == 2, "кто герой — неизвестно: клеить нечем")
    }

    @Test func theFriendsOwnPortraitIsNotGluedToOlgasCard() {
        var clients: [Client] = [], ids = B.Ids()
        var olga = Self.party("a", 24)
        B.save(&olga, &clients, ids: ids)
        var portrait = B.shoot("p", B.day(24, month: 11), genre: .portrait, contact: "Алёна", phone: Self.alyona)
        let o = B.save(&portrait, &clients, ids: ids)
        #expect(o.created && clients.count == 2 && portrait.clientId != olga.clientId,
                "Алёна через месяц заказывает свой портрет — это новый клиент Алёна, не гость карточки Ольги")
        #expect(clients[0].people.count == 2 && clients[0].people[1].relation == .girlfriend, "карточка Ольги осталась как была")
        #expect(clients[1].people.map(\.relation) == [nil], "в своей карточке Алёна — герой")
        #expect(ClientBook.hint(for: portrait, choice: nil, clients: [clients[0]], sessions: [olga], mine: [], country: B.ru) == nil,
                "и в форме нет плашки «Это Ольга?»")
    }

    @Test func theFriendsOwnPortraitByNameAlsoStaysApart() {
        var clients: [Client] = [], ids = B.Ids()
        var olga = Self.party("a", 24, via: ContactVia(relation: .girlfriend, name: "Алёна Петрова", phone: Self.alyona))
        B.save(&olga, &clients, ids: ids)
        let draft = B.shoot("p", B.day(24, month: 11), genre: .portrait, contact: "Алёна Петрова", phone: "")
        #expect(ClientBook.hint(for: draft, choice: nil, clients: clients, sessions: [olga], mine: [], country: B.ru) == nil,
                "«Это …?» по имени не предлагает чужую карточку, где она только на связи")
    }

    @Test func theFriendFirstAClientOfHerOwnThenViaForSomeoneElseStaysTwoCards() {
        var clients: [Client] = [], ids = B.Ids()
        var own = B.shoot("p", B.day(1, month: 10), genre: .portrait, contact: "Алёна", phone: Self.alyona)
        B.save(&own, &clients, ids: ids)
        var olga = Self.party("a", 24)
        let o = B.save(&olga, &clients, ids: ids)
        #expect(o.created && olga.clientId != own.clientId && clients[0].people.count == 1, "её карточка не стала карточкой Ольги")
    }

    @Test func heroAndFriendOnTheSameNumberKeepTheNumberOnTheHero() {
        var clients: [Client] = [], ids = B.Ids()
        var s = Self.party("a", 24, heroPhone: Self.alyona)
        B.save(&s, &clients, ids: ids)
        let c = clients[0]
        #expect(c.people.count == 2 && c.people[0].phone == Self.alyona && c.people[1].phone.isEmpty && c.people[1].name == "Алёна",
                "один номер — один человек в списке номеров")
        #expect(PhoneBook.tels(of: c, country: B.ru).count == 1)
        // и у съёмки по-прежнему оба
        #expect(s.via?.phone == Self.alyona)
    }

    @Test func aFriendWhoLaterGetsTheHeroPhoneDoesNotDuplicateTheNumber() {
        var clients: [Client] = [], ids = B.Ids()
        var s = Self.party("a", 24)
        B.save(&s, &clients, ids: ids)
        s.persons = [Person(name: "Ольга", phone: Self.alyona)]      // Ольгу записали на номер подруги
        B.save(&s, &clients, ids: ids)
        let c = clients[0]
        #expect(clients.count == 1 && PhoneBook.tels(of: c, country: B.ru).count == 1 && c.people.first { $0.relation == nil }?.phone == Self.alyona)
    }

    @Test func ownNumberAsContactIsNotStored() {
        var clients: [Client] = [], ids = B.Ids()
        var s = Self.party("a", 24, via: ContactVia(relation: .friend, name: "Я", phone: "8 913 555-66-77"))
        B.save(&s, &clients, ids: ids, mine: [TelFormat.full(Self.alyona, country: B.ru)])
        #expect(clients[0].people.map(\.name) == ["Ольга"], "свой номер клиентом не становится")
    }

    @Test func editingTheHeroNumberLeavesTheFriendAlone() {
        var clients: [Client] = [], ids = B.Ids()
        var s = Self.party("a", 24, heroPhone: "+7 913 000-11-22")
        B.save(&s, &clients, ids: ids)
        s.persons = [Person(name: "Ольга", phone: "+7 913 000-11-33")]
        B.save(&s, &clients, ids: ids)
        let c = clients[0]
        #expect(c.people.map(\.phone) == ["+7 913 000-11-33", Self.alyona], "новый номер героя встал на место старого, не на место подруги")
        #expect(c.telLog.map(\.phone) == ["+7 913 000-11-22"])
    }

    @Test func aChangedFriendNumberReplacesTheOldOneAndTheOldOneIsNotAHeroKey() {
        var clients: [Client] = [], ids = B.Ids()
        var s = Self.party("a", 24)
        B.save(&s, &clients, ids: ids)
        s.via = ContactVia(relation: .girlfriend, name: "Алёна", phone: "+7 913 777-00-00")
        B.save(&s, &clients, ids: ids)
        let c = clients[0]
        #expect(c.people.map(\.phone) == ["", "+7 913 777-00-00"] && c.telLog.map(\.field) == [PhoneBook.Field.via])
        var portrait = B.shoot("p", B.day(24, month: 11), genre: .portrait, contact: "Алёна", phone: Self.alyona)
        B.save(&portrait, &clients, ids: ids)
        #expect(clients.count == 2, "прежний номер подруги тоже не склеивает её с чужим клиентом")
    }

    @Test func clearingTheRowInTheShootKeepsTheDossierAndRemovingThePersonKeepsTheHero() {
        var clients: [Client] = [], ids = B.Ids()
        var s = Self.party("a", 24)
        B.save(&s, &clients, ids: ids)
        s.via = nil
        B.save(&s, &clients, ids: ids)
        #expect(clients.count == 1 && clients[0].people.count == 2, "съёмку поправили, а досье — история: человек из него сам не уходит")
        ClientBook.removePerson(at: 1, from: &clients[0])
        #expect(clients[0].people.map(\.name) == ["Ольга"] && clients[0].main == 0)
        ClientBook.removePerson(at: 0, from: &clients[0])
        #expect(clients[0].people.isEmpty)
    }

    @Test func removingTheHeroKeepsTheFriendAndTheMainPointer() {
        var c = Client(id: "c1")
        var olga = ClientPerson(name: "Ольга", phone: ""), friend = ClientPerson(name: "Алёна", phone: Self.alyona)
        friend.relation = .girlfriend
        c.people = [olga, friend]; c.main = 1
        olga.phone = ""
        ClientBook.removePerson(at: 0, from: &c)
        #expect(c.people.map(\.name) == ["Алёна"] && c.main == 0)
    }

    @Test func hintForTheSecondShootTellsItIsTheSameClient() {
        var clients: [Client] = [], ids = B.Ids()
        var a = Self.party("a", 24)
        B.save(&a, &clients, ids: ids)
        let draft = Self.party("b", 25)
        let h = ClientBook.hint(for: draft, choice: nil, clients: clients, sessions: [a], mine: [], country: B.ru)
        #expect(h?.clientId == a.clientId && h?.way == .phone)
        let other = Self.party("c", 25, hero: "Мария")
        #expect(ClientBook.hint(for: other, choice: nil, clients: clients, sessions: [a], mine: [], country: B.ru) == nil)
    }

    // MARK: Досье и книга телефонов

    @Test func mergeKeepsTheFriendAFriendAndAHeroOfTheSameNameApart() {
        var clients: [Client] = [], sessions: [Session] = [], trashed: [TrashedItem] = []
        var olga = Client(id: "c1"); olga.people = [ClientPerson(name: "Ольга"), {
            var p = ClientPerson(name: "Алёна", phone: Self.alyona); p.relation = .girlfriend; return p }()]
        var own = Client(id: "c2"); own.people = [ClientPerson(name: "Алёна", phone: Self.alyona)]
        clients = [olga, own]
        ClientBook.merge("c2", into: "c1", clients: &clients, sessions: &sessions, trashed: &trashed, country: B.ru, nowMs: 5)
        #expect(clients.count == 1 && clients[0].people.count == 3, "герой Алёна и Алёна на связи — два человека, пока их не слили руками")
        #expect(clients[0].people.map(\.relation) == [nil, .girlfriend, nil])
    }

    @Test func friendIsNotWrittenToIPhoneContacts() {
        var c = Client(id: "c1")
        var friend = ClientPerson(name: "Алёна", phone: Self.alyona); friend.relation = .girlfriend
        c.people = [ClientPerson(name: "Ольга", phone: "+7 913 000-11-22"), friend]
        let cards = ClientContacts.cards(of: c, anniversary: nil, country: B.ru)
        #expect(cards.map(\.person) == [0], "К7 для того, кто на связи, — только если Алексей попросит")
    }

    @Test func phoneBookListsTheFriendOfAShoot() {
        let s = Self.party("a", 24)
        let t = PhoneBook.tels(of: s, country: B.ru)
        #expect(t.map(\.field) == [PhoneBook.Field.via] && t[0].name == "Алёна")
    }
}
