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

    private static func key(_ name: String, _ side: Int?) -> NSString { "\(name)#\(side ?? 0)" as NSString }

    static func cached(_ name: String, side: Int?) -> CGImage? { cache.object(forKey: key(name, side))?.image }

    static func load(_ store: RefImageStore, _ name: String, side: Int?) async -> CGImage? {
        if let hit = cached(name, side: side) { return hit }
        let img = await Task.detached(priority: .userInitiated) { store.image(name, maxPixel: side) }.value
        if let img, !Task.isCancelled {
            cache.setObject(Box(img), forKey: key(name, side), cost: img.width * img.height * 4)
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
    @State private var shownName: String?

    private var name: String? {
        guard let frame, let images else { return nil }
        if case .photo(let n) = frame.face(hasFile: images.exists) { return n }
        return nil
    }

    var body: some View {
        // Картинка — наложение: размер плитки задаёт штриховка, как до шага 5д, и снимок его не сдвигает.
        RefPlaceholder(pal: pal, radius: radius)
            .overlay {
                if let shown, shownName == name {
                    Image(decorative: shown, scale: 1).resizable().scaledToFill()
                        .transition(.opacity)
                }
            }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: name) {
            guard let name, let images else { shown = nil; shownName = nil; return }
            if let hit = RefPictureLoader.cached(name, side: original ? nil : RefPictureLoader.tile) {
                shown = hit; shownName = name; return
            }
            if original, let small = RefPictureLoader.cached(name, side: RefPictureLoader.tile) {
                shown = small; shownName = name
            } else if shownName != name { shown = nil }
            let side: Int? = original ? nil : RefPictureLoader.tile
            if let img = await RefPictureLoader.load(images, name, side: side) {
                withAnimation(.easeOut(duration: 0.15)) { shown = img; shownName = name }
            }
        }
    }
}
