import Foundation
import LightPlanCore
import simd
#if os(iOS)
import Metal
import QuartzCore
import UIKit
import SwiftUI
#endif

/// Как рисовать Млечный Путь из Gaia в этом кадре (шаг 29.8в.19): лучи окна, оси галактики и яркость. Чистые числа —
/// их считает CPU раз на кадр теми же функциями, что у полосы, ядра и луны (`MilkyWayLook.pixelToSky`,
/// `MilkyWayLook.frame` через `Sky.horizontal`), видеокарта только множит.
struct MilkyWayGaiaLook: Equatable, Sendable {
    /// Луч из точки окна (pt) в осях «восток, север, вверх»: `P · (x, y, 1)`, девять чисел по строкам.
    var pixelToSky: [Double]
    /// Оси галактики (на ядро, на l = 90°, на полюс) в осях «восток, север, вверх».
    var axes: [SIMD3<Double>]
    /// Видимость глазом 0…1 (солнце × засветка × Луна, `MilkyWayLook.visibility`) — без пола.
    var visibility: Double
    /// «Как в тёмном месте» (`lightplan.native.sunar.milkyWayDark`): реалистичная часть на полную яркость.
    var dark: Bool

    /// Пол планирования: ниже него яркость реалистичной части не падает (день, город, Луна) — слово Алексея 20.10
    /// «положение светил показывается всегда». Подобран замером `Tools/ar_milkyway.py --contrast` (контраст полосы
    /// к фону ≥ 1,5:1 на белом, голубом небе, асфальте и ночном небе).
    static let planFloor = 0.4
    /// Тёмный подклад под полосой при светлом небе: множитель кадра 0,75 там, где видимость глазом нуль.
    static let underlay = 0.25
    /// Тонирование «скромно»: `I_out = k · I^γ` по яркости Y, оттенок сохраняется; ядро ≈ 0,6.
    static let toneK = 1.234
    static let toneGamma = 0.7

    init(pixelToSky: [Double], axes: [SIMD3<Double>], visibility: Double, dark: Bool) {
        self.pixelToSky = pixelToSky
        self.axes = axes
        self.visibility = visibility
        self.dark = dark
    }

    init(_ pic: NightSkyARScene.MilkyWayPicture, dark: Bool) {
        let f = pic.frame
        self.init(pixelToSky: pic.pixelToSky,
                  axes: [f.x, f.y, f.z].map { SIMD3($0.east, $0.north, $0.up) },
                  visibility: pic.visibility.factor, dark: dark)
    }

    /// Яркость реалистичной части (свечение и звёзды) на высоте `alt`: правила видимости с дымкой у горизонта,
    /// не ниже пола; в «тёмном месте» — полная. Так же считает шейдер.
    func real(altitude alt: Double) -> Double {
        dark ? 1 : max(visibility * MilkyWayLook.horizonFade(altitude: alt), Self.planFloor)
    }

    var p: simd_double3x3 {
        let m = pixelToSky
        return simd_double3x3(rows: [SIMD3(m[0], m[1], m[2]), SIMD3(m[3], m[4], m[5]), SIMD3(m[6], m[7], m[8])])
    }

    /// Галактика → (x·s, y·s, s) в точках окна: обратное к `P`, умноженное на оси.
    var galacticToScreen: simd_double3x3 { p.inverse * simd_double3x3(columns: (axes[0], axes[1], axes[2])) }

    /// Фокус в точках на радиан (из луча окна: столбец при x — `right / f`).
    var focal: Double { 1 / simd_length(SIMD3(pixelToSky[0], pixelToSky[3], pixelToSky[6])) }

    /// Точка окна, куда ложится звезда (l, b); `nil` — за спиной.
    func screen(l: Double, b: Double) -> CGPoint? {
        let q = galacticToScreen * Self.unit(l: l, b: b)
        guard q.z > 1e-6 else { return nil }
        return CGPoint(x: q.x / q.z, y: q.y / q.z)
    }

    /// Высота над горизонтом направления (l, b), градусы.
    func altitude(l: Double, b: Double) -> Double {
        let v = Self.unit(l: l, b: b)
        let up = axes[0].z * v.x + axes[1].z * v.y + axes[2].z * v.z
        return asin(min(max(up, -1), 1)) * 180 / .pi
    }

    static func unit(l: Double, b: Double) -> SIMD3<Double> {
        let lr = l * .pi / 180, br = b * .pi / 180
        return SIMD3(cos(br) * cos(lr), cos(br) * sin(lr), sin(br))
    }
}

extension MilkyWayGaia {
    /// Сколько первых записей рисовать в этом кадре, чтобы в окне `size` было не больше `budget` звёзд: ячейки
    /// 5° × 5°, попавшие в кадр (с запасом в ячейку), складываются по пределу G; файл идёт от ярких к слабым,
    /// поэтому при повороте к ядру, где звёзд гуще, отсекаются слабейшие. `visible` — оценка сверху.
    func drawRange(_ look: MilkyWayGaiaLook, size: CGSize, origin: CGPoint = .zero) -> (end: Int, visible: Int, gLimit: Double) {
        let m = look.galacticToScreen
        let pad = look.focal * 5.0 * .pi / 180
        var visible: [Int] = []
        for ib in 0..<Self.cellsB {
            let b = (Double(ib) + 0.5) * Self.cellDeg - 90
            for il in 0..<Self.cellsL {
                let l = (Double(il) + 0.5) * Self.cellDeg
                let q = m * MilkyWayGaiaLook.unit(l: l, b: b)
                guard q.z > 0.05, look.altitude(l: l, b: b) > -Self.cellDeg else { continue }
                let x = q.x / q.z - Double(origin.x), y = q.y / q.z - Double(origin.y)
                let r = pad / max(q.z, 0.3)
                if x > -r, x < Double(size.width) + r, y > -r, y < Double(size.height) + r {
                    visible.append(ib * Self.cellsL + il)
                }
            }
        }
        func total(_ g: Int) -> Int { visible.reduce(0) { $0 + Int(cells[$1 * 256 + g]) } }
        let all = total(255)
        if all <= Self.budget { return (count, all, 25.5) }
        var lo = Int((Self.brightestG * 10).rounded()), hi = 255
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if total(mid) <= Self.budget { lo = mid } else { hi = mid - 1 }
        }
        return (prefix[lo], total(lo), Double(lo) / 10)
    }
}

#if os(iOS)

/// Видеокарта для слоя Gaia: один набор на запуск (звёзды, карта, цвета), сколько бы холстов его ни рисовало —
/// экран и копии под линзами меток.
final class MilkyWayGaiaGPU: @unchecked Sendable {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let data: MilkyWayGaia
    private let glowPipeline: MTLRenderPipelineState
    private let starPipeline: MTLRenderPipelineState
    private let stars: MTLBuffer
    private let colors: MTLBuffer
    private let glow: MTLTexture
    private let sampler: MTLSamplerState

    /// Сколько раз собирался (замер памяти: один раз за запуск).
    nonisolated(unsafe) private(set) static var builds = 0
    static let shared: MilkyWayGaiaGPU? = MilkyWayGaia.shared.flatMap(MilkyWayGaiaGPU.init)

    struct Uniforms {
        var p0, p1, p2: SIMD4<Float>
        var gx, gy, gz: SIMD4<Float>
        var q0, q1, q2: SIMD4<Float>
        /// Ширина и высота холста, pt; сдвиг холста в окне.
        var view: SIMD4<Float>
        /// Точек на pt, видимость, пол, «тёмное место».
        var look: SIMD4<Float>
        /// k, γ тонирования, сила подклада, начало звёзд.
        var tone: SIMD4<Float>
    }

    init?(_ data: MilkyWayGaia) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.source, options: nil) else { return nil }
        Self.builds += 1
        self.device = device
        self.queue = queue
        self.data = data
        func pipeline(_ v: String, _ f: String, stars: Bool) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: v)
            d.fragmentFunction = library.makeFunction(name: f)
            let c = d.colorAttachments[0]!
            c.pixelFormat = .bgra8Unorm
            if stars {
                // Звезда ложится «поверх» с альфой = своей яркости: на тёмном — как сложение, на свечении — «экран»
                // (так же звёзды кладёт `preview.py`). Предумноженная альфа остаётся честной.
                c.isBlendingEnabled = true
                c.rgbBlendOperation = .add
                c.sourceRGBBlendFactor = .one
                c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                c.alphaBlendOperation = .add
                c.sourceAlphaBlendFactor = .one
                c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        guard let gp = pipeline("gaiaGlowVertex", "gaiaGlowFragment", stars: false),
              let sp = pipeline("gaiaStarVertex", "gaiaStarFragment", stars: true),
              let sb = data.records.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }),
              let cb = device.makeBuffer(bytes: data.colors, length: data.colors.count * MemoryLayout<SIMD4<Float>>.stride) else { return nil }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Unorm, width: data.glowWidth,
                                                          height: data.glowHeight, mipmapped: false)
        td.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: td) else { return nil }
        data.glow.withUnsafeBytes {
            tex.replace(region: MTLRegionMake2D(0, 0, data.glowWidth, data.glowHeight), mipmapLevel: 0,
                        withBytes: $0.baseAddress!, bytesPerRow: data.glowWidth * 8)
        }
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.sAddressMode = .repeat
        sd.tAddressMode = .clampToEdge
        guard let smp = device.makeSamplerState(descriptor: sd) else { return nil }
        glowPipeline = gp
        starPipeline = sp
        stars = sb
        colors = cb
        glow = tex
        sampler = smp
    }

    func uniforms(_ look: MilkyWayGaiaLook, size: CGSize, origin: CGPoint, scale: CGFloat) -> Uniforms {
        let m = look.pixelToSky.map(Float.init)
        func v3(_ v: SIMD3<Double>) -> SIMD4<Float> { SIMD4(Float(v.x), Float(v.y), Float(v.z), 0) }
        let q = look.galacticToScreen.transpose   // столбцы транспонированной — строки исходной
        // Подклад — по светлому небу (видимость глазом), «тёмное место» его не снимает: небо кадра светлее от флага не стало.
        let under = MilkyWayGaiaLook.underlay * (1 - look.visibility)
        return Uniforms(p0: SIMD4(m[0], m[1], m[2], 0), p1: SIMD4(m[3], m[4], m[5], 0), p2: SIMD4(m[6], m[7], m[8], 0),
                        gx: v3(look.axes[0]), gy: v3(look.axes[1]), gz: v3(look.axes[2]),
                        q0: v3(q.columns.0), q1: v3(q.columns.1), q2: v3(q.columns.2),
                        view: SIMD4(Float(size.width), Float(size.height), Float(origin.x), Float(origin.y)),
                        look: SIMD4(Float(scale), Float(look.visibility), Float(MilkyWayGaiaLook.planFloor), look.dark ? 1 : 0),
                        tone: SIMD4(Float(MilkyWayGaiaLook.toneK), Float(MilkyWayGaiaLook.toneGamma), Float(under),
                                    Float(data.start)))
    }

    /// Два прохода в `target`: свечение (заменяет всё: свет в RGB, подклад в альфе) и звёзды поверх, сложением.
    /// Возвращает, сколько записей нарисовано и оценку звёзд в кадре.
    @discardableResult
    func encode(_ look: MilkyWayGaiaLook, size: CGSize, origin: CGPoint, scale: CGFloat, target: MTLTexture,
                buffer: MTLCommandBuffer, stars drawStars: Bool = true) -> (drawn: Int, visible: Int) {
        var u = uniforms(look, size: size, origin: origin, scale: scale)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return (0, 0) }
        enc.setRenderPipelineState(glowPipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.setFragmentTexture(glow, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        var result = (drawn: 0, visible: 0)
        if drawStars {
            let range = data.drawRange(look, size: size, origin: origin)
            let n = max(0, range.end - data.start)
            result = (n, range.visible)
            if n > 0 {
                enc.setRenderPipelineState(starPipeline)
                enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
                enc.setVertexBuffer(stars, offset: 0, index: 1)
                enc.setVertexBuffer(colors, offset: 0, index: 2)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: n, baseInstance: data.start)
            }
        }
        enc.endEncoding()
        return result
    }

    /// Кадр в память (тесты и замеры): `pixels` — ширина × высота × 4 байта BGRA, свет без подложки (подклад в альфе).
    func render(_ look: MilkyWayGaiaLook, size: CGSize, scale: CGFloat, origin: CGPoint = .zero,
                stars drawStars: Bool = true) -> (pixels: [UInt8], width: Int, height: Int, drawn: Int, visible: Int)? {
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: td), let cmd = queue.makeCommandBuffer() else { return nil }
        let r = encode(look, size: size, origin: origin, scale: scale, target: tex, buffer: cmd, stars: drawStars)
        cmd.commit()
        cmd.waitUntilCompleted()
        var out = [UInt8](repeating: 0, count: w * h * 4)
        out.withUnsafeMutableBytes {
            tex.getBytes($0.baseAddress!, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return (out, w, h, r.drawn, r.visible)
    }

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct U { float4 p0, p1, p2, gx, gy, gz, q0, q1, q2, view, look, tone; };
    constant float DEG = 57.29577951;
    constant float3 LUMA = float3(0.2126, 0.7152, 0.0722);

    static float smooth01(float t) { t = clamp(t, 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }

    // Яркость реалистичной части: видимость с дымкой до 8° (`MilkyWayDust.haze`), не ниже пола; «тёмное место» — 1.
    static float realAt(constant U &u, float alt) {
        if (u.look.w > 0.5) return 1.0;
        return max(u.look.y * smooth01(alt / 8.0), u.look.z);
    }

    struct GlowOut { float4 position [[position]]; };

    vertex GlowOut gaiaGlowVertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        GlowOut o; o.position = float4(p * 2.0 - 1.0, 0.0, 1.0); return o;
    }

    // Свечение слабых звёзд: пиксель → луч → (l, b) → карта (u = fract(0.5 − l/360), v = 0.5 − b/180), билинейно,
    // по u с повтором. Тон I_out = k·Y^γ, оттенок карты сохраняется. Альфа — сила тёмного подклада под полосой.
    fragment float4 gaiaGlowFragment(GlowOut in [[stage_in]], constant U &u [[buffer(0)]],
                                     texture2d<float> map [[texture(0)]], sampler s [[sampler(0)]]) {
        float2 pt = in.position.xy / u.look.x + u.view.zw;
        float3 e = normalize(float3(dot(u.p0.xyz, float3(pt, 1.0)), dot(u.p1.xyz, float3(pt, 1.0)),
                                    dot(u.p2.xyz, float3(pt, 1.0))));
        float alt = asin(clamp(e.z, -1.0, 1.0)) * DEG;
        float edge = smooth01(alt / 1.0);
        if (edge <= 0.0) return float4(0.0);
        float gx = dot(e, u.gx.xyz), gy = dot(e, u.gy.xyz), gz = dot(e, u.gz.xyz);
        float l = atan2(gy, gx) * DEG;
        float b = asin(clamp(gz, -1.0, 1.0)) * DEG;
        float3 rgb = map.sample(s, float2(fract(0.5 - l / 360.0), 0.5 - b / 180.0)).rgb;
        float y = dot(rgb, LUMA);
        float yo = min(u.tone.x * pow(max(y, 1e-7), u.tone.y), 1.0);
        float3 toned = y > 1e-7 ? min(rgb * (yo / y), float3(1.0)) : float3(0.0);
        float3 light = toned * realAt(u, alt) * edge;
        // Подклад: где полоса (тонированная яркость 0,05…0,15 и выше), кадр темнеет; на ярком небе он и виден.
        float under = u.tone.z * smoothstep(0.05, 0.15, yo) * edge;
        // Честная предумноженная альфа (свет не ярче альфы): наложение «поверх» даёт «экран» по подкладу,
        // `light + кадр·(1 − подклад)·(1 − свет)`. Свет при нулевой альфе симулятор складывал плитками.
        float lit = max(light.r, max(light.g, light.b));
        return float4(light, 1.0 - (1.0 - under) * (1.0 - lit));
    }

    struct StarOut {
        float4 position [[position]];
        float3 color;
        float2 local;
        float radius;
    };

    // Звезда Gaia: запись 8 байт (l, b, G, BP−RP, флаги) → квадрат из двух треугольников вокруг точки (не point
    // sprite: в симуляторе координата внутри точки не менялась, звёзды выходили плитками). Вне кадра и под
    // горизонтом — отсекается.
    vertex StarOut gaiaStarVertex(uint vid [[vertex_id]], uint iid [[instance_id]], constant U &u [[buffer(0)]],
                                  device const uchar *rec [[buffer(1)]], device const float4 *lut [[buffer(2)]]) {
        StarOut o;
        o.position = float4(2.0, 2.0, 0.0, 1.0); o.color = float3(0.0); o.local = float2(0.0); o.radius = 0.0;
        uint k = iid * 8;
        float l = float(ushort(rec[k]) | (ushort(rec[k + 1]) << 8)) * (360.0 / 65536.0) / DEG;
        float b = float(short(ushort(rec[k + 2]) | (ushort(rec[k + 3]) << 8))) * (180.0 / 65536.0) / DEG;
        float g = float(rec[k + 4]) / 10.0;
        int c = int(as_type<char>(rec[k + 5]));
        float3 v = float3(cos(b) * cos(l), cos(b) * sin(l), sin(b));
        float3 q = float3(dot(u.q0.xyz, v), dot(u.q1.xyz, v), dot(u.q2.xyz, v));
        if (q.z <= 1e-4) return o;
        float x = q.x / q.z - u.view.z, y = q.y / q.z - u.view.w;
        if (x < -6.0 || y < -6.0 || x > u.view.x + 6.0 || y > u.view.y + 6.0) return o;
        float up = u.gx.z * v.x + u.gy.z * v.y + u.gz.z * v.z;
        float alt = asin(clamp(up, -1.0, 1.0)) * DEG;
        float edge = smooth01(alt / 1.0);
        if (edge <= 0.0) return o;
        // Поперечник от G: G 10 → 1 pt, ярче — до ~4 pt с мягким насыщением (радиус 0,5…2 pt: при радиусе 1…4 pt
        // 41 тысяча звёзд у ядра сливалась в пятна, кадр 22:30 Сочи). Яркость — корень из потока, 0,15…1.
        float r = 0.5 + 1.5 * (1.0 - exp(-max(10.0 - g, 0.0) / 3.0));
        float amp = clamp(pow(10.0, -0.2 * (g - 5.0)), 0.15, 1.0) * realAt(u, alt) * edge;
        float rpx = r * u.look.x, half_ = rpx + 1.0;
        float2 corner = float2(float(vid & 1u), float(vid >> 1u)) * 2.0 - 1.0;
        float2 px = float2(x, y) * u.look.x + corner * half_;
        float2 size = u.view.xy * u.look.x;
        o.position = float4(2.0 * px.x / size.x - 1.0, 1.0 - 2.0 * px.y / size.y, 0.0, 1.0);
        o.color = lut[c + 128].rgb * amp;
        o.local = corner * half_;
        o.radius = rpx;
        return o;
    }

    fragment float4 gaiaStarFragment(StarOut in [[stage_in]]) {
        float cov = clamp(in.radius + 0.5 - length(in.local), 0.0, 1.0);
        float3 c = in.color * cov;
        return float4(c, max(c.r, max(c.g, c.b)));
    }
    """
}

/// Холст Gaia на экране: прозрачный слой Metal, перерисовывается при каждом обновлении сцены (поворот телефона —
/// новая матрица). Предумноженная альфа честная (свет не ярче альфы): кадр под слоем темнеет подкладом и ложится
/// под свет «экраном».
struct SunARGaiaSkyView: UIViewRepresentable {
    let gpu: MilkyWayGaiaGPU
    let look: MilkyWayGaiaLook
    var origin: CGPoint = .zero

    func makeUIView(context: Context) -> GaiaSkyUIView { GaiaSkyUIView(gpu: gpu) }

    func updateUIView(_ view: GaiaSkyUIView, context: Context) {
        view.look = look
        view.origin = origin
        view.redraw()
    }
}

final class GaiaSkyUIView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private let gpu: MilkyWayGaiaGPU
    var look: MilkyWayGaiaLook?
    var origin: CGPoint = .zero
    /// Замер кадра (`-LPShotReport`): сколько записей нарисовано, оценка звёзд в окне, CPU мс на кодирование.
    nonisolated(unsafe) static var lastStats = (drawn: 0, visible: 0, cpuMs: 0.0, gpuMs: 0.0)

    init(gpu: MilkyWayGaiaGPU) {
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
        let r = gpu.encode(look, size: bounds.size, origin: origin, scale: scale, target: drawable.texture, buffer: cmd)
        cmd.addCompletedHandler { b in
            GaiaSkyUIView.lastStats.gpuMs = (b.gpuEndTime - b.gpuStartTime) * 1000
        }
        cmd.present(drawable)
        cmd.commit()
        Self.lastStats.drawn = r.drawn
        Self.lastStats.visible = r.visible
        Self.lastStats.cpuMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    }
}

#endif

/// Откуда слой берёт картину: Gaia, если данные прочитались, иначе формула. В отладке `-LPSunARMWSource formula`
/// включает запасной вариант при живых данных (замер «без файла»).
enum MilkyWayGaiaSource {
    static var useGaia: Bool {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "LPSunARMWSource") == "formula" { return false }
        #endif
        return MilkyWayGaia.shared != nil
    }

    #if os(iOS)
    static var gpu: MilkyWayGaiaGPU? { useGaia ? MilkyWayGaiaGPU.shared : nil }
    #endif
}
