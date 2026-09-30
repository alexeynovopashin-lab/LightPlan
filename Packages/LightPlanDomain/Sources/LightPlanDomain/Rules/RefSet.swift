import Foundation
import LightPlanCore

/// Кадр референса (веб `shots[]`): что нужно экрану — имя картинки `im`,
/// путь в облаке, ссылка. Байтов в файле обмена нет (итерация 27, справка).
public struct RefFrame: Sendable, Hashable {
    public enum Kind: String, Sendable { case img, link, doc }
    public var id: String
    public var kind: Kind
    public var im: String?
    public var path: String?
    public var url: String?
    public var tags: [String]
    /// Размеры картинки (веб `w`, `h`) — по ним плитка сетки берёт пропорции.
    public var w: Double?
    public var h: Double?
    /// Лежит в подборке этой съёмки (веб `own`), а не только в наборе жанра.
    public var own: Bool
    /// Отметка правки для слияния устройств (веб `mt`).
    public var mt: Double?
    /// Поля веба, которых Swift не знает (`pending`, новые): при записи уходят как пришли.
    public var extra: [String: JSONValue]

    public init(id: String, kind: Kind = .img, im: String? = nil, path: String? = nil,
                url: String? = nil, tags: [String] = [], w: Double? = nil, h: Double? = nil,
                own: Bool = false, mt: Double? = nil, extra: [String: JSONValue] = [:]) {
        self.id = id; self.kind = kind; self.im = im; self.path = path; self.url = url
        self.tags = tags; self.w = w; self.h = h; self.own = own; self.mt = mt; self.extra = extra
    }

    /// Открывается в просмотрщике (веб `openRefAt`): ссылка без своей картинки — в браузер;
    /// иначе нужно непустое имя блоба `im` или путь в облаке `path`. Пустая строка — не имя
    /// (веб проверяет `!r.im`); ссылка со своей картинкой (`og:image`) открывается как кадр.
    public var isViewable: Bool {
        let hasIm = !(im ?? "").isEmpty
        if kind == .link && !hasIm { return false }
        return hasIm || !(path ?? "").isEmpty
    }

    /// Чем плитка рисует кадр (итерация 28, шаг 5д): файл картинки, если он лежит на телефоне;
    /// ссылка без картинки — надпись «сайт / хвост пути»; иначе штриховка.
    public enum Face: Sendable, Hashable {
        case photo(String)
        case link(String)
        case placeholder
    }

    public func face(hasFile: (String) -> Bool) -> Face {
        if let im, !im.isEmpty {
            return hasFile(im) ? .photo(im) : .placeholder
        }
        if kind == .link, let url, !url.isEmpty { return .link(url) }
        return .placeholder
    }
}

/// Подборка (веб `boards[]`): `shoot` — съёмки `sid`, `tpl` — папка набора жанра.
public struct RefBoard: Sendable, Hashable {
    public enum Kind: String, Sendable { case shoot, tpl }
    public var id: String
    public var kind: Kind
    public var sid: String?
    public var genre: String?
    public var items: [String]
    /// Имя папки; у основной папки жанра `nil` (она и есть жанр).
    public var name: String?
    /// Кадр-обложка; `nil` — первый кадр с картинкой.
    public var cover: String?
    /// Порядок в папке: 0 вручную, 1 новые сверху, 2 по разделу.
    public var sort: Int
    /// Срок «хранения на устройстве» — только сохраняется (решение 30.09, 2А).
    public var keep: RefKeep?
    public var mt: Double?
    public var extra: [String: JSONValue]

    public init(id: String = "", kind: Kind, sid: String? = nil, genre: String? = nil, items: [String] = [],
                name: String? = nil, cover: String? = nil, sort: Int = 0, keep: RefKeep? = nil,
                mt: Double? = nil, extra: [String: JSONValue] = [:]) {
        self.id = id; self.kind = kind; self.sid = sid; self.genre = genre; self.items = items
        self.name = name; self.cover = cover; self.sort = sort; self.keep = keep
        self.mt = mt; self.extra = extra
    }
}

/// Срок хранения на устройстве (веб `keep`): `mode` — day, half, ever, shoot; `at` — когда выбран.
public struct RefKeep: Sendable, Hashable {
    public var mode: String
    public var at: Double?
    public var extra: [String: JSONValue]
    public init(mode: String, at: Double? = nil, extra: [String: JSONValue] = [:]) {
        self.mode = mode; self.at = at; self.extra = extra
    }
}

/// Референсы съёмки: свои кадры, потом набор жанра (веб `allRefs`,
/// `genreShots`). Кадр из двух мест — один раз, как свой; кадр из двух папок
/// жанра — один раз, на месте первой встречи; id, которого нет среди кадров, —
/// пропуск (веб `boardShots`).
public enum RefSet {
    public static func compose(sessionId: String, genre: String?,
                               shots: [RefFrame], boards: [RefBoard]) -> [RefFrame] {
        var byId: [String: RefFrame] = [:]
        for f in shots where byId[f.id] == nil { byId[f.id] = f }
        func frames(_ b: RefBoard) -> [RefFrame] { b.items.compactMap { byId[$0] } }

        var out: [RefFrame] = []
        var seen = Set<String>()
        if let mine = boards.first(where: { $0.kind == .shoot && $0.sid == sessionId }) {
            for var f in frames(mine) where seen.insert(f.id).inserted { f.own = true; out.append(f) }
        }
        guard let genre else { return out }
        for b in boards where b.kind == .tpl && b.genre == genre {
            for var f in frames(b) where seen.insert(f.id).inserted { f.own = false; out.append(f) }
        }
        return out
    }
}
