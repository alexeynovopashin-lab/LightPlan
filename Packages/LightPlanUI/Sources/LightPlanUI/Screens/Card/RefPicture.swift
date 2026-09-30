import SwiftUI
import CoreGraphics
import LightPlanData
import LightPlanDomain

// MARK: - Настоящая картинка кадра (итерация 28, шаг 5д)

/// Читалка картинок мудборда: чтение и уменьшение идут не на главном потоке, готовое лежит в памяти
/// по имени и размеру, так что прокрутка сетки не читает диск заново. Плитке хватает копии в
/// `tile` точек длинной стороны, оригинал читает только просмотрщик.
enum RefPictureLoader {
    /// Длинная сторона копии для плиток: колонка 158 pt на экране ×3 — 474 px, с запасом.
    static let tile = 640

    private final class Box: @unchecked Sendable { let image: CGImage; init(_ i: CGImage) { image = i } }
    /// NSCache потокобезопасен сам.
    nonisolated(unsafe) private static let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.totalCostLimit = 96 * 1024 * 1024
        return c
    }()

    /// Имя, размер и отпечаток файла: другой файл под тем же именем — другая запись кэша.
    private static func key(_ name: String, _ stamp: String, _ side: Int?) -> NSString {
        "\(name)#\(stamp)#\(side ?? 0)" as NSString
    }

    static func cached(_ name: String, stamp: String, side: Int?) -> CGImage? {
        cache.object(forKey: key(name, stamp, side))?.image
    }

    static func load(_ store: RefImageStore, _ name: String, stamp: String, side: Int?) async -> CGImage? {
        if let hit = cached(name, stamp: stamp, side: side) { return hit }
        let img = await Task.detached(priority: .userInitiated) { store.image(name, maxPixel: side) }.value
        if let img, !Task.isCancelled {
            cache.setObject(Box(img), forKey: key(name, stamp, side), cost: img.width * img.height * 4)
        }
        return img
    }
}

/// Кадр в плитке: картинка из `attachments/`, пока она читается и когда файла нет — штриховка.
/// Ссылки без картинки рисует вызывающий (у каждого экрана своя плитка «сайт / хвост пути»).
/// `original` — для просмотрщика: сперва уже готовая копия плитки, потом оригинал.
struct RefPicture: View {
    let frame: RefFrame?
    let images: RefImageStore?
    let pal: Palette
    var radius: CGFloat = 9
    var original = false
    @State private var shown: CGImage?
    @State private var shownKey: Source?

    /// Что показывать: имя файла и его отпечаток (заменили файл — читаем заново).
    struct Source: Equatable, Hashable { let name: String; let stamp: String }

    private var source: Source? {
        guard let frame, let images else { return nil }
        if case .photo(let n) = frame.face(hasFile: images.exists), let st = images.stamp(n) { return Source(name: n, stamp: st) }
        return nil
    }

    var body: some View {
        // Картинка — наложение: размер плитки задаёт штриховка, как до шага 5д, и снимок его не сдвигает.
        RefPlaceholder(pal: pal, radius: radius)
            .overlay {
                if let shown, shownKey == source {
                    Image(decorative: shown, scale: 1).resizable().scaledToFill()
                        .transition(.opacity)
                }
            }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: source) {
            guard let src = source, let images else { shown = nil; shownKey = nil; return }
            let tile = RefPictureLoader.tile
            if let hit = RefPictureLoader.cached(src.name, stamp: src.stamp, side: original ? nil : tile) {
                shown = hit; shownKey = src; return
            }
            if original, let small = RefPictureLoader.cached(src.name, stamp: src.stamp, side: tile) {
                shown = small; shownKey = src
            } else if shownKey != src { shown = nil }
            if let img = await RefPictureLoader.load(images, src.name, stamp: src.stamp, side: original ? nil : tile) {
                withAnimation(.easeOut(duration: 0.15)) { shown = img; shownKey = src }
            }
        }
    }
}
