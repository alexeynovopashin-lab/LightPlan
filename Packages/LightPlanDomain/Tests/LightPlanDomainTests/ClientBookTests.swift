import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Частные клиенты: вид по жанру, склейка по номеру, разовый проход, список (шаг К1, справка `clients_reference.md` §§ 2–3).
@Suite struct ClientBookTests {
    static let ru = TelCountry.fallback
    static func day(_ d: Int, month: Int = 9) -> CivilDate { CivilDate(year: 2026, month: month, day: d) }

    static func shoot(_ id: String, _ d: CivilDate, genre: Genre? = .portrait, contact: String = "", phone: String = "",
                      persons: [Person] = [], org: String? = nil, start: Int = 600, rate: Decimal? = nil) -> Session {
        var s = Session(id: id, kind: .shoot, day: d, start: start, end: start + 90, duration: 90, genre: genre)
        s.contact = contact
        s.clientPhone = phone
        s.persons = persons
        s.orgId = org
        s.pay = rate == nil ? nil : .flat
        s.rate = rate
        return s
    }

    final class Ids {
        var n = 0
        func next() -> String { n += 1; return "c\(n)" }
    }

    /// Одна запись «сохранена»: склейка с клиентами.
    @discardableResult
    static func save(_ s: inout Session, _ clients: inout [Client], ids: Ids, mine: Set<String> = [],
                     now: Int64 = 1_000) -> ClientBook.Outcome {
        ClientBook.bind(&s, among: &clients, mine: mine, country: ru, nowMs: now, retiredAt: "2026-09-01T00:00:00Z",
                        newId: { ids.next() })
    }

    static let anya = Person(name: "Аня", phone: "+7 913 555-66-77")
    static let mark = Person(name: "Марк", phone: "+7 913 555-66-78")

    // MARK: вид по жанру (§ 2.3)

    @Test func kindFollowsTheGenreTable() {
        func k(_ g: Genre?, org: String? = nil, persons: [Person] = [], kind: RecordKind = .shoot) -> ClientKind? {
            var s = Self.shoot("x", Self.day(1), genre: g, contact: "Кто-то", persons: persons, org: org)
            s.kind = kind
            return ClientBook.kind(for: s)
        }
        #expect(k(.wedding, persons: [Self.anya, Self.mark]) == .couple)
        #expect(k(.lovestory) == .couple)
        #expect(k(.family) == .family)
        for g in [Genre.portrait, .animals, .party, .product, .ad, .architecture, .report] { #expect(k(g) == .person, Comment(rawValue: g.rawValue)) }
        #expect(k(nil) == .person, "«Фотосъёмка» без жанра — персона")
        #expect(k(.landscape) == nil && k(.street) == nil, "у жанра нет клиента")
        #expect(k(.report, org: "o1") == nil && k(.portrait, org: "o1") == nil, "заказчик — организация: это «Компании»")
        #expect(k(.wedding, org: "agency", persons: [Self.anya, Self.mark]) == .couple, "свадьба через агентство: пара — клиент")
        #expect(k(.party, org: "o1", persons: [Person(name: "Нина", phone: "")]) == nil
                && k(.portrait, org: "o1", persons: [Self.anya]) == nil, "исключение — только свадьба: остальным организация клиента не оставляет")
        #expect(k(.wedding, org: "agency") == nil, "свадьба через агентство без людей пары — компания, не клиент")
        #expect(k(.portrait, kind: .meet) == nil, "встреча клиента не заводит")
        #expect(k(.portrait, kind: .event) == nil)
    }

    // MARK: заведение (§ 3.3) и дозаполнение (§ 3.2)

    @Test func newNumberCreatesAClientWithTheShootsPeople() {
        var clients: [Client] = [], ids = Ids()
        var s = Self.shoot("a", Self.day(1), genre: .wedding, contact: "Аня и Марк", phone: Self.anya.phone, persons: [Self.anya, Self.mark])
        let o = Self.save(&s, &clients, ids: ids, now: 77)
        #expect(o == .init(clientId: "c1", created: true, alsoIn: []))
        #expect(s.clientId == "c1")
        #expect(clients.count == 1 && clients[0].kind == .couple && clients[0].modifiedAt == 77)
        #expect(clients[0].people.map(\.name) == ["Аня", "Марк"] && clients[0].people.map(\.phone) == [Self.anya.phone, Self.mark.phone],
                "пара — один клиент, два человека; номер клиента, равный номеру Ани, не плодит третьего")
    }

    @Test func sameNumberInAnotherFormatIsTheSameClient() {
        var clients: [Client] = [], ids = Ids()
        var a = Self.shoot("a", Self.day(1), contact: "Ольга Смирнова", phone: "8 913 787-97-07")
        var b = Self.shoot("b", Self.day(9), genre: .animals, contact: "Ольга", phone: "+7 913 787-97-07")
        Self.save(&a, &clients, ids: ids)
        let o = Self.save(&b, &clients, ids: ids)
        #expect(clients.count == 1 && b.clientId == a.clientId && !o.created, "«8 913…» и «+7 913…» — один номер")
        #expect(clients[0].people.map(\.name) == ["Ольга Смирнова"], "заполненное имя молча не перезаписывается")
    }

    @Test func emptyFieldsAreFilledFromTheShootButFilledOnesAreNot() {
        var clients: [Client] = [], ids = Ids()
        // Пара: у второго человека только номер. Пара узнана по Ане (номер + имя), имя второго дозаполняется.
        var a = Self.shoot("a", Self.day(1), genre: .wedding, persons: [Self.anya, Person(name: "", phone: Self.mark.phone)])
        Self.save(&a, &clients, ids: ids)
        #expect(clients[0].people.map(\.name) == ["Аня", ""])
        var b = Self.shoot("b", Self.day(2), genre: .lovestory, persons: [Self.anya, Self.mark])
        Self.save(&b, &clients, ids: ids, now: 5)
        #expect(clients[0].people.map(\.name) == ["Аня", "Марк"] && clients[0].modifiedAt == 5, "пустое имя дозаполнено, отметка правки свежая")
        var c = Self.shoot("c", Self.day(3), genre: .lovestory, persons: [Self.anya, Person(name: "Марк Петров", phone: Self.mark.phone)])
        Self.save(&c, &clients, ids: ids, now: 9)
        #expect(clients[0].people.map(\.name) == ["Аня", "Марк"] && clients[0].modifiedAt == 5, "ничего не изменилось — правки нет")
        // К3б: у клиента только номер, имени нет — один номер не узнаёт, это новый клиент.
        var d = Self.shoot("d", Self.day(4), contact: "", phone: "+7 913 111-22-33")
        var e = Self.shoot("e", Self.day(5), contact: "Ира", phone: "+7 913 111-22-33")
        Self.save(&d, &clients, ids: ids); Self.save(&e, &clients, ids: ids)
        #expect(clients.count == 3 && d.clientId != e.clientId)
    }

    @Test func secondPersonOfAPairIsFilledIn() {
        var clients: [Client] = [], ids = Ids()
        var love = Self.shoot("l", Self.day(1), genre: .lovestory, contact: "Аня", phone: Self.anya.phone)
        Self.save(&love, &clients, ids: ids)
        #expect(clients[0].kind == .couple && clients[0].people.count == 1)
        var wed = Self.shoot("w", Self.day(20), genre: .wedding, contact: "Аня и Марк", phone: Self.anya.phone, persons: [Self.anya, Self.mark])
        Self.save(&wed, &clients, ids: ids)
        #expect(clients.count == 1 && wed.clientId == love.clientId)
        #expect(clients[0].people.map(\.phone) == [Self.anya.phone, Self.mark.phone], "жених добавлен вторым человеком пары")
    }

    @Test func aPairFoundByEitherNumber() {
        var clients: [Client] = [], ids = Ids()
        var wed = Self.shoot("w", Self.day(1), genre: .wedding, persons: [Self.anya, Self.mark])
        Self.save(&wed, &clients, ids: ids)
        var love = Self.shoot("l", Self.day(30), genre: .lovestory, contact: "Марк", phone: Self.mark.phone)
        let o = Self.save(&love, &clients, ids: ids)
        #expect(clients.count == 1 && love.clientId == wed.clientId && !o.created, "лавстори только с номером жениха — та же пара (§ 3.4)")
    }

    @Test func kindOnceSetStaysWhateverTheNextShootIs() {
        var clients: [Client] = [], ids = Ids()
        var wed = Self.shoot("w", Self.day(1), genre: .wedding, persons: [Self.anya, Self.mark])
        Self.save(&wed, &clients, ids: ids)
        var portrait = Self.shoot("p", Self.day(20), genre: .portrait, contact: "Аня", phone: Self.anya.phone)
        Self.save(&portrait, &clients, ids: ids)
        #expect(clients.count == 1 && clients[0].kind == .couple, "портрет невесты после свадьбы пару в персону не превращает")
    }

    // MARK: два номера у двух клиентов (§ 3.4)

    @Test func twoClientsNumbersAreNotMergedByThemselves() {
        var clients: [Client] = [], ids = Ids()
        var a = Self.shoot("a", Self.day(1), contact: "Аня", phone: Self.anya.phone)
        var m = Self.shoot("m", Self.day(2), contact: "Марк", phone: Self.mark.phone)
        Self.save(&a, &clients, ids: ids); Self.save(&m, &clients, ids: ids)
        #expect(clients.count == 2)
        var wed = Self.shoot("w", Self.day(30), genre: .wedding, persons: [Self.anya, Self.mark])
        let o = Self.save(&wed, &clients, ids: ids)
        #expect(wed.clientId == a.clientId, "запись идёт к клиенту по первому человеку")
        #expect(o.alsoIn == [m.clientId!], "номер жениха есть у другого — карточка спросит «объединить?»")
        #expect(clients.count == 2 && clients[0].people.map(\.phone) == [Self.anya.phone], "номер жениха к первому клиенту сам не переехал")
        #expect(clients[1].people.map(\.phone) == [Self.mark.phone])
    }

    @Test func aSharedNumberOfANamedPairBelongsToTheFirstNamedPersonAndDoesNotDuplicate() {
        var clients: [Client] = [], ids = Ids()
        let names = [Person(name: "Аня", phone: ""), Person(name: "Марк", phone: "")]
        var wed = Self.shoot("w", Self.day(1), genre: .wedding, contact: "Аня и Марк", phone: "+7 913 555-66-77", persons: names)
        Self.save(&wed, &clients, ids: ids)
        #expect(clients.count == 1 && clients[0].people.map(\.name) == ["Аня", "Марк"] && clients[0].people.map(\.phone) == ["+7 913 555-66-77", ""],
                "общий номер — первому названному, третьего человека нет")
        var next = Self.shoot("l", Self.day(20), genre: .lovestory, contact: "Аня", phone: "8 913 555-66-77")
        Self.save(&next, &clients, ids: ids)
        #expect(clients.count == 1 && next.clientId == wed.clientId, "следующая съёмка с тем же номером находит пару, а не заводит дубль")
    }

    @Test func aNumberOfThreeIsNotLostOnCreation() {
        var clients: [Client] = [], ids = Ids()
        var wed = Self.shoot("w", Self.day(1), genre: .wedding, contact: "Аня и Марк", phone: "+7 913 000-00-33", persons: [Self.anya, Self.mark])
        Self.save(&wed, &clients, ids: ids)
        #expect(clients.count == 1 && clients[0].people.map(\.phone).contains("+7 913 000-00-33"), "номер, названный третьим, не потерян")
        // К3б, ревью GPT к 8c67c5a: третий номер — у человека без имени; имя сверяется с хозяином номера, так что «Аня» с ним
        // пару не узнаёт (один фактор), «Мама» — тем более.
        var again = Self.shoot("a", Self.day(9), contact: "Аня", phone: "+7 913 000-00-33")
        Self.save(&again, &clients, ids: ids)
        var mom = Self.shoot("m", Self.day(10), contact: "Мама", phone: "+7 913 000-00-33")
        Self.save(&mom, &clients, ids: ids)
        #expect(clients.count == 3 && again.clientId != wed.clientId && mom.clientId != wed.clientId)
    }

    @Test func anArchivedNumberFindsTheClientButIsNotWrittenBackAsAPerson() {
        var clients: [Client] = [], ids = Ids()
        var s = Self.shoot("a", Self.day(1), contact: "Ольга", phone: "+7 913 787-97-07")
        Self.save(&s, &clients, ids: ids)
        s.clientPhone = "+7 913 111-00-00"
        Self.save(&s, &clients, ids: ids)
        var call = Self.shoot("c", Self.day(5), contact: "Ольга", phone: "8 913 787-97-07")
        Self.save(&call, &clients, ids: ids)
        #expect(call.clientId == s.clientId && clients[0].people.map(\.phone) == ["+7 913 111-00-00"], "прежний номер человека не воскресает вторым")
        var wed = Self.shoot("w", Self.day(9), genre: .wedding, persons: [Person(name: "Ольга", phone: "+7 913 787-97-07"), Self.mark])
        Self.save(&wed, &clients, ids: ids)
        #expect(wed.clientId == s.clientId && clients[0].people.map(\.phone) == ["+7 913 111-00-00", Self.mark.phone],
                "жених дописан вторым, прежний номер невесты места не занял")
    }

    // MARK: клиент без номера (§ 3.7)

    @Test func aClientWithoutNumberIsCreatedButNeverGluedByName() {
        var clients: [Client] = [], ids = Ids()
        var a = Self.shoot("a", Self.day(1), contact: "Анна")
        var b = Self.shoot("b", Self.day(2), contact: "Анна")
        Self.save(&a, &clients, ids: ids); Self.save(&b, &clients, ids: ids)
        #expect(clients.count == 2 && a.clientId != b.clientId, "два «Анна» без номера — разные люди")
        let first = clients[0].id
        Self.save(&a, &clients, ids: ids)
        #expect(clients.count == 2 && a.clientId == first, "повторное сохранение той же записи нового клиента не заводит")
    }

    @Test func aShortFragmentIsNotANumber() {
        var clients: [Client] = [], ids = Ids()
        var a = Self.shoot("a", Self.day(1), contact: "Лена", phone: "123")
        var b = Self.shoot("b", Self.day(2), contact: "Лена", phone: "123")
        Self.save(&a, &clients, ids: ids); Self.save(&b, &clients, ids: ids)
        #expect(clients.count == 2, "короче пяти цифр — не номер, не склеивает")
    }

    @Test func nothingNamedMeansNoClient() {
        var clients: [Client] = [], ids = Ids()
        var s = Self.shoot("a", Self.day(1))
        #expect(Self.save(&s, &clients, ids: ids).clientId == nil && clients.isEmpty && s.clientId == nil)
        var org = Self.shoot("o", Self.day(1), genre: .report, contact: "Форум", phone: "+7 383 200-10-10", org: "o1")
        #expect(Self.save(&org, &clients, ids: ids).clientId == nil && clients.isEmpty, "заказчик — организация")
        var land = Self.shoot("l", Self.day(1), genre: .landscape, contact: "Кто-то", phone: "+7 913 000-00-00")
        #expect(Self.save(&land, &clients, ids: ids).clientId == nil && clients.isEmpty)
    }

    @Test func clearingTheClientUnbindsButKeepsTheClient() {
        var clients: [Client] = [], ids = Ids()
        var s = Self.shoot("a", Self.day(1), contact: "Ольга", phone: "+7 913 787-97-07")
        Self.save(&s, &clients, ids: ids)
        s.contact = ""; s.clientPhone = ""
        Self.save(&s, &clients, ids: ids)
        #expect(s.clientId == nil && clients.count == 1, "клиент без съёмок не удаляется сам")
    }

    // MARK: свой номер и номер организации (§ 3.6)

    @Test func myOwnNumberNeverBecomesAClient() {
        var clients: [Client] = [], ids = Ids()
        let mine = PhoneBook.mineKeys(["+7 913 000-11-22"], country: Self.ru)
        var s = Self.shoot("a", Self.day(1), contact: "Я сам", phone: "8 913 000-11-22")
        #expect(Self.save(&s, &clients, ids: ids, mine: mine).clientId == nil && clients.isEmpty)
        var wed = Self.shoot("w", Self.day(2), genre: .wedding, persons: [Person(name: "Аня", phone: "+7 913 000-11-22"), Self.mark])
        Self.save(&wed, &clients, ids: ids, mine: mine)
        #expect(clients.count == 1 && clients[0].people.map(\.name) == ["Марк"], "человек с моим номером выпадает, остальные остаются")
    }

    @Test func orderPhoneOfACompanyPersonIsNotUsedForGluing() {
        var clients: [Client] = [], ids = Ids()
        var s = Self.shoot("a", Self.day(1), genre: .report, contact: "Форум", phone: "")
        s.orderPhone = "+7 913 999-88-77"; s.orderPerson = "Маркетолог"
        Self.save(&s, &clients, ids: ids)
        #expect(clients.flatMap(\.people).map(\.phone) == [""], "`orderPhone` — человек заказчика, он к «Компаниям»: в клиента не идёт")
    }

    // MARK: номер сменился (§ 3.5)

    @Test func changedNumberUpdatesThePersonAndKeepsTheOldOneKnown() {
        var clients: [Client] = [], ids = Ids()
        var s = Self.shoot("a", Self.day(1), contact: "Ольга", phone: "+7 913 787-97-07")
        Self.save(&s, &clients, ids: ids)
        var old = Self.shoot("old", Self.day(0), contact: "Ольга", phone: "+7 913 787-97-07")
        Self.save(&old, &clients, ids: ids)
        s.clientPhone = "+7 913 111-00-00"
        Self.save(&s, &clients, ids: ids)
        #expect(clients.count == 1 && clients[0].people.map(\.phone) == ["+7 913 111-00-00"])
        #expect(clients[0].telLog.map(\.phone) == ["+7 913 787-97-07"], "старый уходит в telLog")
        #expect(old.clientPhone == "+7 913 787-97-07", "прошлая запись свой номер не переписывает")
        var call = Self.shoot("call", Self.day(5), contact: "Ольга", phone: "8 913 787-97-07")
        Self.save(&call, &clients, ids: ids)
        #expect(call.clientId == s.clientId && clients.count == 1, "старый номер продолжает узнаваться (с тем же именем)")
    }

    @Test func aNumberOfAnotherClientRebindsInsteadOfChangingThePerson() {
        var clients: [Client] = [], ids = Ids()
        var a = Self.shoot("a", Self.day(1), contact: "Ольга", phone: "+7 913 787-97-07")
        var b = Self.shoot("b", Self.day(2), contact: "Иван", phone: "+7 913 222-33-44")
        Self.save(&a, &clients, ids: ids); Self.save(&b, &clients, ids: ids)
        b.clientPhone = "+7 913 787-97-07"
        Self.save(&b, &clients, ids: ids)
        #expect(b.clientId == clients[1].id && clients.count == 2, "К3б: один чужой номер без имени не переводит съёмку")
        #expect(clients[1].people.map(\.phone) == ["+7 913 222-33-44"], "Иван остался со своим номером, чужой ему не вписан")
        b.contact = "Ольга"
        Self.save(&b, &clients, ids: ids)
        #expect(b.clientId == a.clientId && clients.count == 2, "номер и имя Ольги — съёмка Ольги")
        #expect(clients[1].people.map(\.phone) == ["+7 913 222-33-44"], "Иван остался со своим номером")
    }

    @Test func aPairsChangedNumberReplacesTheRightPerson() {
        var clients: [Client] = [], ids = Ids()
        var wed = Self.shoot("w", Self.day(1), genre: .wedding, persons: [Self.anya, Self.mark])
        Self.save(&wed, &clients, ids: ids)
        wed.persons[1].phone = "+7 913 000-00-99"
        wed.clientPhone = ""
        Self.save(&wed, &clients, ids: ids)
        #expect(clients[0].people.map(\.phone) == [Self.anya.phone, "+7 913 000-00-99"])
        #expect(clients[0].telLog.map(\.phone) == [Self.mark.phone])
    }

    // MARK: разовый проход (§ 3.8)

    @Test func theOneTimePassBuildsClientsFromAllShootsOldestFirst() {
        var sessions = [
            Self.shoot("late", Self.day(20), genre: .animals, contact: "Ольга", phone: "8 913 787-97-07"),
            // К3б: с того же номера записан муж — один номер без имени не склеивает, это свой клиент.
            Self.shoot("husband", Self.day(15), contact: "Сергей Смирнов", phone: "8 913 787-97-07"),
            Self.shoot("early", Self.day(2), genre: .portrait, contact: "Ольга Смирнова", phone: "+7 913 787-97-07"),
            Self.shoot("wed", Self.day(10), genre: .wedding, persons: [Self.anya, Self.mark]),
            Self.shoot("land", Self.day(11), genre: .landscape),
            Self.shoot("org", Self.day(12), genre: .report, contact: "Форум", phone: "+7 383 200-10-10", org: "o1"),
            Self.shoot("nobody", Self.day(13)),
        ]
        var clients: [Client] = []
        let ids = Ids()
        let n = ClientBook.assemble(sessions: &sessions, clients: &clients, mine: [], country: Self.ru, nowMs: 5,
                                    retiredAt: "x", newId: { ids.next() })
        #expect(n == 4 && clients.count == 3)
        let byId = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        #expect(byId["early"]!.clientId == byId["late"]!.clientId && byId["early"]!.clientId != nil)
        #expect(byId["husband"]!.clientId != nil && byId["husband"]!.clientId != byId["early"]!.clientId)
        #expect(clients.first { $0.id == byId["early"]!.clientId }!.people.map(\.name) == ["Ольга Смирнова"], "имя берётся с самой ранней записи")
        #expect(clients.first { $0.id == byId["wed"]!.clientId }!.kind == .couple)
        #expect(byId["land"]!.clientId == nil && byId["org"]!.clientId == nil && byId["nobody"]!.clientId == nil)
        // Второй проход ничего не добавляет: все, у кого мог быть клиент, его уже имеют.
        let again = ClientBook.assemble(sessions: &sessions, clients: &clients, mine: [], country: Self.ru, nowMs: 6,
                                        retiredAt: "x", newId: { ids.next() })
        #expect(again == 0 && clients.count == 3, "повторный проход не плодит клиентов")
    }

    // MARK: список, суммы, фильтры

    @Test func shootsAndLineAreComputedFromTheShootsNotStored() {
        var a = Self.shoot("a", Self.day(1), rate: 8_000); a.clientId = "c1"
        var b = Self.shoot("b", Self.day(9), rate: 12_000); b.clientId = "c1"
        var c = Self.shoot("c", Self.day(5), rate: 1); c.clientId = "c2"
        let all = [a, b, c]
        #expect(ClientBook.shoots(of: "c1", in: all).map(\.id) == ["b", "a"])
        let l = ClientBook.line(of: "c1", in: all, home: .rub)
        #expect(l.shootCount == 2 && l.sums.map(\.sum) == [20_000] && l.sums.map(\.currency) == [.rub])
        #expect(ClientBook.line(of: "none", in: all, home: .rub) == OrgBook.Line(shootCount: 0, sums: []))
    }

    @Test func listIsNewestShootFirstAndFiltersByKind() {
        var p = Client(id: "p", kind: .person), k = Client(id: "k", kind: .couple), f = Client(id: "f", kind: .family)
        let n = Client(id: "n", kind: .person)         // без съёмок
        p.modifiedAt = 1; k.modifiedAt = 2; f.modifiedAt = 3
        var s1 = Self.shoot("1", Self.day(3)); s1.clientId = "p"
        var s2 = Self.shoot("2", Self.day(9)); s2.clientId = "k"
        var s3 = Self.shoot("3", Self.day(9), start: 900); s3.clientId = "f"
        let sessions = [s1, s2, s3]
        let all = [p, k, f, n]
        #expect(ClientBook.list(all, sessions: sessions).map(\.id) == ["f", "k", "p", "n"], "по последней съёмке; без съёмок — внизу")
        #expect(ClientBook.list(all, sessions: sessions, filter: .couples).map(\.id) == ["k"])
        #expect(ClientBook.list(all, sessions: sessions, filter: .families).map(\.id) == ["f"])
        #expect(ClientBook.list(all, sessions: sessions, filter: .persons).map(\.id) == ["p", "n"])
    }

    @Test func titleNamesAPairByFirstNamesAndOthersAsWritten() {
        var c = Client(id: "k", kind: .couple)
        c.people = [ClientPerson(name: "Анна Петрова", phone: ""), ClientPerson(name: "Иван Петров", phone: "")]
        #expect(ClientBook.title(of: c, and: " и ") == "Анна и Иван")
        var p = Client(id: "p", kind: .person)
        p.people = [ClientPerson(name: "Ольга Смирнова", phone: "+7 913 787-97-07")]
        #expect(ClientBook.title(of: p, and: " и ") == "Ольга Смирнова")
        p.people[0].name = ""
        #expect(ClientBook.title(of: p, and: " и ") == "+7 913 787-97-07", "имени нет — первый номер")
        #expect(ClientBook.title(of: Client(id: "e"), and: " и ").isEmpty)
    }

    @Test func idHasTheOrgIdShape() {
        let id = ClientBook.newId(at: 1_790_000_000_000, random: { 5 })
        #expect(id.hasPrefix("c") && id.count == 1 + String(1_790_000_000_000, radix: 36).count + 4)
        #expect(id.hasSuffix("0005"))
    }

    // MARK: запись на диск

    @Test func clientRoundTripsAndKeepsEveryField() throws {
        var c = Client(id: "c1", kind: .couple)
        var a = ClientPerson(name: "Анна Петрова", phone: "+7 916 111-22-33")
        a.birthday = "04-05"; a.preferred = "telegram"
        a.messengers = [ClientMessenger(kind: "telegram", value: "@anna")]
        c.people = [a, ClientPerson(name: "Иван", phone: "")]
        c.main = 1; c.anniversary = Self.day(14, month: 6); c.anniversaryManual = true; c.greet = true
        c.telLog = [TelLogEntry(field: "p1", phone: "+7 916 000-00-00", name: "Анна", retiredAt: "2026-09-01T00:00:00Z")]
        c.modifiedAt = 123
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(Client.self, from: data) == c)
        // Пустое в файл не идёт.
        let bare = String(decoding: try JSONEncoder().encode(Client(id: "c2")), as: UTF8.self)
        #expect(!bare.contains("main") && !bare.contains("greet") && !bare.contains("links") && !bare.contains("anniv"))
    }

    @Test func unknownKindIsReadAsAPersonAndSessionKeepsItsClientId() throws {
        let c = try JSONDecoder().decode(Client.self, from: Data(#"{"id":"c9","kind":"tribe","people":[{"n":"Х"}]}"#.utf8))
        #expect(c.kind == .person && c.people.first?.name == "Х")
        var s = Self.shoot("a", Self.day(1), contact: "Ольга")
        s.clientId = "c9"
        let back = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(s))
        #expect(back.clientId == "c9")
        #expect(!String(decoding: try JSONEncoder().encode(Self.shoot("b", Self.day(1))), as: UTF8.self).contains("clientId"),
                "у записи без клиента ключа нет — веб и старые файлы не видят разницы")
    }
}
