import Foundation
import LightPlanCore

/// Вид частного клиента: «Пара» / «Семья» / «Персона» (шаг К1 «Клиенты», справка `docs/clients_reference.md` § 2.1).
/// Ставится по жанру съёмки, из которой клиент завёлся, дальше правится руками.
public enum ClientKind: String, CaseIterable, Sendable {
    case couple, family, person
}

/// Способ связи человека: мессенджер и то, что в нём вписано (имя пользователя, номер или ссылка). Тип способа лежит
/// строкой: Telegram, VK, Instagram, WhatsApp, MAX и разбор ссылок — шаг К4, здесь они только переживают чтение-запись.
public struct ClientMessenger: Sendable, Hashable, Codable {
    public var kind: String
    public var value: String
    public init(kind: String, value: String) {
        self.kind = kind
        self.value = value
    }
    enum CodingKeys: String, CodingKey { case kind = "k", value = "v" }
}

/// Человек в карточке клиента (справка § 2.1: `n`, `tel`, `bd`, `msg`, `pref`). День рождения и мессенджеры заполняют
/// шаги К2, К4, К6; К1 хранит их как есть и склеивает по телефону.
public struct ClientPerson: Sendable, Hashable {
    /// `n` — имя и фамилия одной строкой (как `persons[].n`).
    public var name: String = ""
    /// `tel`.
    public var phone: String = ""
    /// `bd` — день рождения, `ММ-ДД` или `ГГГГ-ММ-ДД`: год необязателен, как в Контактах iPhone.
    public var birthday: String?
    /// `msg`.
    public var messengers: [ClientMessenger] = []
    /// `pref` — основной мессенджер (его тип).
    public var preferred: String?

    public init(name: String = "", phone: String = "") {
        self.name = name
        self.phone = phone
    }

    /// Ничего не вписано: ни имени, ни телефона, ни дня рождения, ни мессенджеров.
    public var isBlank: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (birthday ?? "").isEmpty && messengers.isEmpty
    }
}

/// Частный клиент: отдельная запись с вечным `id`, как организация (справка `docs/clients_reference.md` § 0, § 2).
/// В записи лежит `clientId`, не имя. Клиент хранит только своё — людей, телефоны, дни рождения, ссылки; съёмки, даты и
/// гонорары **не копируются**, а считаются из записей с этим `clientId` (`ClientBook`).
public struct Client: Sendable, Hashable, Identifiable {
    /// `id` — `ClientBook.newId`.
    public var id: String
    /// `kind`.
    public var kind: ClientKind = .person
    /// `people` — люди карточки: у персоны один, у пары два, у семьи сколько угодно.
    public var people: [ClientPerson] = []
    /// `main` — номер человека в `people`, «кому пишем».
    public var main: Int = 0
    /// `anniv` — годовщина пары (день), из самой ранней свадьбы (K6 её считает; K1 только хранит).
    public var anniversary: CivilDate?
    /// `annivManual` — годовщину правили руками: дата свадьбы её больше не двигает.
    public var anniversaryManual: Bool = false
    /// `greet` — «Поздравлять»: один тумблер на карточку (К6).
    public var greet: Bool = false
    /// `greetHand` — тумблер «Поздравлять» трогали руками (К6б): дальше он сам не включается ни от даты, ни от свадьбы.
    public var greetHand: Bool = false
    /// `links` — свои ссылки клиента; ссылки съёмок сюда не копируются.
    public var links: [Attachment] = []
    /// `telLog` — ушедшие номера людей карточки: по ним клиент узнаётся и по старому номеру.
    public var telLog: [TelLogEntry] = []
    /// `mt` — отметка правки (миллисекунды); по ней сольются устройства, когда придёт облако (31).
    public var modifiedAt: Int64?

    public init(id: String, kind: ClientKind = .person) {
        self.id = id
        self.kind = kind
    }
}

extension ClientPerson: Codable {
    enum CodingKeys: String, CodingKey { case n, tel, bd, msg, pref }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .n) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .tel) ?? ""
        birthday = try c.decodeIfPresent(String.self, forKey: .bd)
        messengers = try c.decodeIfPresent([ClientMessenger].self, forKey: .msg) ?? []
        preferred = try c.decodeIfPresent(String.self, forKey: .pref)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .n)
        try c.encode(phone, forKey: .tel)
        try c.encodeIfPresent(birthday, forKey: .bd)
        if !messengers.isEmpty { try c.encode(messengers, forKey: .msg) }
        try c.encodeIfPresent(preferred, forKey: .pref)
    }
}

extension Client: Codable {
    enum CodingKeys: String, CodingKey {
        case id, kind, people, main, anniv, annivManual, greet, greetHand, links, telLog, mt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id))
        // Незнакомый вид (файл новее приложения) читается как «Персона»: запись не теряется.
        kind = try c.decodeIfPresent(String.self, forKey: .kind).flatMap(ClientKind.init(rawValue:)) ?? .person
        people = try c.decodeIfPresent([ClientPerson].self, forKey: .people) ?? []
        main = try c.decodeIfPresent(Int.self, forKey: .main) ?? 0
        anniversary = (try c.decodeIfPresent(String.self, forKey: .anniv)).flatMap(CivilDate.init(snapshotString:))
        anniversaryManual = try c.decodeIfPresent(Bool.self, forKey: .annivManual) ?? false
        greet = try c.decodeIfPresent(Bool.self, forKey: .greet) ?? false
        greetHand = try c.decodeIfPresent(Bool.self, forKey: .greetHand) ?? false
        links = try c.decodeIfPresent([Attachment].self, forKey: .links) ?? []
        telLog = try c.decodeIfPresent([TelLogEntry].self, forKey: .telLog) ?? []
        modifiedAt = try c.decodeIfPresent(Int64.self, forKey: .mt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encode(people, forKey: .people)
        if main != 0 { try c.encode(main, forKey: .main) }
        try c.encodeIfPresent(anniversary?.snapshotString, forKey: .anniv)
        if anniversaryManual { try c.encode(true, forKey: .annivManual) }
        if greet { try c.encode(true, forKey: .greet) }
        if greetHand { try c.encode(true, forKey: .greetHand) }
        if !links.isEmpty { try c.encode(links, forKey: .links) }
        if !telLog.isEmpty { try c.encode(telLog, forKey: .telLog) }
        try c.encodeIfPresent(modifiedAt, forKey: .mt)
    }
}
