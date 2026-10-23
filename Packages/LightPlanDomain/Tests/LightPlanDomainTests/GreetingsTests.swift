import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// «Поздравлять» (шаг К6, справка `clients_reference.md` § 6): дни рождения, годовщина из свадьбы, праздники по дням,
/// 29 февраля, одно уведомление на день, 40 ближайших дней.
@Suite struct GreetingsTests {
    typealias B = ClientBookTests

    static func d(_ y: Int, _ m: Int, _ d: Int) -> CivilDate { CivilDate(year: y, month: m, day: d) }

    static func person(_ id: String, _ name: String, bd: String?, greet: Bool = true) -> Client {
        var c = Client(id: id, kind: .person)
        var p = ClientPerson(name: name)
        p.birthday = bd
        c.people = [p]
        c.greet = greet
        return c
    }

    static func couple(_ id: String, _ a: String, _ b: String, greet: Bool = true) -> Client {
        var c = Client(id: id, kind: .couple)
        c.people = [ClientPerson(name: a), ClientPerson(name: b)]
        c.greet = greet
        return c
    }

    static func wedding(_ id: String, _ day: CivilDate, client: String) -> Session {
        var s = B.shoot(id, day, genre: .wedding)
        s.clientId = client
        return s
    }

    static func days(_ clients: [Client], _ sessions: [Session] = [], from start: CivilDate, cap: Int = Greetings.cap) -> [Greetings.Day] {
        Greetings.days(clients: clients, sessions: sessions, from: start, cap: cap, and: " и ")
    }

    // MARK: день рождения

    @Test func birthdayReadsMonthDayWithOrWithoutYear() {
        #expect(Birthday("11-02") == Birthday(month: 11, day: 2))
        #expect(Birthday("1990-11-02") == Birthday(year: 1990, month: 11, day: 2))
        #expect(Birthday("02-29") != nil, "29 февраля без года — законный день")
        #expect(Birthday("2023-02-29") == nil, "в невисокосный год 29 февраля не бывает")
        #expect(Birthday("13-01") == nil && Birthday("04-31") == nil && Birthday("") == nil && Birthday(nil) == nil)
        #expect(Birthday("abc") == nil && Birthday("90-11-02") == nil)
        // Не падает на «цифрах», которых `Int` не знает, и на слишком длинных числах (ревью GPT к 570ed3e).
        #expect(Birthday("½-02") == nil && Birthday("٠٣-٠٧") == nil && Birthday("99999999999999999999-01") == nil)
        #expect(Birthday("+3-07") == nil && Birthday("03--07") == nil && Birthday("-03-07") == nil)
        #expect(Birthday(month: 3, day: 7)!.snapshotString == "03-07")
        #expect(Birthday(year: 1990, month: 3, day: 7)!.snapshotString == "1990-03-07")
    }

    @Test func ageIsKnownOnlyWithTheYear() {
        let b = Birthday(year: 1990, month: 11, day: 2)!
        #expect(b.age(on: Self.d(2026, 11, 1)) == 35)
        #expect(b.age(on: Self.d(2026, 11, 2)) == 36)
        #expect(Birthday(month: 11, day: 2)!.age(on: Self.d(2026, 11, 2)) == nil)
        // 29 февраля: в невисокосный год год прибавляется 28-го — в день поздравления (ревью GPT к 570ed3e).
        let leap = Birthday(year: 2000, month: 2, day: 29)!
        #expect(leap.age(on: Self.d(2027, 2, 27)) == 26 && leap.age(on: Self.d(2027, 2, 28)) == 27)
        #expect(leap.age(on: Self.d(2028, 2, 28)) == 27 && leap.age(on: Self.d(2028, 2, 29)) == 28)
    }

    // MARK: по дням

    @Test func occasionsListedPerDayNearestFirst() {
        let olga = Self.person("c1", "Ольга", bd: "11-02")
        let petr = Self.person("c2", "Пётр", bd: "1980-10-30")
        let days = Self.days([olga, petr], from: Self.d(2026, 10, 24))
        #expect(days.prefix(2).map(\.date) == [Self.d(2026, 10, 30), Self.d(2026, 11, 2)])
        #expect(days[0].occasions == [Greetings.Occasion(kind: .birthday, clientId: "c2", name: "Пётр", years: 46)])
        #expect(days[1].occasions[0].years == nil, "года нет — возраста нет")
        // Год вперёд: каждый праздник один раз, следующий — в 2027.
        #expect(days.map(\.date) == [Self.d(2026, 10, 30), Self.d(2026, 11, 2)])
    }

    @Test func passedBirthdayComesNextYear() {
        let days = Self.days([Self.person("c1", "Ольга", bd: "03-07")], from: Self.d(2026, 10, 24))
        #expect(days.map(\.date) == [Self.d(2027, 3, 7)])
    }

    @Test func clientsWithoutGreetAreSilent() {
        let days = Self.days([Self.person("c1", "Ольга", bd: "11-02", greet: false)], from: Self.d(2026, 10, 24))
        #expect(days.isEmpty)
    }

    @Test func oneNotificationPerDayListsEveryOccasionAnniversariesFirst() {
        var anna = Self.couple("c1", "Анна Петрова", "Иван Петров")
        anna.people[1].birthday = "11-02"
        let olga = Self.person("c2", "Ольга", bd: "11-02")
        let w = Self.wedding("w", Self.d(2024, 11, 2), client: "c1")
        let days = Self.days([olga, anna], [w], from: Self.d(2026, 10, 24))
        #expect(days.count == 1)
        #expect(days[0].date == Self.d(2026, 11, 2))
        #expect(days[0].occasions.map(\.kind) == [.anniversary, .birthday, .birthday])
        #expect(days[0].occasions.map(\.name) == ["Анна и Иван", "Иван Петров", "Ольга"])
        #expect(days[0].occasions[0].years == 2)
        #expect(days[0].clientId == nil, "праздники разных клиентов — нажатие ведёт в «Клиенты»")
        let one = Self.days([anna], [w], from: Self.d(2026, 10, 24))
        #expect(one[0].occasions.count == 2 && one[0].clientId == "c1", "праздники одного клиента — его карточка")
    }

    @Test func leapDayFallsOnFebruary28InCommonYears() {
        let c = Self.person("c1", "Ольга", bd: "2000-02-29")
        #expect(Self.days([c], from: Self.d(2026, 10, 24)).map(\.date) == [Self.d(2027, 2, 28)])
        #expect(Self.days([c], from: Self.d(2027, 10, 24)).map(\.date) == [Self.d(2028, 2, 29)])
        #expect(Greetings.observed(month: 2, day: 29, in: 2100) == Self.d(2100, 2, 28), "2100 — не високосный")
        // Годовщина свадьбы 29 февраля — так же.
        let w = Self.wedding("w", Self.d(2024, 2, 29), client: "c2")
        let days = Self.days([Self.couple("c2", "Анна", "Иван")], [w], from: Self.d(2026, 10, 24))
        #expect(days.map(\.date) == [Self.d(2027, 2, 28)])
    }

    @Test func capKeepsTheFortyNearestDays() {
        // 100 клиентов с разными днями рождения подряд с 25.10.
        let clients = (0..<100).map { i -> Client in
            let day = Self.d(2026, 10, 25).adding(days: i)
            return Self.person("c\(i)", "Человек \(i)", bd: String(format: "%02d-%02d", day.month, day.day))
        }
        let days = Self.days(clients, from: Self.d(2026, 10, 24))
        #expect(days.count == 40)
        #expect(days.first?.date == Self.d(2026, 10, 25) && days.last?.date == Self.d(2026, 12, 3))
        #expect(days == days.sorted { $0.date < $1.date })
    }

    @Test func todayCountsUntilTenOClock() {
        let today = Self.d(2026, 10, 24)
        #expect(Greetings.firstDay(today: today, minute: 9 * 60 + 59) == today)
        #expect(Greetings.firstDay(today: today, minute: 10 * 60) == Self.d(2026, 10, 25))
    }

    // MARK: годовщина

    @Test func anniversaryComesFromTheEarliestWedding() {
        let c = Self.couple("c1", "Анна", "Иван")
        let first = Self.wedding("w1", Self.d(2025, 6, 14), client: "c1")
        let later = Self.wedding("w2", Self.d(2025, 8, 1), client: "c1")
        var portrait = B.shoot("p", Self.d(2025, 5, 1)); portrait.clientId = "c1"
        var other = Self.wedding("x", Self.d(2020, 1, 1), client: "c9")
        other.genre = .wedding
        #expect(Greetings.anniversary(of: c, in: [later, portrait, first, other]) == Self.d(2025, 6, 14))
        // Свадьба на два дня — день начала.
        var two = Self.wedding("w3", Self.d(2025, 6, 13), client: "c1")
        two.duration = 2 * 24 * 60
        #expect(Greetings.anniversary(of: c, in: [first, two]) == Self.d(2025, 6, 13))
    }

    @Test func handEditedAnniversaryIsNotMovedByWeddingsAndCanBeCleared() {
        var c = Self.couple("c1", "Анна", "Иван")
        let w = Self.wedding("w", Self.d(2025, 6, 14), client: "c1")
        c.anniversary = Self.d(2019, 9, 1); c.anniversaryManual = true
        #expect(Greetings.anniversary(of: c, in: [w]) == Self.d(2019, 9, 1))
        #expect(!Greetings.settleAnniversary(&c, in: [w]))
        c.anniversary = nil
        #expect(Greetings.anniversary(of: c, in: [w]) == nil, "убрали руками — свадьба не возвращает")
        #expect(Self.days([c], [w], from: Self.d(2026, 1, 1)).isEmpty)
    }

    @Test func settleWritesTheWeddingDayForTheCloud() {
        var c = Self.couple("c1", "Анна", "Иван")
        let w = Self.wedding("w", Self.d(2025, 6, 14), client: "c1")
        #expect(Greetings.settleAnniversary(&c, in: [w]) && c.anniversary == Self.d(2025, 6, 14) && !c.anniversaryManual)
        #expect(!Greetings.settleAnniversary(&c, in: [w]))
        #expect(Greetings.settleAnniversary(&c, in: []) && c.anniversary == nil, "свадьба ушла — годовщины нет")
    }

    @Test func anniversaryOnlyForCouplesAndOnlyAfterTheWedding() {
        let w = Self.wedding("w", Self.d(2026, 11, 7), client: "c1")
        // Свадьба впереди: первая годовщина — через год, не в день свадьбы.
        #expect(Self.days([Self.couple("c1", "Анна", "Иван")], [w], from: Self.d(2026, 10, 24)).isEmpty)
        let past = Self.wedding("w", Self.d(2025, 11, 7), client: "c1")
        var family = Self.couple("c1", "Анна", "Иван")
        family.kind = .family
        #expect(Self.days([family], [past], from: Self.d(2026, 10, 24)).isEmpty, "у семьи годовщины нет")
        #expect(Self.days([Self.couple("c1", "Анна", "Иван")], [past], from: Self.d(2026, 10, 24)).map(\.date) == [Self.d(2026, 11, 7)])
    }

    // MARK: тумблер сам

    @Test func greetTurnsOnWhenTheFirstDateIsWritten() {
        let blank = Self.person("c1", "Ольга", bd: nil, greet: false)
        var with = blank
        with.people[0].birthday = "11-02"
        #expect(Greetings.turnsGreetOn(before: blank, after: with))
        var changed = with
        changed.people[0].birthday = "11-03"
        #expect(!Greetings.turnsGreetOn(before: with, after: changed), "дата уже была — выключенный руками остаётся")
        var anniv = Self.couple("c2", "Анна", "Иван", greet: false)
        let before = anniv
        anniv.anniversary = Self.d(2020, 5, 5); anniv.anniversaryManual = true
        #expect(Greetings.turnsGreetOn(before: before, after: anniv))
    }
}
