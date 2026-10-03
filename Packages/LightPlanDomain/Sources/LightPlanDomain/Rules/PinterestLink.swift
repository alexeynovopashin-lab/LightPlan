import Foundation

/// Ссылка на Pinterest в мудборде (итерация 28м, шаг 3): что это — пин, доска, короткая `pin.it`
/// или чужой адрес. Правила — ровно как у беты (`isPinterestBoardUrl`, `docs/pinterest_reference.md` § 2.1),
/// плюс одно сверх беты: служебные первые сегменты (`search`, `ideas`…) и вкладки профиля (`_saved`)
/// доской не считаются — иначе поиск Pinterest шёл бы в читалку как «доска».
public enum PinterestLink: Equatable, Sendable {
    case pin(id: String)
    case board(user: String, slug: String)
    /// `pin.it/<код>`: куда ведёт, знает только Pinterest — пин или доска.
    case short
    case other

    /// Хост как у читалки (`lightplanogreader`): `pinterest.<tld>` с любым поддоменом, кроме `api.`.
    static func isPinterestHost(_ h: String) -> Bool {
        let h = h.lowercased()
        if h.hasPrefix("api.") { return false }
        return h.range(of: #"(^|\.)pinterest\.(com|ru|[a-z]{2}|co\.[a-z]{2}|com\.[a-z]{2})$"#, options: .regularExpression) != nil
    }

    private static let reserved: Set<String> = ["pin", "search", "ideas", "today", "explore", "business", "settings",
                                                "news_hub", "topics", "login", "about", "_"]

    private static func segments(_ u: URL) -> [String] {
        u.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
    }

    /// Номер пина из `…/pin/<id>/` (или `…/pin/<слово>--<id>/`); иначе `nil`.
    public static func pinId(of url: String) -> String? {
        guard let u = URL(string: url), let h = u.host, isPinterestHost(h) else { return nil }
        let s = segments(u)
        guard s.count >= 2, s[0] == "pin" else { return nil }
        let id = s[1].components(separatedBy: "--").last ?? s[1]
        return !id.isEmpty && id.allSatisfy(\.isASCII) && id.allSatisfy(\.isNumber) ? id : nil
    }

    /// Адрес пина как его отдаёт читалка и как хранит кадр.
    public static func permalink(id: String) -> String { "https://www.pinterest.com/pin/\(id)/" }

    /// Разбор адреса; не разобрался или чужой сайт — `.other` (дальше идёт текстовая плитка, как раньше).
    public static func kind(_ raw: String) -> PinterestLink {
        guard let norm = RefLink.normalize(raw), let u = URL(string: norm), let host = u.host?.lowercased() else { return .other }
        let segs = segments(u)
        if host == "pin.it" || host == "www.pin.it" { return segs.isEmpty ? .other : .short }
        guard isPinterestHost(host) else { return .other }
        if let id = pinId(of: norm) { return .pin(id: id) }
        guard segs.count >= 2, !reserved.contains(segs[0].lowercased()), !segs[1].hasPrefix("_") else { return .other }
        return .board(user: segs[0], slug: segs[1])
    }

    /// Адрес для читалки: она принимает только https.
    public static func secure(_ raw: String) -> String? {
        guard var s = RefLink.normalize(raw) else { return nil }
        if s.lowercased().hasPrefix("http://") { s = "https://" + s.dropFirst(7) }
        return s
    }
}

/// Итог «добавить пин в папку».
public enum PinAdd: Equatable, Sendable {
    case added(String)
    case duplicate
    case invalid
}

extension RefLibrary {

    private static func pinKey(_ url: String) -> String { PinterestLink.pinId(of: url) ?? url.lowercased() }

    /// Номера пинов, что уже лежат в подборке (по адресу кадра: «Скопировать ссылку» в Pinterest каждый раз
    /// даёт новый инвайт, поэтому по номеру пина, а не по ссылке целиком — веб `onPin`).
    public func pinKeys(in boardId: String) -> Set<String> {
        guard let b = board(boardId) else { return [] }
        return Set(b.items.compactMap { shot($0)?.url }.map(Self.pinKey))
    }

    /// Пин доски: кадр-ссылка с картинкой (`kind: .link`, `url` — адрес пина, `im`, размеры) ложится в подборку.
    /// Дубль (тот же пин уже в этой подборке), пустое имя файла, занятое имя или нет подборки — ничего не меняется.
    @discardableResult
    public mutating func addPin(permalink: String, im: String, w: Double?, h: Double?, to boardId: String,
                                tag: String? = nil, now: Double? = nil) -> PinAdd {
        guard !im.isEmpty, board(boardId) != nil, !permalink.isEmpty, shot(im) == nil,
              !shots.contains(where: { $0.im == im }) else { return .invalid }
        if pinKeys(in: boardId).contains(Self.pinKey(permalink)) { return .duplicate }
        shots.append(RefFrame(id: im, kind: .link, im: im, url: permalink, tags: tag.map { [$0] } ?? [], w: w, h: h, mt: now))
        put(im, into: boardId, now: now)
        return .added(im)
    }

    /// Картинка догнала кадр-ссылку (превью одного пина): кадр жив, это ссылка, своей картинки ещё нет и имя
    /// файла никому не принадлежит. Иначе ничего не меняется (человек успел убрать кадр или картинка уже есть).
    @discardableResult
    public mutating func attachImage(im: String, w: Double?, h: Double?, toFrame id: String, now: Double? = nil) -> Bool {
        guard !im.isEmpty, let i = shots.firstIndex(where: { $0.id == id }), shots[i].kind == .link,
              (shots[i].im ?? "").isEmpty, shot(im) == nil, !shots.contains(where: { $0.im == im }) else { return false }
        shots[i].im = im; shots[i].w = w; shots[i].h = h; shots[i].mt = now ?? shots[i].mt
        return true
    }
}
