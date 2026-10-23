import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Плашка клиента в форме съёмки (шаг К3, справка `clients_reference.md` § 4.5): по номеру — привязано сразу, по одному
/// имени — подсказка, привязка по «Да», «Другой» — новый клиент и подсказка больше не навязывается.
@Suite struct ClientHintTests {
    typealias B = ClientBookTests
    static let ru = B.ru

    static func hint(_ s: Session, _ clients: [Client], choice: ClientBook.Choice? = nil,
                     sessions: [Session] = []) -> ClientBook.Hint? {
        ClientBook.hint(for: s, choice: choice, clients: clients, sessions: sessions, mine: [], country: ru)
    }

    /// «Сохранить» формы: ответ плашке, затем склейка — как `AppModel.saveForm`.
    @discardableResult
    static func save(_ s: inout Session, _ clients: inout [Client], choice: ClientBook.Choice? = nil,
                     ids: B.Ids) -> ClientBook.Outcome {
        ClientBook.applying(choice, to: &s)
        return B.save(&s, &clients, ids: ids)
    }

    /// Клиент «Анна Петрова» с номером и две её съёмки.
    static func anna(phone: String = "+7 913 111-22-33") -> (clients: [Client], sessions: [Session], ids: B.Ids) {
        let ids = B.Ids()
        var clients: [Client] = []
        var a = B.shoot("s1", B.day(1), contact: "Анна Петрова", phone: phone)
        var b = B.shoot("s2", B.day(5), contact: "Анна Петрова", phone: phone)
        B.save(&a, &clients, ids: ids)
        // Без номера вторая съёмка сама не склеится — её привязали «Да».
        Self.save(&b, &clients, choice: phone.isEmpty ? .pick("c1") : nil, ids: ids)
        return (clients, [a, b], ids)
    }

    // MARK: по номеру

    @Test func oldClientsNumberBindsAtOnceAndThePlateOnlyTells() {
        var (clients, _, ids) = Self.anna()
        var s = B.shoot("n1", B.day(20), contact: "Аня", phone: "8 913 111 22 33")
        #expect(Self.hint(s, clients) == .init(clientId: "c1", way: .phone), "тот же номер в другом виде — тот же клиент")
        let o = Self.save(&s, &clients, ids: ids)
        #expect(o.clientId == "c1" && !o.created && clients.count == 1, "новая съёмка с номером старого клиента — его")
    }

    @Test func numberBeatsTheChoice() {
        var (clients, _, ids) = Self.anna()
        var other = B.shoot("o1", B.day(3), contact: "Ольга", phone: "+7 913 999-00-00")
        B.save(&other, &clients, ids: ids)                                         // c2
        var s = B.shoot("n1", B.day(20), contact: "Анна", phone: "+7 913 999-00-00")
        #expect(Self.hint(s, clients, choice: .pick("c1")) == .init(clientId: "c2", way: .phone))
        #expect(Self.hint(s, clients, choice: .other) == .init(clientId: "c2", way: .phone),
                "«Другой» номер чужого клиента не отменяет: номер главнее")
        #expect(Self.save(&s, &clients, choice: .pick("c1"), ids: ids).clientId == "c2")
    }

    @Test func archivedNumberIsRecognisedToo() {
        var (clients, _, _) = Self.anna()
        clients[0].telLog = [TelLogEntry(field: nil, phone: "+7 913 000-00-01", name: nil, retiredAt: "2026-08-01T00:00:00Z")]
        let s = B.shoot("n1", B.day(20), contact: "", phone: "+7 913 000-00-01")
        #expect(Self.hint(s, clients) == .init(clientId: "c1", way: .phone))
    }

    // MARK: по имени

    @Test func nameAloneOnlyHintsAndYesBinds() {
        var (clients, sessions, ids) = Self.anna()
        var s = B.shoot("n1", B.day(20), contact: "Анна Петрова")
        #expect(Self.hint(s, clients, sessions: sessions) == .init(clientId: "c1", way: .name))
        var kept = s
        var c2 = clients
        let o = Self.save(&kept, &c2, ids: ids)
        #expect(o.created && c2.count == 2, "без «Да» клиент без номера ни с кем не склеивается (слово Алексея 23.10)")

        #expect(Self.hint(s, clients, choice: .pick("c1"), sessions: sessions) == .init(clientId: "c1", way: .bound),
                "после «Да» плашка говорит «Это …» без вопроса")
        let yes = Self.save(&s, &clients, choice: .pick("c1"), ids: ids)
        #expect(yes.clientId == "c1" && !yes.created && clients.count == 1)
        #expect(clients[0].people.count == 1, "«Да» по имени не добавляет человека")
    }

    @Test func otherMakesANewClientAndTheHintStaysAway() {
        var (clients, sessions, ids) = Self.anna()
        var s = B.shoot("n1", B.day(20), contact: "Анна Петрова")
        #expect(Self.hint(s, clients, choice: .other, sessions: sessions) == nil)
        let o = Self.save(&s, &clients, choice: .other, ids: ids)
        #expect(o.created && o.clientId == "c2" && clients.count == 2)
        // Пересохранили ту же съёмку — она уже за новым клиентом, подсказка о прежней Анне не возвращается.
        #expect(Self.hint(s, clients, sessions: sessions + [s]) == .init(clientId: "c2", way: .bound))
    }

    @Test func otherOnABoundShootMovesItToANewClient() {
        var (clients, sessions, ids) = Self.anna(phone: "")
        var s = sessions[1]
        #expect(Self.hint(s, clients, sessions: sessions) == .init(clientId: "c1", way: .bound), "правка своей съёмки — «Это …»")
        #expect(Self.hint(s, clients, choice: .other, sessions: sessions) == nil)
        let o = Self.save(&s, &clients, choice: .other, ids: ids)
        #expect(o.created && s.clientId == "c2", "«Другой» — новый клиент; прежний остаётся со своей первой съёмкой")
    }

    @Test func exactNameBeatsAPrefixAndFreshBeatsOld() {
        let ids = B.Ids()
        var clients: [Client] = []
        var a = B.shoot("a", B.day(1), contact: "Анна Петрова")      // c1, давно
        var b = B.shoot("b", B.day(9), contact: "Анна Сидорова")     // c2, недавно
        var c = B.shoot("c", B.day(2), contact: "Анна")              // c3, давно
        B.save(&a, &clients, ids: ids); B.save(&b, &clients, ids: ids); B.save(&c, &clients, ids: ids)
        let sessions = [a, b, c]
        func h(_ name: String) -> String? { Self.hint(B.shoot("n", B.day(20), contact: name), clients, sessions: sessions)?.clientId }
        #expect(h("Анна") == "c3", "имя целиком главнее начала")
        #expect(h("анна петрова") == "c1", "регистр не важен")
        #expect(h("Анна Сидорова") == "c2")
        #expect(h("Анна Иванова") == "c3", "фамилия другая — подходит только «Анна» началом")
        #expect(h("Ольга") == nil)
        #expect(h("А") == nil, "одна буква — не имя")
    }

    @Test func prefixTiesGoToTheFreshestShoot() {
        let ids = B.Ids()
        var clients: [Client] = []
        var a = B.shoot("a", B.day(1), contact: "Анна Петрова")
        var b = B.shoot("b", B.day(9), contact: "Анна Сидорова")
        B.save(&a, &clients, ids: ids); B.save(&b, &clients, ids: ids)
        let s = B.shoot("n", B.day(20), contact: "Анна")
        #expect(Self.hint(s, clients, sessions: [a, b])?.clientId == "c2")
    }

    @Test func coupleIsFoundByEitherName() {
        let ids = B.Ids()
        var clients: [Client] = []
        var w = B.shoot("w", B.day(1), genre: .wedding,
                        persons: [Person(name: "Аня Ким", phone: ""), Person(name: "Марк Ким", phone: "")])
        B.save(&w, &clients, ids: ids)
        let s = B.shoot("l", B.day(20), genre: .lovestory, persons: [Person(name: "", phone: ""), Person(name: "Марк", phone: "")])
        #expect(Self.hint(s, clients, sessions: [w]) == .init(clientId: "c1", way: .name))
    }

    @Test func noHintWhereNoClientIsMade() {
        let (clients, sessions, _) = Self.anna()
        #expect(Self.hint(B.shoot("x", B.day(20), genre: .landscape, contact: "Анна Петрова"), clients, sessions: sessions) == nil)
        #expect(Self.hint(B.shoot("x", B.day(20), contact: "Анна Петрова", org: "o1"), clients, sessions: sessions) == nil,
                "заказчик — организация: это «Компании»")
        #expect(Self.hint(B.shoot("x", B.day(20)), clients, sessions: sessions) == nil, "пустая форма")
        var meet = B.shoot("x", B.day(20), contact: "Анна Петрова")
        meet.kind = .meet
        #expect(Self.hint(meet, clients, sessions: sessions) == nil)
    }

    // MARK: смена номера в форме

    @Test func typingANumberSwitchesThePlate() {
        var (clients, sessions, ids) = Self.anna()
        var other = B.shoot("o1", B.day(3), contact: "Ольга", phone: "+7 913 999-00-00")
        B.save(&other, &clients, ids: ids)
        var s = B.shoot("n1", B.day(20), contact: "Анна Петрова")
        #expect(Self.hint(s, clients, sessions: sessions)?.way == .name)
        s.clientPhone = "+7 91"
        #expect(Self.hint(s, clients, sessions: sessions)?.way == .name, "меньше пяти цифр — ещё не номер, подсказка держится")
        s.clientPhone = "+7 913 444-55-66"
        #expect(Self.hint(s, clients, sessions: sessions) == nil, "незнакомый номер — будет новый клиент с номером, имени не подсказываем")
        s.clientPhone = "+7 913 999-00-00"
        #expect(Self.hint(s, clients, sessions: sessions) == .init(clientId: "c2", way: .phone), "номер Ольги — съёмка Ольги")
        s.clientPhone = ""
        #expect(Self.hint(s, clients, sessions: sessions)?.way == .name, "номер стёрли — подсказка вернулась")
    }

    @Test func yesThenANewNumberFillsTheSamePerson() {
        var (clients, sessions, ids) = Self.anna(phone: "")
        var s = B.shoot("n1", B.day(20), contact: "Анна Петрова", phone: "+7 913 444-55-66")
        #expect(Self.hint(s, clients, choice: .pick("c1"), sessions: sessions) == .init(clientId: "c1", way: .bound))
        Self.save(&s, &clients, choice: .pick("c1"), ids: ids)
        #expect(s.clientId == "c1" && clients.count == 1)
        #expect(clients[0].people.map(\.phone) == ["+7 913 444-55-66"], "у Анны без номера номер дозаполнился, второй Анны нет")
    }

    @Test func emptyPhoneOfTheSameNameIsFilledInACouple() {
        let ids = B.Ids()
        var clients: [Client] = []
        var w = B.shoot("w", B.day(1), genre: .wedding, persons: [B.anya, Person(name: "Марк", phone: "")])
        B.save(&w, &clients, ids: ids)
        var l = B.shoot("l", B.day(20), genre: .lovestory, persons: [B.anya, B.mark])
        B.save(&l, &clients, ids: ids)
        #expect(l.clientId == "c1" && clients.count == 1)
        #expect(clients[0].people.map(\.phone) == [B.anya.phone, B.mark.phone], "жених пары получил номер, а не потерял его")
    }

    /// Ревью GPT к f4c1e94: в паре два одинаковых имени, номер одного сменили — новый номер его, старый в архиве, а не у второго.
    @Test func aChangedNumberIsNotGivenToTheNamesakeWithoutOne() {
        let ids = B.Ids()
        var clients: [Client] = []
        var w = B.shoot("w", B.day(1), genre: .wedding,
                        persons: [Person(name: "Саша", phone: "+7 913 111-00-01"), Person(name: "Саша", phone: "")])
        B.save(&w, &clients, ids: ids)
        w.persons[0].phone = "+7 913 111-00-02"
        B.save(&w, &clients, ids: ids)
        #expect(clients.count == 1 && clients[0].people.map(\.phone) == ["+7 913 111-00-02", ""],
                "номер сменился у первой Саши, вторая без номера")
        #expect(clients[0].telLog.map(\.phone) == ["+7 913 111-00-01"], "старый номер — в архив")
    }

    // MARK: плашка = склейка

    /// Что плашка обещает словами «по номеру» и «это …», то и делает «Сохранить».
    @Test func plateTellsWhatSaveDoes() {
        let base = Self.anna()
        var with = base.clients
        var other = B.shoot("o1", B.day(3), contact: "Ольга", phone: "+7 913 999-00-00")
        B.save(&other, &with, ids: base.ids)
        let phones = ["", "+7 913 111-22-33", "8 913 999 00 00", "+7 913 444-55-66"]
        let names = ["", "Анна Петрова", "Ольга", "Кто-то"]
        let choices: [ClientBook.Choice?] = [nil, .pick("c1"), .pick("c2"), .other]
        var checked = 0
        for p in phones { for n in names { for ch in choices { for bound in [nil, "c1", "c2"] as [String?] {
            var s = B.shoot("n", B.day(20), contact: n, phone: p)
            s.clientId = bound
            guard let h = Self.hint(s, with, choice: ch, sessions: base.sessions), h.way != .name else { continue }
            var clients = with
            let o = Self.save(&s, &clients, choice: ch, ids: B.Ids())
            #expect(o.clientId == h.clientId && !o.created, "\(p) \(n) \(String(describing: ch)) \(bound ?? "-")")
            checked += 1
        } } } }
        #expect(checked > 40)
    }
}
