import Foundation

/// Разбор и запись отметок времени снимка (веб пишет их `.toISOString()`,
/// формат `docs/17` § 6). Общее место для полей вроде `deliveredAt`,
/// `questSent`, `exported` — все они ISO-строка с миллисекундами и `Z`, но
/// читаем и без миллисекунд: старый файл обмена мог быть short-form.
public enum SnapshotDate {
    // Не статический кэш: `ISO8601DateFormatter` не `Sendable`, а `Store` и
    // `Codable`-разбор снимка могут звать разбор с разных задач. Своя
    // копия на вызов дешевле, чем актор ради форматтера.
    private static func formatter(fractional: Bool) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return f
    }

    /// `nil` — строка не ISO-8601: пустая, повреждённая или неузнанная.
    public static func parse(_ s: String) -> Date? {
        formatter(fractional: true).date(from: s) ?? formatter(fractional: false).date(from: s)
    }

    /// Каноническая запись — с миллисекундами, как `.toISOString()`.
    public static func format(_ d: Date) -> String {
        formatter(fractional: true).string(from: d)
    }
}
