import Foundation
import ImageIO
import LightPlanCore
import simd
#if os(iOS)
import Metal
import QuartzCore
import UIKit
import SwiftUI
#endif

/// Млечный Путь панорамой на всю сферу (шаг 29.8в.20). Слово Алексея 20.10: полоса из каталога Gaia точками выглядела
/// не так — на небе везде звёзды, а полоса обрезалась горизонтом. Он принёс свои панорамы (`MW`, `MW2`): эквидистантная
/// проекция в галактических координатах, ядро l = 0 в центре картинки, l растёт ВЛЕВО, b = 0 посередине по высоте.
/// Файлы `MilkyWayData/pano_<name>.jpg` только уменьшенные копии 4096 пикселей (оригиналы 6000 × 2425 не кладутся);
/// источник — ESO/S. Brunier, eso0932a, CC BY 4.0, кредит и ссылка — `MilkyWayData/README.md`. Нет файла — слой рисует прежнюю гладкую полосу шейдера.
///
/// Планирование: полоса рисуется и под горизонтом, «сквозь пол» — положение показывается всегда, горизонт только линия.
enum MilkyWayPano {
    /// Картинка 6000 × 2425 при 0,06° на пиксель по обеим осям: по вертикали она охватывает не 180°, а 145,5°
    /// (проверено по Большому Магелланову Облаку: l = 280,5°, b = −32,9° — на 0,2° от ожидаемого места).
    static let sourceWidth = 6000.0, sourceHeight = 2425.0
    static let verticalSpan = 360.0 * sourceHeight / sourceWidth

    /// Точка панорамы (0…1, 0…1; верх = 0) для галактических (l, b). Вне картины по высоте `v` выходит за 0…1.
    static func uv(l: Double, b: Double) -> (u: Double, v: Double) {
        let u = 0.5 - l / 360
        return (u - u.rounded(.down), 0.5 - b / verticalSpan)
    }

    /// Панорама одна (29.8в.24, Алексей выбрал MW2): имя в файле `pano_mw2.jpg`.
    static let names = ["mw2"]
    static let selected = "mw2"

    static func url(_ name: String) -> URL? {
        Bundle.module.url(forResource: "MilkyWayData/pano_\(name)", withExtension: "jpg")
    }

    /// Панорама лежит в приложении — для подписи слоя.
    static var bundled: Bool { url(selected) != nil }

    /// Подпись в строке слоя, пока источник не подтверждён (слово задания: нейтрально, без ESA/Gaia).
    static let creditKey = "ar.mwPano"
}

#if os(iOS)

/// Видеокарта для панорамы: одна на запуск и имя (текстура 4096 × 1655, с цепочкой уменьшенных копий).
final class MilkyWayPanoGPU: @unchecked Sendable {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let name: String
    let texture: MTLTexture
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    nonisolated(unsafe) private(set) static var builds = 0
    nonisolated(unsafe) private static var cache: [String: MilkyWayPanoGPU] = [:]
    private static let lock = NSLock()

    /// `nil` — файла нет или он не читается: слой рисует запасной вариант.
    static func shared(_ name: String) -> MilkyWayPanoGPU? {
        lock.lock(); defer { lock.unlock() }
        if let g = cache[name] { return g }
        guard let url = MilkyWayPano.url(name), let g = MilkyWayPanoGPU(name: name, url: url) else { return nil }
        // Предыдущую панораму отпускаем: на телефоне держим одну текстуру (~36 МБ с уменьшенными копиями).
        cache = [name: g]
        return g
    }

    /// Выбранная на устройстве.
    static var current: MilkyWayPanoGPU? { shared(MilkyWayPano.selected) }

    struct Uniforms {
        var p0, p1, p2: SIMD4<Float>
        var gx, gy, gz: SIMD4<Float>
        /// Ширина и высота холста, pt; сдвиг холста в окне.
        var view: SIMD4<Float>
        /// Точек на pt, видимость, пол, «тёмное место».
        var look: SIMD4<Float>
        /// Сила подклада, охват панорамы по вертикали, °.
        var tone: SIMD4<Float>
    }

    init?(name: String, url: URL) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.source, options: nil),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let w = img.width, h = img.height
        // 8 бит RGBA без альфы (чёрное — прозрачное, свет складывается): читаем в sRGB-пространстве «как есть».
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let px = ctx.data else { return nil }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: true)
        td.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: td), let cmd = queue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: px, bytesPerRow: w * 4)
        blit.generateMipmaps(for: tex)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "panoVertex")
        d.fragmentFunction = library.makeFunction(name: "panoFragment")
        d.colorAttachments[0].pixelFormat = .bgra8Unorm
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.mipFilter = .linear
        sd.maxAnisotropy = 4
        sd.sAddressMode = .repeat
        sd.tAddressMode = .clampToEdge
        guard let ps = try? device.makeRenderPipelineState(descriptor: d), let smp = device.makeSamplerState(descriptor: sd) else { return nil }
        Self.builds += 1
        self.device = device
        self.queue = queue
        self.name = name
        texture = tex
        pipeline = ps
        sampler = smp
    }

    /// Память текстуры с цепочкой уменьшенных копий, МБ.
    var textureMB: Double {
        var total = 0.0, w = Double(texture.width), h = Double(texture.height)
        for _ in 0..<texture.mipmapLevelCount { total += w * h * 4; w = max(1, (w / 2).rounded(.down)); h = max(1, (h / 2).rounded(.down)) }
        return total / 1_048_576
    }

    func uniforms(_ look: MilkyWayGaiaLook, size: CGSize, origin: CGPoint, scale: CGFloat) -> Uniforms {
        let m = look.pixelToSky.map(Float.init)
        func v3(_ v: SIMD3<Double>) -> SIMD4<Float> { SIMD4(Float(v.x), Float(v.y), Float(v.z), 0) }
        // Подклад — по светлому небу (видимость глазом); «тёмное место» его не снимает.
        let under = MilkyWayGaiaLook.underlay * (1 - look.visibility)
        return Uniforms(p0: SIMD4(m[0], m[1], m[2], 0), p1: SIMD4(m[3], m[4], m[5], 0), p2: SIMD4(m[6], m[7], m[8], 0),
                        gx: v3(look.axes[0]), gy: v3(look.axes[1]), gz: v3(look.axes[2]),
                        view: SIMD4(Float(size.width), Float(size.height), Float(origin.x), Float(origin.y)),
                        look: SIMD4(Float(scale), Float(look.visibility), Float(MilkyWayGaiaLook.planFloor), look.dark ? 1 : 0),
                        tone: SIMD4(Float(under), Float(MilkyWayPano.verticalSpan), 0, 0))
    }

    func encode(_ look: MilkyWayGaiaLook, size: CGSize, origin: CGPoint, scale: CGFloat, target: MTLTexture, buffer: MTLCommandBuffer) {
        var u = uniforms(look, size: size, origin: origin, scale: scale)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Кадр в память (тесты и замеры): BGRA, ширина × высота × 4, свет без подложки (подклад в альфе).
    func render(_ look: MilkyWayGaiaLook, size: CGSize, scale: CGFloat, origin: CGPoint = .zero) -> (pixels: [UInt8], width: Int, height: Int)? {
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: td), let cmd = queue.makeCommandBuffer() else { return nil }
        encode(look, size: size, origin: origin, scale: scale, target: tex, buffer: cmd)
        cmd.commit()
        cmd.waitUntilCompleted()
        var out = [UInt8](repeating: 0, count: w * h * 4)
        out.withUnsafeMutableBytes {
            tex.getBytes($0.baseAddress!, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return (out, w, h)
    }

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct U { float4 p0, p1, p2, gx, gy, gz, view, look, tone; };
    constant float DEG = 57.29577951;
    constant float3 LUMA = float3(0.2126, 0.7152, 0.0722);

    // Рефракция `SunTrack.apparent` (Сэмундссон): добавка к геометрической высоте, градусы; ниже −1° — как на −1°.
    static float refraction(float h) {
        float g = max(h, -1.0);
        return 1.02 / tan((g + 10.3 / (g + 5.11)) / DEG) / 60.0;
    }

    static float3 withAltitude(float3 e, float alt) {
        float n = length(e.xy);
        if (n < 1e-7) return e;
        return float3(e.xy / n * cos(alt / DEG), sin(alt / DEG));
    }

    struct PanoOut { float4 position [[position]]; };

    vertex PanoOut panoVertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        PanoOut o; o.position = float4(p * 2.0 - 1.0, 0.0, 1.0); return o;
    }

    // Пиксель → луч (видимая высота) → геометрическое направление (обратная рефракция, как у звёзд и ядра) →
    // галактические (l, b) → панорама (u = fract(0,5 − l/360), v = 0,5 − b/охват), трилинейно. Горизонта нет:
    // полоса рисуется и под ним. Яркость — видимость глазом не ниже пола планирования; «тёмное место» — 1.
    // Производные для выбора уровня берутся с той из двух долгот (шов l = ±180° / середина), где нет скачка.
    fragment float4 panoFragment(PanoOut in [[stage_in]], constant U &u [[buffer(0)]],
                                 texture2d<float> pano [[texture(0)]], sampler s [[sampler(0)]]) {
        float2 pt = in.position.xy / u.look.x + u.view.zw;
        float3 e = normalize(float3(dot(u.p0.xyz, float3(pt, 1.0)), dot(u.p1.xyz, float3(pt, 1.0)),
                                    dot(u.p2.xyz, float3(pt, 1.0))));
        float alt = asin(clamp(e.z, -1.0, 1.0)) * DEG;
        float h = alt;
        for (int i = 0; i < 3; i++) { h = alt - refraction(h); }
        e = withAltitude(e, h);
        float gx = dot(e, u.gx.xyz), gy = dot(e, u.gy.xyz), gz = dot(e, u.gz.xyz);
        float l = atan2(gy, gx) * DEG;
        float b = asin(clamp(gz, -1.0, 1.0)) * DEG;
        float v = 0.5 - b / u.tone.y;
        float uu = 0.5 - l / 360.0;                       // −0,0 … 1,0: скачок на шве l = ±180°
        float ua = uu - floor(uu), ub = fract(uu + 0.5);  // ub сдвинута на пол-оборота: её шов в l = 0
        float2 dax = dfdx(float2(ua, v)), day = dfdy(float2(ua, v));
        float2 dbx = dfdx(float2(ub, v)), dby = dfdy(float2(ub, v));
        bool useA = (dot(dax, dax) + dot(day, day)) <= (dot(dbx, dbx) + dot(dby, dby));
        float3 rgb = pano.sample(s, float2(ua, clamp(v, 0.0, 1.0)), useA ? gradient2d(dax, day) : gradient2d(dbx, dby)).rgb;
        if (v < 0.0 || v > 1.0) return float4(0.0);   // после выборки: производные — только в общем потоке
        float gain = u.look.w > 0.5 ? 1.0 : max(u.look.y, u.look.z);
        float3 light = rgb * gain;
        float y = dot(rgb, LUMA);
        // Подклад: где светится полоса, кадр темнеет; на ярком небе он и виден. Предумноженная альфа честная.
        float under = u.tone.x * smoothstep(0.05, 0.15, y);
        float lit = max(light.r, max(light.g, light.b));
        return float4(light, 1.0 - (1.0 - under) * (1.0 - lit));
    }
    """
}

/// Холст панорамы на экране: прозрачный слой Metal, перерисовывается при каждом обновлении сцены.
struct SunARPanoSkyView: UIViewRepresentable {
    let gpu: MilkyWayPanoGPU
    let look: MilkyWayGaiaLook
    var origin: CGPoint = .zero

    func makeUIView(context: Context) -> PanoSkyUIView { PanoSkyUIView(gpu: gpu) }

    func updateUIView(_ view: PanoSkyUIView, context: Context) {
        view.gpu = gpu
        view.look = look
        view.origin = origin
        view.redraw()
    }
}

final class PanoSkyUIView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var gpu: MilkyWayPanoGPU
    var look: MilkyWayGaiaLook?
    var origin: CGPoint = .zero
    /// Замер кадра (`-LPShotReport`): имя панорамы, мс CPU на кодирование и мс GPU.
    nonisolated(unsafe) static var lastStats = (name: "", cpuMs: 0.0, gpuMs: 0.0)

    init(gpu: MilkyWayPanoGPU) {
        self.gpu = gpu
        super.init(frame: .zero)
        isOpaque = false
        isUserInteractionEnabled = false
        backgroundColor = .clear
        let l = layer as! CAMetalLayer
        l.device = gpu.device
        l.pixelFormat = .bgra8Unorm
        l.isOpaque = false
        l.framebufferOnly = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        redraw()
    }

    func redraw() {
        guard let look, bounds.width > 0, bounds.height > 0 else { return }
        let l = layer as! CAMetalLayer
        let scale = window?.screen.scale ?? UIScreen.main.scale
        l.contentsScale = scale
        let px = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        if l.drawableSize != px { l.drawableSize = px }
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let drawable = l.nextDrawable(), let cmd = gpu.queue.makeCommandBuffer() else { return }
        gpu.encode(look, size: bounds.size, origin: origin, scale: scale, target: drawable.texture, buffer: cmd)
        let name = gpu.name
        cmd.addCompletedHandler { b in
            PanoSkyUIView.lastStats.gpuMs = (b.gpuEndTime - b.gpuStartTime) * 1000
        }
        cmd.present(drawable)
        cmd.commit()
        Self.lastStats.name = name
        Self.lastStats.cpuMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    }
}

#endif
