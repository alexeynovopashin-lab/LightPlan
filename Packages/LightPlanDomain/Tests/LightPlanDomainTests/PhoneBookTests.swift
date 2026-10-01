import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// «Контакты»: список номеров на лету, дубли, пустые, роли; ушедший номер; встреча → съёмка
/// (итерация 28, шаг 7; справка `docs/org_reference.md` §§ 2–3, ошибки веба 25, 26, 29–31).
@Suite struct PhoneBookTests {
    static let ru = TelCountry.of("RU")!
    static func day(_ d: Int, month: Int = 9) -> CivilDate { CivilDate(year: 2026, month: month, day: d) }

    static func shoot(_ id: String, _ d: CivilDate, client: (String, String)? = nil, persons: [(String, String)] = [],
                      person: (String, String)? = nil, kind: RecordKind = .shoot, log: [TelLogEntry] = []) -> Session {
        var s = Session(id: id, kind: kind, day: d, start: 600, end: 720, duration: 120, genre: .wedding)
        if let client { s.contact = client.0; s.clientPhone = client.1 }
        s.persons = persons.map { Person(name: $0.0, phone: $0.1) }
        if let person { s.orderPerson = person.0; s.orderPhone = person.1 }
        s.telLog = log
        return s
    }

    static func org(_ id: String, _ name: String, phone: String, person: String = "", log: [TelLogEntry] = []) -> Org {
        var o = Org(id: id, name: name)
        o.phone = phone
        o.person = person
        o.telLog = log
        return o
    }

    static func index(_ sessions: [Session], _ orgs: [Org] = [], mine: Set<String> = []) -> [PhoneBook.Group] {
        PhoneBook.index(sessions: sessions, orgs: orgs, mine: mine, country: ru)
    }

    // MARK: - Дубли и пустые

    @Test func sameNumberInAnyNotationIsOneGroup() {
        let g = Self.index([Self.shoot("a", Self.day(1), client: ("Ирина", "8 916 123-45-67")),
                            Self.shoot("b", Self.day(2), client: ("Ирина", "+7 916 123-45-67"))])
        #expect(g.count == 1 && g[0].rows.count == 2, "«8 916…» и «+7 916…» — один номер")
        #expect(g[0].phone == "+7 916 123-45-67" || g[0].phone == "8 916 123-45-67")
    }

    @Test func emptyAndStubsNeverEnterTheList() {
        let g = Self.index([Self.shoot("a", Self.day(1), client: ("Ирина", "")),
                            Self.shoot("b", Self.day(2), client: ("Пётр", "1234"), person: ("Анна", "  ")),
                            Self.shoot("c", Self.day(3), client: ("Ольга", "8 916 000-11-22"))],
                           [Self.org("o", "Пустая", phone: "12")])
        #expect(g.count == 1 && g[0].rows.map(\.name) == ["Ольга"], "короче пяти цифр и пустое — не номер")
    }

    @Test func retiredStubIsNotListedEither() {
        let log = [TelLogEntry(field: "client", phone: "123", name: "Х", retiredAt: "2026-09-01T10:00:00Z")]
        #expect(Self.index([Self.shoot("a", Self.day(1), log: log)]).isEmpty)
    }

    @Test func fullestLiveNotationIsShown() {
        let g = Self.index([Self.shoot("a", Self.day(1), client: ("Ирина", "916 123-45-67")),
                            Self.shoot("b", Self.day(2), client: ("Ирина", "+7 916 123-45-67"))])
        #expect(g[0].phone == "+7 916 123-45-67", "звонить надо по записи с кодом страны")
    }

    // MARK: - Один человек — одна строка (ошибка веба 26)

    @Test func clientWhoIsAlsoTheBrideTakesOneRowWithTheSharperRole() {
        let s = Self.shoot("a", Self.day(1), client: ("Настя", "8 923 898-08-18"), persons: [("Настя", "+7 923 898-08-18")])
        let g = Self.index([s])
        #expect(g.count == 1 && g[0].rows.count == 1, "один человек занимает одну строку")
        #expect(g[0].rows[0].field == "p1" && g[0].rows[0].name == "Настя", "невеста точнее клиента")
        #expect(!g[0].isLink, "одна карточка — не связка")
    }

    @Test func differentPeopleOnOneNumberKeepTheirOwnRows() {
        let s = Self.shoot("a", Self.day(1), client: ("Отец", "8 923 898-08-18"), persons: [("Настя", "8 923 898-08-18")])
        let g = Self.index([s])
        #expect(g[0].rows.map(\.name).sorted() == ["Настя", "Отец"], "разные имена — разные люди")
    }

    // MARK: - Связки, порядок, живые и прошлые

    @Test func numberInTwoCardsIsALinkAndGoesFirst() {
        let a = Self.shoot("a", Self.day(1), client: ("Ирина", "8 913 787-97-07"))
        let b = Self.shoot("b", Self.day(5), client: ("Мария", "8 900 111-22-33"))
        let c = Self.shoot("c", Self.day(3), person: ("Ирина", "+7 913 787-97-07"))
        let g = Self.index([a, b, c])
        #expect(g.map(\.isLink) == [true, false] && g[0].cards == 2)
        #expect(PhoneBook.linkCount(g) == 1)
    }

    @Test func sortsByFreshnessWhenNoLinks() {
        let g = Self.index([Self.shoot("old", Self.day(1, month: 3), client: ("А", "8 900 000-00-01")),
                            Self.shoot("new", Self.day(1, month: 9), client: ("Б", "8 900 000-00-02")),
                            Self.shoot("mid", Self.day(1, month: 6), client: ("В", "8 900 000-00-03"))],
                           [Self.org("o", "Без даты", phone: "8 900 000-00-04")])
        #expect(g.map { $0.rows[0].name } == ["Б", "В", "А", ""], "от свежих к старым, организация без даты — в конец")
    }

    @Test func meetingsAndEventsAreIncludedToo() {
        let g = Self.index([Self.shoot("m", Self.day(1), client: ("Ирина", "8 900 000-00-01"), kind: .meet),
                            Self.shoot("e", Self.day(2), client: ("Пётр", "8 900 000-00-02"), kind: .event)])
        #expect(g.count == 2, "все записи без фильтра по роду")
    }

    @Test func pastRowInsideALiveNumberStaysMarkedPast() {
        let log = [TelLogEntry(field: "client", phone: "8 916 123-45-67", name: "Ирина", retiredAt: "2026-09-10T10:00:00Z")]
        let g = Self.index([Self.shoot("old", Self.day(1), log: log)],
                           [Self.org("o", "Агентство", phone: "8 916 123-45-67", person: "Мария")])
        #expect(g.count == 1 && g[0].live && g[0].isLink)
        #expect(g[0].rows.filter(\.past).count == 1 && g[0].rows.filter { !$0.past }.count == 1)
    }

    @Test func onlyRetiredNumberIsNotLive() {
        let log = [TelLogEntry(field: "client", phone: "8 916 123-45-67", name: "Ирина", retiredAt: "2026-09-10T10:00:00Z")]
        let g = Self.index([Self.shoot("old", Self.day(1), log: log)])
        #expect(g.count == 1 && !g[0].live, "всё прежнее — номер приглушён, без звонка")
    }

    @Test func retiredRowIsDroppedWhereTheSameCardHoldsTheNumberAgain() {
        let log = [TelLogEntry(field: "client", phone: "8 916 123-45-67", name: "Ирина", retiredAt: "2026-09-10T10:00:00Z")]
        let g = Self.index([Self.shoot("a", Self.day(1), client: ("Ирина", "+7 916 123-45-67"), log: log)])
        #expect(g[0].rows.count == 1 && !g[0].rows[0].past, "вернулись к старому номеру — не двойник")
    }

    @Test func retiredRowWithAnotherNameDoesNotHideBehindALiveOneOfTheSameCard() {
        let log = [TelLogEntry(field: "person", phone: "8 916 123-45-67", name: "Ирина", retiredAt: "2026-09-10T10:00:00Z")]
        let g = Self.index([Self.shoot("a", Self.day(1), client: ("Мария", "+7 916 123-45-67"), log: log)])
        #expect(g[0].rows.map(\.name) == ["Мария"] && g[0].rows.allSatisfy { !$0.past }, "в той же карточке номер снова жив: прежняя строка — шум")
    }

    @Test func retiredNumbersOfOrgsAreListedAndStubsAreNot() {
        let ok = TelLogEntry(field: "org", phone: "8 916 123-45-67", name: "Ирина", retiredAt: "2026-09-10T10:00:00Z")
        let stub = TelLogEntry(field: "org", phone: "12", name: "X", retiredAt: "2026-09-11T10:00:00Z")
        let g = Self.index([], [Self.org("o", "Агентство", phone: "12", log: [ok, stub])])
        #expect(g.count == 1 && !g[0].live && g[0].rows[0].past && g[0].rows[0].card == .org("o"))
    }

    @Test func myNumberIsFlaggedNotRemoved() {
        let mine = PhoneBook.mineKeys(["id79161234567", "8 999 000-00-00"], country: Self.ru)
        let g = Self.index([Self.shoot("a", Self.day(1), client: ("Я", "+7 916 123-45-67")),
                            Self.shoot("b", Self.day(2), client: ("Ты", "8 900 111-22-33"))], mine: mine)
        #expect(g.first { $0.rows[0].name == "Я" }?.mine == true)
        #expect(g.first { $0.rows[0].name == "Ты" }?.mine == false)
    }

    @Test func firstNameDropsTheSurname() {
        #expect(PhoneBook.firstName("  Алексей  Иванов ") == "Алексей")
        #expect(PhoneBook.firstName("") == "")
    }

    // MARK: - Ушедший номер (веб `telRetire`, ошибка 29)

    @Test func goneNumberGoesIntoTheLogWithItsName() {
        let before = [PhoneBook.Tel(field: "client", phone: "8 916 123-45-67", name: "Ирина")]
        let out = PhoneBook.retire(before: before, after: [], log: [], at: "2026-09-30T10:00:00Z", country: Self.ru)
        #expect(out == [TelLogEntry(field: "client", phone: "8 916 123-45-67", name: "Ирина", retiredAt: "2026-09-30T10:00:00Z")])
    }

    @Test func numberMovedInsideOneCardIsNotGone() {
        let before = [PhoneBook.Tel(field: "client", phone: "8 916 123-45-67", name: "Настя")]
        let after = [PhoneBook.Tel(field: "p1", phone: "+7 916 123-45-67", name: "Настя")]
        #expect(PhoneBook.retire(before: before, after: after, log: [], at: "x", country: Self.ru).isEmpty,
                "переезд в другое поле — не смена номера")
    }

    @Test func numberAlreadyInTheLogIsNotWrittenTwice() {
        let log = [TelLogEntry(field: "client", phone: "+7 916 123-45-67", name: "Ирина", retiredAt: "old")]
        let before = [PhoneBook.Tel(field: "client", phone: "8 916 123-45-67", name: "Ирина")]
        #expect(PhoneBook.retire(before: before, after: [], log: log, at: "new", country: Self.ru) == log)
    }

    @Test func logKeepsTheLastTwelve() {
        var before: [PhoneBook.Tel] = []
        for i in 0..<15 { before.append(PhoneBook.Tel(field: "p1", phone: "8 900 000-00-\(String(format: "%02d", i))", name: "n\(i)")) }
        let out = PhoneBook.retire(before: before, after: [], log: [], at: "t", country: Self.ru)
        #expect(out.count == 12 && out.first?.name == "n3" && out.last?.name == "n14", "старые срезаются")
    }

    @Test func telsOfAShootAreFourRolesAndSkipStubs() {
        let s = Self.shoot("a", Self.day(1), client: ("К", "8 900 000-00-01"), persons: [("Н", "8 900 000-00-02"), ("Ж", "12")],
                           person: ("Л", "8 900 000-00-03"))
        #expect(PhoneBook.tels(of: s, country: Self.ru).map(\.field) == ["client", "p1", "person"])
    }
}

/// Встреча → съёмка (веб `#cdGrow`).
@Suite struct MeetGrowTests {
    static func meet() -> Session {
        var m = Session(id: "m1", kind: .meet, day: CivilDate(year: 2026, month: 9, day: 5), start: 840, end: 900, duration: 60, genre: .wedding)
        m.contact = "Ирина"; m.clientPhone = "8 916 123-45-67"
        m.persons = [Person(name: "Настя", phone: "8 923 000-11-22")]
        m.orderPerson = "Мария"; m.orderPhone = "8 900 000-00-01"
        m.orgId = "o1"; m.place = "Кафе"; m.placeTown = "Москва"; m.notes = "обсудить свет"
        m.questSent = Date(timeIntervalSince1970: 1_780_000_000)
        return m
    }
    static let when = CivilDate(year: 2026, month: 10, day: 5)

    @Test func draftLeavesTheMeetUntouchedUntilLinked() throws {
        let meet = Self.meet()
        let draft = MeetGrow.draft(from: meet, shootId: "s1", day: Self.when, start: 1080, duration: 120)
        #expect(draft.kind == .shoot && draft.fromMeetId == meet.id && MeetGrow.canGrow(meet), "встреча по-прежнему встреча")
        #expect(meet.grewOn == nil && meet.grewToId == nil)
        let linked = MeetGrow.link(meet, to: draft, modifiedAt: 9)
        #expect(linked.grewOn == draft.day && linked.grewToId == "s1" && linked.modifiedAt == 9 && !MeetGrow.canGrow(linked))
    }

    @Test func formWithoutDateCannotBeSaved() {
        var f = EventForm.new(id: "n", day: Self.when, start: 600, fromLight: false, genre: .portrait, light: nil, step: 5)
        #expect(SaveGuard.verdict(f) == .ok, "обычная новая форма сохраняется")
        f.dayUnset = true
        #expect(SaveGuard.verdict(f) == .noDate)
        f.setStart(minute: 660)
        #expect(SaveGuard.verdict(f) == .noDate, "время дату не называет")
        f.setStart(day: Self.when)
        #expect(SaveGuard.verdict(f) == .ok && !f.dayUnset, "выбор даты снимает запрет")
    }

    @Test func shootCarriesGenreNamesPhonesPlaceNotesAndQuest() throws {
        let r = try #require(MeetGrow.make(from: Self.meet(), shootId: "s1", day: Self.when, start: 1080, duration: 120, modifiedAt: 5))
        let s = r.shoot
        #expect(s.kind == .shoot && s.day == Self.when && s.start == 1080 && s.end == 1200 && s.duration == 120)
        #expect(s.genre == .wedding && s.contact == "Ирина" && s.notes == "обсудить свет" && s.orgId == "o1")
        #expect(s.clientPhone == "8 916 123-45-67", "телефон клиента переезжает (ошибка веба 31)")
        #expect(s.persons == Self.meet().persons && s.orderPerson == "Мария" && s.orderPhone == "8 900 000-00-01")
        #expect(s.place == "Кафе" && s.placeTown == "Москва")
        #expect(s.questSent != nil, "отправленный опросник не уходит второй раз")
        #expect(s.fromMeetId == "m1" && s.fromMeetOn == Self.meet().day)
    }

    @Test func meetingStaysAndRemembersTheShootByKey() throws {
        let r = try #require(MeetGrow.make(from: Self.meet(), shootId: "s1", day: Self.when, start: 1080, duration: 120, modifiedAt: 5))
        #expect(r.meet.kind == .meet && r.meet.id == "m1" && r.meet.day == Self.meet().day, "встреча остаётся в календаре")
        #expect(r.meet.grewOn == Self.when && r.meet.grewToId == "s1" && r.meet.modifiedAt == 5)
    }

    @Test func secondGrowIsRefused() throws {
        let r = try #require(MeetGrow.make(from: Self.meet(), shootId: "s1", day: Self.when, start: 1080, duration: 120, modifiedAt: 5))
        #expect(!MeetGrow.canGrow(r.meet))
        #expect(MeetGrow.make(from: r.meet, shootId: "s2", day: Self.when, start: 1080, duration: 120, modifiedAt: 6) == nil,
                "повторное назначение не создаёт вторую съёмку")
    }

    @Test func aShootCannotGrow() {
        var s = Self.meet(); s.kind = .shoot
        #expect(!MeetGrow.canGrow(s) && MeetGrow.make(from: s, shootId: "x", day: Self.when, start: 0, duration: 60, modifiedAt: nil) == nil)
    }
}
