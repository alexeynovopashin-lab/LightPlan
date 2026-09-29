import Foundation

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
    /// Лежит в подборке этой съёмки (веб `own`), а не только в наборе жанра.
    public var own: Bool

    public init(id: String, kind: Kind = .img, im: String? = nil, path: String? = nil,
                url: String? = nil, tags: [String] = [], own: Bool = false) {
        self.id = id; self.kind = kind; self.im = im; self.path = path; self.url = url
        self.tags = tags; self.own = own
    }
}

/// Подборка (веб `boards[]`): `shoot` — съёмки `sid`, `tpl` — папка набора жанра.
public struct RefBoard: Sendable, Hashable {
    public enum Kind: String, Sendable { case shoot, tpl }
    public var kind: Kind
    public var sid: String?
    public var genre: String?
    public var items: [String]

    public init(kind: Kind, sid: String? = nil, genre: String? = nil, items: [String] = []) {
        self.kind = kind; self.sid = sid; self.genre = genre; self.items = items
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
