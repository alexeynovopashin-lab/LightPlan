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
    fileprivate func isUsedByForeign(_ shotId: String) -> Bool {
        foreignBoards.contains { v in
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

    /// Что помнит «Вернуть» после «Объединить» (веб `mbMergeBoards`): сама исчезающая подборка,
    /// её место в списке и то, чем был `to.items`. Воскрешать по новому `id` нельзя — оборвались бы
    /// ссылки на старый.
    public struct MergeUndo: Sendable, Hashable {
        public var from: RefBoard
        public var fromIndex: Int
        public var toId: String
        public var toItems: [String]
        public var toMt: Double?
    }

    /// Слепок для отката; снимать до `merge`. Нет обеих подборок или они одна — `nil`.
    public func mergeUndo(_ fromId: String, into toId: String) -> MergeUndo? {
        guard fromId != toId, let i = boards.firstIndex(where: { $0.id == fromId }), let to = board(toId) else { return nil }
        return MergeUndo(from: boards[i], fromIndex: i, toId: toId, toItems: to.items, toMt: to.mt)
    }

    /// Вернуть подборку на место, а у целевой — убрать то, что принесло слияние (кадры исчезнувшей,
    /// которых у целевой не было). Правки за эти секунды — кадр, положенный в целевую, или снятый из
    /// неё, — остаются (ревью GPT к d0535cd; веб возвращал старый список целиком и затирал их).
    /// Целевую могли удалить — тогда возвращается только исчезнувшая. Ответ — вернулась ли она.
    @discardableResult
    public mutating func undoMerge(_ m: MergeUndo) -> Bool {
        if let i = boards.firstIndex(where: { $0.id == m.toId }) {
            let brought = Set(m.from.items).subtracting(m.toItems)
            boards[i].items.removeAll { brought.contains($0) }
            boards[i].mt = m.toMt
        }
        guard !boards.contains(where: { $0.id == m.from.id }) else { return false }
        boards.insert(m.from, at: min(m.fromIndex, boards.count))
        return true
    }

    /// Новая папка в жанре — всегда со своим именем (веб `boardAddFolder`): безымянных
    /// папок в одном жанре не отличить. Пустое имя — ничего не делает (веб `mbNewFolder`).
    @discardableResult
    public mutating func addFolder(genre: String, name: String, id: String, now: Double? = nil) -> RefBoard? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !genre.isEmpty else { return nil }
        let b = RefBoard(id: id, kind: .tpl, genre: genre, name: n, mt: now)
        boards.append(b)
        return b
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

// MARK: - Листы мудборда (итерация 28, шаг 5в)

extension RefLibrary {
    /// Кадр лежит в какой-то другой подборке, кроме этой (веб: `boards.some(o !== b && boardHas(o, id))`).
    /// Сырые подборки неизвестного рода тоже считаются — их ссылку рвать нельзя.
    public func isUsed(_ shotId: String, except boardId: String) -> Bool {
        boards.contains { $0.id != boardId && $0.items.contains(shotId) } || isUsedByForeign(shotId)
    }

    /// Сколько кадров подборки уйдут насовсем вместе с ней — лежат только здесь (веб `openMbBoardSheet`, `lone`).
    public func loneCount(_ boardId: String) -> Int {
        guard let b = board(boardId) else { return 0 }
        return b.items.filter { !isUsed($0, except: boardId) }.count
    }

    /// Порядок папки: 0 вручную, 1 новые сверху, 2 по разделу; другое число не пишется (веб `b.sort = i`).
    @discardableResult
    public mutating func setSort(_ sort: Int, of boardId: String, now: Double? = nil) -> Bool {
        guard (0...2).contains(sort), let i = boards.firstIndex(where: { $0.id == boardId }) else { return false }
        boards[i].sort = sort
        if let now { boards[i].mt = now }
        return true
    }

    /// Обложка: id кадра, лежащего в подборке, или `nil` — «Автоматически» (веб `b.cover = …`).
    /// Кадр не из этой подборки обложкой не становится.
    @discardableResult
    public mutating func setCover(_ shotId: String?, of boardId: String, now: Double? = nil) -> Bool {
        guard let i = boards.firstIndex(where: { $0.id == boardId }) else { return false }
        if let shotId, !boards[i].items.contains(shotId) { return false }
        boards[i].cover = shotId
        if let now { boards[i].mt = now }
        return true
    }

    /// Кадры, что можно поставить обложкой: только с картинкой, в порядке подборки (веб `r.im`).
    public func coverCandidates(_ boardId: String) -> [RefFrame] {
        guard let b = board(boardId) else { return [] }
        return MbFolderView.frames(of: b, in: shots).filter { !($0.im ?? "").isEmpty }
    }

    /// Имя подборки: пробелы по краям срезаются, пусто — имя снято (у папки жанра это значит
    /// «зовётся жанром», веб `b.name = name || null`).
    @discardableResult
    public mutating func rename(_ boardId: String, to name: String, now: Double? = nil) -> Bool {
        guard let i = boards.firstIndex(where: { $0.id == boardId }) else { return false }
        let n = name.trimmingCharacters(in: .whitespaces)
        boards[i].name = n.isEmpty ? nil : n
        if let now { boards[i].mt = now }
        return true
    }

    /// Основная папка жанра — первая; нет ни одной — заводится пустая с этим `id` (веб `boardTpl(g, true)`).
    /// Ответ — `id` основной папки.
    @discardableResult
    public mutating func ensureGenreBoard(_ genre: String, id: String, now: Double? = nil) -> String {
        if let b = folders(ofGenre: genre).first { return b.id }
        boards.append(RefBoard(id: id, kind: .tpl, genre: genre, mt: now))
        return id
    }

    /// Слово на кадре: стоит (по коду) — снимается со всех записей, не стоит — добавляется кодом.
    /// Старое русское слово («Пара») и код (`couple`) для кадра одно слово. Ответ — стоит ли теперь.
    @discardableResult
    public mutating func toggleTag(_ tag: String, on shotId: String, now: Double? = nil) -> Bool {
        guard let i = shots.firstIndex(where: { $0.id == shotId }) else { return false }
        let code = RefFolders.code(tag)
        let had = shots[i].tags.contains { RefFolders.code($0) == code }
        if had { shots[i].tags.removeAll { RefFolders.code($0) == code } } else { shots[i].tags.append(code) }
        if let now { shots[i].mt = now }
        return !had
    }

    /// Свой тег из поля: слово приводится к известному коду без учёта регистра, иначе остаётся строчным
    /// (веб `tagCanon`). Уже стоящий не дублируется. Пустое — ничего.
    @discardableResult
    public mutating func addTag(_ word: String, to shotId: String, tagName: (String) -> String, now: Double? = nil) -> Bool {
        let w = RefFolders.canon(word.replacingOccurrences(of: ",", with: ""), tagName: tagName)
        guard !w.isEmpty, let i = shots.firstIndex(where: { $0.id == shotId }),
              !shots[i].tags.contains(where: { RefFolders.code($0) == w }) else { return false }
        shots[i].tags.append(w)
        if let now { shots[i].mt = now }
        return true
    }
}
