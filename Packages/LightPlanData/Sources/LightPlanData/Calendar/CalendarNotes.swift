import Foundation
import LightPlanDomain

/// Заметки события в Календаре (шаг 30.4): телефоны клиента и заметки съёмки.
///
/// Календарь здесь личный — решение Алексея 22.10.2026, — поэтому в событие едет то, что нужно под рукой в день
/// съёмки: кому звонить. Деньги, предоплата и документы не едут. Текст детерминирован — одни и те же данные дают одни
/// и те же байты, иначе проход переписывал бы неизменные события.
///
///     Клиент: Ирина +7 916 123-45-67
///     Анна: +7 903 000-00-01
///
///     Приезжать за час, парковка во дворе.
///
/// Номера пишутся в международном виде («+7 …»): Календарь сам делает их нажимаемыми, а телефон в другой стране
/// набирает их так же, как дома.
public enum CalendarNotes {

    /// Слова подписей: клиент строкой, контактное лицо заказчика, номер без имени. Приходят из словаря.
    public struct Words: Sendable {
        public var client: String
        public var contact: String
        public var phone: String
        public init(client: String, contact: String, phone: String) {
            self.client = client; self.contact = contact; self.phone = phone
        }
    }

    /// Предел длины: заметка в событии — подсказка, не архив.
    static let limit = 4000

    public static func text(of s: Session, country: TelCountry, words: Words) -> String? {
        let lines = PhoneBook.tels(of: s, country: country).map { line($0, of: s, country: country, words: words) }
        let notes = s.notes.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let phones = lines.joined(separator: "\n")
        var out = phones
        if !notes.isEmpty { out += (phones.isEmpty ? "" : "\n\n") + notes }
        guard !out.isEmpty else { return nil }
        return out.count > limit ? String(out.prefix(limit)) : out
    }

    private static func line(_ t: PhoneBook.Tel, of s: Session, country: TelCountry, words: Words) -> String {
        let number = international(t.phone, country: country)
        switch t.field {
        case PhoneBook.Field.client:
            return join(words.client, name: clientName(s.contact, removing: t.phone), number)
        case PhoneBook.Field.contact:
            return join(words.contact, name: t.name, number)
        default:
            // Люди пары: подпись — имя, а без имени — слово «Телефон».
            let name = t.name.trimmingCharacters(in: .whitespaces)
            return "\(name.isEmpty ? words.phone : name): \(number)"
        }
    }

    private static func join(_ label: String, name: String, _ number: String) -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        return "\(label): " + [n, number].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// «+7 916 123-45-67» при любой записи, «8 916…» тоже; то, что на номер не похоже, остаётся как написано.
    static func international(_ raw: String, country: TelCountry) -> String {
        let full = TelFormat.full(raw, country: country)
        return full.isEmpty ? raw : TelFormat.format("+" + full, country: country)
    }

    /// Клиент строкой без номера, вписанного в неё же («Ирина +7 916…» → «Ирина»).
    static func clientName(_ contact: String, removing phone: String) -> String {
        let edge = CharacterSet(charactersIn: "·,;|—-").union(.whitespacesAndNewlines)
        return contact.replacingOccurrences(of: phone, with: "").trimmingCharacters(in: edge)
    }
}
