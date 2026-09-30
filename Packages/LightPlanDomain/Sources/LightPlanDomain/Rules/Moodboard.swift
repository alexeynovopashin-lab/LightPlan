import Foundation
import LightPlanCore

/// Плитка ленты мудборда (веб `mbFolders`, описатель `f`): подборка съёмки или полка
/// жанра. Жанр — одна плитка, сколько бы папок в нём ни лежало (решение Алексея 30.08.2026);
/// `boardId` — основная папка (первая), `boardIds` — все папки за плиткой.
public struct MbFolder: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable { case shoot, genre }
    public var kind: Kind
    public var boardId: String
    public var boardIds: [String]
    public var sessionId: String?
    public var genre: String?
    /// Кадры за плиткой (кружок на обложке): у полки — по всем папкам, только найденные в фонде.
    public var frameCount: Int
    public var id: String { boardId }

    public init(kind: Kind, boardId: String, boardIds: [String], sessionId: String? = nil,
                genre: String? = nil, frameCount: Int = 0) {
        self.kind = kind; self.boardId = boardId; self.boardIds = boardIds
        self.sessionId = sessionId; self.genre = genre; self.frameCount = frameCount
    }
}

/// Цвет неба обложки: пара из восьми, выбор — хэш знака подборки (веб `mbSkyIdx`).
public enum MbSky {
    public static let pairCount = 8

    /// FNV-1a, 32 бита, по кодам знаков (UTF-16, как `charCodeAt`); берутся старшие
    /// биты — у коротких знаков младшие похожи (комментарий веба, L22296).
    public static func index(_ id: String) -> Int {
        var h: UInt32 = 2_166_136_261
        for u in id.utf16 {
            h ^= UInt32(u)
            h = h &* 16_777_619
        }
        return Int((h >> 16) % UInt32(pairCount))
    }
}

/// Мудборд: что стоит на ленте, в галерее, на полке; поиск и чипы разделов.
public enum Moodboard {
    /// Плиток в ряду полосы (веб `MB_STRIP_MAX`).
    public static let stripMax = 6

    // MARK: - Состав ленты

    /// Жанры, у которых есть плитка: пустой список снимка — включены все (веб: «изначально
    /// включены все»; `genresOn` пуст только у файла, где человек ещё не выбирал).
    public static func enabledGenres(_ saved: [Genre]) -> [Genre] {
        saved.isEmpty ? Genre.allCases : Genre.allCases.filter(saved.contains)
    }

    /// Плитки в порядке веба: подборки съёмок с кадрами (по порядку списка съёмок),
    /// затем по одной полке на каждый включённый жанр (по порядку папок в `boards[]`).
    /// Пустая подборка съёмки на ленте не стоит, пустая папка жанра — стоит.
    public static func folders(library: RefLibrary, sessions: [Session], genresOn: Set<String>) -> [MbFolder] {
        let known = Set(library.shots.map(\.id))
        func count(_ b: RefBoard) -> Int { b.items.filter(known.contains).count }
        var out: [MbFolder] = []
        for s in sessions {
            guard let b = library.boards.first(where: { $0.kind == .shoot && $0.sid == s.id }),
                  !b.items.isEmpty else { continue }
            out.append(MbFolder(kind: .shoot, boardId: b.id, boardIds: [b.id], sessionId: s.id,
                                genre: b.genre, frameCount: count(b)))
        }
        var seen = Set<String>()
        for b in library.boards where b.kind == .tpl {
            guard let g = b.genre, genresOn.contains(g), seen.insert(g).inserted else { continue }
            let shelf = library.folders(ofGenre: g)
            out.append(MbFolder(kind: .genre, boardId: shelf[0].id, boardIds: shelf.map(\.id), genre: g,
                                frameCount: shelf.reduce(0) { $0 + count($1) }))
        }
        return out
    }

    private static func key(_ d: CivilDate) -> Int { d.year * 10_000 + d.month * 100 + d.day }

    private static func dayOf(_ f: MbFolder, _ sessions: [Session]) -> Int? {
        sessions.first { $0.id == f.sessionId }.map { key($0.day) }
    }

    /// «Съёмки» на полосе: ближайшая первой, прошедшие — в хвост по убыванию даты (веб L22690).
    public static func stripShoots(_ folders: [MbFolder], sessions: [Session], today: CivilDate) -> [MbFolder] {
        let t = key(today)
        let list = folders.filter { $0.kind == .shoot }.compactMap { f in dayOf(f, sessions).map { (f, $0) } }
        let ahead = list.filter { $0.1 >= t }.sorted { $0.1 < $1.1 }
        let past = list.filter { $0.1 < t }.sorted { $0.1 > $1.1 }
        return (ahead + past).map(\.0)
    }

    /// «Съёмки» в галерее — по убыванию даты (веб `renderMbTiles`).
    public static func galleryShoots(_ folders: [MbFolder], sessions: [Session]) -> [MbFolder] {
        folders.filter { $0.kind == .shoot }.compactMap { f in dayOf(f, sessions).map { (f, $0) } }
            .sorted { $0.1 > $1.1 }.map(\.0)
    }

    // MARK: - Ряд полосы

    /// Что стоит в ряду: показанные плитки, скрытые и число на плитке «Все» (`nil` — влезло).
    /// У «Подборок» одно место занято плиткой «+»; не влезло — последнее место отдаёт «Все».
    public static func row(_ list: [MbFolder], withAdd: Bool, max: Int = stripMax)
        -> (shown: [MbFolder], hidden: [MbFolder], badge: Int?) {
        let slots = max - (withAdd ? 1 : 0)
        let over = list.count - slots
        guard over > 0 else { return (list, [], nil) }
        let shown = Array(list.prefix(Swift.max(slots - 1, 0)))
        return (shown, Array(list.dropFirst(shown.count)), over + 1)
    }

    /// Мозаика плитки «Все»: до четырёх подборок — сначала скрытые, потом добор из всех
    /// (веб `mbMosaic`). Порядок «с картинкой впереди» веба здесь не нужен: картинок в
    /// нативе нет до 30 (решение 30.09, 1Б).
    public static func mosaic(hidden: [MbFolder], all: [MbFolder]) -> [MbFolder] {
        var seen = Set<String>(), out: [MbFolder] = []
        for f in hidden + all where seen.insert(f.boardId).inserted { out.append(f) }
        return Array(out.prefix(4))
    }

    // MARK: - Вход в плитку

    public enum Target: Equatable, Sendable { case folder(String), shelf(String) }

    /// Жанр с несколькими папками открывается полкой, с одной — сразу кадрами (веб `openFolderOrShelf`).
    public static func openTarget(_ f: MbFolder, in library: RefLibrary) -> Target {
        if f.kind == .genre, let g = f.genre, library.folders(ofGenre: g).count > 1 { return .shelf(g) }
        return .folder(f.boardId)
    }

    public struct Shelf: Sendable, Equatable {
        public var genre: String
        public var folders: [RefBoard]
        public var frameCount: Int
    }

    /// Полка жанра: папки в порядке `boards[]`, основная первая; кадры — по всем (веб `renderMbShelf`).
    public static func shelf(_ library: RefLibrary, genre: String) -> Shelf {
        let fs = library.folders(ofGenre: genre)
        let known = Set(library.shots.map(\.id))
        return Shelf(genre: genre, folders: fs,
                     frameCount: fs.reduce(0) { $0 + $1.items.filter(known.contains).count })
    }

    /// Имя папки на полке: своё, а у основной — имя жанра.
    public static func title(of b: RefBoard, genreName: String) -> String { b.name ?? genreName }

    // MARK: - Галерея: чипы и поиск

    public struct TagCount: Sendable, Equatable { public var tag: String; public var n: Int }

    /// Все слова со всех кадров фонда: по убыванию счёта, потом по алфавиту (веб `mbAllTagCounts`).
    public static func tagCounts(_ shots: [RefFrame]) -> [TagCount] {
        var counts: [String: Int] = [:]
        for s in shots { for t in s.tags { counts[t, default: 0] += 1 } }
        return counts.map { TagCount(tag: $0.key, n: $0.value) }
            .sorted { $0.n != $1.n ? $0.n > $1.n : $0.tag.localizedCompare($1.tag) == .orderedAscending }
    }

    /// Выбранный чип, которого больше нет среди слов, сбрасывается (веб `renderMbTagRail`).
    public static func activeTag(_ tag: String?, in counts: [TagCount]) -> String? {
        guard let tag, counts.contains(where: { $0.tag == tag }) else { return nil }
        return tag
    }

    /// Поле и чип — два независимых входа; сетка кадров вместо плиток, когда включён любой.
    public static func isSearching(query: String, tag: String?) -> Bool {
        tag != nil || !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Что ищется в кадре (веб `mbShotHay`): названия слов на нынешнем языке (не коды),
    /// названия подборок, где кадр лежит, адрес и сайт ссылки.
    static func haystack(_ f: RefFrame, tagName: (String) -> String, boardTitles: [String]) -> String {
        var bits = f.tags.map(tagName) + boardTitles
        if f.kind == .link, let url = f.url { bits.append(RefLink.host(url) ?? ""); bits.append(url) }
        return bits.joined(separator: " ").lowercased()
    }

    /// Плоская сетка галереи (веб `renderMbSearchGrid`): слово-чип и строка поиска вместе.
    public static func search(_ shots: [RefFrame], query: String, tag: String?,
                              tagName: (String) -> String,
                              boardTitles: (RefFrame) -> [String]) -> [RefFrame] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return shots.filter { f in
            if let tag, !f.tags.contains(tag) { return false }
            if !q.isEmpty, !haystack(f, tagName: tagName, boardTitles: boardTitles(f)).contains(q) { return false }
            return true
        }
    }

    // MARK: - Прыжок

    /// Кнопка «вниз/вверх» нужна, когда прокрутки (высота содержимого минус окно) не меньше
    /// `0,6` окна (веб `jumpAttach`: `over < clientHeight * JUMP_MIN` — прячет). Короткому
    /// списку свайп быстрее.
    public static func jumpVisible(scrollable: Double, screen: Double) -> Bool { scrollable >= 0.6 * screen }

    /// Куда ведёт кнопка: у начала — вниз, за серединой — вверх (веб `toEnd`).
    public static func jumpGoesDown(offset: Double, scrollable: Double) -> Bool { offset < scrollable / 2 }
}
