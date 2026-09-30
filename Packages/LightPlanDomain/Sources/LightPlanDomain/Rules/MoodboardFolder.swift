import Foundation

/// Папка мудборда — экран одной подборки (веб `renderMbFolder`, L22897): разделы, поиск,
/// порядок, выбор кадров, подписи. Чистые функции над кадрами подборки, без экрана.
public enum MbFolderView {
    /// Чип раздела: слово и сколько кадров его несут (у веба — `.rf-tag .n`).
    public struct Section: Sendable, Equatable {
        public var tag: String
        public var n: Int
        public init(tag: String, n: Int) { self.tag = tag; self.n = n }
    }

    /// Кадры подборки в порядке `items[]`; ссылка на кадр, которого нет в фонде, пропускается
    /// (веб `boardShots`).
    public static func frames(of board: RefBoard, in shots: [RefFrame]) -> [RefFrame] {
        var byId: [String: RefFrame] = [:]
        for s in shots { byId[s.id] = s }
        return board.items.compactMap { byId[$0] }
    }

    /// Разделы папки — только использованные: сперва слова жанра, потом чужие (веб `#mbTags`).
    /// Слова нет ни на одном кадре — рейла нет вовсе.
    public static func sections(_ list: [RefFrame], genre: String?) -> [Section] {
        RefFolders.used(in: list, genre: genre).map { code in
            Section(tag: code, n: list.filter { $0.tags.contains { RefFolders.code($0) == code } }.count)
        }
    }

    /// Выбранный раздел, которого в папке больше нет, сбрасывается (веб: `mbTag` → `null`).
    public static func activeTag(_ tag: String?, in sections: [Section]) -> String? {
        guard let tag, sections.contains(where: { $0.tag == tag }) else { return nil }
        return tag
    }

    /// Что ищется в кадре папки (веб `mbFolderHay`): названия слов, заметка кадра, у ссылки —
    /// сайт и адрес. Названий подборок нет — внутри папки подборка одна.
    static func haystack(_ f: RefFrame, tagName: (String) -> String) -> String {
        var bits = f.tags.map(tagName)
        if case .string(let n)? = f.extra["name"], !n.isEmpty { bits.append(n) }
        if f.kind == .link, let url = f.url { bits.append(RefLink.host(url) ?? ""); bits.append(url) }
        return bits.joined(separator: " ").lowercased()
    }

    /// Порядок папки (веб `board.sort`): 0 вручную — как в `items[]`, 1 новые сверху — разворот,
    /// 2 по разделу — по первому в алфавите названию слова кадра; кадр без слова — в конец.
    public static func ordered(_ list: [RefFrame], sort: Int, tagName: (String) -> String) -> [RefFrame] {
        switch sort {
        case 1: return list.reversed()
        case 2:
            func first(_ f: RefFrame) -> String? { f.tags.map(tagName).sorted().first }
            // Устойчивая: равные остаются в порядке подборки (порядок JS-`sort` устойчив).
            return list.enumerated().sorted { a, b in
                switch (first(a.element), first(b.element)) {
                case (nil, nil): return a.offset < b.offset
                case (nil, _): return false
                case (_, nil): return true
                case (let x?, let y?): return x == y ? a.offset < b.offset : x < y
                }
            }.map(\.element)
        default: return list
        }
    }

    /// Кадры на экране: раздел и поле вместе, потом порядок папки (веб `shown`).
    public static func shown(_ list: [RefFrame], tag: String?, query: String, sort: Int,
                             tagName: (String) -> String) -> [RefFrame] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let kept = list.filter { f in
            if let tag, !f.tags.contains(where: { RefFolders.code($0) == tag }) { return false }
            return q.isEmpty || haystack(f, tagName: tagName).contains(q)
        }
        return ordered(kept, sort: sort, tagName: tagName)
    }

    public static func isFiltered(tag: String?, query: String) -> Bool {
        tag != nil || !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Подпись над сеткой (веб `#mbGridLabel`): в выборе — «Выбрано: N», под фильтром — «3 из 10
    /// кадров», иначе «10 кадров»; у пустой папки её нет.
    public enum GridLabel: Sendable, Equatable {
        case hidden
        case count(Int)
        case some(shown: Int, total: Int)
        case picked(Int)
    }

    public static func gridLabel(total: Int, shown: Int, filtered: Bool, picked: Int?) -> GridLabel {
        if total == 0 { return .hidden }
        if let picked { return .picked(picked) }
        return filtered ? .some(shown: shown, total: total) : .count(total)
    }

    /// Плитка «+» и кнопки «Фото/Ссылка» — только в спокойном виде без фильтра и выбора
    /// (веб `addTile`: нет ни разделов, ни поиска, ни выбора).
    public static func showsAddTile(filtered: Bool, picking: Bool, shownCount: Int) -> Bool {
        !filtered && !picking && shownCount > 0
    }

    /// Высота плитки при ширине колонки: ссылка без картинки — квадрат, остальное — по
    /// пропорциям кадра (4:3, когда размеров нет).
    public static func tileHeight(_ f: RefFrame, width: Double) -> Double {
        isBareLink(f) ? width : RefColumns.height(w: f.w, h: f.h, width: width)
    }

    /// Ссылка без картинки — плитка-надпись «сайт / хвост пути» (веб `k === "link" && !im`).
    public static func isBareLink(_ f: RefFrame) -> Bool { f.kind == .link && f.im == nil }

    /// Кадры просмотрщика: только картинки, в порядке сетки на экране (веб `imgList`).
    public static func viewerList(_ shown: [RefFrame]) -> [RefFrame] { shown.filter(\.isViewable) }
}

/// Выбор кадров в папке (веб `mbPicked`): режим живёт, пока открыта папка; «все» — это всё, что
/// сейчас на глазах, а не вся подборка.
public struct MbPick: Sendable, Equatable {
    public private(set) var ids: [String] = []
    public init(ids: [String] = []) { self.ids = ids }

    public var count: Int { ids.count }
    public func contains(_ id: String) -> Bool { ids.contains(id) }

    public mutating func toggle(_ id: String) {
        if let i = ids.firstIndex(of: id) { ids.remove(at: i) } else { ids.append(id) }
    }

    /// Отмечено всё, что на глазах, и там что-то есть (веб `allOn`).
    public func allOn(shown: [String]) -> Bool { !shown.isEmpty && shown.allSatisfy(ids.contains) }

    /// «Выбрать все» / «Снять все»: всё, что на глазах, либо ничего.
    public mutating func toggleAll(shown: [String]) { ids = allOn(shown: shown) ? [] : shown }
}

extension RefLibrary {
    /// «Убрать N» в выборе (веб `mbSelDel`): снять кадры с подборки; кадр, что больше нигде не
    /// лежит, уходит из фонда совсем; опустевшая подборка съёмки без имени и обложки исчезает.
    /// Ответ — кадры, ушедшие насовсем.
    @discardableResult
    public mutating func remove(_ shotIds: [String], from boardId: String, now: Double? = nil) -> [String] {
        var gone: [String] = []
        for id in shotIds where take(id, from: boardId, now: now) {   // чужого кадра, что в подборке не лежал, не трогаем
            if !isUsed(id), dropShot(id) { gone.append(id) }
        }
        prune(boardId)
        return gone
    }
}
