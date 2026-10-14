import Foundation
import LightPlanCore
#if canImport(CoreMotion)
import CoreMotion
#endif

/// Поворот телефона целиком для слоя AR (шаг 29.8в): куда смотрит задняя камера, наклон и крен.
/// Курс одним числом (`HeadingSource`) для этого мало: AR нужен весь поворот, а не его горизонтальная часть.
public struct AttitudeSample: Sendable, Equatable {
    /// Секунды от запуска системы — только для окна устойчивости курса.
    public let time: TimeInterval
    public let basis: CameraBasis
    /// Модуль угловой скорости, градусы в секунду: объясняет часть разброса курса (`HeadingSteadiness`).
    public let rotationRate: Double
    /// Точность магнитного поля от системы; `nil` — источник её не сообщает (подставной датчик без поля).
    public let magneticAccuracy: MagneticAccuracy?

    public init(time: TimeInterval, basis: CameraBasis, rotationRate: Double, magneticAccuracy: MagneticAccuracy? = nil) {
        self.time = time
        self.basis = basis
        self.rotationRate = rotationRate
        self.magneticAccuracy = magneticAccuracy
    }
}

/// От какого севера отсчитан поворот.
public enum AttitudeNorth: Sendable, Equatable {
    /// `xTrueNorthZVertical`: система поправила магнитный север на склонение (нужно место телефона).
    case trueNorth
    /// `xMagneticNorthZVertical`: истинный север недоступен — курс уйдёт на склонение (в Москве около +12°).
    case magneticNorth
}

@MainActor
public protocol AttitudeSource: AnyObject {
    /// Датчик есть: в симуляторе и на Mac его нет, экран тогда даёт водить пальцем.
    var isAvailable: Bool { get }
    /// От какого севера идут отсчёты; известно после `start`.
    var north: AttitudeNorth? { get }
    func start(_ onSample: @escaping @MainActor (AttitudeSample) -> Void)
    func stop()
    /// Перепроверить, не стал ли доступен истинный север (включили геолокацию, пока экран открыт). Отсчёты после
    /// этого идут уже от истинного севера, `north` обновляется.
    func recheckNorth()
}

public extension AttitudeSource {
    func recheckNorth() {}
}

#if canImport(CoreMotion) && os(iOS)
/// `CMMotionManager`: гироскоп, акселерометр и магнитометр слиты системой. Истинный север — как у ARKit в
/// режиме `gravityAndHeading`; камера и магнитометр здесь независимы, камера может быть и закрыта.
@MainActor
public final class CoreMotionAttitude: AttitudeSource {
    private let manager = CMMotionManager()
    public private(set) var north: AttitudeNorth?
    private var handler: (@MainActor (AttitudeSample) -> Void)?

    public init() {}

    public var isAvailable: Bool { manager.isDeviceMotionAvailable }

    public func start(_ onSample: @escaping @MainActor (AttitudeSample) -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        handler = onSample
        begin()
    }

    private func begin() {
        guard let onSample = handler else { return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        north = frame == .xTrueNorthZVertical ? .trueNorth : .magneticNorth
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(using: frame, to: .main) { motion, _ in
            guard let motion else { return }
            let m = motion.attitude.rotationMatrix
            let r = motion.rotationRate
            let rate = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot() * 180 / Double.pi
            let sample = AttitudeSample(
                time: motion.timestamp,
                basis: CameraBasis(rotation: DeviceRotation(
                    m11: m.m11, m12: m.m12, m13: m.m13,
                    m21: m.m21, m22: m.m22, m23: m.m23,
                    m31: m.m31, m32: m.m32, m33: m.m33)),
                rotationRate: rate,
                magneticAccuracy: Self.accuracy(motion.magneticField.accuracy))
            MainActor.assumeIsolated { onSample(sample) }
        }
    }

    private nonisolated static func accuracy(_ a: CMMagneticFieldCalibrationAccuracy) -> MagneticAccuracy {
        switch a {
        case .uncalibrated: return .uncalibrated
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        @unknown default: return .uncalibrated
        }
    }

    public func recheckNorth() {
        guard north == .magneticNorth, handler != nil, manager.isDeviceMotionActive,
              CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical) else { return }
        manager.stopDeviceMotionUpdates()
        begin()
    }

    public func stop() {
        manager.stopDeviceMotionUpdates()
        handler = nil
    }
}
#endif

/// Подставной поворот: в симуляторе датчика нет, а проверку «дуга встала на место» это не отменяет. Держит одну
/// позу (`-LPSunARPose az,alt,roll`) или водит камеру по списку, как `ScriptedHeading` карты. Четвёртое число —
/// точность магнитного поля позы (`0` не откалиброван … `3` высокая): так в симуляторе проходит калибровка.
/// Каждая поза повторяется 20 раз в секунду, пока держится, — иначе у окна устойчивости курса не набралось бы
/// отсчётов; последняя держится, пока источник не остановят.
@MainActor
public final class ScriptedAttitude: AttitudeSource {
    public typealias Pose = (azimuth: Degrees, altitude: Degrees, roll: Degrees)

    public let poses: [Pose]
    public let accuracies: [MagneticAccuracy?]
    public let hold: Duration
    public let north: AttitudeNorth?
    private var play: Task<Void, Never>?

    public init(poses: [Pose], hold: Duration = .seconds(3), accuracies: [MagneticAccuracy?] = [],
                north: AttitudeNorth = .trueNorth) {
        self.poses = poses
        self.hold = hold
        self.accuracies = accuracies
        self.north = north
    }

    /// `"170,25,0"` или `"170,25,0;250,5,0"` → позы; нет чисел — `nil`.
    public nonisolated static func poses(_ list: String) -> [Pose]? {
        script(list)?.poses
    }

    /// То же вместе с точностью поля: `"170,25,0,0;170,25,0,1;170,25,0,2"`.
    public nonisolated static func script(_ list: String) -> (poses: [Pose], accuracies: [MagneticAccuracy?])? {
        var poses: [Pose] = []
        var accuracies: [MagneticAccuracy?] = []
        for chunk in list.split(separator: ";") {
            let v = chunk.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard v.count >= 2 else { continue }
            poses.append((v[0], v[1], v.count > 2 ? v[2] : 0))
            accuracies.append(v.count > 3 ? MagneticAccuracy(rawValue: Int(v[3])) : nil)
        }
        return poses.isEmpty ? nil : (poses, accuracies)
    }

    public var isAvailable: Bool { true }

    public func start(_ onSample: @escaping @MainActor (AttitudeSample) -> Void) {
        play?.cancel()
        let poses = poses, hold = hold, accuracies = accuracies
        play = Task { @MainActor in
            let tick = Duration.milliseconds(50)
            for (i, p) in poses.enumerated() {
                let last = i == poses.count - 1
                let accuracy = i < accuracies.count ? accuracies[i] : nil
                let deadline = ContinuousClock.now.advanced(by: hold)
                repeat {
                    guard !Task.isCancelled else { return }
                    onSample(AttitudeSample(time: ProcessInfo.processInfo.systemUptime,
                                            basis: CameraBasis(azimuth: p.azimuth, altitude: p.altitude, roll: p.roll),
                                            rotationRate: 0, magneticAccuracy: accuracy))
                    try? await Task.sleep(for: tick)
                } while last || ContinuousClock.now < deadline
            }
        }
    }

    public func stop() {
        play?.cancel()
        play = nil
    }
}
