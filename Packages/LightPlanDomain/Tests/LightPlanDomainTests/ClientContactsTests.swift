import Testing
import LightPlanCore
@testable import LightPlanDomain

/// Клиенты в Контактах iPhone (шаг К7, справка `docs/clients_reference.md` § 5): номер, контакт человека, план прохода,
/// чтение недостающего из «твоего» контакта, кто пишет.
struct ClientContactsTests {
    private let ru = TelCountry.of("RU")!

    private func client(_ id: String, _ kind: ClientKind = .person, _ people: [(String, String)]) -> Client {
        var c = Client(id: id, kind: kind)
        c.people = people.map { ClientPerson(name: $0.0, phone: $0.1) }
        return c
    }

    // MARK: Защита 1

    @Test func onlyTheOrdinaryAppWrites() {
        #expect(ClientContacts.writes(bundleID: "Novopashin.LightPlan"))
        for id in ["Novopashin.LightPlan.slotA", "Novopashin.LightPlan.slotD", "Novopashin.LightPlan.wt26", "", nil] as [String?] {
            #expect(!ClientContacts.writes(bundleID: id), "\(id ?? "nil")")
        }
    }

    // MARK: Номер

    @Test func eightAndPlusSevenAreOneNumber() {
        let forms = ["8 916 123-45-67", "+7 (916) 123-45-67", "89161234567", "+7 916 123 45 67", "8-916-123-45-67",
                     "+7 916 123-45-67 доб. 12", "8 (916) 123-45-67,12", "+79161234567;1", "8 916 123 45 67 ext 3"]
        for f in forms { #expect(ClientContacts.phoneKey(f, country: ru) == "79161234567", "\(f)") }
        #expect(ClientContacts.phoneKey("+7 903 111-22-33", country: ru) != ClientContacts.phoneKey("8 916 123-45-67", country: ru))
    }

    // MARK: Контакт человека

    @Test func oneCardPerPersonWithANumberChildWithoutIsLeftOut() {
        var fam = client("c1", .family, [("Мария Иванова", "8 913 222-33-44"), ("Петя", ""), ("Иван Петрович Иванов", "+7 913 555-66-77")])
        fam.people[0].birthday = "1985-04-02"
        fam.people[0].messengers = [ClientMessenger(kind: "telegram", value: "maria"), ClientMessenger(kind: "vk", value: " ")]
        let cards = ClientContacts.cards(of: fam, anniversary: CivilDate(year: 2020, month: 1, day: 1), country: ru)
        #expect(cards.map(\.key) == ["c1#0", "c1#2"])
        #expect(cards[0].card == ContactCard(given: "Мария", family: "Иванова", phone: "+79132223344", birthday: "1985-04-02",
                                             messengers: [ClientMessenger(kind: "telegram", value: "maria")]))
        #expect(cards[1].card.given == "Иван" && cards[1].card.middle == "Петрович" && cards[1].card.family == "Иванов")
        #expect(cards.allSatisfy { $0.card.anniversary == nil })    // годовщина — только у пары
    }

    @Test func coupleAnniversaryGoesToBoth() {
        let pair = client("p", .couple, [("Анна", "+7 903 111-22-33"), ("Иван", "8 903 444-55-66")])
        let day = CivilDate(year: 2025, month: 6, day: 14)
        let cards = ClientContacts.cards(of: pair, anniversary: day, country: ru)
        #expect(cards.count == 2)
        #expect(cards.allSatisfy { $0.card.anniversary == day })
    }

    // MARK: План прохода

    private func plan(_ clients: [Client], allowed: Set<String>? = nil, links: [String: ClientContacts.Link] = [:],
                      dropped: Set<String> = [], book: [ClientContacts.BookEntry] = []) -> ClientContacts.Plan {
        ClientContacts.plan(clients: clients, allowed: allowed ?? Set(clients.map(\.id)), anniversary: { _ in nil },
                            links: links, dropped: dropped, book: book, country: ru)
    }

    @Test func numberAlreadyInTheBookIsNotCreatedOnlyRead() {
        let c = client("c1", .person, [("Ольга Смирнова", "+7 916 123-45-67")])
        let p = plan([c], book: [.init(id: "mine", phones: ["8 (916) 123-45-67"])])
        #expect(p.actions.isEmpty)
        #expect(p.reads == [ClientContacts.Read(client: "c1", person: 0, contactId: "mine")])
    }

    @Test func newNumberIsCreatedOnce() {
        let a = client("a", .person, [("Ольга", "8 916 123-45-67")])
        let b = client("b", .person, [("Ольга С", "+7 916 123-45-67")])     // тот же номер у второго клиента
        let p = plan([a, b])
        #expect(p.actions.count == 1)
        guard case .create(let key, let card)? = p.actions.first else { Issue.record("нет create"); return }
        #expect(key == "a#0" && card.phone == "+79161234567")
    }

    @Test func ownContactIsUpdatedOnlyWhenTheClientChanged() {
        let c = client("c1", .person, [("Ольга Смирнова", "8 916 123-45-67")])
        let card = ClientContacts.cards(of: c, anniversary: nil, country: ru)[0].card
        let book = [ClientContacts.BookEntry(id: "app-1", phones: ["+79161234567"])]
        #expect(plan([c], links: ["c1#0": .init(id: "app-1", card: card)], book: book).actions.isEmpty)
        var edited = c
        edited.people[0].name = "Ольга Петрова"
        let p = plan([edited], links: ["c1#0": .init(id: "app-1", card: card)], book: book)
        guard case .update(let key, let id, let new, _)? = p.actions.first, p.actions.count == 1 else { Issue.record("\(p.actions)"); return }
        #expect(key == "c1#0" && id == "app-1" && new.family == "Петрова")
        #expect(p.reads.isEmpty)    // свой контакт — не «твой»: из него не читаем
    }

    /// Ревью GPT к 3e34cb3: номер клиента сменили на номер, что уже есть в твоём контакте, — свой не правим (был бы дубль),
    /// из твоего читаем.
    @Test func numberChangedToOneInTheBookDoesNotDuplicate() {
        let c = client("c1", .person, [("Ольга", "8 916 123-45-67")])
        let card = ClientContacts.cards(of: c, anniversary: nil, country: ru)[0].card
        var moved = c
        moved.people[0].phone = "8 903 111-22-33"
        let book = [ClientContacts.BookEntry(id: "app-1", phones: ["+79161234567"]), .init(id: "mine", phones: ["+7 903 111-22-33"])]
        let p = plan([moved], links: ["c1#0": .init(id: "app-1", card: card)], book: book)
        #expect(p.actions.isEmpty)
        #expect(p.reads == [ClientContacts.Read(client: "c1", person: 0, contactId: "mine")])
    }

    /// Ревью GPT к 3e34cb3: удалили первого человека семьи — второй узнаёт свой контакт по номеру, а не по месту.
    @Test func peopleShiftedKeepTheirOwnContacts() {
        let fam = client("f", .family, [("Мария", "8 913 222-33-44"), ("Иван", "8 913 555-66-77")])
        let cards = ClientContacts.cards(of: fam, anniversary: nil, country: ru)
        let links = ["f#0": ClientContacts.Link(id: "app-m", card: cards[0].card), "f#1": .init(id: "app-i", card: cards[1].card)]
        let book = [ClientContacts.BookEntry(id: "app-m", phones: ["+79132223344"]), .init(id: "app-i", phones: ["+79135556677"])]
        var left = fam
        left.people.remove(at: 0)
        let p = plan([left], links: links, book: book)
        guard case .update(let key, let id, let card, _)? = p.actions.first, p.actions.count == 1 else { Issue.record("\(p.actions)"); return }
        #expect(key == "f#0" && id == "app-i" && card.given == "Иван")
        // Поменяли местами — каждый остаётся в своём контакте.
        var swapped = fam
        swapped.people.swapAt(0, 1)
        let q = plan([swapped], links: links, book: book)
        let ids = q.actions.compactMap { a -> String? in if case .update(_, let id, let card, _) = a { return id + ":" + card.given } else { return nil } }
        #expect(ids.sorted() == ["app-i:Иван", "app-m:Мария"])
    }

    /// Ревью GPT к d613efc: люди сдвинулись, а контакт второго удалили руками — его не заводят снова и не пишут в
    /// оставшийся контакт первого.
    @Test func shiftedPersonWithDeletedContactStaysOut() {
        let fam = client("f", .family, [("Мария", "8 913 222-33-44"), ("Иван", "8 913 555-66-77")])
        let cards = ClientContacts.cards(of: fam, anniversary: nil, country: ru)
        let links = ["f#0": ClientContacts.Link(id: "app-m", card: cards[0].card), "f#1": .init(id: "app-i", card: cards[1].card)]
        let book = [ClientContacts.BookEntry(id: "app-m", phones: ["+79132223344"])]      // контакт Ивана удалён руками
        var left = fam
        left.people.remove(at: 0)
        let p = plan([left], links: links, book: book)
        #expect(p.actions == [.gone(key: "f#1", tel: "f#tel:79135556677")])
        let next = plan([left], links: ["f#0": links["f#0"]!], dropped: ["f#tel:79135556677"], book: book)
        #expect(next.actions.isEmpty && next.reads.isEmpty)
    }

    @Test func ownContactDeletedByHandIsForgottenAndNotRecreated() {
        let c = client("c1", .person, [("Ольга", "8 916 123-45-67")])
        let card = ClientContacts.cards(of: c, anniversary: nil, country: ru)[0].card
        let p = plan([c], links: ["c1#0": .init(id: "app-1", card: card)], book: [])
        #expect(p.actions == [.gone(key: "c1#0", tel: "c1#tel:79161234567")])
        #expect(plan([c], dropped: ["c1#tel:79161234567"]).actions.isEmpty)
    }

    @Test func notAllowedClientIsLeftAlone() {
        let c = client("old", .person, [("Сергей", "8 999 555-66-77")])
        let p = plan([c], allowed: [], book: [.init(id: "mine", phones: ["8 999 555-66-77"])])
        #expect(p.actions.isEmpty && p.reads.isEmpty)
    }

    // MARK: Чтение из книги

    @Test func fillTakesOnlyWhatIsMissing() {
        var p = ClientPerson(name: "Нина", phone: "+7 913 000-00-01")
        p.messengers = [ClientMessenger(kind: "telegram", value: "mine")]
        let f = FoundContact(name: "Нина Своя", phones: ["8 913 000-00-01"], birthday: "1960-03-08",
                             messengers: [ClientMessenger(kind: "telegram", value: "other"), ClientMessenger(kind: "vk", value: "id5")])
        #expect(ClientContacts.fill(&p, from: f))
        #expect(p.name == "Нина" && p.birthday == "1960-03-08")
        #expect(p.messengers == [ClientMessenger(kind: "telegram", value: "mine"), ClientMessenger(kind: "vk", value: "id5")])
        #expect(!ClientContacts.fill(&p, from: f))       // второй раз брать нечего
        p.birthday = "05-01"
        ClientContacts.fill(&p, from: f)
        #expect(p.birthday == "05-01")                   // свой день рождения не перезаписан
    }

    @Test func profileServicesBecomeMessengers() {
        #expect(ClientContacts.messenger(service: "Telegram", username: "@olga", url: "") == ClientMessenger(kind: "telegram", value: "olga"))
        #expect(ClientContacts.messenger(service: "ВКонтакте", username: "", url: "https://vk.com/id123") == ClientMessenger(kind: "vk", value: "id123"))
        #expect(ClientContacts.messenger(service: "VK", username: "durov", url: "") == ClientMessenger(kind: "vk", value: "durov"))
        #expect(ClientContacts.messenger(service: "instagram", username: "", url: "instagram.com/olga/") == ClientMessenger(kind: "instagram", value: "olga"))
        #expect(ClientContacts.messenger(service: "WhatsApp", username: "", url: "https://wa.me/79161234567")?.kind == "whatsapp")
        #expect(ClientContacts.messenger(service: "Facebook", username: "olga", url: "") == nil)
        #expect(ClientContacts.messenger(service: "Telegram", username: "", url: "") == nil)
        #expect(ClientContacts.birthday(year: nil, month: 2, day: 29) == "02-29")
        #expect(ClientContacts.birthday(year: 1990, month: 10, day: 25) == "1990-10-25")
        #expect(ClientContacts.birthday(year: nil, month: 2, day: 31) == nil)
    }
}
