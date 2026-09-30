import Foundation
import LightPlanCore

/// Кадры и подборки ⇄ JSON снимка (`shots`, `boards`). Поля, которых нет в типе,
/// лежат в `extra` и уходят обратно как пришли. Поле, чьё значение не разобралось
/// (другой тип, неизвестный `k`, число не по размеру), тоже остаётся в `extra`
/// сырым и не затирается: простой цикл чтение-запись ничего не меняет.
private extension JSONValue {
    var str: String? { if case .string(let v) = self { v } else { nil } }
    var num: Double? { if case .number(let v) = self { v } else { nil } }
}

private extension Dictionary where Key == String, Value == JSONValue {
    /// Вынуть поле, только если оно разобралось; иначе оно остаётся сырым.
    mutating func take<T>(_ key: String, _ parse: (JSONValue) -> T?) -> T? {
        guard let raw = self[key], let v = parse(raw) else { return nil }
        removeValue(forKey: key)
        return v
    }

    /// Список строк: чисто строковый вынимается; с чужими элементами — читается, а сырой остаётся.
    mutating func takeStrings(_ key: String) -> [String] {
        guard case .array(let a)? = self[key] else { return [] }
        let s = a.compactMap(\.str)
        if s.count == a.count { removeValue(forKey: key) }
        return s
    }

    /// Записать список строк. Есть сырой массив с чужими элементами — они остаются на местах,
    /// а строки собираются заново: снятые уходят (даже последняя), новые дописываются в конец.
    mutating func putStrings(_ key: String, _ list: [String], keepEmpty: Bool) {
        if case .array(let raw)? = self[key] {
            if raw.compactMap(\.str) == list { return }
            var rest = list
            var out: [JSONValue] = []
            for v in raw {
                guard let s = v.str else { out.append(v); continue }
                if let i = rest.firstIndex(of: s) { out.append(v); rest.remove(at: i) }
            }
            self[key] = .array(out + rest.map { .string($0) })
            return
        }
        if list.isEmpty && !keepEmpty { return }
        self[key] = .array(list.map { .string($0) })
    }
}

extension RefKeep {
    init?(json: JSONValue?) {
        guard case .object(var o)? = json, let mode = o.take("mode", \.str) else { return nil }
        let at = o.take("at", \.num)
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
        let im = o.take("im", \.str)
        guard let id = o.take("id", \.str) ?? im else { return nil }
        let tags = o.takeStrings("tags")
        // Неизвестный `k` кадр показывает картинкой, но в файле остаётся как был.
        let kind = o.take("k") { Kind(rawValue: $0.str ?? "") } ?? .img
        self.init(id: id, kind: kind, im: im, path: o.take("path", \.str), url: o.take("url", \.str),
                  tags: tags, w: o.take("w", \.num), h: o.take("h", \.num), mt: o.take("mt", \.num), extra: o)
    }

    public var json: JSONValue {
        var o = extra
        o["id"] = .string(id)
        if o["k"] == nil || kind != .img { o["k"] = .string(kind.rawValue) }
        if let im { o["im"] = .string(im) }
        if let path { o["path"] = .string(path) }
        if let url { o["url"] = .string(url) }
        o.putStrings("tags", tags, keepEmpty: false)
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
        let sid = o.take("sid", \.str)
        let genre = o.take("genre", \.str)
        let items = o.takeStrings("items")
        let id = o.take("id", \.str) ?? "\(k.rawValue):\(sid ?? genre ?? ""):\(position)"
        // Номер порядка — только целое в разумных пределах; иное остаётся сырым.
        let sort = o.take("sort") { v -> Int? in
            guard let n = v.num, n.isFinite, n == n.rounded(), abs(n) < 1_000_000 else { return nil }
            return Int(n)
        } ?? 0
        self.init(id: id, kind: k, sid: sid, genre: genre, items: items,
                  name: o.take("name", \.str), cover: o.take("cover", \.str), sort: sort,
                  keep: o.take("keep") { RefKeep(json: $0) }, mt: o.take("mt", \.num), extra: o)
    }

    public var json: JSONValue {
        var o = extra
        o["id"] = .string(id)
        o["kind"] = .string(kind.rawValue)
        if let sid { o["sid"] = .string(sid) }
        if let genre { o["genre"] = .string(genre) }
        o.putStrings("items", items, keepEmpty: true)
        if let name { o["name"] = .string(name) } else if o["name"] == nil { o["name"] = .null }
        if let cover { o["cover"] = .string(cover) } else if o["cover"] == nil { o["cover"] = .null }
        if sort != 0 { o["sort"] = .number(Double(sort)) }
        if let keep { o["keep"] = keep.json }
        if let mt { o["mt"] = .number(mt) }
        return .object(o)
    }
}
