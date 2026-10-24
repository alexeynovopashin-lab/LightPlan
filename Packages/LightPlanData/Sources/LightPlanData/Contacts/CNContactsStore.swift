import Contacts
import Foundation
import LightPlanCore
import LightPlanDomain

/// Настоящая телефонная книга: `CNContactStore` (шаг К7). Единственное место, где приложение трогает `Contacts`.
///
/// Всё идёт по одной последовательной очереди, как у календаря: запросы книги синхронные и не для главного потока.
/// «Заметки» контакта не читаются и не пишутся — для них нужно особое разрешение Apple (`contacts.notes`).
public final class CNContactsStore: ContactsStoring, @unchecked Sendable {

    nonisolated(unsafe) private let store = CNContactStore()
    private let queue = DispatchQueue(label: "lightplan.contacts")

    public init() {}

    private func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async { cont.resume(with: Result { try body() }) }
        }
    }

    // MARK: - Право

    public func authorization() async -> ContactsAuthorization { Self.authorization() }

    static func authorization() -> ContactsAuthorization {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: .notDetermined
        case .authorized: .full
        case .limited: .limited
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    public func requestAccess() async -> ContactsAuthorization {
        guard Self.authorization() == .notDetermined else { return Self.authorization() }
        _ = try? await self.store.requestAccess(for: .contacts)
        return Self.authorization()
    }

    // MARK: - Чтение

    public func book() async throws -> [ClientContacts.BookEntry] {
        return try await run {
            let req = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as NSString, CNContactPhoneNumbersKey as NSString])
            // Каждый контакт своим идентификатором: свой контакт узнаётся по тому, что вернула запись, а не по
            // объединённому (связанные контакты разных учётных записей).
            req.unifyResults = false
            var out: [ClientContacts.BookEntry] = []
            try self.store.enumerateContacts(with: req) { c, _ in
                out.append(.init(id: c.identifier, phones: c.phoneNumbers.map { $0.value.stringValue }))
            }
            return out
        }
    }

    static var readKeys: [CNKeyDescriptor] {
        [
        CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey,
        CNContactBirthdayKey, CNContactSocialProfilesKey, CNContactInstantMessageAddressesKey,
    ].map { $0 as NSString }
    }

    public func found(id: String) async -> FoundContact? {
        return try? await run {
            let pred = CNContact.predicateForContacts(withIdentifiers: [id])
            return try self.store.unifiedContacts(matching: pred, keysToFetch: Self.readKeys).first.map(Self.found)
        }
    }

    /// Что взять из контакта книги — и при записи (чужой контакт с тем же номером), и из системного выбора
    /// «Из Контактов» (`CNContactPickerViewController`). Ключ, которого у контакта не запросили, пропускается.
    public static func found(_ c: CNContact) -> FoundContact {
        var f = FoundContact()
        func has(_ k: String) -> Bool { c.isKeyAvailable(k) }
        if has(CNContactGivenNameKey), has(CNContactFamilyNameKey) {
            let middle = has(CNContactMiddleNameKey) ? c.middleName : ""
            f.name = [c.givenName, middle, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        }
        if has(CNContactPhoneNumbersKey) { f.phones = c.phoneNumbers.map { $0.value.stringValue } }
        if has(CNContactBirthdayKey), let b = c.birthday {
            f.birthday = ClientContacts.birthday(year: b.year, month: b.month, day: b.day)
        }
        var msg: [ClientMessenger] = []
        func add(_ m: ClientMessenger?) { if let m, !msg.contains(where: { $0.kind == m.kind }) { msg.append(m) } }
        if has(CNContactSocialProfilesKey) {
            for p in c.socialProfiles {
                add(ClientContacts.messenger(service: p.value.service, username: p.value.username, url: p.value.urlString))
            }
        }
        if has(CNContactInstantMessageAddressesKey) {
            for a in c.instantMessageAddresses {
                add(ClientContacts.messenger(service: a.value.service, username: a.value.username, url: ""))
            }
        }
        f.messengers = msg
        return f
    }

    // MARK: - Запись

    private struct Missing: Error {}

    public func create(_ card: ContactCard) async throws -> String {
        return try await run {
            let c = CNMutableContact()
            Self.fill(c, card)
            let req = CNSaveRequest()
            req.add(c, toContainerWithIdentifier: nil)
            try self.store.execute(req)
            return c.identifier
        }
    }

    /// Поля, которые приложение пишет в свой контакт; остальное (фото, адрес, что человек дописал сам) не трогает.
    static var writeKeys: [CNKeyDescriptor] {
        [
        CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey,
        CNContactBirthdayKey, CNContactDatesKey, CNContactSocialProfilesKey,
    ].map { $0 as NSString }
    }

    public func update(id: String, _ card: ContactCard, was: ContactCard) async throws {
        try await run {
            guard let c = try self.store.unifiedContacts(matching: CNContact.predicateForContacts(withIdentifiers: [id]),
                                                    keysToFetch: Self.writeKeys).first?.mutableCopy() as? CNMutableContact
            else { throw Missing() }
            Self.fill(c, card, was: was)
            let req = CNSaveRequest()
            req.update(c)
            try self.store.execute(req)
        }
    }

    public func delete(id: String) async throws {
        try await run {
            guard let c = try self.store.unifiedContacts(matching: CNContact.predicateForContacts(withIdentifiers: [id]),
                                                    keysToFetch: [CNContactIdentifierKey as NSString]).first?.mutableCopy() as? CNMutableContact
            else { throw Missing() }
            let req = CNSaveRequest()
            req.delete(c)
            try self.store.execute(req)
        }
    }

    /// Записать карту в контакт. `was` — каким приложение записало его прошлый раз (`nil` — новый контакт): из номеров,
    /// дат и профилей убирается только записанное приложением, дописанное человеком в Контактах остаётся (ревью GPT к
    /// 3e34cb3: правка имени стирала чужие профили). Имя приложение держит своим.
    static func fill(_ c: CNMutableContact, _ card: ContactCard, was: ContactCard? = nil) {
        let cc = TelCountry.fallback
        c.givenName = card.given
        c.middleName = card.middle
        c.familyName = card.family
        let ours = Set([was?.phone, card.phone].compactMap { $0 }.map { ClientContacts.phoneKey($0, country: cc) }.filter { !$0.isEmpty })
        var phones = c.phoneNumbers.filter { !ours.contains(ClientContacts.phoneKey($0.value.stringValue, country: cc)) }
        if !card.phone.isEmpty {
            phones.insert(CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: card.phone)), at: 0)
        }
        c.phoneNumbers = phones
        let now = c.birthday.flatMap { ClientContacts.birthday(year: $0.year, month: $0.month, day: $0.day) }
        // День рождения, исправленный человеком в Контактах после нашей записи, остаётся его (ревью GPT к d613efc).
        let handEdited = now != nil && now != was?.birthday
        if let b = Birthday(card.birthday), !handEdited {
            var d = DateComponents()
            d.year = b.year
            d.month = b.month
            d.day = b.day
            c.birthday = d
        } else if card.birthday == nil, now != nil, now == was?.birthday {
            c.birthday = nil            // у клиента день рождения стёрли — стираем и тот, что записали сами
        }
        // Годовщина — среди «Дат» с меткой «годовщина»; убирается только записанная приложением.
        func same(_ v: CNLabeledValue<NSDateComponents>, _ a: CivilDate?) -> Bool {
            guard let a else { return false }
            return v.label == CNLabelDateAnniversary && v.value.year == a.year && v.value.month == a.month && v.value.day == a.day
        }
        var dates = c.dates.filter { !same($0, was?.anniversary) && !same($0, card.anniversary) }
        if let a = card.anniversary {
            let d = NSDateComponents()
            d.year = a.year
            d.month = a.month
            d.day = a.day
            dates.append(CNLabeledValue(label: CNLabelDateAnniversary, value: d))
        }
        c.dates = dates
        let written = Set((was?.messengers ?? []) + card.messengers)
        var profiles = c.socialProfiles.filter { p in
            guard let m = ClientContacts.messenger(service: p.value.service, username: p.value.username, url: p.value.urlString) else { return true }
            return !written.contains(m)
        }
        profiles += card.messengers.compactMap { m in
            guard let kind = MessengerKind(rawValue: m.kind) else { return nil }
            let url = ClientReach.url(kind, value: m.value, phone: card.phone, country: cc)?.absoluteString ?? ""
            return CNLabeledValue(label: nil, value: CNSocialProfile(urlString: url, username: m.value, userIdentifier: nil,
                                                                     service: kind.title))
        }
        c.socialProfiles = profiles
    }
}
