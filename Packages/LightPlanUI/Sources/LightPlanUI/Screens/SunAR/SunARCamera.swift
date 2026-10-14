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

#if os(iOS)
/// Сессия камеры слоя AR. Только живое превью: ни выхода кадров (`AVCaptureVideoDataOutput`), ни фото, ни записи
/// файла — кадр показывается на экране и нигде не сохраняется и никуда не уходит.
///
/// Разрешение спрашивается здесь, при первом входе в AR, и только если камера на устройстве есть: в симуляторе
/// и на Mac устройства нет, и системное окно не появляется.
final class ARCameraRig: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "lightplan.sunar.camera")
    private var configured = false

    /// Итог запуска: состояние и, если камера идёт, её оптика.
    struct Outcome: Sendable {
        let state: ARCameraState
        let optics: CameraOptics?
    }

    func start() async -> Outcome {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return Outcome(state: .noDevice, optics: nil)
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return Outcome(state: .denied, optics: nil) }
        case .denied: return Outcome(state: .denied, optics: nil)
        case .restricted: return Outcome(state: .restricted, optics: nil)
        default: break
        }
        return await withCheckedContinuation { (c: CheckedContinuation<Outcome, Never>) in
            queue.async { [self] in
                if !configured {
                    session.beginConfiguration()
                    session.sessionPreset = .photo
                    guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                        session.commitConfiguration()
                        c.resume(returning: Outcome(state: .failed, optics: nil))
                        return
                    }
                    session.addInput(input)
                    session.commitConfiguration()
                    configured = true
                }
                if !session.isRunning { session.startRunning() }
                // Формат читается после запуска: от пресета зависит, какой именно кадр у превью.
                let format = device.activeFormat
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let long = Double(max(dims.width, dims.height)), short = Double(min(dims.width, dims.height))
                let fov = Double(format.videoFieldOfView)
                let optics = fov > 1 && short > 0 ? CameraOptics(longSideFOV: fov, aspect: long / short) : nil
                c.resume(returning: Outcome(state: session.isRunning ? .running : .failed, optics: optics))
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

/// Превью сессии на весь экран, кадр заполняет окно целиком (как считает `SkyProjection.focalLength`).
struct ARCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ v: PreviewView, context: Context) {
        // Только портрет (docs/17 § 19): превью повёрнуто на 90° от сенсора, который стоит в альбоме.
        if let c = v.previewLayer.connection, c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
#endif
