import Foundation
import LightPlanCore

/// Плашка клиента в форме съёмки (шаг К3, справка `docs/clients_reference.md` § 4.5): «Это Анна и Иван? 3 съёмки».
///
/// Плашка считается из того, что сейчас вписано в форму, и ничего не пишет: клиенты появляются и меняются только при
/// «Сохранить» (`ClientBook.bind`). Отмена формы — никаких клиентов.
extension ClientBook {

    /// Что фотограф ответил плашке в этой форме. Живёт в форме, на диск не идёт.
    public enum Choice: Equatable, Sendable {
        /// «Да» на подсказку по имени: съёмка этого клиента.
        case pick(String)
        /// «Другой»: съёмка не того клиента — при сохранении (без совпавшего номера) заводится новый, подсказка по имени
        /// больше не показывается.
        case other
    }

    /// Плашка: какой клиент и почему.
    public struct Hint: Equatable, Sendable {
        public enum Way: Equatable, Sendable {
            /// Номер из формы уже есть у клиента — съёмка будет его, плашка только сообщает (§ 3.2).
            case phone
            /// Номера, узнающего клиента, нет, но съёмка уже его: записана за ним раньше или выбрана «Да».
            case bound
            /// Только подсказка по имени: привязка — по «Да» (§ 3.7, слово Алексея 23.10).
            case name
        }
        public var clientId: String
        public var way: Way
        public init(clientId: String, way: Way) { self.clientId = clientId; self.way = way }
    }

    /// Ответ плашке ложится в запись перед склейкой: «Да» — ключ выбранного клиента, «Другой» — без клиента (номер,
    /// совпавший с чужим клиентом, всё равно найдёт своего: номер главнее).
    public static func applying(_ choice: Choice?, to s: inout Session) {
        switch choice {
        case .pick(let id)?: s.clientId = id
        case .other?: s.clientId = nil
        case nil: break
        }
    }

    /// Плашка для записи, собранной из формы (`EventForm.session`) — до ответа плашке. Тот же порядок, что у склейки:
    /// номер вместе с именем или фамилией главнее, потом клиент, за которым запись уже числится, потом вопрос «Это …?» —
    /// когда совпали имя и фамилия, а номера нет или он другой, и «Другой» не нажат. Одно совпадение (только имя, только
    /// фамилия, только номер) плашки не даёт: будет новый клиент (слово Алексея 23.10). `nil` — плашки нет.
    public static func hint(for draft: Session, choice: Choice?, clients: [Client], sessions: [Session],
                            mine: Set<String>, country: TelCountry) -> Hint? {
        var s = draft
        applying(choice, to: &s)
        guard kind(for: s) != nil else { return nil }
        let cands = people(of: s, mine: mine, country: country)
        guard !cands.isEmpty else { return nil }

        let hits = linkedHits(cands, clients: clients, country: country).map { clients[$0].id }
        let current = s.clientId.flatMap { id in clients.contains { $0.id == id } ? id : nil }
        if !hits.isEmpty {
            // Как `bind`: запись остаётся за своим клиентом, если он узнан; иначе — первый узнанный.
            return Hint(clientId: current.flatMap { hits.contains($0) ? $0 : nil } ?? hits[0], way: .phone)
        }
        if let current { return Hint(clientId: current, way: .bound) }
        guard choice != .other else { return nil }
        return nameMatch(cands, clients: list(clients, sessions: sessions)).map { Hint(clientId: $0, way: .name) }
    }

    // MARK: - Два фактора из трёх (слово Алексея 23.10)

    /// Клиенты (номера в `clients`), которых запись узнаёт сразу: номер человека записи есть у клиента (живой или прежний)
    /// **и** совпало имя или фамилия — с кем-то из людей этого клиента или с именем у прежнего номера. Один номер без
    /// имени не узнаёт: с телефона мужа записалась жена — это новый клиент. В порядке названных номеров.
    static func linkedHits(_ cands: [ClientPerson], clients: [Client], country: TelCountry) -> [Int] {
        let byPhone = phoneOwners(clients, country: country)
        var out: [Int] = []
        for p in cands where TelFormat.isReal(p.phone, country: country) {
            let k = TelFormat.full(p.phone, country: country)
            for i in byPhone[k] ?? [] where !out.contains(i) && linked(p, to: clients[i], key: k, country: country) {
                out.append(i)
            }
        }
        return out
    }

    /// Номер `key` у клиента есть, и человек записи делит имя или фамилию с **тем, чей это номер** (ревью GPT к 8c67c5a):
    /// живой номер — с его хозяином, прежний — с именем в архиве; у прежнего номера без имени хозяин неизвестен — со всеми
    /// людьми клиента. Анна с телефона Марка их пару не узнаёт.
    static func linked(_ p: ClientPerson, to c: Client, key: String, country: TelCountry) -> Bool {
        var names = c.people.filter { TelFormat.full($0.phone, country: country) == key }.map(\.name)
        for t in c.telLog where TelFormat.full(t.phone, country: country) == key {
            if let n = t.name, !n.trimmingCharacters(in: .whitespaces).isEmpty { names.append(n) } else { names += c.people.map(\.name) }
        }
        return names.contains { nameFactors(p.name, $0) >= 1 }
    }

    /// Чьи номера: номер — все клиенты, у кого он есть (живой раньше прежнего, раньше заведённый раньше). Один номер может
    /// быть у двух клиентов: муж и жена с одного телефона.
    static func phoneOwners(_ clients: [Client], country: TelCountry) -> [String: [Int]] {
        var owner: [String: [Int]] = [:]
        func add(_ phone: String, _ i: Int) {
            guard TelFormat.isReal(phone, country: country) else { return }
            let k = TelFormat.full(phone, country: country)
            if !(owner[k] ?? []).contains(i) { owner[k, default: []].append(i) }
        }
        for (i, c) in clients.enumerated() { for p in c.people { add(p.phone, i) } }
        for (i, c) in clients.enumerated() { for t in c.telLog { add(t.phone, i) } }
        return owner
    }

    /// Клиент для вопроса «Это …?»: у кого-то из его людей те же имя и фамилия, что у человека записи; при нескольких —
    /// тот, что выше в списке (свежая съёмка).
    static func nameMatch(_ cands: [ClientPerson], clients ordered: [Client]) -> String? {
        ordered.first { c in cands.contains { cand in c.people.contains { nameFactors(cand.name, $0.name) >= 2 } } }?.id
    }

    /// Сколько совпало из «имя, фамилия»: 0, 1 или 2. Слова сравниваются без порядка («Петрова Анна» — «Анна Петрова»: 2),
    /// регистр и «ё» не различаются, слова короче двух букв (инициалы, «и») и отчество не считаются — общее слово
    /// считается один раз. Совпали два слова — это имя и фамилия.
    static func nameFactors(_ a: String, _ b: String) -> Int {
        let x = Set(nameWords(a)), y = Set(nameWords(b))
        return min(2, x.intersection(y).count)
    }

    /// Слова имени: без регистра, «ё» = «е», без инициалов. Отчество — не имя и не фамилия (ревью GPT к 8c67c5a: «Анна
    /// Сергеевна Петрова» и «Мария Сергеевна Петрова» — разные люди). Выпадает одно слово и по месту: в имени из трёх слов и
    /// больше — второе («Имя Отчество Фамилия»), а если оно не похоже на отчество (…вич, …вна, …чна) — последнее
    /// («Фамилия Имя Отчество»). Фамилия на «-вич» остаётся: «Роман Аркадьевич Абрамович» — роман, абрамович. В имени из
    /// двух слов не выпадает ничего: «Роман Абрамович» — с фамилией (цена: «Анна Сергеевна» — отчество считается словом).
    static func nameWords(_ s: String) -> [String] {
        var words = s.lowercased().replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: { !$0.isLetter && $0 != "-" }).map(String.init)
            .filter { $0.count >= 2 && $0 != "and" }
        guard words.count > 2 else { return words }
        func patronymic(_ w: String) -> Bool { w.count > 5 && ["вич", "вна", "чна"].contains { w.hasSuffix($0) } }
        if patronymic(words[1]) { words.remove(at: 1) } else if patronymic(words[words.count - 1]) { words.removeLast() }
        return words
    }
}
