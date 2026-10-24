import Foundation
import Synchronization
import LightPlanDomain

/// Книга в памяти: тесты и снимки. Свои контакты лежат картой (`ContactCard`), «твои» — тем, что из них читается
/// (`FoundContact`); право выдаётся снаружи, как в настройках iPhone.
public final class InMemoryContactsStore: ContactsStoring, @unchecked Sendable {
    public struct Entry: Sendable, Equatable {
        public var id: String
        /// Заведён приложением (через `create`).
        public var card: ContactCard?
        public var found: FoundContact
    }

    private struct State {
        var auth: ContactsAuthorization
        /// Что даст системный вопрос.
        var answer: ContactsAuthorization
        var entries: [Entry] = []
        var next = 1
        var asked = 0
        var writes = 0
        var failWrites = false
    }

    private let box: Mutex<State>

    public init(auth: ContactsAuthorization = .full, answer: ContactsAuthorization = .full) {
        box = Mutex(State(auth: auth, answer: answer))
    }

    // MARK: подставка

    public var auth: ContactsAuthorization {
        get { box.withLock { $0.auth } }
        set { box.withLock { $0.auth = newValue } }
    }
    public var entries: [Entry] { box.withLock { $0.entries } }
    /// Сколько раз задали системный вопрос.
    public var asked: Int { box.withLock { $0.asked } }
    /// Сколько записей (заведено, поправлено, удалено) сделано.
    public var writes: Int { box.withLock { $0.writes } }
    public var failWrites: Bool {
        get { box.withLock { $0.failWrites } }
        set { box.withLock { $0.failWrites = newValue } }
    }

    /// Контакт, сохранённый человеком самим (не приложением).
    @discardableResult
    public func addOwn(_ f: FoundContact) -> String {
        box.withLock { s in
            let id = "own-\(s.next)"
            s.next += 1
            s.entries.append(Entry(id: id, card: nil, found: f))
            return id
        }
    }

    /// Удалить руками, как в Контактах.
    public func deleteByHand(_ id: String) { box.withLock { $0.entries.removeAll { $0.id == id } } }

    // MARK: ContactsStoring

    public func authorization() async -> ContactsAuthorization { auth }

    public func requestAccess() async -> ContactsAuthorization {
        box.withLock { s in
            guard s.auth == .notDetermined else { return s.auth }
            s.asked += 1
            s.auth = s.answer
            return s.auth
        }
    }

    public func book() async throws -> [ClientContacts.BookEntry] {
        box.withLock { $0.entries.map { ClientContacts.BookEntry(id: $0.id, phones: $0.found.phones) } }
    }

    public func found(id: String) async -> FoundContact? { box.withLock { s in s.entries.first { $0.id == id }?.found } }

    private struct Failed: Error {}

    public func create(_ card: ContactCard) async throws -> String {
        try box.withLock { s in
            guard s.auth == .full, !s.failWrites else { throw Failed() }
            let id = "app-\(s.next)"
            s.next += 1
            s.writes += 1
            s.entries.append(Entry(id: id, card: card, found: Self.found(card)))
            return id
        }
    }

    public func update(id: String, _ card: ContactCard) async throws {
        try box.withLock { s in
            guard s.auth == .full, !s.failWrites, let i = s.entries.firstIndex(where: { $0.id == id }) else { throw Failed() }
            s.writes += 1
            s.entries[i].card = card
            s.entries[i].found = Self.found(card)
        }
    }

    public func delete(id: String) async throws {
        try box.withLock { s in
            guard s.auth == .full, !s.failWrites, let i = s.entries.firstIndex(where: { $0.id == id }) else { throw Failed() }
            s.writes += 1
            s.entries.remove(at: i)
        }
    }

    static func found(_ c: ContactCard) -> FoundContact {
        FoundContact(name: [c.given, c.middle, c.family].filter { !$0.isEmpty }.joined(separator: " "),
                     phones: [c.phone], birthday: c.birthday, messengers: c.messengers)
    }
}
