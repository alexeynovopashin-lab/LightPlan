import Foundation
import LightPlanCore

/// Картинки и ссылки, что человек кладёт в папку мудборда (итерация 28, шаг 5г). Файл лежит на
/// телефоне под именем `im` (веб: «один файл — одно имя», `shotAdd`); кадр — запись в фонде.
/// Логика чистая: сам файл пишет и стирает слой данных, а кому пора уйти, решает `orphanImages`.

/// Итог «Ссылка».
public enum RefLinkAdd: Equatable, Sendable {
    case added(String)
    case invalid
    case duplicate
}

extension RefLink {
    /// Адрес как в вебе (`askUrl`): обрезать, без `http(s)://` — дописать `https://`. Сверх веба —
    /// отсев мусора: нужен разбираемый адрес схемы http/https, у хоста есть точка (`abc` не адрес).
    public static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(where: \.isWhitespace) else { return nil }
        if s.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) == nil { s = "https://" + s }
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = u.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
        return s
    }
}

extension RefLibrary {

    /// Имена файлов картинок, что держат кадры фонда (`im`).
    public var imageNames: Set<String> { Set(shots.compactMap { $0.im }.filter { !$0.isEmpty }) }

    /// Файлы, которые после правки никому не нужны: `im` был у кадра до правки и не остался ни у одного
    /// после. Кадр ушёл совсем (`dropShot`, `dropWithShots`, «Убрать N») — его файлу пора уйти; кадр,
    /// что лежит в другой подборке, остаётся, и файл вместе с ним.
    public static func orphanImages(before: RefLibrary, after: RefLibrary) -> [String] {
        before.imageNames.subtracting(after.imageNames).sorted()
    }

    /// Фото из библиотеки телефона: кадр с `im`, размерами и отметкой правки ложится в подборку.
    /// Ответ — id кадра; подборки нет, имя пустое или такой файл уже держит кадр — `nil`, ничего не меняется.
    @discardableResult
    public mutating func addPhoto(im: String, w: Double?, h: Double?, to boardId: String,
                                  tag: String? = nil, now: Double? = nil) -> String? {
        guard !im.isEmpty, board(boardId) != nil, shot(im) == nil else { return nil }
        shots.append(RefFrame(id: im, kind: .img, im: im, tags: tag.map { [$0] } ?? [], w: w, h: h, mt: now))
        put(im, into: boardId, now: now)
        return im
    }

    /// «Ссылка» (веб `addLinkTo`): текстовая карточка ложится в подборку сразу. Веб дубль обычной
    /// ссылки не смотрит; здесь тот же адрес в этой же подборке второй плиткой не встаёт.
    @discardableResult
    public mutating func addLink(_ raw: String, to boardId: String, id: String,
                                 tag: String? = nil, now: Double? = nil) -> RefLinkAdd {
        guard let url = RefLink.normalize(raw), let b = board(boardId) else { return .invalid }
        let key = url.lowercased()
        if b.items.contains(where: { shot($0)?.url?.lowercased() == key }) { return .duplicate }
        guard shot(id) == nil else { return .invalid }
        shots.append(RefFrame(id: id, kind: .link, url: url, tags: tag.map { [$0] } ?? [], mt: now))
        put(id, into: boardId, now: now)
        return .added(id)
    }
}
