import Foundation

/// Листы мудборда — что в них стоит и что делает тап (веб `askPick` шестерёнки, `#mbAddSheet`,
/// `#mbNewSheet`, `#mbBoardSheet`, `#mbItemSheet`; итерация 28, шаг 5в). Чистые функции, без экрана.
public enum MbSheets {
    // MARK: меню шестерёнки

    /// Пункты меню подборки в порядке веба (L23254).
    public enum MenuItem: Sendable, Equatable { case sort, cover, pick, rename, newFolder, merge, delete }

    /// «Выбрать обложку» и «Выбрать» — только когда в папке есть кадры; «Новая папка» и «Объединить с…» —
    /// только у жанровой (у съёмочной подборки чужого набора нет), «Объединить» — если есть с кем.
    public static func menu(_ b: RefBoard, frames: Int, mergeTargets: Int) -> [MenuItem] {
        var out: [MenuItem] = [.sort]
        if frames > 0 { out += [.cover, .pick] }
        out.append(.rename)
        if b.kind == .tpl {
            out.append(.newFolder)
            if mergeTargets > 0 { out.append(.merge) }
        }
        out.append(.delete)
        return out
    }

    /// Ключи подписей порядка (веб `SORT_KEYS`).
    public static let sortKeys = ["mb.sortManual", "mb.sortNewest", "mb.sortByTag"]

    /// С кем можно слить: сперва папки своего жанра, потом папки чужих жанров; подборки съёмок не годятся
    /// (веб `mbMergeTargets`).
    public static func mergeTargets(of b: RefBoard, in lib: RefLibrary) -> [RefBoard] {
        guard b.kind == .tpl else { return [] }
        let own = lib.folders(ofGenre: b.genre ?? "").filter { $0.id != b.id }
        let other = lib.boards.filter { $0.kind == .tpl && $0.genre != b.genre }
        return own + other
    }

    /// «N переедут в …» — сколько кадров `from` ещё не лежат в `to` (веб `confirmMbMerge`).
    public static func mergeMoving(_ from: RefBoard, into to: RefBoard) -> Int {
        from.items.filter { !to.items.contains($0) }.count
    }

    // MARK: «Добавить в…» / «Переместить…»

    /// Строка листа: подборка либо жанр без подборки (тап заводит её).
    public struct AddRow: Sendable, Equatable {
        public enum Target: Sendable, Equatable { case board(String), newGenre(String) }
        public var target: Target
        public var title: String
        /// Кадр уже лежит здесь (только в режиме одного кадра): галочка, тап снимает.
        public var checked: Bool
    }

    /// Строки листа: подборки съёмок с кадрами, папки включённых жанров («Жанр · папка»), потом включённые
    /// жанры без папки (веб `renderMbAddList`, `mbAllFolders`, `mbFreeGenres`). `excluding` — папка, из которой
    /// берут пачку: её в списке нет (ошибка веба 25: тап по ней ничего не делает; решение 28: не показывать).
    public static func addRows(_ lib: RefLibrary, genresOn: [String], shot: String?, excluding: String?,
                               shootTitle: (RefBoard) -> String?, genreName: (String) -> String) -> [AddRow] {
        var rows: [AddRow] = []
        for b in lib.boards where b.kind == .shoot && !b.items.isEmpty && b.id != excluding {
            guard let title = shootTitle(b) else { continue }
            rows.append(AddRow(target: .board(b.id), title: title, checked: shot.map(b.items.contains) ?? false))
        }
        var haveFolder = Set<String>()
        for b in lib.boards where b.kind == .tpl {
            guard let g = b.genre, genresOn.contains(g) else { continue }
            haveFolder.insert(g)
            if b.id == excluding { continue }
            rows.append(AddRow(target: .board(b.id), title: genreName(g) + (b.name.map { " · " + $0 } ?? ""),
                               checked: shot.map(b.items.contains) ?? false))
        }
        for g in genresOn where !haveFolder.contains(g) {
            rows.append(AddRow(target: .newGenre(g), title: genreName(g), checked: false))
        }
        return rows
    }

    // MARK: «Новая подборка»

    /// Что делает тап по жанру (веб `openMbNew`): есть папки — спросить имя новой; нет — открыть пустую основную.
    public enum NewAction: Sendable, Equatable { case askFolderName, openEmpty }

    public static func newAction(genre: String, in lib: RefLibrary) -> NewAction {
        lib.folders(ofGenre: genre).isEmpty ? .openEmpty : .askFolderName
    }

    // MARK: лист кадра

    /// Чипы тегов листа кадра: сперва слова жанра, потом свои слова кадра, которых там нет — порядок не
    /// прыгает, когда подсказанное слово снимают и ставят (веб `renderMbItemSheet`).
    public static func itemTags(_ f: RefFrame, genre: String?) -> [String] {
        let suggest = RefFolders.genreTags[genre ?? ""] ?? RefFolders.defaultTags
        let mine = f.tags.map(RefFolders.code)
        var out = suggest
        for c in mine where !out.contains(c) { out.append(c) }
        return out
    }

    /// Слово стоит на кадре (по коду).
    public static func hasTag(_ f: RefFrame, _ code: String) -> Bool { f.tags.contains { RefFolders.code($0) == code } }
}
