import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Карточка клиента: «Объединить», «Удалить», подсказка «номер есть у другого клиента», пустота, люди, ссылки
/// (шаг К2, справка `clients_reference.md` § 4.4; правило объединения — DECISIONS «Клиенты, шаг К2»).
@Suite struct ClientCardTests {
    static let ru = TelCountry.fallback
    typealias B = ClientBookTests

    static func client(_ id: String, _ kind: ClientKind = .person, _ people: [ClientPerson]) -> Client {
        var c = Client(id: id, kind: kind)
        c.people = people
        return c
    }

    static func p(_ name: String, _ tel: String = "") -> ClientPerson { ClientPerson(name: name, phone: tel) }

    static func trashed(_ s: Session) -> TrashedItem { TrashedItem(record: s, index: 0, deletedAt: 1) }

    // MARK: объединить

    @Test func mergingMovesShootsLiveAndTrashedAndRemovesTheSecondClient() {
        var clients = [Self.client("c1", .person, [Self.p("Иван", "8 903 111-22-33")]),
                       Self.client("c2", .person, [Self.p("Ваня", "+7 903 444-55-66")])]
        var a = B.shoot("a", B.day(5)); a.clientId = "c1"
        var b = B.shoot("b", B.day(6)); b.clientId = "c2"
        var t = B.shoot("t", B.day(7)); t.clientId = "c2"
        var sessions = [a, b]
        var bin = [Self.trashed(t)]
        #expect(ClientBook.merge("c2", into: "c1", clients: &clients, sessions: &sessions, trashed: &bin, country: Self.ru, nowMs: 5_000))
        #expect(clients.map(\.id) == ["c1"], "второй клиент исчез, карточка, где нажали, осталась")
        #expect(sessions.allSatisfy { $0.clientId == "c1" } && bin[0].record.clientId == "c1")
        #expect(sessions.first { $0.id == "b" }?.modifiedAt == 5_000 && bin[0].record.modifiedAt == 5_000)
        #expect(sessions.first { $0.id == "a" }?.modifiedAt == nil, "съёмки цели не тронуты")
        #expect(clients[0].modifiedAt == 5_000)
        #expect(clients[0].people.map(\.phone) == ["8 903 111-22-33", "+7 903 444-55-66"], "разные номера — оба человека")
    }

    @Test func theSameNumberIsOnePersonAndFilledFieldsAreNotOverwritten() {
        var x = Self.client("c1", .couple, [Self.p("", "8 913 555-66-77"), Self.p("Марк", "+7 913 555-66-78")])
        x.people[1].birthday = "05-04"
        var y = Self.client("c2", .person, [Self.p("Аня Петрова", "+7 913 555-66-77"), Self.p("Марк Петров", "8 913 555-66-78")])
        y.people[0].birthday = "1990-02-14"
        y.people[0].messengers = [ClientMessenger(kind: "telegram", value: "@anya")]
        y.people[1].birthday = "01-01"
        var clients = [x, y]
        var sessions: [Session] = []
        var bin: [TrashedItem] = []
        ClientBook.merge("c2", into: "c1", clients: &clients, sessions: &sessions, trashed: &bin, country: Self.ru, nowMs: 9)
        let m = clients[0]
        #expect(m.people.count == 2, "«8…» и «+7…» — один номер: людей не прибавилось")
        #expect(m.people[0].name == "Аня Петрова" && m.people[0].birthday == "1990-02-14" && m.people[0].messengers.count == 1,
                "пустое у цели дозаполнено")
        #expect(m.people[1].name == "Марк" && m.people[1].birthday == "05-04", "заполненное у цели не перезаписано")
        #expect(m.kind == .couple, "вид — цели")
    }

    @Test func peopleWithoutNumbersMeetByNameOtherwiseAreAppended() {
        var x = Self.client("c1", .family, [Self.p("Кузнецова Ольга", "8 913 000-11-22"), Self.p("Миша")])
        var y = Self.client("c2", .person, [Self.p("миша "), Self.p("Даша")])
        y.people[0].birthday = "03-08"
        x.main = 1
        var clients = [x, y]
        var sessions: [Session] = []
        var bin: [TrashedItem] = []
        ClientBook.merge("c2", into: "c1", clients: &clients, sessions: &sessions, trashed: &bin, country: Self.ru, nowMs: 9)
        #expect(clients[0].people.map(\.name) == ["Кузнецова Ольга", "Миша", "Даша"])
        #expect(clients[0].people[1].birthday == "03-08")
        #expect(clients[0].main == 1, "«кому пишем» — цели")
    }

    @Test func mergingDoesNotCutByKindCapacity() {
        var clients = [Self.client("c1", .person, [Self.p("Ольга", "8 913 787-97-07")]),
                       Self.client("c2", .person, [Self.p("Ольга", "8 913 787-97-08")])]
        var sessions: [Session] = []
        var bin: [TrashedItem] = []
        ClientBook.merge("c2", into: "c1", clients: &clients, sessions: &sessions, trashed: &bin, country: Self.ru, nowMs: 9)
        #expect(clients[0].people.count == 2 && clients[0].kind == .person, "номер не теряется, вид не меняется сам")
    }

    @Test func linksTelLogAnniversaryAndGreetAreJoined() {
        var x = Self.client("c1", .couple, [Self.p("Аня", "8 913 555-66-77")])
        var y = Self.client("c2", .couple, [Self.p("Марк", "8 913 555-66-78")])
        x.links = [Attachment.link("disk.yandex.ru/a", kind: nil)!]
        y.links = [Attachment.link("https://disk.yandex.ru/a", kind: nil)!, Attachment.link("vk.com/mark", kind: nil)!]
        x.telLog = [TelLogEntry(field: "p1", phone: "8 913 000-00-01", name: "Аня", retiredAt: "x")]
        y.telLog = [TelLogEntry(field: "p1", phone: "+7 913 000-00-01", name: "Аня", retiredAt: "y"),
                    TelLogEntry(field: "p1", phone: "8 913 555-66-77", name: "Аня", retiredAt: "y"),
                    TelLogEntry(field: "p1", phone: "8 913 000-00-02", name: "Марк", retiredAt: "y")]
        y.anniversary = CivilDate(year: 2025, month: 6, day: 14)
        y.greet = true
        var clients = [x, y]
        var sessions: [Session] = []
        var bin: [TrashedItem] = []
        ClientBook.merge("c2", into: "c1", clients: &clients, sessions: &sessions, trashed: &bin, country: Self.ru, nowMs: 9)
        let m = clients[0]
        #expect(m.links.compactMap(\.url) == ["https://disk.yandex.ru/a", "https://vk.com/mark"], "ссылки без повторов по адресу")
        #expect(m.telLog.map(\.phone) == ["8 913 000-00-01", "8 913 000-00-02"],
                "архив номеров без повторов и без номера, что снова живой")
        #expect(m.anniversary == CivilDate(year: 2025, month: 6, day: 14) && m.greet)
    }

    @Test func aHandEditedAnniversaryOfTheTargetStays() {
        var x = Self.client("c1", .couple, [Self.p("Аня", "8 913 555-66-77")])
        var y = Self.client("c2", .couple, [Self.p("Марк", "8 913 555-66-78")])
        x.anniversary = CivilDate(year: 2024, month: 8, day: 1); x.anniversaryManual = true
        y.anniversary = CivilDate(year: 2025, month: 6, day: 14); y.anniversaryManual = true
        var clients = [x, y]
        var sessions: [Session] = []
        var bin: [TrashedItem] = []
        ClientBook.merge("c2", into: "c1", clients: &clients, sessions: &sessions, trashed: &bin, country: Self.ru, nowMs: 9)
        #expect(clients[0].anniversary == CivilDate(year: 2024, month: 8, day: 1) && clients[0].anniversaryManual)
    }

    @Test func mergingWithItselfOrAMissingClientDoesNothing() {
        var clients = [Self.client("c1", .person, [Self.p("Иван", "8 903 111-22-33")])]
        let before = clients
        var sessions: [Session] = []
        var bin: [TrashedItem] = []
        #expect(!ClientBook.merge("c1", into: "c1", clients: &clients, sessions: &sessions, trashed: &bin, country: Self.ru, nowMs: 9))
        #expect(!ClientBook.merge("zz", into: "c1", clients: &clients, sessions: &sessions, trashed: &bin, country: Self.ru, nowMs: 9))
        #expect(clients == before)
    }

    @Test func afterMergingTheNextShootWithEitherNumberFindsTheSameClient() {
        let ids = B.Ids()
        var clients: [Client] = []
        var a = B.shoot("a", B.day(5), contact: "Иван", phone: "8 903 111-22-33")
        var b = B.shoot("b", B.day(6), contact: "Ваня", phone: "8 903 444-55-66")
        B.save(&a, &clients, ids: ids)
        B.save(&b, &clients, ids: ids)
        #expect(clients.count == 2)
        var sessions = [a, b]
        var bin: [TrashedItem] = []
        ClientBook.merge(b.clientId!, into: a.clientId!, clients: &clients, sessions: &sessions, trashed: &bin, country: Self.ru, nowMs: 9)
        var c = B.shoot("c", B.day(7), contact: "Иван", phone: "+7 903 444-55-66")
        B.save(&c, &clients, ids: ids)
        #expect(clients.count == 1 && c.clientId == a.clientId, "второй номер теперь у объединённого клиента")
    }

    // MARK: номер, сменённый в карточке (§ 3.5)

    @Test func aNumberChangedInTheCardHoldsWhenAnOldShootIsSavedAgain() {
        let ids = B.Ids()
        var clients: [Client] = []
        var a = B.shoot("a", B.day(5), contact: "Ирина", phone: "8 916 123-45-67")
        B.save(&a, &clients, ids: ids)
        // В карточке номер сменили; при «Назад» старый ушёл в архив.
        let before = PhoneBook.tels(of: clients[0], country: Self.ru)
        clients[0].people[0].phone = "8 916 999-88-77"
        clients[0].telLog = PhoneBook.retire(before: before, after: PhoneBook.tels(of: clients[0], country: Self.ru),
                                             log: clients[0].telLog, at: "t", country: Self.ru)
        B.save(&a, &clients, ids: ids)
        #expect(clients.count == 1 && a.clientId == clients[0].id, "старая съёмка узнаёт клиента по архиву")
        #expect(clients[0].people.map(\.phone) == ["8 916 999-88-77"], "и не откатывает номер карточки")
        var b = B.shoot("b", B.day(9), contact: "Ирина", phone: "+7 916 999-88-77")
        B.save(&b, &clients, ids: ids)
        #expect(b.clientId == clients[0].id, "новая съёмка берёт номер из карточки")
    }

    // MARK: удалить

    @Test func deletingKeepsTheShootsWithoutTheClient() {
        var clients = [Self.client("c1", .person, [Self.p("Иван", "8 903 111-22-33")]),
                       Self.client("c2", .person, [Self.p("Ольга", "8 913 787-97-07")])]
        var a = B.shoot("a", B.day(5), contact: "Иван", phone: "8 903 111-22-33"); a.clientId = "c1"
        var o = B.shoot("o", B.day(6)); o.clientId = "c2"
        var t = B.shoot("t", B.day(7)); t.clientId = "c1"
        var sessions = [a, o]
        var bin = [Self.trashed(t)]
        #expect(ClientBook.delete("c1", clients: &clients, sessions: &sessions, trashed: &bin, nowMs: 7))
        #expect(clients.map(\.id) == ["c2"])
        #expect(sessions.count == 2, "съёмки остаются")
        let left = sessions.first { $0.id == "a" }!
        #expect(left.clientId == nil && left.modifiedAt == 7 && left.contact == "Иван" && left.clientPhone == "8 903 111-22-33",
                "теряется только связь: имя и номер в съёмке на месте")
        #expect(bin[0].record.clientId == nil, "и у съёмки в корзине")
        #expect(sessions.first { $0.id == "o" }?.clientId == "c2", "чужие съёмки не тронуты")
        #expect(!ClientBook.delete("c1", clients: &clients, sessions: &sessions, trashed: &bin, nowMs: 8))
    }

    // MARK: номер есть у другого клиента (§ 3.4)

    @Test func aNumberOfAnotherClientNamedInTheShootsIsATwin() {
        let ids = B.Ids()
        var clients: [Client] = []
        var love = B.shoot("l", B.day(1), genre: .lovestory, contact: "Аня", phone: B.anya.phone)
        B.save(&love, &clients, ids: ids)
        var portrait = B.shoot("p", B.day(2), contact: "Марк П.", phone: B.mark.phone)
        B.save(&portrait, &clients, ids: ids)
        var wed = B.shoot("w", B.day(10), genre: .wedding, contact: "Аня и Марк", persons: [B.anya, B.mark])
        let out = B.save(&wed, &clients, ids: ids)
        #expect(wed.clientId == love.clientId && out.alsoIn == [portrait.clientId!], "склейка сама не объединила")
        let all = [love, portrait, wed]
        let twins = ClientBook.twins(of: wed.clientId!, clients: clients, sessions: all, mine: [], country: Self.ru)
        #expect(twins == [ClientBook.Twin(clientId: portrait.clientId!, name: "Марк", phone: B.mark.phone)])
        let back = ClientBook.twins(of: portrait.clientId!, clients: clients, sessions: all, mine: [], country: Self.ru)
        #expect(back.isEmpty, "у портрета в съёмках только свой номер")
    }

    @Test func aNumberTypedInTheCardOrAnOldNumberAlsoCounts() {
        var x = Self.client("c1", .person, [Self.p("Ольга", "8 913 787-97-07")])
        var y = Self.client("c2", .person, [Self.p("Оля", "8 913 000-00-09")])
        y.telLog = [TelLogEntry(field: "p1", phone: "+7 913 787-97-07", name: "Оля", retiredAt: "x")]
        let z = Self.client("c3", .person, [Self.p("Мама", "8 913 222-33-44")])
        x.people.append(Self.p("", "+7 913 222-33-44"))
        let twins = ClientBook.twins(of: "c1", clients: [x, y, z], sessions: [], mine: [], country: Self.ru)
        #expect(twins.map(\.clientId) == ["c2", "c3"], "прежний номер другого клиента и вписанный руками")
    }

    @Test func myOwnNumberIsNeverATwin() {
        let x = Self.client("c1", .person, [Self.p("Ольга", "8 913 787-97-07")])
        let y = Self.client("c2", .person, [Self.p("Оля", "8 913 787-97-07")])
        let mine: Set<String> = [TelFormat.full("8 913 787-97-07", country: Self.ru)]
        #expect(ClientBook.twins(of: "c1", clients: [x, y], sessions: [], mine: mine, country: Self.ru).isEmpty)
    }

    // MARK: пустота, люди, ссылки

    @Test func aBlankClientWithoutShootsIsNotKept() {
        var c = Client(id: "c1", kind: .couple)
        c.people = [ClientPerson()]
        #expect(ClientBook.isBlank(c) && !ClientBook.keeps(c, in: []))
        var s = B.shoot("a", B.day(1)); s.clientId = "c1"
        #expect(ClientBook.keeps(c, in: [s]), "съёмки держат клиента, даже если имя стёрли")
        #expect(ClientBook.keeps(c, in: [], trashed: [Self.trashed(s)]), "и съёмка в корзине тоже")
        c.links = [Attachment.link("vk.com/x", kind: nil)!]
        #expect(!ClientBook.isBlank(c))
    }

    @Test func blankPeopleArePrunedAndMainFollowsItsPerson() {
        var c = Self.client("c1", .family, [Self.p(""), Self.p("Ольга"), Self.p(""), Self.p("Миша")])
        c.main = 3
        ClientBook.pruneBlankPeople(&c)
        #expect(c.people.map(\.name) == ["Ольга", "Миша"] && c.main == 1)
        c.main = 1
        ClientBook.removePerson(at: 0, from: &c)
        #expect(c.people.map(\.name) == ["Миша"] && c.main == 0)
    }

    @Test func addingPeopleFollowsTheKind() {
        var c = Self.client("c1", .couple, [Self.p("Аня")])
        #expect(ClientBook.canAddPerson(c))
        ClientBook.addPerson(to: &c)
        #expect(!ClientBook.canAddPerson(c), "у пары двое")
        c.kind = .family
        #expect(ClientBook.canAddPerson(c))
        c.kind = .person
        #expect(!ClientBook.canAddPerson(c) && c.people.count == 2, "лишних у персоны не прячем, но и не дописываем")
    }

    @Test func clientLinksAreUniqueAndShootLinksAreComputed() {
        var c = Client(id: "c1")
        #expect(ClientBook.addLink("disk.yandex.ru/g", title: "Галерея 2025", to: &c))
        #expect(!ClientBook.addLink("https://disk.yandex.ru/g", to: &c), "та же ссылка второй раз не ложится")
        #expect(!ClientBook.addLink("  ", to: &c))
        #expect(c.links.count == 1 && c.links[0].title == "Галерея 2025")
        ClientBook.removeLink(id: c.links[0].id, from: &c)
        #expect(c.links.isEmpty)
        var a = B.shoot("a", B.day(3)); a.clientId = "c1"
        a.docs = [Attachment.link("disk.yandex.ru/a", kind: nil)!, Attachment(source: .doc, name: "договор.pdf")]
        var b = B.shoot("b", B.day(9)); b.clientId = "c1"
        b.docs = [Attachment.link("disk.yandex.ru/b", kind: nil)!]
        var other = B.shoot("x", B.day(9)); other.docs = [Attachment.link("disk.yandex.ru/x", kind: nil)!]
        let links = ClientBook.shootLinks(of: "c1", in: [a, b, other])
        #expect(links.map(\.doc.url) == ["https://disk.yandex.ru/b", "https://disk.yandex.ru/a"] && links.map(\.sessionId) == ["b", "a"],
                "только ссылки, только этого клиента, от новых к старым")
    }
}
