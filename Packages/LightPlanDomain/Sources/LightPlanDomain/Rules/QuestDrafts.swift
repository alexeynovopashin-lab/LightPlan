import Foundation

/// Черновики ответов клиента: пришедший ответ не пропадает вместе с закрытой формой (веб держал его только в
/// полях формы — ошибка веба А3; итерация 28, шаг 8). Хранится сам код ответа, не разобранное: на форму его
/// накладывает `QuestMerge.apply`, а повторное наложение заметки не дублирует. Экрана здесь нет.
public struct QuestDrafts: Sendable, Equatable, Codable {
    public struct Draft: Sendable, Equatable, Codable {
        public var code: String
        public var savedAt: Date
        public init(code: String, savedAt: Date) { self.code = code; self.savedAt = savedAt }
    }

    /// Ответ без записи (новая встреча): у неё ещё нет знака.
    public static let newKey = "_new"
    /// Сколько дней черновик живёт: в нём телефоны клиента, копить их без срока незачем.
    public static let lifetimeDays = 30

    public private(set) var items: [String: Draft]

    public init(items: [String: Draft] = [:]) { self.items = items }

    static func key(_ recordId: String?) -> String {
        guard let recordId, !recordId.isEmpty else { return newKey }
        return recordId
    }

    /// Положить ответ; новый ответ той же записи заменяет прежний.
    public mutating func hold(code: String, for recordId: String?, at now: Date) {
        items[Self.key(recordId)] = Draft(code: code, savedAt: now)
    }

    public func pending(for recordId: String?) -> Draft? { items[Self.key(recordId)] }

    /// Ответ принят (запись сохранена) или отброшен фотографом.
    public mutating func release(_ recordId: String?) { items[Self.key(recordId)] = nil }

    /// Убрать давнее; `true` — что-то ушло (нужно перезаписать файл).
    @discardableResult
    public mutating func prune(now: Date) -> Bool {
        let limit = now.addingTimeInterval(-Double(Self.lifetimeDays) * 86_400)
        let keep = items.filter { $0.value.savedAt >= limit }
        defer { items = keep }
        return keep.count != items.count
    }
}
