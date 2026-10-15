import SwiftUI
import LightPlanCore
#if os(iOS)
import AVFoundation
import Metal
import QuartzCore
import UIKit
#endif

/// Кадр камеры в метках AR (шаг 29.8в.4). Слово Алексея 14.10: «мы не меняем кадр, у нас не фотоаппарат… в
/// интерфейсе камеры Apple используется стекло вокруг кнопки спуска и накладывается на кадр. изгиб допустим».
///
/// **Что делается с кадром.** Камера отдаёт кадры в приложение (`AVCaptureVideoDataOutput`), и слой Metal
/// гнёт ими кромку стеклянных дисков солнца и луны. Кадр только показывается: он не сохраняется, не пишется
/// на диск, никуда не отправляется и не живёт дольше следующего кадра (одна текстура, её сменяет следующая;
/// `stop()` её отпускает). Остальной экран — по-прежнему живое превью системы.

/// Один стеклянный диск для слоя Metal: центр, радиус и ширина гнущей кромки в точках окна.
struct ARLensSpec: Equatable, Sendable {
    var center: CGPoint
    var radius: CGFloat
    var rim: CGFloat
    var fade: Double
}

/// Как точка окна (pt) ложится на кадр (0…1, начало слева сверху у кадра в родной ориентации датчика):
/// `uv = origin + dx·x + dy·y`. Чистая арифметика — проверяется юнит-тестом без камеры.
struct ARFrameMapping: Equatable, Sendable {
    var origin: SIMD2<Double>
    var dx: SIMD2<Double>
    var dy: SIMD2<Double>

    func uv(at p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + dx.x * p.x + dy.x * p.y, y: origin.y + dx.y * p.x + dy.y * p.y)
    }

    /// Портрет, кадр заполняет окно целиком (`resizeAspectFill`), датчик стоит в альбоме и повёрнут на 90° по
    /// часовой, чтобы встать в портрет — так же, как превью системы при `videoRotationAngle = 90`.
    /// `buffer` — размер кадра в родной (альбомной) ориентации.
    static func aspectFillPortrait(view: CGSize, buffer: CGSize) -> ARFrameMapping {
        let bw = Double(buffer.width), bh = Double(buffer.height)
        // Портретное изображение: ширина = bh, высота = bw.
        let scale = max(Double(view.width) / bh, Double(view.height) / bw)
        let vw = Double(view.width), vh = Double(view.height)
        // Точка окна → точка портретного изображения (ix, iy); оттуда в родные (nx, ny) = (iy, bh − ix).
        // ix = (x − vw/2)/scale + bh/2;  iy = (y − vh/2)/scale + bw/2.
        // u = iy / bw;  v = (bh − ix) / bh = 1 − ix / bh.
        let origin = SIMD2((-vh / 2 / scale + bw / 2) / bw, 1 - (-vw / 2 / scale + bh / 2) / bh)
        return ARFrameMapping(origin: origin,
                              dx: SIMD2(0, -1 / (scale * bh)),
                              dy: SIMD2(1 / (scale * bw), 0))
    }

    /// По трём точкам окна и тому, куда их переводит система (превью камеры): начало, точка справа, точка снизу.
    static func fromSamples(view: CGSize, origin o: CGPoint, right r: CGPoint, bottom b: CGPoint) -> ARFrameMapping? {
        guard view.width > 0, view.height > 0 else { return nil }
        let dx = SIMD2((r.x - o.x) / view.width, (r.y - o.y) / view.width)
        let dy = SIMD2((b.x - o.x) / view.height, (b.y - o.y) / view.height)
        // Все три точки в одно место — превью ещё не запущено и ничего не знает о кадре.
        guard abs(dx.x) + abs(dx.y) + abs(dy.x) + abs(dy.y) > 1e-9,
              [o.x, o.y, r.x, r.y, b.x, b.y].allSatisfy(\.isFinite) else { return nil }
        return ARFrameMapping(origin: SIMD2(Double(o.x), Double(o.y)), dx: SIMD2(Double(dx.x), Double(dx.y)),
                              dy: SIMD2(Double(dy.x), Double(dy.y)))
    }
}

#if os(iOS)

/// Рисует стеклянные диски по кадрам камеры в прозрачный слой над превью. Один проход, до четырёх дисков:
/// кадр читается только внутри дисков (сплошь вне их слой прозрачен — виден системный превью).
final class ARLensRenderer: @unchecked Sendable {
    /// Замеры слоя: сколько кадров принято и сколько нарисовано, миллисекунды CPU на кадр.
    struct Stats: Sendable {
        var framesIn = 0
        var framesDrawn = 0
        var cpuSeconds = 0.0
        var firstFrame: CFAbsoluteTime = 0
        var lastFrame: CFAbsoluteTime = 0
        /// Кадров в секунду между первым и последним принятым.
        var fps: Double { lastFrame > firstFrame ? Double(framesIn - 1) / (lastFrame - firstFrame) : 0 }
        var cpuMillisecondsPerFrame: Double { framesDrawn > 0 ? cpuSeconds * 1000 / Double(framesDrawn) : 0 }
    }

    private struct LensGPU {
        var center: SIMD2<Float>
        var radius: Float
        var rim: Float
        var fade: Float
        var pad0: Float = 0, pad1: Float = 0, pad2: Float = 0
    }

    private struct FrameGPU {
        var view: SIMD2<Float>
        var scale: Float
        var shift: Float
        var m0: SIMD2<Float>
        var mx: SIMD2<Float>
        var my: SIMD2<Float>
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let lensPipeline: MTLRenderPipelineState
    private let framePipeline: MTLRenderPipelineState
    private var cache: CVMetalTextureCache?

    private let lock = NSLock()
    private var lenses: [ARLensSpec] = []
    private var mapping: ARFrameMapping?
    private var texture: MTLTexture?
    private var retained: CVMetalTexture?
    private var bufferSize = CGSize.zero
    private var viewSize = CGSize.zero
    private var scale: CGFloat = 1
    private var layer: CAMetalLayer?
    private var drewSomething = false
    private var stats = Stats()
    /// Кадр рисуется целиком (подставная камера в симуляторе: системного превью под слоем нет).
    var drawsFullFrame = false

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.source, options: nil) else { return nil }
        self.device = device
        self.queue = queue
        func pipeline(_ v: String, _ f: String) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: v)
            d.fragmentFunction = library.makeFunction(name: f)
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        guard let lp = pipeline("lensVertex", "lensFragment"), let fp = pipeline("frameVertex", "frameFragment") else { return nil }
        lensPipeline = lp
        framePipeline = fp
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        guard cache != nil else { return nil }
    }

    // MARK: Вход с главной нити

    func attach(_ layer: CAMetalLayer, size: CGSize, scale: CGFloat) {
        lock.lock(); defer { lock.unlock() }
        self.layer = layer
        viewSize = size
        self.scale = scale
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.maximumDrawableCount = 2
        layer.drawableSize = CGSize(width: size.width * scale, height: size.height * scale)
    }

    func set(lenses: [ARLensSpec]) {
        lock.lock(); self.lenses = lenses; lock.unlock()
    }

    /// Соответствие окна и кадра, от превью системы. `nil` — берётся расчётное (`aspectFillPortrait`).
    func set(mapping: ARFrameMapping?) {
        lock.lock(); self.mapping = mapping; lock.unlock()
    }

    func statsSnapshot() -> Stats {
        lock.lock(); defer { lock.unlock() }
        return stats
    }

    /// Экран закрыт: кадр отпущен.
    func release() {
        lock.lock()
        texture = nil
        retained = nil
        lenses = []
        lock.unlock()
        if let cache { CVMetalTextureCacheFlush(cache, 0) }
    }

    // MARK: Кадры

    /// Принять кадр (очередь камеры) и нарисовать диски. Кадр держится только в этой текстуре — до следующего.
    func ingest(_ buffer: CVPixelBuffer) {
        guard let cache else { return }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        var cv: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm, w, h, 0, &cv) == kCVReturnSuccess,
              let cv, let tex = CVMetalTextureGetTexture(cv) else { return }
        let started = CFAbsoluteTimeGetCurrent()
        lock.lock()
        texture = tex
        retained = cv
        bufferSize = CGSize(width: w, height: h)
        if stats.framesIn == 0 { stats.firstFrame = started }
        stats.framesIn += 1
        stats.lastFrame = started
        lock.unlock()
        if draw() {
            lock.lock()
            stats.framesDrawn += 1
            stats.cpuSeconds += CFAbsoluteTimeGetCurrent() - started
            lock.unlock()
        }
    }

    /// Нарисовать диски по последнему кадру. `false` — рисовать нечего.
    private func draw() -> Bool {
        lock.lock()
        let lenses = self.lenses
        let tex = texture
        let layer = self.layer
        let view = viewSize, scale = self.scale, buffer = bufferSize
        let mapping = self.mapping ?? ARFrameMapping.aspectFillPortrait(view: view, buffer: buffer)
        let full = drawsFullFrame
        let hadContent = drewSomething
        lock.unlock()
        guard let layer, let tex, view.width > 0 else { return false }
        let empty = lenses.isEmpty && !full
        // Дисков нет: один раз стереть то, что нарисовано, и молчать.
        if empty && !hadContent { return false }

        guard let drawable = layer.nextDrawable(), let cmd = queue.makeCommandBuffer() else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return false }

        let s = Float(scale)
        var frame = FrameGPU(view: SIMD2(Float(view.width) * s, Float(view.height) * s), scale: s, shift: 5 * s,
                             m0: SIMD2(Float(mapping.origin.x), Float(mapping.origin.y)),
                             mx: SIMD2(Float(mapping.dx.x), Float(mapping.dx.y)),
                             my: SIMD2(Float(mapping.dy.x), Float(mapping.dy.y)))
        enc.setFragmentTexture(tex, index: 0)
        enc.setVertexBytes(&frame, length: MemoryLayout<FrameGPU>.stride, index: 1)
        enc.setFragmentBytes(&frame, length: MemoryLayout<FrameGPU>.stride, index: 1)
        if full {
            enc.setRenderPipelineState(framePipeline)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        if !lenses.isEmpty {
            var gpu = lenses.prefix(4).map {
                LensGPU(center: SIMD2(Float($0.center.x) * s, Float($0.center.y) * s), radius: Float($0.radius) * s,
                        rim: Float($0.rim) * s, fade: Float($0.fade))
            }
            enc.setRenderPipelineState(lensPipeline)
            enc.setVertexBytes(&gpu, length: MemoryLayout<LensGPU>.stride * gpu.count, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: gpu.count)
        }
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
        lock.lock(); drewSomething = !empty; lock.unlock()
        return true
    }

    // Фрагмент читает кадр только внутри диска; у кромки берёт точку дальше от центра, как `glassRing`
    // (`Glass.metal`): сдвиг растёт к кромке квадратом, насыщенность и яркость — `--glass-optic` веба.
    private static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Lens { float2 center; float radius; float rim; float fade; float pad0; float pad1; float pad2; };
    struct Frame { float2 view; float scale; float shift; float2 m0; float2 mx; float2 my; };
    struct LensOut { float4 position [[position]]; float2 center; float radius; float rim; float fade; };

    vertex LensOut lensVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                              constant Lens *lenses [[buffer(0)]], constant Frame &f [[buffer(1)]]) {
        Lens l = lenses[iid];
        float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
        float2 p = l.center + corner * (l.radius + 1.5);
        LensOut o;
        o.position = float4(p.x / f.view.x * 2.0 - 1.0, 1.0 - p.y / f.view.y * 2.0, 0.0, 1.0);
        o.center = l.center; o.radius = l.radius; o.rim = l.rim; o.fade = l.fade;
        return o;
    }

    static float3 optic(float3 c, float s, float b) {
        float3x3 m = float3x3(float3(0.213 + 0.787 * s, 0.213 - 0.213 * s, 0.213 - 0.213 * s),
                              float3(0.715 - 0.715 * s, 0.715 + 0.285 * s, 0.715 - 0.715 * s),
                              float3(0.072 - 0.072 * s, 0.072 - 0.072 * s, 0.072 + 0.928 * s));
        return clamp((m * c) * b, 0.0, 1.0);
    }

    fragment float4 lensFragment(LensOut in [[stage_in]], texture2d<float> frame [[texture(0)]],
                                 constant Frame &f [[buffer(1)]]) {
        float2 p = in.position.xy;
        float2 d = p - in.center;
        float r = length(d);
        float cover = clamp(in.radius - r + 0.5, 0.0, 1.0);
        if (cover <= 0.0) discard_fragment();
        float k = r / in.radius;
        float rin = 1.0 - in.rim / in.radius;
        float2 q = p;
        bool onRim = k > rin && r > 0.0;
        if (onRim) {
            float t = (k - rin) / (1.0 - rin);
            q = p + (d / r) * f.shift * t * t;
        }
        float2 v = q / f.scale;
        float2 uv = f.m0 + f.mx * v.x + f.my * v.y;
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float3 c = frame.sample(s, uv).rgb;
        if (onRim) c = optic(c, 1.5, 1.06);
        float a = cover * in.fade;
        return float4(c * a, a);
    }

    struct FrameOut { float4 position [[position]]; };

    vertex FrameOut frameVertex(uint vid [[vertex_id]]) {
        float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
        FrameOut o;
        o.position = float4(corner, 0.0, 1.0);
        return o;
    }

    fragment float4 frameFragment(FrameOut in [[stage_in]], texture2d<float> frame [[texture(0)]],
                                  constant Frame &f [[buffer(1)]]) {
        float2 v = in.position.xy / f.scale;
        float2 uv = f.m0 + f.mx * v.x + f.my * v.y;
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        return float4(frame.sample(s, uv).rgb, 1.0);
    }
    """
}

/// Что ставит кадры в слой Metal: источник кадров и сам слой одним хозяином.
enum ARFrameFeed {
    /// Живая камера: системное превью и слой дисков над ним.
    case session(AVCaptureSession, ARLensRenderer?)
    /// Подставная камера (отладка, симулятор): кадр целиком рисует слой Metal.
    case synthetic(ARLensRenderer)
}

/// Сессия камеры с выходом кадров в `ARLensRenderer`.
final class ARFrameTap: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let output = AVCaptureVideoDataOutput()
    let queue = DispatchQueue(label: "lightplan.sunar.frames", qos: .userInteractive)
    private let renderer: ARLensRenderer

    init(renderer: ARLensRenderer) {
        self.renderer = renderer
        super.init()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        renderer.ingest(buffer)
    }
}

/// Слой над превью: прозрачный `CAMetalLayer` на весь экран. Системное превью лежит под ним.
final class ARLensLayerView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    var renderer: ARLensRenderer?
    /// Превью, у которого спрашивается, как окно ложится на кадр. `nil` — расчётное соответствие.
    weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var mappedFor = CGSize.zero
    private var mappedLive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.windowScene?.screen.scale ?? traitCollection.displayScale
        renderer?.attach(metalLayer, size: bounds.size, scale: scale)
        refreshMapping(force: true)
        #if DEBUG
        startLog()
        #endif
    }

    #if DEBUG
    private var logTimer: Timer?

    /// `-LPSunARLensLog <файл>`: раз в секунду строка замера слоя — принято и нарисовано кадров, кадров/с,
    /// миллисекунд процессора на нарисованный кадр (`Tools/ar_lens_bench.js`).
    private func startLog() {
        guard logTimer == nil, let path = UserDefaults.standard.string(forKey: "LPSunARLensLog") else { return }
        logTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let s = self?.renderer?.statsSnapshot() else { return }
            let line = String(format: "t=%.0f in=%d drawn=%d fps=%.1f cpuMsPerFrame=%.3f\n", Date().timeIntervalSince1970,
                              s.framesIn, s.framesDrawn, s.fps, s.cpuMillisecondsPerFrame)
            if let h = FileHandle(forWritingAtPath: path) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? Data(line.utf8).write(to: URL(fileURLWithPath: path))
            }
        }
    }
    #endif

    /// Соответствие окна и кадра — по трём точкам превью системы, чтобы диск брал ровно тот кадр, что видно
    /// вокруг него (поворот и «заполнить» решает система, а не наша арифметика).
    func refreshMapping(force: Bool = false) {
        guard let renderer, let preview = previewLayer, bounds.width > 0 else { return }
        guard force || mappedFor != bounds.size || !mappedLive else { return }
        mappedFor = bounds.size
        let o = preview.captureDevicePointConverted(fromLayerPoint: CGPoint(x: 0, y: 0))
        let r = preview.captureDevicePointConverted(fromLayerPoint: CGPoint(x: bounds.width, y: 0))
        let b = preview.captureDevicePointConverted(fromLayerPoint: CGPoint(x: 0, y: bounds.height))
        let m = ARFrameMapping.fromSamples(view: bounds.size, origin: o, right: r, bottom: b)
        mappedLive = m != nil
        renderer.set(mapping: m)
    }
}

/// Фон экрана AR на iPhone: превью системы, над ним слой дисков. Диски — из SwiftUI (`lenses`), каждый кадр.
struct ARCameraBackdrop: UIViewRepresentable {
    let feed: ARFrameFeed
    let lenses: [ARLensSpec]

    func makeUIView(context: Context) -> ARBackdropView {
        let v = ARBackdropView()
        switch feed {
        case .session(let session, let renderer):
            v.preview.session = session
            v.preview.videoGravity = .resizeAspectFill
            v.lensView.renderer = renderer
            v.lensView.previewLayer = v.preview
        case .synthetic(let renderer):
            renderer.drawsFullFrame = true
            v.lensView.renderer = renderer
        }
        return v
    }

    func updateUIView(_ v: ARBackdropView, context: Context) {
        switch feed {
        case .session(_, let renderer):
            if let c = v.preview.connection, c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
            renderer?.set(lenses: lenses)
        case .synthetic(let renderer):
            renderer.set(lenses: lenses)
        }
        v.lensView.refreshMapping()
    }

    static func dismantleUIView(_ v: ARBackdropView, coordinator: ()) {
        v.lensView.renderer?.release()
    }

    final class ARBackdropView: UIView {
        let lensView = ARLensLayerView()
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        override init(frame: CGRect) {
            super.init(frame: frame)
            addSubview(lensView)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            lensView.frame = bounds
        }
    }
}
#endif
