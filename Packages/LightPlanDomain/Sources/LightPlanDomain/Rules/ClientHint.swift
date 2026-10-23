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
    /// номер главнее, потом клиент, за которым запись уже числится, потом подсказка по имени — только когда номера в форме
    /// нет совсем и «Другой» не нажат. `nil` — плашки нет (клиента запись не заводит или он будет новым).
    public static func hint(for draft: Session, choice: Choice?, clients: [Client], sessions: [Session],
                            mine: Set<String>, country: TelCountry) -> Hint? {
        var s = draft
        applying(choice, to: &s)
        guard kind(for: s) != nil else { return nil }
        let cands = people(of: s, mine: mine, country: country)
        guard !cands.isEmpty else { return nil }
        let real = cands.filter { TelFormat.isReal($0.phone, country: country) }

        let hits = phoneHits(real, clients: clients, country: country)
        let current = s.clientId.flatMap { id in clients.contains { $0.id == id } ? id : nil }
        if !hits.isEmpty {
            // Как `bind`: запись остаётся за своим клиентом, если номер его; иначе — первый, чей номер назван.
            return Hint(clientId: current.flatMap { hits.contains($0) ? $0 : nil } ?? hits[0], way: .phone)
        }
        if let current { return Hint(clientId: current, way: .bound) }
        guard choice != .other, real.isEmpty else { return nil }
        return nameMatch(cands, clients: list(clients, sessions: sessions)).map { Hint(clientId: $0, way: .name) }
    }

    /// Клиенты, чей живой или прежний номер назван, в порядке названных номеров (как `bind`).
    static func phoneHits(_ cands: [ClientPerson], clients: [Client], country: TelCountry) -> [String] {
        let owner = owners(clients, country: country)
        var out: [String] = []
        for p in cands {
            if let i = owner[TelFormat.full(p.phone, country: country)], !out.contains(clients[i].id) { out.append(clients[i].id) }
        }
        return out
    }

    /// Чей чей номер: живой главнее прежнего, раньше заведённый — главнее позднего.
    static func owners(_ clients: [Client], country: TelCountry) -> [String: Int] {
        var owner: [String: Int] = [:]
        for (i, c) in clients.enumerated() {
            for p in c.people where TelFormat.isReal(p.phone, country: country) {
                let k = TelFormat.full(p.phone, country: country)
                owner[k] = owner[k] ?? i
            }
        }
        for (i, c) in clients.enumerated() {
            for t in c.telLog where TelFormat.isReal(t.phone, country: country) {
                let k = TelFormat.full(t.phone, country: country)
                owner[k] = owner[k] ?? i
            }
        }
        return owner
    }

    /// Клиент, чьё имя совпало с названным: целиком — главнее, чем началом («Анна» — «Анна Петрова»); при равных — тот,
    /// что выше в списке (свежая съёмка). Имя короче двух букв не ищется.
    static func nameMatch(_ cands: [ClientPerson], clients ordered: [Client]) -> String? {
        var best: (id: String, score: Int)?
        for c in ordered {
            var score = 0
            for cand in cands { for p in c.people { score = max(score, nameScore(cand.name, p.name)) } }
            if score > (best?.score ?? 0) { best = (c.id, score) }
        }
        return best?.id
    }

    /// 2 — имя то же, 1 — одно начинается другим по словам, 0 — не то. Регистр и «ё» не различаются.
    static func nameScore(_ a: String, _ b: String) -> Int {
        let x = nameWords(a), y = nameWords(b)
        guard let first = x.first, first.count >= 2, !y.isEmpty else { return 0 }
        if x == y { return 2 }
        let n = min(x.count, y.count)
        return Array(x.prefix(n)) == Array(y.prefix(n)) ? 1 : 0
    }

    private static func nameWords(_ s: String) -> [String] {
        s.lowercased().replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
    }
}
