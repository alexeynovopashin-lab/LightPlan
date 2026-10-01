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

    /// Ответ, который ждёт фотографа: чья запись (`nil` — ответ без записи, откроется новой встречей) и когда пришёл.
    public struct Waiting: Sendable, Equatable {
        public var recordId: String?
        public var savedAt: Date
    }

    /// Ответы, ждущие на «Съёмках» (значок «пришёл ответ», слово Алексея 01.10: «значок нужен»): те, что пришли, пока была
    /// открыта форма другой записи (шаг 9). Черновик записи, которой больше нет, не считается — открывать нечего.
    /// Давние первыми: тап по значку ведёт к тому, что ждёт дольше всех.
    public func waiting(existing ids: Set<String>) -> [Waiting] {
        items.compactMap { key, d -> Waiting? in
            if key == Self.newKey { return Waiting(recordId: nil, savedAt: d.savedAt) }
            return ids.contains(key) ? Waiting(recordId: key, savedAt: d.savedAt) : nil
        }
        .sorted { $0.savedAt != $1.savedAt ? $0.savedAt < $1.savedAt : ($0.recordId ?? "") < ($1.recordId ?? "") }
    }

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
