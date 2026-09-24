import Foundation
import LightPlanDomain

/// Имена в планировщике — те же вопросы, что задаёт веб: как назвать съёмку в
/// тесной клетке месяца, в строке недели и на ленте дня (`typeName`,
/// `shortType`, `clientName`). Ответ зависит от записи целиком: уточнение
/// жанра сильнее жанра, пара сильнее организации.
struct PlannerWords {
    let lexicon: Lexicon
    let orgs: [Org]

    /// Уточнение, если оно принадлежит жанру записи (веб `subOk`).
    private func sub(_ s: Session) -> SubGenre? {
        guard let g = s.genre, let x = s.subGenre, g.allows(x) else { return nil }
        return x
    }

    private func subName(_ x: SubGenre) -> String { soft("sub." + x.rawValue, x.rawValue) }

    /// Слово словаря или запасное, если ключа нет (веб `v === k ? … : v`).
    private func soft(_ key: String, _ fallback: String) -> String {
        let v = lexicon.t(key)
        return v == key ? fallback : v
    }

    func genreName(_ g: Genre?) -> String {
        guard let g else { return "" }
        return soft("genre." + g.rawValue, g.rawValue)
    }

    /// Имя съёмки (веб `typeName`).
    func typeName(_ s: Session) -> String { sub(s).map(subName) ?? genreName(s.genre) }

    /// Короткое имя для узких мест (веб `shortType`): «Архитект.» в клетке.
    func shortType(_ s: Session) -> String {
        if let x = sub(s) { return subName(x) }
        guard let g = s.genre else { return "" }
        return soft("genreShort." + g.rawValue, genreName(g))
    }

    /// Знак съёмки: уточнения — свой, иначе жанра (веб `typeSvg`).
    func iconName(_ s: Session) -> String? { sub(s)?.iconName }

    /// Кого снимаем (веб `clientName`): пару — по именам без фамилий, заказ —
    /// организацией, остальное — строкой клиента без телефона.
    func clientName(_ s: Session) -> String {
        let names = s.persons.map { Self.firstName($0.name) }.filter { !$0.isEmpty }
        if !names.isEmpty { return names.joined(separator: lexicon.t("card.and")) }
        if let id = s.orgId, let org = orgs.first(where: { $0.id == id }), !org.name.isEmpty { return org.name }
        let tel = firstPhone(s)
        var n = tel.isEmpty ? s.contact : s.contact.replacingOccurrences(of: tel, with: "")
        let edge = CharacterSet(charactersIn: "·,;|—-").union(.whitespaces)
        n = n.trimmingCharacters(in: edge).trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? s.contact : n
    }

    static func firstName(_ n: String) -> String {
        n.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    }

    /// Первый телефон записи (веб `firstPhone`): пара, заказчик, клиент,
    /// организация, потом номер, вписанный в строку клиента или заметки.
    func firstPhone(_ s: Session) -> String {
        if let p = s.persons.first(where: { !$0.phone.isEmpty }) { return p.phone }
        if !s.orderPhone.isEmpty { return s.orderPhone }
        if !s.clientPhone.isEmpty { return s.clientPhone }
        if let id = s.orgId, let org = orgs.first(where: { $0.id == id }), !org.phone.isEmpty { return org.phone }
        let text = s.contact + " " + s.notes
        guard let r = text.range(of: #"\+?\d[\d\-\s()]{8,}\d"#, options: .regularExpression) else { return "" }
        return String(text[r]).trimmingCharacters(in: .whitespaces)
    }
}
