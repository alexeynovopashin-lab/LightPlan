import Foundation
import LightPlanCore

/// Карточка клиента (шаг К2 «Клиенты», справка `docs/clients_reference.md` § 4.4): люди, пустота, «Объединить», «Удалить»,
/// подсказка «этот номер есть у другого клиента». Съёмки и суммы карточки — `ClientBook.shoots` / `line`: считаются, не хранятся.
extension ClientBook {

    // MARK: - Пустой клиент

    /// В клиенте нет ничего, что человек вписал: люди пусты, своих ссылок и годовщины нет. Вид не считается — его ставят
    /// и у пустой карточки.
    public static func isBlank(_ c: Client) -> Bool {
        c.people.allSatisfy(\.isBlank) && c.links.isEmpty && c.anniversary == nil
    }

    /// Клиента держат, если в нём что-то есть или за ним числятся съёмки — живые или в корзине (вернувшаяся из корзины
    /// съёмка не должна указывать в пустоту).
    public static func keeps(_ c: Client, in sessions: [Session], trashed: [TrashedItem] = []) -> Bool {
        !isBlank(c) || sessions.contains { $0.clientId == c.id } || trashed.contains { $0.record.clientId == c.id }
    }

    /// Пустые строки людей при закрытии карточки не остаются; «кому пишем» сдвигается вместе с человеком.
    public static func pruneBlankPeople(_ c: inout Client) {
        let keep = c.people.indices.filter { !c.people[$0].isBlank }
        guard keep.count != c.people.count else { return }
        let mainPerson = keep.firstIndex(of: c.main) ?? 0
        c.people = keep.map { c.people[$0] }
        c.main = mainPerson
    }

    // MARK: - Люди

    /// Сколько людей показывает и даёт дописать карточка вида: у пары двое, у персоны один, у семьи сколько угодно.
    /// Лишних (персона, у которой из свадьбы остался жених) карточка не прячет — она только не даёт дописать.
    public static func canAddPerson(_ c: Client) -> Bool {
        switch c.kind {
        case .family: true
        case .couple: c.people.count < 2
        case .person: c.people.isEmpty
        }
    }

    /// «+ человек»: новая пустая строка.
    public static func addPerson(to c: inout Client) { c.people.append(ClientPerson()) }

    /// Убрать человека; «кому пишем» остаётся на том же человеке (или первом, если убрали его самого).
    public static func removePerson(at i: Int, from c: inout Client) {
        guard c.people.indices.contains(i) else { return }
        c.people.remove(at: i)
        if c.main == i { c.main = 0 } else if c.main > i { c.main -= 1 }
        if c.main >= c.people.count { c.main = 0 }
    }

    // MARK: - Ссылки клиента

    /// Своя ссылка клиента (галерея, отзыв, страница). Пустая или та же, что уже есть, — ничего.
    @discardableResult
    public static func addLink(_ raw: String, title: String? = nil, date: CivilDate? = nil, to c: inout Client) -> Bool {
        guard let d = Attachment.link(raw, kind: nil, title: title, date: date) else { return false }
        if c.links.contains(where: { $0.url == d.url }) { return false }
        c.links.append(d)
        return true
    }

    public static func removeLink(id: String, from c: inout Client) {
        c.links.removeAll { $0.id == id }
    }

    /// Ссылки съёмок клиента (справка § 4.4 «ссылки съёмок»): живут в съёмках, в клиента не копируются; от новых к старым.
    public static func shootLinks(of clientId: String, in sessions: [Session]) -> [(doc: Attachment, sessionId: String, day: CivilDate)] {
        shoots(of: clientId, in: sessions).flatMap { s in
            s.docs.filter { $0.source == .link }.map { (doc: $0, sessionId: s.id, day: s.day) }
        }
    }

    // MARK: - «Этот номер есть у другого клиента» (§ 3.4)

    /// Подсказка карточки: номер, названный в карточке или в её съёмках, принадлежит другому клиенту.
    public struct Twin: Equatable, Sendable {
        /// Другой клиент.
        public var clientId: String
        /// Чей номер — как вписан в карточке или съёмке; имени нет — пусто.
        public var name: String
        public var phone: String
        public init(clientId: String, name: String, phone: String) {
            self.clientId = clientId; self.name = name; self.phone = phone
        }
    }

    /// Другие клиенты, чей живой или прежний номер назван в этой карточке или в её съёмках — кандидаты «объединить?».
    /// Сами не склеиваем (§ 3.4): решает фотограф. Свой номер не в счёт. По одному на клиента, в порядке, как номера
    /// встретились (сперва люди карточки, потом съёмки от новых к старым).
    public static func twins(of clientId: String, clients: [Client], sessions: [Session], mine: Set<String>,
                             country: TelCountry) -> [Twin] {
        guard let me = clients.first(where: { $0.id == clientId }) else { return [] }
        // Другой клиент — тот, кого номер узнал бы при склейке: номер и имя или фамилия (два фактора из трёх, К3б). Один
        // общий номер — не повод объединять: муж и жена с одного телефона — разные клиенты.
        let others = clients.filter { $0.id != clientId }
        var named: [ClientPerson] = me.people
        for s in shoots(of: clientId, in: sessions) { named += people(of: s, mine: mine, country: country) }
        var out: [Twin] = []
        for p in named where TelFormat.isReal(p.phone, country: country) {
            let k = TelFormat.full(p.phone, country: country)
            guard !mine.contains(k) else { continue }
            for i in linkedHits([p], clients: others, country: country) where !out.contains(where: { $0.clientId == others[i].id }) {
                out.append(Twin(clientId: others[i].id, name: p.name.trimmingCharacters(in: .whitespacesAndNewlines), phone: p.phone))
            }
        }
        return out
    }

    // MARK: - Объединить (§ 4.4)

    /// «Объединить»: клиент `source` вливается в `target` — карточка, где нажали, остаётся, второй исчезает.
    ///
    /// Правило (вывод исполнителя К2, DECISIONS «Клиенты, шаг К2»):
    /// - **Съёмки** `source` — живые и в корзине — получают `clientId` цели и свежую отметку правки. Их имена и номера
    ///   не меняются: это история.
    /// - **Люди.** Тот же номер (`TelFormat.full`) — один человек: пустые поля цели (имя, день рождения, мессенджеры,
    ///   основной мессенджер) дозаполняются, заполненные не перезаписываются. Без номера — то же по совпадению имени.
    ///   Остальные люди дописываются в конец; вместимость вида не режет (объединяют руками — терять номер нельзя).
    /// - **Вид**, «кому пишем» и годовщина, правленная руками, — цели; чего у цели нет, берётся у `source`.
    /// - **«Поздравлять»** — если стоит хоть у одного: выключенное по умолчанию не отличить от выключенного руками, а
    ///   тумблер включается сам, как только вписана дата (решение Алексея 23.10, справка § 8, вопрос 4).
    /// - **Ссылки** — все, без повторов по адресу. **Прежние номера** (`telLog`) — оба архива, без повторов и без
    ///   номеров, что снова живые; не длиннее `PhoneBook.logMax`.
    /// - Отметка правки цели свежая; `source` убирается из списка (могилу кладёт вызывающий — она в снимке).
    ///
    /// `false` — объединять нечего: тот же клиент или кого-то из двух нет.
    @discardableResult
    public static func merge(_ sourceId: String, into targetId: String, clients: inout [Client], sessions: inout [Session],
                             trashed: inout [TrashedItem], country: TelCountry, nowMs: Int64) -> Bool {
        guard sourceId != targetId,
              let si = clients.firstIndex(where: { $0.id == sourceId }),
              let ti = clients.firstIndex(where: { $0.id == targetId }) else { return false }
        let src = clients[si]
        var dst = clients[ti]
        func key(_ p: ClientPerson) -> String { TelFormat.full(p.phone, country: country) }
        func real(_ p: ClientPerson) -> Bool { TelFormat.isReal(p.phone, country: country) }
        func sameName(_ a: String, _ b: String) -> Bool {
            let x = a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !x.isEmpty && x == b.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        for p in src.people where !p.isBlank {
            let j: Int? = real(p) ? dst.people.firstIndex { real($0) && key($0) == key(p) }
                                  : dst.people.firstIndex { !real($0) && sameName($0.name, p.name) }
            if let j { fill(&dst.people[j], from: p) } else { dst.people.append(p) }
        }

        if dst.anniversary == nil || (!dst.anniversaryManual && src.anniversaryManual) {
            if let a = src.anniversary { dst.anniversary = a; dst.anniversaryManual = src.anniversaryManual }
        }
        dst.greet = dst.greet || src.greet
        for l in src.links where !dst.links.contains(where: { $0.id == l.id || ($0.url != nil && $0.url == l.url) }) {
            dst.links.append(l)
        }
        let live = Set(dst.people.filter(real).map(key))
        var log: [TelLogEntry] = []
        for t in dst.telLog + src.telLog {
            let k = TelFormat.full(t.phone, country: country)
            if live.contains(k) || log.contains(where: { TelFormat.full($0.phone, country: country) == k }) { continue }
            log.append(t)
        }
        dst.telLog = Array(log.suffix(PhoneBook.logMax))
        dst.modifiedAt = nowMs
        clients[ti] = dst
        clients.remove(at: si)

        for i in sessions.indices where sessions[i].clientId == sourceId {
            sessions[i].clientId = targetId
            sessions[i].modifiedAt = nowMs
        }
        for i in trashed.indices where trashed[i].record.clientId == sourceId {
            trashed[i].record.clientId = targetId
            trashed[i].record.modifiedAt = nowMs
        }
        return true
    }

    /// Пустые поля человека дозаполняются из второго, заполненные остаются.
    private static func fill(_ p: inout ClientPerson, from q: ClientPerson) {
        if p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { p.name = q.name }
        if p.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { p.phone = q.phone }
        if (p.birthday ?? "").isEmpty, let b = q.birthday, !b.isEmpty { p.birthday = b }
        for m in q.messengers where !p.messengers.contains(where: { $0.kind == m.kind }) { p.messengers.append(m) }
        if p.preferred == nil { p.preferred = q.preferred }
    }

    // MARK: - Удалить (§ 2.2)

    /// «Удалить клиента»: клиент уходит из списка, его съёмки (живые и в корзине) **остаются** — без `clientId`, со свежей
    /// отметкой правки. Справка про съёмки удалённого клиента молчит; так же поступает удаление организации
    /// (`OrgBook.detach`): имя и номер в съёмке остаются, теряется только связь. Могилу кладёт вызывающий.
    @discardableResult
    public static func delete(_ id: String, clients: inout [Client], sessions: inout [Session], trashed: inout [TrashedItem],
                              nowMs: Int64) -> Bool {
        guard let i = clients.firstIndex(where: { $0.id == id }) else { return false }
        clients.remove(at: i)
        for j in sessions.indices where sessions[j].clientId == id {
            sessions[j].clientId = nil
            sessions[j].modifiedAt = nowMs
        }
        for j in trashed.indices where trashed[j].record.clientId == id {
            trashed[j].record.clientId = nil
            trashed[j].record.modifiedAt = nowMs
        }
        return true
    }
}
