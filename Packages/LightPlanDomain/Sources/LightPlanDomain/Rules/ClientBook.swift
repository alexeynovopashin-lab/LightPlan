import Foundation
import LightPlanCore

/// Частные клиенты: склейка по номеру, вид по жанру, список (шаг К1 «Клиенты», справка `docs/clients_reference.md`
/// §§ 2–3). Клиент хранит только своё; съёмки, даты и гонорары считаются из записей с `clientId` (как `OrgBook.shoots`).
public enum ClientBook {

    // MARK: - Ключ клиента

    /// `"c" + base36(время) + 4 знака` (как `newOrgId` у организаций): вечный.
    public static func newId(at ms: Int64, random: () -> Int = { Int.random(in: 0..<1_679_616) }) -> String {
        let tail = String(random() % 1_679_616, radix: 36)
        return "c" + String(max(0, ms), radix: 36) + String(repeating: "0", count: max(0, 4 - tail.count)) + tail
    }

    // MARK: - Вид по жанру (§ 2.3)

    /// Вид клиента, которого заводит эта запись; `nil` — запись клиента не заводит.
    ///
    /// Не заводят: не съёмка (встреча, чужое событие); жанр без заказчика (пейзаж, стрит); заказчик — организация
    /// (это «Компании»), кроме свадьбы через агентство, где люди пары вписаны поимённо.
    public static func kind(for s: Session) -> ClientKind? {
        guard s.kind == .shoot, GenreProfile(s.genre).spec.client else { return nil }
        if s.orgId != nil {
            // Свадьба через агентство: заказчик — компания, а пара вписана поимённо — она и клиент. Остальным жанрам
            // организация-заказчик клиента не оставляет, кто бы ни был вписан.
            guard s.genre == .wedding, s.persons.contains(where: { !blank($0.name) || !blank($0.phone) }) else { return nil }
        }
        switch s.genre {
        case .wedding, .lovestory: return .couple
        case .family: return .family
        default: return .person
        }
    }

    // MARK: - Люди записи

    /// Кого называет запись: люди пары поимённо, а у остальных жанров — клиент строкой. Свой номер клиентом не становится
    /// (§ 3.6): человек с ним выпадает целиком.
    public static func people(of s: Session, mine: Set<String>, country: TelCountry) -> [ClientPerson] {
        var out: [ClientPerson] = s.persons.map { ClientPerson(name: trimmed($0.name), phone: trimmed($0.phone)) }
            .filter { !$0.isBlank }
        let own = trimmed(s.clientPhone)
        if out.isEmpty {
            let p = ClientPerson(name: trimmed(s.contact), phone: own)
            if !p.isBlank { out = [p] }
        } else if TelFormat.isReal(own, country: country),
                  !out.contains(where: { TelFormat.full($0.phone, country: country) == TelFormat.full(own, country: country) }) {
            // Номер клиента сверх людей пары: общий номер достаётся первому названному без своего телефона, а если у
            // всех свой — это ещё один человек без имени.
            if let i = out.firstIndex(where: { blank($0.phone) }) { out[i].phone = own }
            else { out.append(ClientPerson(name: "", phone: own)) }
        }
        return out.filter { p in
            let k = TelFormat.full(p.phone, country: country)
            return k.isEmpty || !mine.contains(k)
        }
    }

    // MARK: - Склейка (§ 3)

    /// Чем кончилась склейка одной записи.
    public struct Outcome: Equatable, Sendable {
        /// Клиент записи; `nil` — запись клиента не имеет (нет имени и номера, жанр без заказчика, заказчик — организация).
        public var clientId: String?
        /// Клиент заведён этой записью.
        public var created: Bool
        /// Другие клиенты, чей номер назван в записи: сами не склеиваем, карточка спросит «объединить?» (§ 3.4).
        public var alsoIn: [String]
        public init(clientId: String?, created: Bool, alsoIn: [String]) {
            self.clientId = clientId; self.created = created; self.alsoIn = alsoIn
        }
    }

    /// Сколько людей берёт карточка вида: у пары двое, у персоны — она и тот, кто с ней заказал (свадьба с женихом, пока
    /// вид не поменяли руками), у семьи сколько угодно.
    static func capacity(_ kind: ClientKind) -> Int { kind == .family ? Int.max : 2 }

    /// Склейка записи с клиентами при «Сохранить» (§ 3, правила 1–7). Меняет запись (`clientId`) и список клиентов.
    ///
    /// - Тот же номер (живой или прежний из `telLog`) — тот же клиент; пустые поля клиента дозаполняются из записи,
    ///   заполненные не перезаписываются.
    /// - Нет совпадения — новый клиент (вид по жанру); без номера он ни с кем не склеивается, только по подсказке (7).
    /// - Два номера одной пары: найден по любому; номер, что у другого клиента, сами не переносим (4).
    /// - Номер связанной записи сменили и он никому не принадлежит — человек клиента получает новый, старый уходит в
    ///   `telLog` и продолжает узнаваться (5). Прошлые записи свои номера не переписывают.
    @discardableResult
    public static func bind(_ s: inout Session, among clients: inout [Client], mine: Set<String>, country: TelCountry,
                            nowMs: Int64, retiredAt: String, newId: () -> String) -> Outcome {
        guard let kind = kind(for: s) else {
            s.clientId = nil
            return Outcome(clientId: nil, created: false, alsoIn: [])
        }
        let cands = people(of: s, mine: mine, country: country)
        guard !cands.isEmpty else {
            s.clientId = nil
            return Outcome(clientId: nil, created: false, alsoIn: [])
        }
        func key(_ p: ClientPerson) -> String { TelFormat.full(p.phone, country: country) }
        func real(_ p: ClientPerson) -> Bool { TelFormat.isReal(p.phone, country: country) }

        // Чей чей номер: живой главнее прежнего.
        var owner: [String: Int] = [:]
        for (i, c) in clients.enumerated() {
            for p in c.people where TelFormat.isReal(p.phone, country: country) { owner[key(p)] = owner[key(p)] ?? i }
        }
        for (i, c) in clients.enumerated() {
            for t in c.telLog where TelFormat.isReal(t.phone, country: country) {
                let k = TelFormat.full(t.phone, country: country)
                owner[k] = owner[k] ?? i
            }
        }
        var hits: [Int] = []
        for p in cands where real(p) {
            if let i = owner[key(p)], !hits.contains(i) { hits.append(i) }
        }
        let current = s.clientId.flatMap { id in clients.firstIndex { $0.id == id } }

        let target: Int
        if let current, hits.contains(current) || hits.isEmpty {
            target = current
        } else if let first = hits.first {
            target = first
        } else {
            var id = newId()
            for _ in 0..<8 where clients.contains(where: { $0.id == id }) { id = newId() }
            var c = Client(id: id, kind: kind)
            c.people = cands            // вместимость ограничивает дописывание, а не заведение: номер записи не теряется
            c.modifiedAt = nowMs
            clients.append(c)
            s.clientId = c.id
            return Outcome(clientId: c.id, created: true, alsoIn: [])
        }

        // Дозаполнение и смена номера у найденного клиента.
        var c = clients[target]
        let before = PhoneBook.tels(of: c, country: country)
        let wasBound = s.clientId == c.id
        func covered(_ p: ClientPerson) -> Bool { cands.contains { real($0) && key($0) == key(p) } }
        for cand in cands {
            if real(cand) {
                let k = key(cand)
                if let j = c.people.firstIndex(where: { key($0) == k }) {
                    if blank(c.people[j].name) && !blank(cand.name) { c.people[j].name = cand.name }
                } else if let o = owner[k], o != target {
                    continue                                       // номер другого клиента: не переносим (4)
                } else if wasBound, let j = replaceable(in: c, for: cand, covered: covered, country: country) {
                    c.people[j].phone = cand.phone                 // номер сменился (5)
                    if blank(c.people[j].name) { c.people[j].name = cand.name }
                } else if owner[k] == target {
                    continue                                       // прежний номер из `telLog`: узнан, но заново не вписывается
                } else if c.people.count < capacity(c.kind) {
                    c.people.append(cand)
                }
            } else if !blank(cand.name), c.people.isEmpty {
                // Имя без номера нового человека не заводит: найти клиента по нему нельзя (7).
                c.people.append(cand)
            }
        }
        let after = PhoneBook.tels(of: c, country: country)
        c.telLog = PhoneBook.retire(before: before, after: after, log: c.telLog, at: retiredAt, country: country)
        if c != clients[target] {
            c.modifiedAt = nowMs
            clients[target] = c
        }
        s.clientId = c.id
        let also = hits.filter { $0 != target }.map { clients[$0].id }
        return Outcome(clientId: c.id, created: false, alsoIn: also)
    }

    /// Кому достаётся новый номер связанной записи: человеку, чей номер запись больше не называет, — тому же имени,
    /// а без имён тому, кто на том же месте в записи.
    private static func replaceable(in c: Client, for cand: ClientPerson, covered: (ClientPerson) -> Bool,
                                    country: TelCountry) -> Int? {
        let free = c.people.indices.filter { !covered(c.people[$0]) && TelFormat.isReal(c.people[$0].phone, country: country) }
        if free.isEmpty { return nil }
        let first = PhoneBook.firstName(cand.name).lowercased()
        if !first.isEmpty, let j = free.first(where: { PhoneBook.firstName(c.people[$0].name).lowercased() == first }) { return j }
        if blank(cand.name) || free.allSatisfy({ blank(c.people[$0].name) }) { return free.count == 1 ? free[0] : nil }
        return nil
    }

    // MARK: - Разовый проход (§ 3.8)

    /// Первый запуск сборки с клиентами: те же правила по всем записям, у которых клиента ещё нет (или он пропал), от старых к новым.
    /// Это та же склейка, что при сохранении, — не перенос старого формата. Возвращает, сколько записей получили клиента.
    @discardableResult
    public static func assemble(sessions: inout [Session], clients: inout [Client], mine: Set<String>, country: TelCountry,
                                nowMs: Int64, retiredAt: String, newId: () -> String) -> Int {
        // Без клиента — и с ключом, чьего клиента в данных нет (веб пересохранил файл без раздела `clients`).
        let known = Set(clients.map(\.id))
        let order = sessions.indices.filter { sessions[$0].clientId.map { !known.contains($0) } ?? true }.sorted { a, b in
            let x = sessions[a], y = sessions[b]
            return x.day != y.day ? x.day < y.day : x.start != y.start ? x.start < y.start : a < b
        }
        var n = 0
        for i in order {
            if bind(&sessions[i], among: &clients, mine: mine, country: country, nowMs: nowMs, retiredAt: retiredAt,
                    newId: newId).clientId != nil { n += 1 }
        }
        return n
    }

    // MARK: - Съёмки, суммы, список

    /// Записи клиента, от новых к старым (как `OrgBook.shoots`).
    public static func shoots(of clientId: String, in sessions: [Session]) -> [Session] {
        sessions.filter { $0.clientId == clientId }.sorted { a, b in
            a.day != b.day ? a.day > b.day : a.start > b.start
        }
    }

    /// Итог строки списка: сколько записей и сколько по валютам — тем же счётом, что у организации.
    public static func line(of clientId: String, in sessions: [Session], home: Currency) -> OrgBook.Line {
        let list = sessions.filter { $0.clientId == clientId }
        return OrgBook.Line(shootCount: list.count,
                            sums: Money.sumByCurrency(list, home: home) { Money.income(of: $0, among: sessions) })
    }

    /// Фильтр «Все · Пары · Семьи · Персоны».
    public enum Filter: String, CaseIterable, Sendable {
        case all, couples, families, persons

        public func matches(_ c: Client) -> Bool {
            switch self {
            case .all: true
            case .couples: c.kind == .couple
            case .families: c.kind == .family
            case .persons: c.kind == .person
            }
        }
    }

    /// Список «Частные»: порядок по последней съёмке, свежие сверху; у клиента без съёмок — по правке. Одинаковые
    /// остаются в порядке заведения.
    public static func list(_ clients: [Client], sessions: [Session], filter: Filter = .all) -> [Client] {
        var last: [String: (day: CivilDate, start: Int)] = [:]
        for s in sessions {
            guard let id = s.clientId else { continue }
            if let l = last[id], (l.day, l.start) >= (s.day, s.start) { continue }
            last[id] = (s.day, s.start)
        }
        return clients.enumerated().filter { filter.matches($0.element) }.sorted { a, b in
            switch (last[a.element.id], last[b.element.id]) {
            case let (x?, y?): return x.day != y.day ? x.day > y.day : x.start != y.start ? x.start > y.start : a.offset < b.offset
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                let x = a.element.modifiedAt ?? 0, y = b.element.modifiedAt ?? 0
                return x != y ? x > y : a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Имя в строке списка: у пары — имена без фамилий через союз («Анна и Иван»), у остальных — как вписано. Имён нет —
    /// первый номер; нет и его — пусто (экран подставит «Без имени»).
    public static func title(of c: Client, and: String) -> String {
        let named = c.people.filter { !blank($0.name) }
        if c.kind == .couple, named.count > 1 {
            return named.map { PhoneBook.firstName($0.name) }.joined(separator: and)
        }
        if !named.isEmpty { return named.map { trimmed($0.name) }.joined(separator: ", ") }
        return c.people.map { trimmed($0.phone) }.first { !$0.isEmpty } ?? ""
    }

    // MARK: - Мелочи

    private static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func blank(_ s: String) -> Bool { trimmed(s).isEmpty }
}
