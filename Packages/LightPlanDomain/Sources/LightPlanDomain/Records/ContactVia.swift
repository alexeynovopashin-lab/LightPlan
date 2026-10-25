import Foundation

/// Кем приходится тот, кто на связи (шаг «Поле-2», слова Алексея 25.10): организатор, подруга, друг, родственник.
/// Порядок случаев — порядок кнопок в форме.
public enum ViaRelation: String, CaseIterable, Sendable {
    case organizer, girlfriend, friend, relative
}

/// «На связи через»: человек, через которого идёт связь со съёмкой, когда герой съёмки сам не на связи — именинницу
/// Ольгу ведёт подруга Алёна (шаг «Поле-2»). Лежит в съёмке (`via`: `r`, `n`, `tel`) и не заменяет героя — у героя
/// остаются свои имя и телефон, он может быть без номера. Только у нас: веб ключа не знает и при пересохранении теряет.
public struct ContactVia: Sendable, Hashable {
    public var relation: ViaRelation
    public var name: String
    public var phone: String

    public init(relation: ViaRelation = .organizer, name: String = "", phone: String = "") {
        self.relation = relation
        self.name = name
        self.phone = phone
    }

    /// Ни имени, ни телефона: одно отношение человека не называет.
    public var isBlank: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension ContactVia: Codable {
    enum CodingKeys: String, CodingKey { case relation = "r", name = "n", phone = "tel" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Незнакомое отношение (файл новее приложения) читается как «организатор»: человек на связи не теряется.
        relation = try c.decodeIfPresent(String.self, forKey: .relation).flatMap(ViaRelation.init(rawValue:)) ?? .organizer
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(relation.rawValue, forKey: .relation)
        try c.encode(name, forKey: .name)
        try c.encode(phone, forKey: .phone)
    }
}
