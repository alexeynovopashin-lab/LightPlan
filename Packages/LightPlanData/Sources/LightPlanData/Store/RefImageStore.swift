import Foundation
import ImageIO

/// Файлы картинок мудборда: папка внутри песочницы приложения, имя файла = `im` кадра
/// (итерация 28, шаг 5г; `docs/17` § 6 — «под теми же именами, что у блобов веба»).
/// Запись — атомарная. Облака и переезда на другой телефон здесь нет (итерация 30).
public struct RefImageStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Имя — один компонент пути: без `/`, `..` и пустоты, иначе файл ушёл бы из папки.
    public static func isSafe(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }

    public func url(_ name: String) -> URL? {
        Self.isSafe(name) ? directory.appendingPathComponent(name) : nil
    }

    public func exists(_ name: String) -> Bool {
        url(name).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    public func read(_ name: String) -> Data? { url(name).flatMap { try? Data(contentsOf: $0) } }

    /// Записать; то же имя — заменить. Небезопасное имя — `false`.
    @discardableResult
    public func save(_ data: Data, as name: String) -> Bool {
        guard let u = url(name) else { return false }
        return (try? data.write(to: u, options: .atomic)) != nil
    }

    /// Стереть; файла нет — `false`, ошибкой не считается.
    @discardableResult
    public func delete(_ name: String) -> Bool {
        guard let u = url(name), FileManager.default.fileExists(atPath: u.path) else { return false }
        return (try? FileManager.default.removeItem(at: u)) != nil
    }

    public func names() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    /// Картинка файла с поворотом из EXIF; `maxPixel` — длинная сторона, до которой её уменьшить
    /// при чтении (плитке не нужен оригинал: он в десятки раз больше по памяти). `nil` — целиком,
    /// для просмотрщика. Нет файла или он не картинка — `nil`. Синхронно: звать не с главного потока.
    public func image(_ name: String, maxPixel: Int?) -> CGImage? {
        guard let u = url(name), let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
        var side = maxPixel ?? 0
        if side <= 0 {
            guard let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let w = (p[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let h = (p[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return nil }
            side = max(w, h)
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Размеры в пикселях с учётом поворота из EXIF (снимок с телефона лежит боком, а показывается прямо).
    public static func pixelSize(of data: Data) -> (w: Double, h: Double)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (p[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (p[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, w > 0, h > 0 else { return nil }
        let o = (p[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(o) ? (h, w) : (w, h)
    }
}
