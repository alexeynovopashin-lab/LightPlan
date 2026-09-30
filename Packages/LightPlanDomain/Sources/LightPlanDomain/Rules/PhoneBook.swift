import Foundation
import LightPlanCore

/// «Контакты»: все номера из съёмок и организаций одним списком, считается на лету, не хранится
/// (веб `phoneIndex`, `shootTels`, `orgTels`, `telRetire`; итерация 28, шаг 7; справка
/// `docs/org_reference.md` § 2). Ключ номера — международные цифры (`TelFormat.full`): «8 916…» и
/// «+7 916…» — один номер.
public enum PhoneBook {

    // MARK: - Поля-роли (`f` в `telLog`)

    public enum Field {
        public static let client = "client"
        public static let personOne = "p1"
        public static let personTwo = "p2"
        /// Контактное лицо заказчика.
        public static let contact = "person"
        public static let org = "org"
    }

    /// Прежних номеров у одной карточки не больше (веб `TEL_LOG_MAX`).
    public static let logMax = 12

    /// Номер в карточке: чей (`field`), как записан, имя при нём.
    public struct Tel: Sendable, Hashable {
        public var field: String
        public var phone: String
        public var name: String
        public init(field: String, phone: String, name: String = "") {
            self.field = field
            self.phone = phone
            self.name = name
        }
    }

    /// Номера записи (веб `shootTels`): клиент, люди пары, контактное лицо; обрывки короче пяти цифр не берём.
    public static func tels(of s: Session, country: TelCountry) -> [Tel] {
        var out: [Tel] = []
        if !s.clientPhone.isEmpty { out.append(Tel(field: Field.client, phone: s.clientPhone, name: s.contact)) }
        for (i, p) in s.persons.enumerated() where !p.phone.isEmpty {
            out.append(Tel(field: "p\(i + 1)", phone: p.phone, name: p.name))
        }
        if !s.orderPhone.isEmpty { out.append(Tel(field: Field.contact, phone: s.orderPhone, name: s.orderPerson)) }
        return out.filter { TelFormat.isReal($0.phone, country: country) }
    }

    /// Номер организации (веб `orgTels`).
    public static func tels(of o: Org, country: TelCountry) -> [Tel] {
        TelFormat.isReal(o.phone, country: country) ? [Tel(field: Field.org, phone: o.phone, name: o.person)] : []
    }

    // MARK: - Ушедший номер (веб `telRetire`)

    /// Сверка карточки до правки и после: номер, которого больше нет **нигде в карточке**, ложится в
    /// архив с именем и временем ухода. Переезд номера между полями одной карточки — не уход; тот,
    /// что в архиве уже есть, второй раз не пишется; архив не длиннее `logMax` (старые срезаются).
    public static func retire(before: [Tel], after: [Tel], log: [TelLogEntry], at now: String,
                              country: TelCountry) -> [TelLogEntry] {
        var out = log
        let live = Set(after.map { TelFormat.full($0.phone, country: country) })
        for t in before {
            let k = TelFormat.full(t.phone, country: country)
            if live.contains(k) { continue }
            if out.contains(where: { TelFormat.full($0.phone, country: country) == k }) { continue }
            out.append(TelLogEntry(field: t.field, phone: t.phone, name: t.name, retiredAt: now))
        }
        return Array(out.suffix(logMax))
    }

    // MARK: - Список

    /// Где номер встречается: запись или организация.
    public enum Card: Sendable, Hashable {
        case shoot(String)
        case org(String)
    }

    /// Строка «где встречается».
    public struct Row: Sendable, Hashable {
        public var card: Card
        public var field: String
        /// Имя при номере, как записано (фамилию срезает показ).
        public var name: String
        /// Прежний номер карточки.
        public var past: Bool
    }

    /// Номер списка: все встречи одного ключа.
    public struct Group: Sendable, Hashable {
        public var key: String
        /// Как показать: самая полная запись среди живых.
        public var phone: String
        /// Свежесть: запись — её день, ушедший номер — время ухода; у организации без даты `nil`.
        public var at: String?
        public var rows: [Row]
        /// Число разных карточек, где встретился номер.
        public var cards: Int
        /// Есть хоть одна не-«прежняя» строка.
        public var live: Bool
        /// Свой номер (или прежний свой).
        public var mine: Bool
        /// Связка: номер в двух и более карточках. Разные роли одной записи связкой не считаются.
        public var isLink: Bool { cards > 1 }
    }

    /// Ключи своих номеров: сегодняшний и прежние — старая симка в чужой карточке остаётся «моей».
    public static func mineKeys(_ ids: [String], country: TelCountry) -> Set<String> {
        Set(ids.map { TelFormat.full($0, country: country) }.filter { !$0.isEmpty })
    }

    private static func dayKey(_ d: CivilDate) -> String {
        String(format: "%04d-%02d-%02d", d.year, d.month, d.day)
    }

    /// Роль при номере: чем больше, тем точнее. У записи «Настя» — и заказчик, и невеста: показываем невесту.
    private static func weight(_ field: String) -> Int {
        switch field {
        case Field.personOne, Field.personTwo: 3
        case Field.contact, Field.org: 2
        default: 1
        }
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        let x = a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let y = b.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return x.isEmpty || y.isEmpty || x == y
    }

    /// Строки одного номера внутри одной карточки, сведённые до людей. Ошибка веба 26: клиент и невеста с
    /// одним номером и одним именем занимали две строки — один человек, одна строка, роль точнее. Разные
    /// имена — разные люди, обе остаются. Прежняя строка карточки, у которой номер сейчас жив, шум — не пишем.
    static func collapse(_ rows: [Row]) -> [Row] {
        var kept: [Row] = []
        for r in rows {
            if r.past { continue }
            if let i = kept.firstIndex(where: { $0.card == r.card && !$0.past && same($0.name, r.name) }) {
                if weight(r.field) > weight(kept[i].field) {
                    var n = r
                    if n.name.isEmpty { n.name = kept[i].name }
                    kept[i] = n
                } else if kept[i].name.isEmpty {
                    kept[i].name = r.name
                }
            } else {
                kept.append(r)
            }
        }
        let liveCards = Set(kept.map(\.card))
        for r in rows where r.past {
            // Ушедший номер той же карточки, где он снова жив, — не история, а повтор.
            if liveCards.contains(r.card) { continue }
            if !kept.contains(where: { $0.card == r.card && $0.past && same($0.name, r.name) }) { kept.append(r) }
        }
        return kept
    }

    /// Список номеров: сначала связки, потом свежие вперёд. Свой номер сверяется, но в список идёт наравне.
    public static func index(sessions: [Session], orgs: [Org], mine: Set<String> = [], country: TelCountry) -> [Group] {
        struct Acc { var key: String; var phone: String; var at: String?; var rows: [Row] }
        var map: [String: Acc] = [:]
        var order: [String] = []

        func put(_ phone: String, _ row: Row, at: String?) {
            let k = TelFormat.full(phone, country: country)
            if k.isEmpty { return }
            if map[k] == nil { map[k] = Acc(key: k, phone: phone, at: at, rows: []); order.append(k) }
            map[k]!.rows.append(row)
            let cur = map[k]!
            // Самая полная из живых записей: где-то номер с кодом страны, а где-то без — звонят по первому.
            if !row.past, TelFormat.digits(phone).count > TelFormat.digits(cur.phone).count { map[k]!.phone = phone }
            if let at, cur.at == nil || at > cur.at! { map[k]!.at = at }
        }

        for s in sessions {
            let when = dayKey(s.day)
            for t in tels(of: s, country: country) {
                put(t.phone, Row(card: .shoot(s.id), field: t.field, name: t.name, past: false), at: when)
            }
            for t in s.telLog where TelFormat.isReal(t.phone, country: country) {
                put(t.phone, Row(card: .shoot(s.id), field: t.field ?? Field.contact, name: t.name ?? "", past: true),
                    at: t.retiredAt)
            }
        }
        for o in orgs {
            for t in tels(of: o, country: country) {
                put(t.phone, Row(card: .org(o.id), field: t.field, name: t.name, past: false), at: nil)
            }
            for t in o.telLog where TelFormat.isReal(t.phone, country: country) {
                put(t.phone, Row(card: .org(o.id), field: t.field ?? Field.org, name: t.name ?? "", past: true),
                    at: t.retiredAt)
            }
        }

        let groups: [Group] = order.map { k in
            let a = map[k]!
            let cards = Set(a.rows.map(\.card)).count
            return Group(key: k, phone: a.phone, at: a.at, rows: collapse(a.rows), cards: cards,
                         live: a.rows.contains { !$0.past }, mine: mine.contains(k))
        }
        // Устойчиво: у равных по свежести остаётся порядок появления.
        return groups.enumerated().sorted { x, y in
            if x.element.isLink != y.element.isLink { return x.element.isLink }
            let a = x.element.at ?? "", b = y.element.at ?? ""
            return a != b ? a > b : x.offset < y.offset
        }.map(\.element)
    }

    /// Сколько в списке связок (подпись в шапке).
    public static func linkCount(_ groups: [Group]) -> Int { groups.filter(\.isLink).count }

    /// Имя без фамилии: в строке нужны Алексей и Елена, а не паспорт.
    public static func firstName(_ n: String) -> String {
        n.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    }
}
