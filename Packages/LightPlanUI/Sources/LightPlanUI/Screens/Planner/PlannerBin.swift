import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Корзина (итерация 22; веб `removeSession`, `restoreTrashed`, `#binClear`,
/// `removeBlock`). Удаление обратимо (инвариант 17): запись уходит в
/// `trashed` целиком, с местом в списке и временем удаления, и стирается
/// насовсем только «Очистить корзину» — после вопроса.
///
/// Чистые правки снимка: `AppModel` зовёт их и пишет снимок на диск.
enum Bin {
    /// Сколько живёт тень стёртой записи (веб `GRAVE_DAYS`): обмен устройств
    /// узнаёт по ней, что запись стёрта, а не потеряна.
    static let graveDays = 90

    /// Убрать запись в корзину (веб `removeSession`): новая — первой.
    @discardableResult
    static func trash(_ id: String, in s: inout Snapshot, now ms: Int64) -> Session? {
        guard let i = s.sessions.firstIndex(where: { $0.id == id }) else { return nil }
        let rec = s.sessions.remove(at: i)
        s.trashed.insert(TrashedItem(record: rec, index: i, deletedAt: ms), at: 0)
        return rec
    }

    /// Вернуть запись на её место (веб `restoreTrashed`). По знаку записи, а не
    /// по номеру в корзине: у веба полоса «Вернуть» возвращала `trashed[0]` —
    /// после возврата из листа корзины она подняла бы другую, старую запись.
    /// Возврат — событие со своим временем (`mt`), иначе обмен устройств
    /// увёз бы запись обратно: удаление новее правки. Тень, если приехала,
    /// снимается.
    @discardableResult
    static func restore(_ id: String, in s: inout Snapshot, now ms: Int64) -> Bool {
        guard let k = s.trashed.firstIndex(where: { $0.record.id == id }) else { return false }
        let t = s.trashed.remove(at: k)
        var rec = t.record
        rec.modifiedAt = ms
        s.sessions.insert(rec, at: min(max(0, t.index), s.sessions.count))
        unbury(id, in: &s)
        return true
    }

    /// «Очистить корзину» (веб `#binClear` после «Стереть»): каждой записи —
    /// тень на 90 дней, корзина пуста. Подборки стёртых съёмок (веб
    /// `dropSessionBoard`) — итерация 28: у Swift ещё нет типа подборок, они
    /// лежат в снимке как есть.
    static func clear(_ s: inout Snapshot, now ms: Int64) {
        for t in s.trashed { bury(t.record.id, in: &s, now: ms) }
        s.trashed = []
    }

    /// Убрать занятость (веб `removeBlock`). У веба это навсегда и без
    /// возврата; здесь — с полосой «Вернуть», как у съёмок (DECISIONS,
    /// итерация 22), поэтому занятость и её место возвращаются вызывающему.
    static func removeBlock(_ id: String, in s: inout Snapshot, now ms: Int64) -> (Block, Int)? {
        guard let i = s.blocks.firstIndex(where: { $0.id == id }) else { return nil }
        let b = s.blocks.remove(at: i)
        bury(id, in: &s, now: ms)
        return (b, i)
    }

    static func restoreBlock(_ b: Block, at i: Int, in s: inout Snapshot, now ms: Int64) {
        guard !s.blocks.contains(where: { $0.id == b.id }) else { return }
        var b = b
        b.modifiedAt = ms
        s.blocks.insert(b, at: min(max(0, i), s.blocks.count))
        unbury(b.id, in: &s)
    }

    // MARK: - Тени (веб `graves`, `bury`)

    static func bury(_ id: String, in s: inout Snapshot, now ms: Int64) {
        var g = graves(s)
        g.removeAll { graveId($0) == id }
        g.append(.object(["id": .string(id), "del": .number(Double(ms))]))
        s.extra["graves"] = .array(g)
    }

    static func unbury(_ id: String, in s: inout Snapshot) {
        var g = graves(s)
        let n = g.count
        g.removeAll { graveId($0) == id }
        if g.count != n { s.extra["graves"] = .array(g) }
    }

    private static func graves(_ s: Snapshot) -> [JSONValue] {
        if case .array(let g)? = s.extra["graves"] { return g }
        return []
    }

    private static func graveId(_ v: JSONValue) -> String? {
        if case .object(let o) = v, case .string(let id)? = o["id"] { return id }
        return nil
    }
}

/// Полоса «Вернуть» (веб `#undoBar`): 6 секунд после удаления, новое удаление
/// перезапускает срок. Держит то, что вернуть, а не номер в корзине.
public struct UndoOffer: Equatable, Sendable {
    public enum What: Equatable, Sendable {
        case session(id: String)
        case block(Block, index: Int)
    }
    public let what: What
    public let text: String
    /// Знак показа: одинаковый текст двух удалений подряд — два показа.
    public let token = UUID()

    public static let seconds: Double = 6
}

/// Заготовка листа «Занять время»: правится в листе и пишется только по
/// «Готово» (веб: закрыть подложкой — изменения пропадают).
public struct BlockDraft: Identifiable, Equatable, Sendable {
    public var block: Block
    public let editing: Bool
    public var id: String { block.id }
}
