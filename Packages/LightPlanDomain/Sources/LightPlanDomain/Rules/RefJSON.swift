import Foundation
import LightPlanCore

/// Кадры и подборки ⇄ JSON снимка (`shots`, `boards`). Поля, которых нет в типе,
/// лежат в `extra` и уходят обратно как пришли: импорт и правка ничего не стирают.
private extension JSONValue {
    var str: String? { if case .string(let v) = self { v } else { nil } }
    var num: Double? { if case .number(let v) = self { v } else { nil } }
}

extension RefKeep {
    init?(json: JSONValue?) {
        guard case .object(var o)? = json, let mode = o.removeValue(forKey: "mode")?.str else { return nil }
        let at = o.removeValue(forKey: "at")?.num
        self.init(mode: mode, at: at, extra: o)
    }

    var json: JSONValue {
        var o = extra
        o["mode"] = .string(mode)
        if let at { o["at"] = .number(at) }
        return .object(o)
    }
}

extension RefFrame {
    /// Как раньше в `refFrames()`: без `id` берётся `im`; ни того, ни другого — не кадр.
    public init?(json: JSONValue) {
        guard case .object(var o) = json else { return nil }
        let im = o.removeValue(forKey: "im")?.str
        guard let id = o.removeValue(forKey: "id")?.str ?? im else { return nil }
        var tags: [String] = []
        if case .array(let t)? = o.removeValue(forKey: "tags") { tags = t.compactMap(\.str) }
        let k = o.removeValue(forKey: "k")?.str
        self.init(id: id, kind: Kind(rawValue: k ?? "img") ?? .img, im: im,
                  path: o.removeValue(forKey: "path")?.str, url: o.removeValue(forKey: "url")?.str,
                  tags: tags, w: o.removeValue(forKey: "w")?.num, h: o.removeValue(forKey: "h")?.num,
                  mt: o.removeValue(forKey: "mt")?.num, extra: o)
    }

    public var json: JSONValue {
        var o = extra
        o["id"] = .string(id)
        o["k"] = .string(kind.rawValue)
        if let im { o["im"] = .string(im) }
        if let path { o["path"] = .string(path) }
        if let url { o["url"] = .string(url) }
        if !tags.isEmpty { o["tags"] = .array(tags.map { .string($0) }) }
        if let w { o["w"] = .number(w) }
        if let h { o["h"] = .number(h) }
        if let mt { o["mt"] = .number(mt) }
        return .object(o)
    }
}

extension RefBoard {
    /// Подборка неизвестного рода (`kind` не shoot/tpl) сюда не проходит — `RefLibrary` держит её сырой.
    /// Нет `id` (старый файл) — стабильный выводной: род + знак съёмки или жанр + место.
    public init?(json: JSONValue, position: Int = 0) {
        guard case .object(var o) = json, let k = Kind(rawValue: o.removeValue(forKey: "kind")?.str ?? "") else { return nil }
        let sid = o.removeValue(forKey: "sid")?.str
        let genre = o.removeValue(forKey: "genre")?.str
        var items: [String] = []
        if case .array(let t)? = o.removeValue(forKey: "items") { items = t.compactMap(\.str) }
        let id = o.removeValue(forKey: "id")?.str ?? "\(k.rawValue):\(sid ?? genre ?? ""):\(position)"
        self.init(id: id, kind: k, sid: sid, genre: genre, items: items,
                  name: o.removeValue(forKey: "name")?.str, cover: o.removeValue(forKey: "cover")?.str,
                  sort: Int(o.removeValue(forKey: "sort")?.num ?? 0),
                  keep: RefKeep(json: o.removeValue(forKey: "keep")),
                  mt: o.removeValue(forKey: "mt")?.num, extra: o)
    }

    public var json: JSONValue {
        var o = extra
        o["id"] = .string(id)
        o["kind"] = .string(kind.rawValue)
        if let sid { o["sid"] = .string(sid) }
        if let genre { o["genre"] = .string(genre) }
        o["items"] = .array(items.map { .string($0) })
        o["name"] = name.map { .string($0) } ?? .null
        o["cover"] = cover.map { .string($0) } ?? .null
        if sort != 0 { o["sort"] = .number(Double(sort)) }
        if let keep { o["keep"] = keep.json }
        if let mt { o["mt"] = .number(mt) }
        return .object(o)
    }
}
