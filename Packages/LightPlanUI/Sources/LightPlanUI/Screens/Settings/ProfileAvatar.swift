import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import LightPlanData

// Своя аватарка (31.13; схема `light_plan:Light_Plan/docs/avatar_31_13_sketch_2026-11-23.html`, принята Алексеем 23.11).

// MARK: - Картинка: квадрат JPEG 512 без EXIF

enum AvatarImage {
    static let side = 512
    static let maxBytes = 300_000

    /// Фото как его видит человек (поворот из EXIF применён), длинная сторона ≤ 2048 — обрезке больше не нужно.
    static func load(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 2048]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Вырезать квадрат `crop` (в точках картинки, начало сверху слева) и сжать в JPEG 512×512 до 300 КБ.
    /// Метаданные не копируются вовсе: ни геометки, ни модели камеры (CORE-02).
    static func square(_ img: CGImage, crop: CGRect) -> Data? {
        guard crop.width > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let k = CGFloat(side) / crop.width
        let h = CGFloat(img.height)
        ctx.draw(img, in: CGRect(x: -crop.minX * k, y: -(h - crop.maxY) * k, width: CGFloat(img.width) * k, height: h * k))
        guard let out = ctx.makeImage() else { return nil }
        var last: Data?
        for q in [0.85, 0.75, 0.65, 0.5, 0.4] {
            guard let d = jpeg(out, quality: q) else { return nil }
            last = d
            if d.count <= maxBytes { return d }
        }
        return last
    }

    static func jpeg(_ img: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    #if DEBUG
    /// Нарисованное «фото» для снимков: небо, лицо, плечи — без чужих снимков в репозитории.
    static func demoImage(_ w: Int = 1200, _ h: Int = 900) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [CGColor(red: 0.84, green: 0.76, blue: 0.66, alpha: 1),
                             CGColor(red: 0.62, green: 0.72, blue: 0.81, alpha: 1)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        ctx.setFillColor(CGColor(red: 0.23, green: 0.29, blue: 0.36, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: w / 2 - 330, y: -260, width: 660, height: 560))
        ctx.setFillColor(CGColor(red: 0.91, green: 0.77, blue: 0.64, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: w / 2 - 140, y: 300, width: 280, height: 330))
        return ctx.makeImage()
    }
    static func demoJpeg() -> Data? {
        guard let img = demoImage() else { return nil }
        return square(img, crop: AvatarCrop.rect(image: CGSize(width: img.width, height: img.height), d: 300, scale: 1.2, offset: .zero))
    }
    #endif

    /// Размер картинки без раскодирования: годна ли она вообще (копия с Диска).
    nonisolated static func decodedSize(_ data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Готовый квадрат для круга; один последний в памяти — шапка и «Профиль» читают одно и то же.
    @MainActor private static var cache: (Data, CGImage)?
    @MainActor static func decoded(_ jpeg: Data) -> CGImage? {
        if let c = cache, c.0 == jpeg { return c.1 }
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        cache = (jpeg, img)
        return img
    }
}

// MARK: - Обрезка: геометрия

/// Круг диаметром `d` по центру; картинка заполняет его при `scale` 1 и увеличивается пальцами до 5.
/// Сдвиг ограничен так, что квадрат под кругом не выходит за край фото.
enum AvatarCrop {
    static let maxScale: CGFloat = 5

    /// Точек экрана на точку картинки.
    static func k(_ image: CGSize, _ d: CGFloat, _ scale: CGFloat) -> CGFloat { d / min(image.width, image.height) * scale }

    static func clamp(_ offset: CGSize, image: CGSize, d: CGFloat, scale: CGFloat) -> CGSize {
        let kk = k(image, d, scale)
        let mx = max(0, (image.width * kk - d) / 2), my = max(0, (image.height * kk - d) / 2)
        return CGSize(width: min(mx, max(-mx, offset.width)), height: min(my, max(-my, offset.height)))
    }

    /// Квадрат под кругом в точках картинки (начало сверху слева).
    static func rect(image: CGSize, d: CGFloat, scale: CGFloat, offset: CGSize) -> CGRect {
        let kk = k(image, d, scale)
        let o = clamp(offset, image: image, d: d, scale: scale)
        let side = d / kk
        let cx = image.width / 2 - o.width / kk, cy = image.height / 2 - o.height / kk
        return CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
    }
}

// MARK: - Круг

/// Круг аватарки: фото, если есть; иначе инициалы имени; без имени — заглушка установки (кошка, собака или человек;
/// Алексей 23.11: вместо диафрагмы).
struct AvatarCircle: View {
    @Bindable var app: AppModel
    var size: CGFloat = 88
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let jpeg = app.avatar.jpeg, let img = AvatarImage.decoded(jpeg) {
            Image(decorative: img, scale: 1).resizable().interpolation(.high)
                .frame(width: size, height: size).clipShape(Circle())
                .shotNode("avatar.photo")
        } else {
            AvatarPlaceholder(initials: app.myInitials, stub: app.avatarStub, size: size)
        }
    }
}

// MARK: - Верх «Профиля»

struct ProfileAvatarHeader: View {
    @Bindable var app: AppModel
    @State private var picking = false
    @State private var item: PhotosPickerItem?
    @State private var source: CGImage?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme), t = app.lexicon
        let has = app.avatar.jpeg != nil
        VStack(spacing: 0) {
            Button { picking = true } label: {
                AvatarCircle(app: app, size: 96)
                    .overlay(alignment: .bottomTrailing) {
                        if !has {
                            Icon("camera", size: 16, line: 1.6).foregroundStyle(pal.ink)
                                .frame(width: 30, height: 30)
                                .background(pal.sheet, in: Circle())
                                .overlay(Circle().stroke(pal.surface, lineWidth: 2))
                                .offset(x: 2, y: 2)
                        }
                    }
            }
            .buttonStyle(.plain).shotNode("profile.avatar")
            Group {
                if has {
                    Menu {
                        Button(t.t("av.pickOther")) { picking = true }
                        Button(t.t("av.remove"), role: .destructive) { app.removeAvatar() }
                    } label: { pill(t.t("av.change"), pal) }
                    .shotNode("profile.avatarChange", text: t.t("av.change"))
                } else {
                    Button { picking = true } label: { pill(t.t("av.pick"), pal) }
                        .buttonStyle(.plain).shotNode("profile.avatarPick", text: t.t("av.pick"))
                }
            }
            .padding(.top, 10)
            Text(app.avatar.unreadable ? t.t("av.unreadable") : t.t("av.note"))
                .font(.system(size: 12)).foregroundStyle(pal.ink6).multilineTextAlignment(.center)
                .padding(.horizontal, 32).padding(.top, 8)
                .shotNode("profile.avatarNote")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .photosPicker(isPresented: $picking, selection: $item, matching: .images)
        .onChange(of: item) { _, it in
            guard let it else { return }
            item = nil
            Task {
                let data = try? await it.loadTransferable(type: Data.self)
                if let data, let img = AvatarImage.load(data) { app.avatar.unreadable = false; source = img }
                else { app.avatar.unreadable = true }
            }
        }
        .modifier(CropCover(app: app, source: $source))
        #if DEBUG
        .onAppear { if app.avatar.shotCrop { app.avatar.shotCrop = false; source = AvatarImage.demoImage() } }
        #endif
    }

    private func pill(_ s: String, _ pal: Palette) -> some View {
        Text(s).font(.system(size: 15)).foregroundStyle(pal.ink)
            .padding(.vertical, 6).padding(.horizontal, 14)
            .background(pal.press, in: Capsule())
    }
}

/// Обрезка на весь экран (на Mac — лист: `fullScreenCover` там нет).
private struct CropCover: ViewModifier {
    @Bindable var app: AppModel
    @Binding var source: CGImage?

    func body(content: Content) -> some View {
        let shown = Binding(get: { source != nil }, set: { if !$0 { source = nil } })
        #if os(iOS)
        content.fullScreenCover(isPresented: shown) { screen }
        #else
        content.sheet(isPresented: shown) { screen.frame(minWidth: 420, minHeight: 640) }
        #endif
    }

    @ViewBuilder private var screen: some View {
        if let img = source {
            AvatarCropScreen(app: app, image: img) { jpeg in
                if let jpeg { app.setAvatar(jpeg) }
                source = nil
            }
        }
    }
}

// MARK: - Экран обрезки

/// Всегда чёрный, как системная обрезка, в обеих темах. Пальцами — сдвиг и увеличение; круг показывает, что войдёт.
struct AvatarCropScreen: View {
    @Bindable var app: AppModel
    let image: CGImage
    let done: (Data?) -> Void
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        let t = app.lexicon
        let size = CGSize(width: image.width, height: image.height)
        GeometryReader { geo in
            let d = max(120, min(geo.size.width - 32, geo.size.height - 260))
            let s = min(AvatarCrop.maxScale, max(1, scale * pinch))
            let o = AvatarCrop.clamp(CGSize(width: offset.width + drag.width, height: offset.height + drag.height),
                                     image: size, d: d, scale: s)
            let kk = AvatarCrop.k(size, d, s)
            ZStack {
                Color.black
                Image(decorative: image, scale: 1).resizable().interpolation(.high)
                    .frame(width: size.width * kk, height: size.height * kk)
                    .offset(o)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                Rectangle().fill(Color.black.opacity(0.55))
                    .mask(Rectangle().overlay(Circle().frame(width: d, height: d).blendMode(.destinationOut)).compositingGroup())
                    .allowsHitTesting(false)
                Circle().stroke(Color.white.opacity(0.35), lineWidth: 1).frame(width: d, height: d).allowsHitTesting(false)
                VStack {
                    Text(t.t("av.cropHint")).font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.85))
                        .padding(.top, 24)
                    Spacer()
                    HStack {
                        Button(t.t("ask.cancel")) { done(nil) }.shotNode("crop.cancel")
                        Spacer()
                        Button(t.t("pick.done")) {
                            let r = AvatarCrop.rect(image: size, d: d, scale: s, offset: o)
                            done(AvatarImage.square(image, crop: r))
                        }
                        .fontWeight(.semibold).shotNode("crop.done")
                    }
                    .font(.system(size: 17)).foregroundStyle(.white).buttonStyle(.plain)
                    .padding(.horizontal, 24).padding(.bottom, 24)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($drag) { v, st, _ in st = v.translation }
                    .onEnded { v in
                        offset = AvatarCrop.clamp(CGSize(width: offset.width + v.translation.width, height: offset.height + v.translation.height),
                                                  image: size, d: d, scale: s)
                    }
                    .simultaneously(with: MagnifyGesture()
                        .updating($pinch) { v, st, _ in st = v.magnification }
                        .onEnded { v in
                            scale = min(AvatarCrop.maxScale, max(1, scale * v.magnification))
                            offset = AvatarCrop.clamp(offset, image: size, d: d, scale: scale)
                        })
            )
        }
        .ignoresSafeArea(edges: .horizontal)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .shotNode("crop")
    }
}

// MARK: - «Мои данные» внизу «Профиля»

/// Строка видна всегда (Алексей 23.11, «Всегда»). Стирает пропуск, фото и всё, что сервер знает о номере; на телефоне —
/// фото («Да, и на телефоне»). Слово «ядро» не показывается (23.11).
struct ProfileForgetSection: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme), t = app.lexicon
        SecLabel(text: t.t("my.data"))
        Button { app.avatar.confirmForget = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.t("my.delete")).font(.system(size: 15)).foregroundStyle(pal.brassDeep)
                Text(t.t("my.deleteSub")).font(.system(size: 12)).foregroundStyle(pal.ink4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 13).padding(.bottom, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(pal.hair2).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).shotNode("profile.forget", text: t.t("my.delete"))
        SetNote(text: t.t("my.deleteNote"))
            .alert(t.t("my.deleteQ"), isPresented: $app.avatar.confirmForget) {
                Button(t.t("ask.cancel"), role: .cancel) {}
                Button(t.t("ask.del"), role: .destructive) { app.forgetMe() }
            } message: {
                Text(t.t("my.deleteText"))
            }
    }
}
