import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Плашка клиента в форме и склейка (шаги К3, К3б; справка `clients_reference.md` § 3, § 4.5). Правило Алексея 23.10 —
/// два фактора из трёх (имя, фамилия, номер): номер + имя или фамилия — привязано сразу; имя + фамилия без номера или с
/// другим — вопрос «Это …?» с «Да» / «Другой»; одно совпадение (только имя, только фамилия, только номер) — новый клиент.
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

    static let tel = "+7 913 111-22-33"

    /// Клиент «Анна Петрова» и две её съёмки (вторая узнана по номеру и имени, а без номера — привязана «Да»).
    static func anna(phone: String = tel) -> (clients: [Client], sessions: [Session], ids: B.Ids) {
        let ids = B.Ids()
        var clients: [Client] = []
        var a = B.shoot("s1", B.day(1), contact: "Анна Петрова", phone: phone)
        var b = B.shoot("s2", B.day(5), contact: "Анна Петрова", phone: phone)
        B.save(&a, &clients, ids: ids)
        Self.save(&b, &clients, choice: phone.isEmpty ? .pick("c1") : nil, ids: ids)
        return (clients, [a, b], ids)
    }

    // MARK: номер + имя или фамилия — сразу

    @Test func phoneAndFirstNameBindAtOnce() {
        var (clients, _, ids) = Self.anna()
        var s = B.shoot("n1", B.day(20), contact: "Анна", phone: "8 913 111 22 33")
        #expect(Self.hint(s, clients) == .init(clientId: "c1", way: .phone), "номер в другом виде + имя — тот же клиент")
        let o = Self.save(&s, &clients, ids: ids)
        #expect(o.clientId == "c1" && !o.created && clients.count == 1, "новая съёмка с номером и именем старого клиента — его")
    }

    @Test func phoneAndLastNameBindAtOnce() {
        var (clients, _, ids) = Self.anna()
        var s = B.shoot("n1", B.day(20), contact: "Аня Петрова", phone: Self.tel)
        #expect(Self.hint(s, clients) == .init(clientId: "c1", way: .phone))
        #expect(Self.save(&s, &clients, ids: ids).clientId == "c1" && clients.count == 1)
    }

    @Test func allThreeBindAtOnce() {
        var (clients, _, ids) = Self.anna()
        var s = B.shoot("n1", B.day(20), contact: "Петрова Анна", phone: Self.tel)
        #expect(Self.hint(s, clients)?.way == .phone)
        #expect(Self.save(&s, &clients, ids: ids).clientId == "c1")
    }

    @Test func phoneAndNameBeatTheChoice() {
        var (clients, _, ids) = Self.anna()
        var other = B.shoot("o1", B.day(3), contact: "Ольга", phone: "+7 913 999-00-00")
        B.save(&other, &clients, ids: ids)                                         // c2
        var s = B.shoot("n1", B.day(20), contact: "Ольга", phone: "+7 913 999-00-00")
        #expect(Self.hint(s, clients, choice: .pick("c1")) == .init(clientId: "c2", way: .phone))
        #expect(Self.hint(s, clients, choice: .other) == .init(clientId: "c2", way: .phone), "номер и имя главнее «Другой»")
        #expect(Self.save(&s, &clients, choice: .pick("c1"), ids: ids).clientId == "c2")
    }

    @Test func archivedNumberCountsWithAName() {
        var (clients, _, _) = Self.anna()
        clients[0].telLog = [TelLogEntry(field: nil, phone: "+7 913 000-00-01", name: "Анна", retiredAt: "2026-08-01T00:00:00Z")]
        #expect(Self.hint(B.shoot("n1", B.day(20), contact: "Анна", phone: "+7 913 000-00-01"), clients)?.way == .phone)
        #expect(Self.hint(B.shoot("n2", B.day(20), contact: "", phone: "+7 913 000-00-01"), clients) == nil,
                "прежний номер без имени — один фактор")
    }

    // MARK: имя + фамилия — вопрос

    @Test func firstAndLastNameAskAndYesBinds() {
        var (clients, sessions, ids) = Self.anna()
        var s = B.shoot("n1", B.day(20), contact: "Анна Петрова")
        #expect(Self.hint(s, clients, sessions: sessions) == .init(clientId: "c1", way: .name))
        var kept = s
        var c2 = clients
        #expect(Self.save(&kept, &c2, ids: ids).created && c2.count == 2, "без «Да» — новый клиент")
        #expect(Self.hint(s, clients, choice: .pick("c1"), sessions: sessions) == .init(clientId: "c1", way: .bound),
                "после «Да» плашка говорит «Это …» без вопроса")
        let yes = Self.save(&s, &clients, choice: .pick("c1"), ids: ids)
        #expect(yes.clientId == "c1" && !yes.created && clients.count == 1 && clients[0].people.count == 1)
    }

    @Test func firstAndLastNameWithAnotherNumberAskAndYesTakesTheNumber() {
        var (clients, sessions, ids) = Self.anna()
        var s = B.shoot("n1", B.day(20), contact: "Анна Петрова", phone: "+7 913 444-55-66")
        #expect(Self.hint(s, clients, sessions: sessions) == .init(clientId: "c1", way: .name), "номер другой — спрашиваем")
        Self.save(&s, &clients, choice: .pick("c1"), ids: ids)
        #expect(s.clientId == "c1" && clients.count == 1)
        #expect(clients[0].people.map(\.phone) == ["+7 913 444-55-66"] && clients[0].telLog.map(\.phone) == [Self.tel],
                "«Да»: новый номер у Анны, прежний в архиве и узнаётся")
    }

    @Test func nameOrderCaseAndYoDoNotMatter() {
        let (clients, sessions, _) = Self.anna()
        for n in ["Петрова Анна", "анна петрова", "  АННА   ПЕТРОВА ", "Анна Сергеевна Петрова"] {
            #expect(Self.hint(B.shoot("n", B.day(20), contact: n), clients, sessions: sessions)?.way == .name, Comment(rawValue: n))
        }
        var yo: [Client] = []
        let ids = B.Ids()
        var a = B.shoot("a", B.day(1), contact: "Алёна Сёмина", phone: Self.tel)
        B.save(&a, &yo, ids: ids)
        #expect(Self.hint(B.shoot("n", B.day(20), contact: "Алена Семина"), yo, sessions: [a])?.way == .name, "ё = е")
    }

    @Test func freshestOfTwoNamesakesIsAsked() {
        let ids = B.Ids()
        var clients: [Client] = []
        var a = B.shoot("a", B.day(1), contact: "Анна Петрова", phone: "+7 913 000-00-01")
        var b = B.shoot("b", B.day(9), contact: "Анна Петрова", phone: "+7 913 000-00-02")
        B.save(&a, &clients, ids: ids); B.save(&b, &clients, ids: ids)
        #expect(clients.count == 2, "две Анны Петровы с разными номерами — разные клиенты")
        #expect(Self.hint(B.shoot("n", B.day(20), contact: "Анна Петрова"), clients, sessions: [a, b])?.clientId == "c2")
    }

    @Test func aCoupleIsAskedByEitherFullName() {
        let ids = B.Ids()
        var clients: [Client] = []
        var w = B.shoot("w", B.day(1), genre: .wedding,
                        persons: [Person(name: "Аня Ким", phone: ""), Person(name: "Марк Ким", phone: "")])
        B.save(&w, &clients, ids: ids)
        let s = B.shoot("l", B.day(20), genre: .lovestory, persons: [Person(name: "", phone: ""), Person(name: "Марк Ким", phone: "")])
        #expect(Self.hint(s, clients, sessions: [w]) == .init(clientId: "c1", way: .name))
    }

    @Test func aCoupleIsBoundByTheGroomsNumberAndName() {
        let ids = B.Ids()
        var clients: [Client] = []
        var w = B.shoot("w", B.day(1), genre: .wedding, persons: [B.anya, B.mark])
        B.save(&w, &clients, ids: ids)
        var l = B.shoot("l", B.day(20), genre: .lovestory, persons: [Person(name: "", phone: ""), Person(name: "Марк", phone: B.mark.phone)])
        #expect(Self.hint(l, clients, sessions: [w]) == .init(clientId: "c1", way: .phone))
        #expect(Self.save(&l, &clients, ids: ids).clientId == "c1" && clients.count == 1)
    }

    /// Ревью GPT к 8c67c5a: номер сверяется с тем человеком, чей он, — Анна с номером Марка не узнаёт их пару.
    @Test func thePhoneMustBelongToTheNamedPerson() {
        let ids = B.Ids()
        var clients: [Client] = []
        var w = B.shoot("w", B.day(1), genre: .wedding, persons: [B.anya, B.mark])
        B.save(&w, &clients, ids: ids)
        var s = B.shoot("p", B.day(20), contact: "Аня", phone: B.mark.phone)
        #expect(Self.hint(s, clients, sessions: [w]) == nil, "имя одного человека пары, номер другого — один фактор")
        #expect(Self.save(&s, &clients, ids: ids).created && clients.count == 2)
        var old = clients[0]
        old.telLog = [TelLogEntry(field: nil, phone: "+7 913 000-00-09", name: "Марк", retiredAt: "x")]
        #expect(Self.hint(B.shoot("q", B.day(21), contact: "Аня", phone: "+7 913 000-00-09"), [old], sessions: [w]) == nil,
                "прежний номер — того, чьё имя у него в архиве")
        #expect(Self.hint(B.shoot("r", B.day(21), contact: "Марк", phone: "+7 913 000-00-09"), [old], sessions: [w])?.way == .phone)
    }

    /// Ревью GPT к 8c67c5a: отчество — не имя и не фамилия.
    @Test func aPatronymicIsNotAFactor() {
        let ids = B.Ids()
        var clients: [Client] = []
        var a = B.shoot("a", B.day(1), contact: "Анна Сергеевна Петрова", phone: Self.tel)
        B.save(&a, &clients, ids: ids)
        #expect(Self.hint(B.shoot("n", B.day(20), contact: "Мария Сергеевна Петрова"), clients, sessions: [a]) == nil,
                "общие отчество и фамилия — одно совпадение")
        #expect(Self.hint(B.shoot("n", B.day(20), contact: "Мария Сергеевна", phone: Self.tel), clients, sessions: [a]) == nil,
                "номер и отчество — не два фактора")
        #expect(Self.hint(B.shoot("n", B.day(20), contact: "Петрова Анна Сергеевна"), clients, sessions: [a])?.way == .name)
        var fio: [Client] = []
        var f = B.shoot("f", B.day(1), contact: "Петрова Анна Сергеевна", phone: Self.tel)
        B.save(&f, &fio, ids: B.Ids())
        #expect(Self.hint(B.shoot("n", B.day(20), contact: "Петрова Мария Сергеевна"), fio, sessions: [f]) == nil,
                "«Фамилия Имя Отчество»: отчество последним тоже не фактор")
    }

    /// Отчество выпадает по месту, одно слово: фамилия на «-вич» остаётся (находка К3б, слово оркестратора).
    @Test func aSurnameEndingInVichIsKept() {
        let ids = B.Ids()
        var clients: [Client] = []
        var a = B.shoot("a", B.day(1), contact: "Роман Абрамович", phone: Self.tel)
        B.save(&a, &clients, ids: ids)
        for n in ["Роман Аркадьевич Абрамович", "Абрамович Роман Аркадьевич", "Абрамович Роман"] {
            #expect(Self.hint(B.shoot("n", B.day(20), contact: n), clients, sessions: [a])?.way == .name, Comment(rawValue: n))
        }
        #expect(Self.hint(B.shoot("n", B.day(20), contact: "Роман Абрамович", phone: "+7 913 000-00-07"), clients, sessions: [a])?.way == .name,
                "двухсловное имя с фамилией на «-вич» — не отчество")
        #expect(Self.hint(B.shoot("n", B.day(20), contact: "Олег Абрамович", phone: Self.tel), clients, sessions: [a])?.way == .phone,
                "номер + фамилия на «-вич» — сразу")
    }

    // MARK: одно совпадение — новый клиент

    @Test func onlyTheFirstNameMakesANewClient() {
        var (clients, sessions, ids) = Self.anna()
        var s = B.shoot("n1", B.day(20), contact: "Анна")
        #expect(Self.hint(s, clients, sessions: sessions) == nil)
        #expect(Self.save(&s, &clients, ids: ids).created && clients.count == 2)
    }

    @Test func onlyTheLastNameMakesANewClient() {
        var (clients, sessions, ids) = Self.anna()
        var s = B.shoot("n1", B.day(20), contact: "Мария Петрова")
        #expect(Self.hint(s, clients, sessions: sessions) == nil)
        #expect(Self.save(&s, &clients, ids: ids).created && clients.count == 2)
    }

    @Test func onlyThePhoneMakesANewClientWithTheSamePhone() {
        var (clients, sessions, ids) = Self.anna()
        var wife = B.shoot("n1", B.day(20), contact: "Ольга Иванова", phone: "8 913 111-22-33")
        #expect(Self.hint(wife, clients, sessions: sessions) == nil, "с телефона Анны записалась Ольга — не Анна")
        let o = Self.save(&wife, &clients, ids: ids)
        #expect(o.created && clients.count == 2)
        let keys = clients.map { $0.people.map { TelFormat.full($0.phone, country: Self.ru) } }
        #expect(keys[0] == keys[1], "один номер живёт у двух клиентов")
        var again = B.shoot("n2", B.day(25), contact: "Ольга", phone: Self.tel)
        #expect(Self.save(&again, &clients, ids: ids).clientId == wife.clientId, "дальше Ольга с этого номера — Ольга")
        var nameless = B.shoot("n3", B.day(26), contact: "", phone: Self.tel)
        #expect(Self.save(&nameless, &clients, ids: ids).created, "номер без имени — один фактор")
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

    // MARK: «Другой», своя съёмка

    @Test func otherMakesANewClientAndTheQuestionStaysAway() {
        var (clients, sessions, ids) = Self.anna()
        var s = B.shoot("n1", B.day(20), contact: "Анна Петрова")
        #expect(Self.hint(s, clients, choice: .other, sessions: sessions) == nil)
        let o = Self.save(&s, &clients, choice: .other, ids: ids)
        #expect(o.created && o.clientId == "c2" && clients.count == 2)
        #expect(Self.hint(s, clients, sessions: sessions + [s]) == .init(clientId: "c2", way: .bound),
                "пересохранили — съёмка у нового клиента, вопрос о прежней Анне не возвращается")
    }

    @Test func otherOnABoundShootMovesItToANewClient() {
        var (clients, sessions, ids) = Self.anna(phone: "")
        var s = sessions[1]
        #expect(Self.hint(s, clients, sessions: sessions) == .init(clientId: "c1", way: .bound), "правка своей съёмки — «Это …»")
        #expect(Self.hint(s, clients, choice: .other, sessions: sessions) == nil)
        let o = Self.save(&s, &clients, choice: .other, ids: ids)
        #expect(o.created && s.clientId == "c2")
    }

    // MARK: смена номера в форме

    @Test func typingANumberSwitchesThePlate() {
        var (clients, sessions, ids) = Self.anna()
        var other = B.shoot("o1", B.day(3), contact: "Ольга", phone: "+7 913 999-00-00")
        B.save(&other, &clients, ids: ids)
        var s = B.shoot("n1", B.day(20), contact: "Анна Петрова")
        #expect(Self.hint(s, clients, sessions: sessions)?.way == .name)
        s.clientPhone = "+7 913 444-55-66"
        #expect(Self.hint(s, clients, sessions: sessions) == .init(clientId: "c1", way: .name), "незнакомый номер — вопрос держится")
        s.clientPhone = "+7 913 999-00-00"
        #expect(Self.hint(s, clients, sessions: sessions) == .init(clientId: "c1", way: .name), "номер Ольги без её имени — не Ольга")
        s.clientPhone = Self.tel
        #expect(Self.hint(s, clients, sessions: sessions) == .init(clientId: "c1", way: .phone), "номер Анны — привязано сразу")
        s.clientPhone = ""
        #expect(Self.hint(s, clients, sessions: sessions)?.way == .name)
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
        let phones = ["", Self.tel, "8 913 999 00 00", "+7 913 444-55-66"]
        let names = ["", "Анна", "Анна Петрова", "Ольга", "Кто-то"]
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
