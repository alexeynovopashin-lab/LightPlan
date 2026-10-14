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

    public init(time: TimeInterval, basis: CameraBasis, rotationRate: Double) {
        self.time = time
        self.basis = basis
        self.rotationRate = rotationRate
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
}

#if canImport(CoreMotion) && os(iOS)
/// `CMMotionManager`: гироскоп, акселерометр и магнитометр слиты системой. Истинный север — как у ARKit в
/// режиме `gravityAndHeading`; камера и магнитометр здесь независимы, камера может быть и закрыта.
@MainActor
public final class CoreMotionAttitude: AttitudeSource {
    private let manager = CMMotionManager()
    public private(set) var north: AttitudeNorth?

    public init() {}

    public var isAvailable: Bool { manager.isDeviceMotionAvailable }

    public func start(_ onSample: @escaping @MainActor (AttitudeSample) -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
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
                rotationRate: rate)
            MainActor.assumeIsolated { onSample(sample) }
        }
    }

    public func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
#endif

/// Подставной поворот: в симуляторе датчика нет, а проверку «дуга встала на место» это не отменяет. Держит одну
/// позу (`-LPSunARPose az,alt,roll`) или водит камеру по списку, как `ScriptedHeading` карты.
@MainActor
public final class ScriptedAttitude: AttitudeSource {
    public let poses: [(azimuth: Degrees, altitude: Degrees, roll: Degrees)]
    public let hold: Duration
    public let north: AttitudeNorth? = .trueNorth
    private var play: Task<Void, Never>?

    public init(poses: [(azimuth: Degrees, altitude: Degrees, roll: Degrees)], hold: Duration = .seconds(3)) {
        self.poses = poses
        self.hold = hold
    }

    /// `"170,25,0"` или `"170,25,0;250,5,0"` → позы; нет чисел — `nil`.
    public nonisolated static func poses(_ list: String) -> [(azimuth: Degrees, altitude: Degrees, roll: Degrees)]? {
        let out = list.split(separator: ";").compactMap { chunk -> (Degrees, Degrees, Degrees)? in
            let v = chunk.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard v.count >= 2 else { return nil }
            return (v[0], v[1], v.count > 2 ? v[2] : 0)
        }
        return out.isEmpty ? nil : out
    }

    public var isAvailable: Bool { true }

    public func start(_ onSample: @escaping @MainActor (AttitudeSample) -> Void) {
        play?.cancel()
        let poses = poses, hold = hold
        play = Task { @MainActor in
            for (i, p) in poses.enumerated() {
                guard !Task.isCancelled else { return }
                onSample(AttitudeSample(time: ProcessInfo.processInfo.systemUptime,
                                        basis: CameraBasis(azimuth: p.azimuth, altitude: p.altitude, roll: p.roll),
                                        rotationRate: 0))
                if i < poses.count - 1 { try? await Task.sleep(for: hold) }
            }
        }
    }

    public func stop() {
        play?.cancel()
        play = nil
    }
}
