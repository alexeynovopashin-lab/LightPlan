import Foundation
import LightPlanCore

/// Фонд кадров и подборки (веб `shots[]`, `boards[]`, L25835–26030) и правила
/// переноса. Кадр один — лежит в фонде, подборка держит только ссылки на него
/// (`items`); «переложить» — правка ссылок, копий нет. Правила веба:
/// дубль в одной подборке запрещён (`boardPut`); перенос в ту же подборку —
/// ничего не делает; кадр уходит совсем, только когда нигде не лежит.
/// Записи, которых Swift не разобрал (кадр без `id`, подборка неизвестного рода),
/// лежат сырыми и возвращаются при записи — импорт ничего не стирает.
public struct RefLibrary: Sendable, Hashable {
    public var shots: [RefFrame]
    public var boards: [RefBoard]
    private var foreignShots: [JSONValue] = []
    private var foreignBoards: [JSONValue] = []

    public init(shots: [RefFrame] = [], boards: [RefBoard] = []) {
        self.shots = shots; self.boards = boards
    }

    /// Из `Snapshot.extra` (`shots`, `boards`).
    public init(extra: [String: JSONValue]) {
        self.shots = []; self.boards = []
        if case .array(let a)? = extra["shots"] {
            for v in a { if let f = RefFrame(json: v) { shots.append(f) } else { foreignShots.append(v) } }
        }
        if case .array(let a)? = extra["boards"] {
            for (i, v) in a.enumerated() { if let b = RefBoard(json: v, position: i) { boards.append(b) } else { foreignBoards.append(v) } }
        }
    }

    /// Записать обратно; чужие ключи `extra` не трогаются.
    public func write(into extra: inout [String: JSONValue]) {
        extra["shots"] = .array(shots.map(\.json) + foreignShots)
        extra["boards"] = .array(boards.map(\.json) + foreignBoards)
    }

    // MARK: - Запросы

    public func board(_ id: String) -> RefBoard? { boards.first { $0.id == id } }
    public func shot(_ id: String) -> RefFrame? { shots.first { $0.id == id } }
    /// Кадр лежит хотя бы в одной подборке (веб `shotUsed`).
    /// Сырые подборки неизвестного рода тоже держат кадр: их ссылку рвать нельзя.
    public func isUsed(_ shotId: String) -> Bool {
        boards.contains { $0.items.contains(shotId) } || foreignBoards.contains { v in
            guard case .object(let o) = v, case .array(let a)? = o["items"] else { return false }
            return a.contains(.string(shotId))
        }
    }
    /// Папки жанра в порядке полки; основная — первая (веб `boardsOfGenre`, `boardTpl`).
    public func folders(ofGenre g: String) -> [RefBoard] { boards.filter { $0.kind == .tpl && $0.genre == g } }

    // MARK: - Операции над `items[]`

    /// Положить кадр в подборку (веб `boardPut`). Уже лежит или подборки нет — `false`, ничего не меняется.
    @discardableResult
    public mutating func put(_ shotId: String, into boardId: String, at: Int? = nil, now: Double? = nil) -> Bool {
        guard !shotId.isEmpty, let i = boards.firstIndex(where: { $0.id == boardId }),
              !boards[i].items.contains(shotId) else { return false }
        if let at, at >= 0, at <= boards[i].items.count { boards[i].items.insert(shotId, at: at) }
        else { boards[i].items.append(shotId) }
        if let now { boards[i].mt = now }
        return true
    }

    /// Снять ссылку (веб `boardTake`); сам кадр остаётся в фонде.
    @discardableResult
    public mutating func take(_ shotId: String, from boardId: String, now: Double? = nil) -> Bool {
        guard let i = boards.firstIndex(where: { $0.id == boardId }),
              let at = boards[i].items.firstIndex(of: shotId) else { return false }
        boards[i].items.remove(at: at)
        if let now { boards[i].mt = now }
        return true
    }

    /// Переложить пачку (веб «Добавить в…» / «Переместить…», L22228–22240): положить в
    /// целевую; при переносе — снять с исходной и убрать её, если опустела. В ту же
    /// подборку — ничего не делает. Ответ — id, что впрямь легли в целевую.
    @discardableResult
    public mutating func move(_ shotIds: [String], from: String?, to: String, remove: Bool, now: Double? = nil) -> [String] {
        guard board(to) != nil else { return [] }
        if remove, from == to { return [] }              // в ту же подборку — ничего, что бы ни лежало в списке
        var added: [String] = []
        for id in shotIds where put(id, into: to, now: now) { added.append(id) }
        if remove, let from, board(from) != nil {
            for id in shotIds { take(id, from: from, now: now) }
            prune(from)
        }
        return added
    }

    /// Опустевшая подборка съёмки исчезает, если у неё нет ни имени, ни обложки (веб `boardPrune`);
    /// жанровую пустой не подметаем — это вещь человека с первого тычка.
    @discardableResult
    public mutating func prune(_ boardId: String) -> Bool {
        guard let b = board(boardId), b.kind != .tpl, b.items.isEmpty, b.name == nil, b.cover == nil else { return false }
        boards.removeAll { $0.id == boardId }
        return true
    }

    /// Кадр совсем: из фонда и из всех подборок (веб `shotDrop`). Блоб, облако и
    /// надгробие — забота вызывающего (в нативе картинок нет до 30).
    @discardableResult
    public mutating func dropShot(_ shotId: String) -> Bool {
        guard shots.contains(where: { $0.id == shotId }) else { return false }
        for i in boards.indices { boards[i].items.removeAll { $0 == shotId } }
        shots.removeAll { $0.id == shotId }
        return true
    }

    /// Удалить подборку; кадры, что больше нигде не лежат, уходят насовсем (веб
    /// `dropBoardWithShots`). Ответ — id ушедших кадров (для подписи «N только здесь»).
    @discardableResult
    public mutating func dropWithShots(_ boardId: String) -> [String] {
        guard let b = board(boardId) else { return [] }
        boards.removeAll { $0.id == boardId }
        var gone: [String] = []
        for id in b.items where !isUsed(id) && dropShot(id) { gone.append(id) }
        return gone
    }

    /// «Объединить с…» (веб `mbMergeBoards`): кадры `from`, которых нет в `into`,
    /// переходят в конец, `from` исчезает (кадры остаются в фонде). Ответ — перешедшие.
    @discardableResult
    public mutating func merge(_ fromId: String, into toId: String, now: Double? = nil) -> [String] {
        guard fromId != toId, let from = board(fromId), board(toId) != nil else { return [] }
        var moved: [String] = []
        for id in from.items where put(id, into: toId, now: now) { moved.append(id) }
        boards.removeAll { $0.id == fromId }
        return moved
    }

    // MARK: - Первый запуск

    /// Пустая жанровая папка на каждый включённый жанр, один раз (веб `mbSeeded`,
    /// L26793): признак лежит в снимке под тем же ключом. Ответ — менялось ли что-то
    /// (тогда снимок нужно записать сразу).
    public static func seedGenreFolders(in extra: inout [String: JSONValue], genres: [String],
                                        newId: () -> String, now: Double? = nil) -> Bool {
        if case .bool(true)? = extra["mbSeeded"] { return false }
        var lib = RefLibrary(extra: extra)
        for g in genres where lib.folders(ofGenre: g).isEmpty {
            lib.boards.append(RefBoard(id: newId(), kind: .tpl, genre: g, mt: now))
        }
        lib.write(into: &extra)
        extra["mbSeeded"] = .bool(true)
        return true
    }
}
