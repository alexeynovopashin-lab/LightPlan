import Foundation
import Synchronization
import LightPlanDomain

/// Что система говорит о праве на Контакты. `limited` — iOS 18+: человек открыл только выбранные контакты; так не
/// найти, кто уже записан, и появятся дубли — для записи это всё равно что отказ (справка § 5).
public enum ContactsAuthorization: Sendable, Equatable {
    case notDetermined, full, limited, denied
}

/// Телефонная книга (шаг К7). Настоящая — `CNContactsStore` (единственный, кто трогает `Contacts`), подставка —
/// `InMemoryContactsStore` (тесты, снимки).
public protocol ContactsStoring: Sendable {
    func authorization() async -> ContactsAuthorization
    /// Системный вопрос; уже отвечали — просто нынешнее право.
    func requestAccess() async -> ContactsAuthorization
    /// Все контакты: идентификатор и номера.
    func book() async throws -> [ClientContacts.BookEntry]
    /// Что прочитать из контакта (день рождения, мессенджеры); нет такого — `nil`.
    func found(id: String) async -> FoundContact?
    func create(_ card: ContactCard) async throws -> String
    /// Поправить свой контакт: `was` — каким его записали прошлый раз; дописанное человеком остаётся.
    func update(id: String, _ card: ContactCard, was: ContactCard) async throws
    func delete(id: String) async throws
}

/// Что приложение помнит о книге этого телефона. Лежит на устройстве, не в снимке: идентификаторы контактов у каждого
/// телефона свои (как у календаря, `CalendarMirrorRecord`). Минус (§ 5): после переустановки прежние контакты уже не
/// узнаются как свои.
public struct ContactsRecord: Codable, Equatable, Sendable {
    /// Тумблер «Сохранять клиентов в Контакты iPhone», по умолчанию **вкл** (Алексей, 23.10). Отказ системы его не
    /// гасит: тумблер показывает «выкл» с подписью, и запись сама пойдёт, когда право выдадут.
    public var wanted = true
    /// Человек клиента (`ClientContacts.key`) → контакт, заведённый приложением.
    public var links: [String: ClientContacts.Link] = [:]
    /// Свой контакт удалили руками в Контактах: заново его не заводим (`ClientContacts.dropKey` — клиент и номер).
    public var dropped: Set<String> = []
    /// Прошлые клиенты уже отмечены (первый запуск сборки с К7 или «Убрать всё»).
    public var baseline = false
    /// Клиенты, что были до этого: пишутся только после «Да» (защита 2).
    public var past: Set<String> = []
    /// Ответ на «Сохранить N клиентов из прошлых съёмок?»: `nil` — ещё не спрашивали.
    public var pastAnswer: Bool?

    public init() {}

    private enum CodingKeys: String, CodingKey { case wanted, links, dropped, baseline, past, pastAnswer }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wanted = try c.decodeIfPresent(Bool.self, forKey: .wanted) ?? true
        links = try c.decodeIfPresent([String: ClientContacts.Link].self, forKey: .links) ?? [:]
        dropped = try c.decodeIfPresent(Set<String>.self, forKey: .dropped) ?? []
        baseline = try c.decodeIfPresent(Bool.self, forKey: .baseline) ?? false
        past = try c.decodeIfPresent(Set<String>.self, forKey: .past) ?? []
        pastAnswer = try c.decodeIfPresent(Bool.self, forKey: .pastAnswer)
    }
}

public protocol ContactsMemory: AnyObject, Sendable {
    var record: ContactsRecord { get set }
}

/// Память на время запуска: тесты и снимки.
public final class InMemoryContactsMemory: ContactsMemory, @unchecked Sendable {
    private let box: Mutex<ContactsRecord>
    public init(_ record: ContactsRecord = ContactsRecord()) { box = Mutex(record) }
    public var record: ContactsRecord {
        get { box.withLock { $0 } }
        set { box.withLock { $0 = newValue } }
    }
}

/// Память телефона: одна запись JSON в `UserDefaults`.
public final class DeviceContactsMemory: ContactsMemory, @unchecked Sendable {
    public static let key = "lightplan.native.contacts"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var record: ContactsRecord {
        get { defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ContactsRecord.self, from: $0) } ?? ContactsRecord() }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.key) }
    }
}
