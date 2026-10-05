import Foundation

/// Прямая ссылка на фото в мудборде (итерация 28н.1): `https://…/photo.jpg`, не страница Pinterest.
/// Здесь только то, что видно по адресу; окончательно картинку определяют заголовок типа и первые байты
/// (`ImageLinkReader` в Data). Правило: расширение в адресе → картинка; ни расширения, ни слэша в конце
/// (`images.unsplash.com/photo-123?w=800`) → возможно картинка, это проверяет тихий запрос; всё прочее — обычная ссылка.
public enum ImageLink: Equatable, Sendable {
    /// Расширение `.jpg .jpeg .png .webp .heic .heif` в пути адреса (запрос и якорь не в счёт).
    case image
    /// В пути нет расширения: проверка по ответу сервера, без надписей, если это оказалась страница.
    case maybe
    /// Страница, Pinterest, документ, адрес без пути, не адрес.
    case page

    public static let extensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif"]

    public static func kind(_ raw: String) -> ImageLink {
        guard let norm = RefLink.normalize(raw), let u = URL(string: norm), u.host != nil else { return .page }
        // Страницы и доски Pinterest читает 28м; а `i.pinimg.com/….jpg` — обычная картинка по прямой ссылке.
        if PinterestLink.kind(norm) != .other { return .page }
        let path = URLComponents(string: norm)?.percentEncodedPath ?? u.path // `URL.path` съедает слэш в конце
        guard let last = path.split(separator: "/", omittingEmptySubsequences: false).last, !path.hasSuffix("/"), !last.isEmpty else { return .page }
        if let dot = last.lastIndex(of: ".") {
            let ext = last[last.index(after: dot)...].lowercased()
            return extensions.contains(ext) ? .image : .page
        }
        return .maybe
    }
}
