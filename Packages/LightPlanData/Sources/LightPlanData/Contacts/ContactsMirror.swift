import Foundation
import LightPlanCore
import LightPlanDomain

/// Клиенты в телефонной книге iPhone (шаг К7, справка `docs/clients_reference.md` § 5).
///
/// Правда в Light Plan, книга показывает: iPhone узнаёт, кто звонит. Проход приводит книгу к клиентам, которых можно
/// писать (`allowed`: решает приложение — тумблер, сборка, «Да» на прошлых): заводит контакт человеку с номером, правит
/// только свои контакты, из чужого (номер уже есть в книге) читает недостающее. Из книги в клиента правки не едут;
/// удаление клиента контакт не удаляет. Без полного права — ничего не трогает.
public actor ContactsMirror {
    public struct Report: Sendable, Equatable {
        public var created = 0
        public var updated = 0
        public var gone = 0
        public var failed = 0
        /// Прочитанное из чужих контактов: что приложение возьмёт в клиента, если у того этого нет.
        public var fills: [Fill] = []
        public init() {}
    }

    public struct Fill: Sendable, Equatable {
        public var read: ClientContacts.Read
        public var found: FoundContact
    }

    public enum Outcome: Sendable, Equatable {
        case synced(Report)
        case noAccess(ContactsAuthorization)
        case failed
    }

    private let store: any ContactsStoring
    private let memory: any ContactsMemory

    public init(store: any ContactsStoring, memory: any ContactsMemory) {
        self.store = store
        self.memory = memory
    }

    public var record: ContactsRecord { memory.record }

    /// Каждая правка памяти — свежим чтением: тумблер и ответ на вопрос пишет приложение, проход их не затирает.
    private func edit(_ change: (inout ContactsRecord) -> Void) {
        var r = memory.record
        change(&r)
        memory.record = r
    }

    public func sync(clients: [Client], allowed: Set<String>, anniversaries: [String: CivilDate],
                     country: TelCountry) async -> Outcome {
        let auth = await store.authorization()
        guard auth == .full else { return .noAccess(auth) }
        guard let book = try? await store.book() else { return .failed }
        let rec = memory.record
        let plan = ClientContacts.plan(clients: clients, allowed: allowed, anniversary: { anniversaries[$0.id] },
                                       links: rec.links, dropped: rec.dropped, book: book, country: country)
        var report = Report()
        for action in plan.actions {
            switch action {
            case .create(let key, let card):
                // Связь — сразу после записи: оборвись проход дальше, контакт всё равно узнается своим.
                if let id = try? await store.create(card) {
                    edit { $0.links[key] = ClientContacts.Link(id: id, card: card) }
                    report.created += 1
                } else { report.failed += 1 }
            case .update(let key, let id, let card, let was):
                if (try? await store.update(id: id, card, was: was)) != nil {
                    // Связь переезжает к нынешнему ключу человека; прежний ключ того же контакта забывается.
                    // Ключ занят связью другого контакта (люди сдвинулись) — та связь не теряется, а отходит в запасной
                    // ключ того же клиента: её контакт по-прежнему свой, его найдут по номеру и уберёт «Убрать всё»
                    // (ревью GPT к d613efc).
                    edit { r in
                        r.links = r.links.filter { $0.value.id != id }
                        if let other = r.links[key] { r.links[key + "~" + other.id] = other }
                        r.links[key] = ClientContacts.Link(id: id, card: card)
                    }
                    report.updated += 1
                } else { report.failed += 1 }
            case .gone(let key, let tel):
                edit { $0.links[key] = nil; $0.dropped.insert(tel) }
                report.gone += 1
            }
        }
        for r in plan.reads {
            if let f = await store.found(id: r.contactId) { report.fills.append(Fill(read: r, found: f)) }
        }
        return .synced(report)
    }

    /// «Убрать из Контактов всё, что записало приложение» (защита 3): только контакты по связи этого телефона; твои
    /// контакты не трогает. Не удалённое остаётся в связи — следующая попытка уберёт и его.
    public func removeAll() async -> (removed: Int, failed: Int)? {
        guard await store.authorization() == .full, let book = try? await store.book() else { return nil }
        let inBook = Set(book.map(\.id))
        var removed = 0, failed = 0
        for (key, link) in memory.record.links {
            if inBook.contains(link.id) {
                if (try? await store.delete(id: link.id)) == nil { failed += 1; continue }
                removed += 1
            }
            edit { $0.links[key] = nil }
        }
        edit { $0.dropped = [] }
        return (removed, failed)
    }
}
