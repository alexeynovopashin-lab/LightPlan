import Foundation
import LightPlanCore

/// Контакт телефонной книги, каким его делает приложение из человека клиента (шаг К7, справка
/// `docs/clients_reference.md` § 5): имя, один номер, день рождения, годовщина пары, мессенджеры. «Заметки» не трогаем —
/// для них нужно особое разрешение Apple.
public struct ContactCard: Sendable, Hashable, Codable {
    public var given: String = ""
    public var middle: String = ""
    public var family: String = ""
    /// Международный номер `+7916…`.
    public var phone: String = ""
    /// `ММ-ДД` / `ГГГГ-ММ-ДД`, как `ClientPerson.birthday`.
    public var birthday: String?
    /// Годовщина пары — в «Датах» обоих людей.
    public var anniversary: CivilDate?
    public var messengers: [ClientMessenger] = []

    public init(given: String = "", middle: String = "", family: String = "", phone: String = "",
                birthday: String? = nil, anniversary: CivilDate? = nil, messengers: [ClientMessenger] = []) {
        self.given = given
        self.middle = middle
        self.family = family
        self.phone = phone
        self.birthday = birthday
        self.anniversary = anniversary
        self.messengers = messengers
    }

    enum CodingKeys: String, CodingKey { case given, middle, family, phone, birthday, anniversary, messengers }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        given = try c.decodeIfPresent(String.self, forKey: .given) ?? ""
        middle = try c.decodeIfPresent(String.self, forKey: .middle) ?? ""
        family = try c.decodeIfPresent(String.self, forKey: .family) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        birthday = try c.decodeIfPresent(String.self, forKey: .birthday)
        anniversary = (try c.decodeIfPresent(String.self, forKey: .anniversary)).flatMap(CivilDate.init(snapshotString:))
        messengers = try c.decodeIfPresent([ClientMessenger].self, forKey: .messengers) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(given, forKey: .given)
        try c.encode(middle, forKey: .middle)
        try c.encode(family, forKey: .family)
        try c.encode(phone, forKey: .phone)
        try c.encodeIfPresent(birthday, forKey: .birthday)
        try c.encodeIfPresent(anniversary?.snapshotString, forKey: .anniversary)
        try c.encode(messengers, forKey: .messengers)
    }
}

/// Что приложение узнало из контакта книги: при записи — чужого (номер уже есть у тебя в Контактах), при выборе
/// «Из Контактов» — любого. Только то, что идёт в клиента: имя, номер, день рождения, мессенджеры.
public struct FoundContact: Sendable, Hashable {
    public var name: String = ""
    public var phones: [String] = []
    public var birthday: String?
    public var messengers: [ClientMessenger] = []

    public init(name: String = "", phones: [String] = [], birthday: String? = nil, messengers: [ClientMessenger] = []) {
        self.name = name
        self.phones = phones
        self.birthday = birthday
        self.messengers = messengers
    }
}

/// Клиенты в телефонной книге iPhone (К7, § 5). Правила без системы: какие контакты должны стоять, что из этого уже
/// стоит, что завести, что поправить, что только прочитать. Саму книгу трогает `ContactsMirror` (Data).
public enum ClientContacts {

    // MARK: - Защита 1: пишет только обычный «Light Plan»

    /// Ид обычного приложения. Тестовые копии веток (`…slotA` … `slotD`) живут на засеве — придуманных съёмках — и в
    /// книгу не пишут никогда (Алексей, 23.10); та же проверка решает засев (`AppModel.startSnapshot`).
    public static let mainBundleID = "Novopashin.LightPlan"

    /// Можно ли этой сборке писать в книгу.
    public static func writes(bundleID: String?) -> Bool { bundleID == mainBundleID }

    // MARK: - Номер

    /// Ключ номера для сравнения с книгой: международные цифры (`TelFormat.full`), «8 916…» и «+7 916…» — один номер.
    /// Добавочный («доб. 12», «ext 12», «,12», «;12», «#12») срезается: в книге его пишут по-разному.
    public static func phoneKey(_ raw: String, country: TelCountry) -> String {
        var s = "", digits = 0
        for ch in raw {
            if ch.isASCII && ch.isNumber { s.append(ch); digits += 1; continue }
            if " -()+./\u{00A0}".contains(ch) { s.append(ch); continue }
            // Буква или знак после пяти цифр — начало добавочного (паузы `p`/`w` набора тоже).
            if digits >= 5 { break }
            s.append(ch)
        }
        return TelFormat.full(s, country: country)
    }

    // MARK: - Какие контакты должны стоять

    /// Ключ контакта в связи «клиент → контакт» (память телефона): клиент и номер человека в нём.
    public static func key(client: String, person: Int) -> String { client + "#" + String(person) }

    /// Отметка «свой контакт удалён руками» — по клиенту и **номеру**, не по месту человека: люди семьи сдвинулись —
    /// отметка остаётся при своём человеке (ревью GPT к d613efc).
    public static func dropKey(client: String, phoneKey: String) -> String { client + "#tel:" + phoneKey }

    /// Имя одной строкой → имя / отчество / фамилия контакта: первое слово — имя, последнее — фамилия, между ними —
    /// отчество. Порядок — как вписано.
    public static func nameParts(_ name: String) -> (given: String, middle: String, family: String) {
        let w = name.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        switch w.count {
        case 0: return ("", "", "")
        case 1: return (w[0], "", "")
        default: return (w[0], w.dropFirst().dropLast().joined(separator: " "), w[w.count - 1])
        }
    }

    /// Контакты клиента: каждый человек **с настоящим номером** — свой контакт; без номера (ребёнок в семье) — нет.
    public static func cards(of c: Client, anniversary: CivilDate?, country: TelCountry) -> [(key: String, person: Int, card: ContactCard)] {
        c.people.indices.compactMap { i in
            let p = c.people[i]
            // Тот, кто на связи (подруга, организатор), в Контакты сам не пишется — только если Алексей попросит (Поле-2).
            guard p.relation == nil, TelFormat.isReal(p.phone, country: country) else { return nil }
            let n = nameParts(p.name)
            var card = ContactCard(given: n.given, middle: n.middle, family: n.family,
                                   phone: TelFormat.e164(p.phone, country: country))
            card.birthday = Birthday(p.birthday)?.snapshotString
            if c.kind == .couple { card.anniversary = anniversary }
            card.messengers = p.messengers.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            return (key(client: c.id, person: i), i, card)
        }
    }

    // MARK: - План прохода

    /// Контакт книги, как его видит проход: идентификатор и номера (как записаны).
    public struct BookEntry: Sendable, Hashable {
        public var id: String
        public var phones: [String]
        public init(id: String, phones: [String]) {
            self.id = id
            self.phones = phones
        }
    }

    /// Связь человека клиента с контактом, заведённым приложением, и каким контакт записали в последний раз: правка
    /// уезжает, только когда клиент стал другим.
    public struct Link: Sendable, Hashable, Codable {
        public var id: String
        public var card: ContactCard
        public init(id: String, card: ContactCard) {
            self.id = id
            self.card = card
        }
    }

    public enum Action: Sendable, Hashable {
        /// Номера нет в книге — завести контакт.
        case create(key: String, card: ContactCard)
        /// Свой контакт, клиента поправили — поправить контакт. `was` — каким его записали в прошлый раз: стирается только
        /// записанное приложением, дописанное человеком в Контактах остаётся. `key` — нынешний ключ человека (люди могли
        /// переставиться: связь переезжает к нему).
        case update(key: String, id: String, card: ContactCard, was: ContactCard)
        /// Свой контакт удалили руками в Контактах — связь забыть и заново не заводить (`tel` — отметка `dropKey`).
        case gone(key: String, tel: String)
    }

    /// Чужой контакт с тем же номером: из него читаем недостающее (день рождения, мессенджер), сам он не правится.
    public struct Read: Sendable, Hashable {
        public var client: String
        public var person: Int
        public var contactId: String
        public init(client: String, person: Int, contactId: String) {
            self.client = client
            self.person = person
            self.contactId = contactId
        }
    }

    public struct Plan: Sendable, Hashable {
        public var actions: [Action] = []
        public var reads: [Read] = []
        public init() {}
    }

    /// Что сделать с книгой. `allowed` — клиенты, которых можно писать: новые при включённом тумблере, прошлые — после
    /// «Да» (защита 2). Чужой номер (ты сам его сохранил) — не заводим и не правим, только читаем; номер, что уже стоит
    /// в своём контакте другого клиента, второй раз не заводим. Клиента удалили — его контакт остаётся (§ 5).
    public static func plan(clients: [Client], allowed: Set<String>, anniversary: (Client) -> CivilDate?,
                            links: [String: Link], dropped: Set<String>, book: [BookEntry], country: TelCountry) -> Plan {
        let ownIds = Set(links.values.map(\.id))
        let inBook = Set(book.map(\.id))
        var foreign: [String: String] = [:]          // ключ номера → первый чужой контакт с ним
        var own = Set<String>()                       // номера своих контактов
        for e in book {
            for raw in e.phones {
                let k = phoneKey(raw, country: country)
                guard !k.isEmpty else { continue }
                if ownIds.contains(e.id) { own.insert(k) } else if foreign[k] == nil { foreign[k] = e.id }
            }
        }
        var plan = Plan()
        for c in clients where allowed.contains(c.id) {
            let desired = cards(of: c, anniversary: anniversary(c), country: country)
            // Связи этого клиента. Человек узнаёт свой контакт сперва по номеру, потом по месту: удалили первого человека
            // семьи — второй не переезжает в контакт первого (ревью GPT к 3e34cb3).
            let mine = links.filter { $0.key.hasPrefix(c.id + "#") }.sorted { $0.key < $1.key }
            let desiredPhones = Set(desired.map { phoneKey($0.card.phone, country: country) })
            var claimed = Set<String>()
            for (key, person, card) in desired {
                let k = phoneKey(card.phone, country: country)
                // Свой контакт этого человека удалили руками — ни заводить снова, ни писать его в чужой контакт.
                guard !dropped.contains(dropKey(client: c.id, phoneKey: k)) else { continue }
                let byPhone = mine.first { !claimed.contains($0.key) && phoneKey($0.value.card.phone, country: country) == k }
                let byPlace: (key: String, value: Link)? = links[key].flatMap { l in
                    let lk = phoneKey(l.card.phone, country: country)
                    return claimed.contains(key) || (lk != k && desiredPhones.contains(lk)) ? nil : (key, l)
                }
                if let (lk, link) = byPhone.map({ ($0.key, $0.value) }) ?? byPlace {
                    claimed.insert(lk)
                    if !inBook.contains(link.id) {
                        plan.actions.append(.gone(key: lk, tel: dropKey(client: c.id, phoneKey: phoneKey(link.card.phone, country: country))))
                        continue
                    }
                    // Новый номер уже есть в чужом контакте — свой не правим (был бы дубль), из чужого читаем.
                    if phoneKey(link.card.phone, country: country) != k, let f = foreign[k] {
                        plan.reads.append(Read(client: c.id, person: person, contactId: f))
                        continue
                    }
                    if link.card != card || lk != key {
                        plan.actions.append(.update(key: key, id: link.id, card: card, was: link.card))
                    }
                    own.insert(k)
                    continue
                }
                if let f = foreign[k] {
                    plan.reads.append(Read(client: c.id, person: person, contactId: f))
                    continue
                }
                guard own.insert(k).inserted else { continue }
                plan.actions.append(.create(key: key, card: card))
            }
        }
        return plan
    }

    // MARK: - Чтение из книги

    /// Взять из чужого контакта то, чего нет у человека клиента: день рождения и мессенджеры, которых у него нет.
    /// Имя, номер и то, что уже вписано, не трогаем. `true` — человек изменился.
    @discardableResult
    public static func fill(_ p: inout ClientPerson, from f: FoundContact) -> Bool {
        var changed = false
        if Birthday(p.birthday) == nil, let b = Birthday(f.birthday) {
            p.birthday = b.snapshotString
            changed = true
        }
        for m in f.messengers where !p.messengers.contains(where: { $0.kind == m.kind }) && !m.value.isEmpty {
            p.messengers.append(m)
            changed = true
        }
        return changed
    }

    /// Мессенджер из профиля контакта (`socialProfiles`, `instantMessageAddresses`): служба по имени (Telegram, VK /
    /// ВКонтакте, Instagram, WhatsApp, MAX), значение — имя пользователя, а без него — разобранная ссылка. Незнакомая
    /// служба — `nil`.
    public static func messenger(service: String, username: String, url: String) -> ClientMessenger? {
        let s = service.lowercased().trimmingCharacters(in: .whitespaces)
        let kind: MessengerKind? =
            if s.contains("telegram") { .telegram }
            else if s == "vk" || s.contains("vkontakte") || s.contains("вконтакте") { .vk }
            else if s.contains("instagram") { .instagram }
            else if s.contains("whatsapp") { .whatsapp }
            else if s == "max" { .max }
            else { nil }
        guard let kind else { return nil }
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = name.isEmpty ? ClientReach.parse(url, as: kind) : ClientReach.parse(name, as: kind)
        return value.isEmpty ? nil : ClientMessenger(kind: kind.rawValue, value: value)
    }

    /// День рождения контакта (`birthday`: месяц и день, год необязателен) → строка `ClientPerson.birthday`.
    public static func birthday(year: Int?, month: Int?, day: Int?) -> String? {
        guard let month, let day else { return nil }
        return Birthday(year: year, month: month, day: day)?.snapshotString
    }
}
