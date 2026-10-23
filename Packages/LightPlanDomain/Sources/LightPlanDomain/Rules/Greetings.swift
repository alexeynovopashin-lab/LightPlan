import Foundation
import LightPlanCore

/// День рождения человека (`bd`, справка `docs/clients_reference.md` § 2.1): число и месяц обязательны, год — нет, как в
/// Контактах iPhone. В снимке `ММ-ДД` или `ГГГГ-ММ-ДД`.
public struct Birthday: Sendable, Hashable {
    public var year: Int?
    public var month: Int
    public var day: Int

    /// Число проверяется по месяцу високосного года: 29 февраля без года — законный день рождения.
    public init?(year: Int? = nil, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1,
              day <= Greetings.daysIn(month: month, year: year ?? 2000) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Строка снимка; всё, что не `ММ-ДД` / `ГГГГ-ММ-ДД`, — `nil` (поле не теряется, но и не поздравляет).
    public init?(_ s: String?) {
        guard let parts = s?.split(separator: "-").map(String.init),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        switch parts.count {
        case 2: self.init(month: Int(parts[0])!, day: Int(parts[1])!)
        case 3 where parts[0].count == 4: self.init(year: Int(parts[0])!, month: Int(parts[1])!, day: Int(parts[2])!)
        default: return nil
        }
    }

    public var snapshotString: String {
        let md = String(format: "%02d-%02d", month, day)
        return year.map { String(format: "%04d-", $0) + md } ?? md
    }

    /// Сколько лет исполнилось к дню `d`; года нет — `nil`.
    public func age(on d: CivilDate) -> Int? {
        guard let year else { return nil }
        return d.year - year - ((d.month, d.day) < (month, day) ? 1 : 0)
    }
}

/// «Поздравлять» (шаг К6, справка § 6): дни рождения людей клиента и годовщина пары. Одно уведомление на день в 10:00
/// по часам телефона — со всеми праздниками этого дня; не больше 40 ближайших дней.
public enum Greetings {

    /// Мест под поздравления из 64 ожидающих уведомлений iOS (§ 6, таблица потолка).
    public static let cap = 40
    /// Час поздравления по часам телефона, минуты от полуночи.
    public static let minute = 10 * 60

    public enum Kind: Int, Sendable, Hashable, Comparable {
        case anniversary, birthday
        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    /// Один праздник: кто и что.
    public struct Occasion: Sendable, Hashable {
        public let kind: Kind
        public let clientId: String
        /// Имя человека (день рождения) или пары «Анна и Иван» (годовщина).
        public let name: String
        /// Исполняется лет (день рождения с годом) или лет со свадьбы; `nil` — год неизвестен.
        public let years: Int?

        public init(kind: Kind, clientId: String, name: String, years: Int?) {
            self.kind = kind; self.clientId = clientId; self.name = name; self.years = years
        }
    }

    /// День с праздниками — одно уведомление.
    public struct Day: Sendable, Hashable {
        public let date: CivilDate
        /// Годовщины раньше дней рождения, внутри — по имени.
        public let occasions: [Occasion]
        /// Все праздники дня у одного клиента — нажатие открывает его карточку; у разных — список «Клиенты».
        public var clientId: String? {
            let ids = Set(occasions.map(\.clientId))
            return ids.count == 1 ? ids.first : nil
        }
    }

    // MARK: - Календарь

    static func leap(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

    static func daysIn(month m: Int, year y: Int) -> Int {
        switch m {
        case 2: leap(y) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// День праздника в году `y`: 29 февраля в невисокосный год — 28 февраля.
    public static func observed(month: Int, day: Int, in y: Int) -> CivilDate {
        CivilDate(year: y, month: month, day: min(day, daysIn(month: month, year: y)))
    }

    /// Первый день, на который ещё можно поставить поздравление: сегодня, пока не пробило 10:00, иначе завтра.
    public static func firstDay(today: CivilDate, minute now: Int) -> CivilDate {
        now < minute ? today : today.adding(days: 1)
    }

    // MARK: - Годовщина

    /// День самой ранней свадьбы клиента (§ 2.4); свадьба на два дня — первый день. Съёмки в корзине не считаются.
    public static func weddingDay(of clientId: String, in sessions: [Session]) -> CivilDate? {
        sessions.filter { $0.clientId == clientId && $0.genre == .wedding }.map(\.day).min()
    }

    /// Годовщина, которой живёт карточка: правленая руками — как вписана (и пустая, если её убрали), иначе — из свадьбы.
    public static func anniversary(of c: Client, in sessions: [Session]) -> CivilDate? {
        c.anniversaryManual ? c.anniversary : weddingDay(of: c.id, in: sessions)
    }

    /// Записать годовщину из свадьбы в снимок (для облака, § 2.4): правленую руками не трогает. `true` — изменилась.
    @discardableResult
    public static func settleAnniversary(_ c: inout Client, in sessions: [Session]) -> Bool {
        guard !c.anniversaryManual else { return false }
        let a = weddingDay(of: c.id, in: sessions)
        guard a != c.anniversary else { return false }
        c.anniversary = a
        return true
    }

    // MARK: - Праздники

    /// Праздники клиентов с «Поздравлять» на `days` дней начиная с `start`, по дням, ближайшие первыми, не больше `cap`
    /// дней. Годовщина — только у пары и только после свадьбы; день рождения с годом — не раньше рождения.
    /// - Parameter and: союз между именами пары («и»).
    public static func days(clients: [Client], sessions: [Session], from start: CivilDate, days: Int = 365,
                            cap: Int = cap, and: String) -> [Day] {
        let end = start.adding(days: days)
        var byDate: [CivilDate: [Occasion]] = [:]
        func add(_ d: CivilDate, _ o: Occasion) {
            guard d >= start, d < end else { return }
            byDate[d, default: []].append(o)
        }
        for c in clients where c.greet {
            let title = ClientBook.title(of: c, and: and)
            for p in c.people {
                guard let b = Birthday(p.birthday) else { continue }
                let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
                for y in start.year...end.year {
                    if let by = b.year, y < by { continue }
                    let d = observed(month: b.month, day: b.day, in: y)
                    add(d, Occasion(kind: .birthday, clientId: c.id, name: name.isEmpty ? title : name,
                                    years: b.year.map { y - $0 }))
                }
            }
            if c.kind == .couple, let a = anniversary(of: c, in: sessions) {
                for y in start.year...end.year where y > a.year {
                    add(observed(month: a.month, day: a.day, in: y),
                        Occasion(kind: .anniversary, clientId: c.id, name: title, years: y - a.year))
                }
            }
        }
        return byDate.keys.sorted().prefix(cap).map { d in
            Day(date: d, occasions: byDate[d]!.sorted { ($0.kind, $0.name, $0.clientId) < ($1.kind, $1.name, $1.clientId) })
        }
    }

    /// Поздравлять само включается, когда в карточке впервые вписана дата (решение Алексея 23.10, № 4): было без дат —
    /// стало с датой. Выключенный руками тумблер при правке уже вписанной даты не включается.
    public static func turnsGreetOn(before: Client, after: Client) -> Bool {
        !hasDate(before) && hasDate(after)
    }

    /// Вписана ли руками хоть одна дата: день рождения кого-то из людей или годовщина, правленая руками.
    public static func hasDate(_ c: Client) -> Bool {
        c.people.contains { Birthday($0.birthday) != nil } || (c.anniversaryManual && c.anniversary != nil)
    }
}
