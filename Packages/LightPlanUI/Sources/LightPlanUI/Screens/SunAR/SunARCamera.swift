import SwiftUI
import LightPlanCore
#if os(iOS)
import AVFoundation
#endif

/// Чем кончилась попытка поднять камеру — отсюда экран AR выбирает, что рисовать под дугой.
enum ARCameraState: Equatable {
    case starting
    case running
    /// Камеры нет: симулятор, Mac.
    case noDevice
    /// Отказ в разрешении.
    case denied
    /// Ограничено системой (родительский контроль, профиль).
    case restricted
    /// Камера есть, разрешена, но сессия не поднялась (занята другим приложением, сбой).
    case failed

    var isLive: Bool { self == .running }
}

/// Итог включения камеры: состояние и, если камера идёт, её оптика.
struct ARCameraOutcome: Sendable {
    let state: ARCameraState
    let optics: CameraOptics?
}

/// Что сказала система о камере до включения. Системное окно с вопросом — внутри `authorize`.
enum ARCameraAuthorization: Sendable, Equatable {
    case granted
    /// Камеры нет: симулятор, Mac.
    case noDevice
    case denied
    case restricted
}

/// Камера слоя AR двумя шагами, чтобы между ними модель могла проверить, что экран ещё открыт: окно «Разрешить
/// камеру?» висит, пока человек читает, и за это время экран могут закрыть (ревью GPT к e7db105, пункт 1).
protocol ARCameraDriving: AnyObject, Sendable {
    func authorize() async -> ARCameraAuthorization
    /// Поднять сессию. Зовётся только когда `authorize` дал `.granted` и экран всё ещё открыт.
    func run() async -> ARCameraOutcome
    func stop()
}

/// Без камеры вовсе — сборка не для iPhone.
final class NoCameraRig: ARCameraDriving {
    func authorize() async -> ARCameraAuthorization { .noDevice }
    func run() async -> ARCameraOutcome { ARCameraOutcome(state: .noDevice, optics: nil) }
    func stop() {}
}

#if os(iOS)
/// Кто отдаёт экрану фон: источник кадров для превью и слоя дисков.
protocol ARFrameFeeding: AnyObject {
    var feed: ARFrameFeed { get }
}

/// Сессия камеры слоя AR: живое превью системы и (с 29.8в.4) выход кадров в слой Metal, который гнёт кромку
/// стеклянных дисков солнца и луны. Кадр только показывается: ни фото, ни записи файла, ни сети, ни хранения —
/// держится одна текстура до следующего кадра (`ARLensRenderer`). Слово Алексея 14.10.
///
/// Разрешение спрашивается здесь, при первом включении камеры (после калибровки), и только если камера на
/// устройстве есть: в симуляторе и на Mac устройства нет, и системное окно не появляется.
final class ARCameraRig: ARCameraDriving, ARFrameFeeding, @unchecked Sendable {
    let session = AVCaptureSession()
    /// Слой дисков; `nil`, если Metal недоступен: диски остаются стеклом без изгиба.
    let lens = ARLensRenderer()
    private let queue = DispatchQueue(label: "lightplan.sunar.camera")
    private var frameTap: ARFrameTap?
    private var configured = false

    var feed: ARFrameFeed { .session(session, lens) }

    func authorize() async -> ARCameraAuthorization {
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else { return .noDevice }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .granted
        }
    }

    /// Формат 4 : 3 около 1440 × 1080 при 30 кадрах/с: кадров в секунду столько же, сколько у превью, а в
    /// слой Metal их идёт в десять раз меньше точек, чем с 12-мегапиксельного `.photo`. Тот же кадр во весь
    /// датчик, поэтому поле зрения и проекция те же (`videoFieldOfView` читается после запуска).
    static func lensFormat(of device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let target = 1440.0 * 1080.0
        var best: (format: AVCaptureDevice.Format, score: Double)?
        for f in device.formats {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            guard Int(d.width) * 3 == Int(d.height) * 4 else { continue }
            let sub = CMFormatDescriptionGetMediaSubType(f.formatDescription)
            guard sub == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                    || sub == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else { continue }
            guard f.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) else { continue }
            let score = abs(Double(d.width) * Double(d.height) - target)
            if best == nil || score < best!.score { best = (f, score) }
        }
        return best?.format
    }

    func run() async -> ARCameraOutcome {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return ARCameraOutcome(state: .noDevice, optics: nil)
        }
        return await withCheckedContinuation { (c: CheckedContinuation<ARCameraOutcome, Never>) in
            queue.async { [self] in
                if !configured {
                    session.beginConfiguration()
                    session.sessionPreset = .photo
                    guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                        session.commitConfiguration()
                        c.resume(returning: ARCameraOutcome(state: .failed, optics: nil))
                        return
                    }
                    session.addInput(input)
                    // Выход кадров — только если есть слой Metal и подходящий формат; иначе всё как в 29.8в.3.
                    if let lens, let format = Self.lensFormat(of: device) {
                        let tap = ARFrameTap(renderer: lens)
                        if session.canAddOutput(tap.output), (try? device.lockForConfiguration()) != nil {
                            device.activeFormat = format
                            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                            device.unlockForConfiguration()
                            session.addOutput(tap.output)
                            if let conn = tap.output.connection(with: .video), conn.isVideoRotationAngleSupported(0) {
                                conn.videoRotationAngle = 0
                            }
                            frameTap = tap
                        }
                    }
                    session.commitConfiguration()
                    configured = true
                }
                if !session.isRunning { session.startRunning() }
                // Формат читается после запуска: от формата зависит, какой именно кадр у превью.
                let format = device.activeFormat
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let long = Double(max(dims.width, dims.height)), short = Double(min(dims.width, dims.height))
                let fov = Double(format.videoFieldOfView)
                let optics = fov > 1 && short > 0 ? CameraOptics(longSideFOV: fov, aspect: long / short) : nil
                c.resume(returning: ARCameraOutcome(state: session.isRunning ? .running : .failed, optics: optics))
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            lens?.release()
        }
    }
}

#if DEBUG
/// Подставная камера для симулятора (`-LPSunARFakeCamera 1`): тридцать кадров в секунду из двух заранее
/// нарисованных, чтобы замер слоя Metal не мерил рисование кадра. Кадр показывает слой Metal целиком.
final class SyntheticCameraRig: ARCameraDriving, ARFrameFeeding, @unchecked Sendable {
    let renderer: ARLensRenderer
    private var buffers: [CVPixelBuffer] = []
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "lightplan.sunar.synthetic", qos: .userInteractive)

    var feed: ARFrameFeed { .synthetic(renderer) }

    init?() {
        guard let r = ARLensRenderer() else { return nil }
        renderer = r
        r.drawsFullFrame = true
        for shift in [0, 24] {
            guard let b = Self.makeFrame(width: 1440, height: 1080, shift: shift) else { return nil }
            buffers.append(b)
        }
    }

    func authorize() async -> ARCameraAuthorization { .granted }

    func run() async -> ARCameraOutcome {
        let t = DispatchSource.makeTimerSource(queue: queue)
        var i = 0
        t.schedule(deadline: .now(), repeating: .nanoseconds(33_333_333), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            i += 1
            self.renderer.ingest(self.buffers[i % self.buffers.count])
        }
        timer = t
        t.resume()
        return ARCameraOutcome(state: .running, optics: .typical)
    }

    func stop() {
        timer?.cancel()
        timer = nil
        renderer.release()
    }

    /// Небо от синего к тёплому у горизонта, сетка через 120 пикселей и косая полоса — на ней виден изгиб кромки.
    private static func makeFrame(width: Int, height: Int, shift: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferMetalCompatibilityKey: true,
                                      kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]]
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let ctx = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [CGColor(red: 0.10, green: 0.16, blue: 0.34, alpha: 1),
                                       CGColor(red: 0.85, green: 0.62, blue: 0.42, alpha: 1)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(height)), end: .zero, options: [])
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
        ctx.setLineWidth(3)
        for x in stride(from: shift, to: width, by: 120) { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: height)) }
        for y in stride(from: shift, to: height, by: 120) { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: width, y: y)) }
        ctx.strokePath()
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
        ctx.fill(CGRect(x: 0, y: height / 3, width: width, height: 60))
        return buffer
    }
}
#endif

#endif
