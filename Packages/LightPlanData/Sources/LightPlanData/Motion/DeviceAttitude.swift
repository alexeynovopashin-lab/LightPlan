import Foundation
import LightPlanCore
#if canImport(CoreMotion)
import CoreMotion
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif

/// Поворот телефона целиком для слоя AR (шаг 29.8в): куда смотрит задняя камера, наклон и крен.
/// Курс одним числом (`HeadingSource`) для этого мало: AR нужен весь поворот, а не его горизонтальная часть.
public struct AttitudeSample: Sendable, Equatable {
    /// Секунды от запуска системы — только для окна устойчивости курса.
    public let time: TimeInterval
    public let basis: CameraBasis
    /// Модуль угловой скорости, градусы в секунду: объясняет часть разброса курса (`HeadingSteadiness`).
    public let rotationRate: Double
    /// Часть вращения, что двигает курс, °/с (`HeadingSteadiness.headingRate`); это число, а не полная скорость,
    /// идёт в окно устойчивости курса (шаг 29.8в.6).
    public let headingRate: Double
    /// Ступень точности магнитного поля от системы (`CMDeviceMotion.magneticField.accuracy`); `nil` — источник её
    /// не сообщает (подставной датчик без поля).
    public let magneticAccuracy: MagneticAccuracy?
    /// Скорость вращения вокруг вертикали со знаком, °/с (гироскоп): калибровка из неё знает, куда повернули.
    public let verticalRate: Double
    /// Погрешность курса в градусах, как её сообщает системный компас (`CLHeading.headingAccuracy`); `nil` — свежего
    /// ответа нет (поток курса не идёт, нет доступа) или курс недействителен.
    public let headingAccuracy: Degrees?
    private let gravityOverride: PhoneVector?

    /// Куда в осях телефона смотрит «вверх» мира. Из положения телефона; подставной источник может задать сам.
    public var gravity: PhoneVector { gravityOverride ?? basis.gravityInPhone }

    public init(time: TimeInterval, basis: CameraBasis, rotationRate: Double, headingRate: Double? = nil,
                magneticAccuracy: MagneticAccuracy? = nil, verticalRate: Double = 0,
                headingAccuracy: Degrees? = nil, gravity: PhoneVector? = nil) {
        self.time = time
        self.basis = basis
        self.rotationRate = rotationRate
        self.headingRate = headingRate ?? rotationRate
        self.magneticAccuracy = magneticAccuracy
        self.verticalRate = verticalRate
        self.headingAccuracy = headingAccuracy
        self.gravityOverride = gravity
    }

    /// Отсчёт для калибровки компаса.
    public var calibrationReading: CalibrationReading {
        CalibrationReading(time: time, gravity: gravity, verticalRate: verticalRate, rotationRate: rotationRate,
                           level: magneticAccuracy, headingAccuracy: headingAccuracy)
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

#if canImport(CoreLocation) && os(iOS)
/// Живой поток курса системного компаса ради одного числа — `CLHeading.headingAccuracy` (шаг 29.8в.8).
///
/// До этого шага на экране AR работал только `CMMotionManager`; `CLLocationManager.startUpdatingHeading` не
/// запускался нигде, кроме карты, поэтому градусов погрешности экран не видел совсем. Здесь поток идёт, пока открыт
/// AR, с `headingFilter = kCLHeadingFilterNone` — каждое изменение, в том числе одной точности без сдвига курса.
/// Ответ старше `maxAge` секунд за свежий не выдаётся: устаревшее число было бы враньём.
@MainActor
final class HeadingAccuracyFeed: NSObject {
    static let maxAge: TimeInterval = 3

    private let manager = CLLocationManager()
    private let showsSystemPanel: Bool
    private var latest: (degrees: Degrees, at: TimeInterval)?

    init(showsSystemPanel: Bool) {
        self.showsSystemPanel = showsSystemPanel
        super.init()
        manager.delegate = self
    }

    var isAvailable: Bool { CLLocationManager.headingAvailable() }

    func start() {
        guard isAvailable else { return }
        manager.headingFilter = kCLHeadingFilterNone
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingHeading()
        latest = nil
    }

    /// Свежая погрешность курса, °; `nil` — ответа нет, он устарел или курс недействителен.
    func current(at time: TimeInterval) -> Degrees? {
        guard let latest, time - latest.at <= Self.maxAge, latest.degrees >= 0 else { return nil }
        return latest.degrees
    }
}

extension HeadingAccuracyFeed: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        latest = (h.headingAccuracy, ProcessInfo.processInfo.systemUptime)
    }

    /// Системная панель калибровки («покрутите телефон») поверх нашего экрана. Она решает только показ панели, а не
    /// саму калибровку; по умолчанию не показывается — её закрыл бы наш экран с градусами и кнопками.
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { showsSystemPanel }
}
#endif

#if canImport(CoreMotion) && os(iOS)
/// `CMMotionManager`: гироскоп, акселерометр и магнитометр слиты системой. Истинный север — как у ARKit в
/// режиме `gravityAndHeading`; камера и магнитометр здесь независимы, камера может быть и закрыта.
@MainActor
public final class CoreMotionAttitude: AttitudeSource {
    private let manager = CMMotionManager()
    private let heading: HeadingAccuracyFeed
    public private(set) var north: AttitudeNorth?
    private var handler: (@MainActor (AttitudeSample) -> Void)?
    private var lastPose: (time: TimeInterval, basis: CameraBasis)?

    /// - Parameter showsSystemCalibrationPanel: показывать ли системную панель калибровки поверх экрана (и у
    ///   `CMMotionManager`, и у `CLLocationManager`). Выключена: её закрыл бы наш экран.
    public init(showsSystemCalibrationPanel: Bool = false) {
        heading = HeadingAccuracyFeed(showsSystemPanel: showsSystemCalibrationPanel)
        manager.showsDeviceMovementDisplay = showsSystemCalibrationPanel
    }

    public var isAvailable: Bool { manager.isDeviceMotionAvailable }

    public func start(_ onSample: @escaping @MainActor (AttitudeSample) -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        handler = onSample
        // Поток курса системного компаса — ради погрешности в градусах (см. `HeadingAccuracyFeed`).
        heading.start()
        begin()
    }

    private func begin() {
        guard let onSample = handler else { return }
        lastPose = nil
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        north = frame == .xTrueNorthZVertical ? .trueNorth : .magneticNorth
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(using: frame, to: .main) { motion, _ in
            guard let motion else { return }
            let m = motion.attitude.rotationMatrix
            let r = motion.rotationRate
            let rate = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot() * 180 / Double.pi
            let rotation = DeviceRotation(
                m11: m.m11, m12: m.m12, m13: m.m13,
                m21: m.m21, m22: m.m22, m23: m.m23,
                m31: m.m31, m32: m.m32, m33: m.m33)
            MainActor.assumeIsolated {
                let basis = CameraBasis(rotation: rotation)
                let sample = AttitudeSample(
                    time: motion.timestamp,
                    basis: basis,
                    rotationRate: rate,
                    headingRate: HeadingSteadiness.headingRate(angularVelocity: (r.x, r.y, r.z), rotation: rotation),
                    magneticAccuracy: Self.accuracy(motion.magneticField.accuracy),
                    verticalRate: self.verticalRate(time: motion.timestamp, basis: basis,
                                                    gyro: HeadingSteadiness.verticalRate(angularVelocity: (r.x, r.y, r.z), rotation: rotation)),
                    headingAccuracy: self.heading.current(at: motion.timestamp))
                onSample(sample)
            }
        }
    }

    /// Поворот вокруг вертикали со знаком, °/с — для калибровки (`VerticalRate.agreed`): шаг положения между двумя
    /// отсчётами (`CameraBasis.yawStep`, те же оси, что рисуют дугу) и проекция гироскопа должны согласиться;
    /// выбирается меньшее из двух. Одного гироскопа мало: знаки и оси `rotationRate` на живом телефоне не проверялись;
    /// одного положения мало: оно привязано к магнитному северу, и поправка компаса при наклоне телефона была бы
    /// принята за поворот.
    private func verticalRate(time: TimeInterval, basis: CameraBasis, gyro: Double) -> Double {
        defer { lastPose = (time, basis) }
        guard let last = lastPose, time > last.time, time - last.time <= 0.2 else { return 0 }
        return VerticalRate.agreed(gyro: gyro, pose: basis.yawStep(from: last.basis) / (time - last.time))
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
        heading.stop()
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

/// Подставной датчик для экрана калибровки (отладка, `-LPSunARCalibScript`): гонит `CalibrationScript` в реальном
/// времени 30 раз в секунду. Положение камеры стоит на месте, меняются сила тяжести, поворот и точность —
/// ровно то, что читает калибровка. Закрывает код экрана и модели, не датчик: настоящие руки и поле — на телефоне.
@MainActor
public final class ScriptedCalibrationAttitude: AttitudeSource {
    public let script: CalibrationScript
    public let north: AttitudeNorth?
    private var play: Task<Void, Never>?

    public init(script: CalibrationScript, north: AttitudeNorth = .trueNorth) {
        self.script = script
        self.north = north
    }

    public var isAvailable: Bool { true }

    public func start(_ onSample: @escaping @MainActor (AttitudeSample) -> Void) {
        play?.cancel()
        let script = script
        play = Task { @MainActor in
            let t0 = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                let now = ProcessInfo.processInfo.systemUptime
                let r = script.reading(at: now - t0)
                onSample(AttitudeSample(time: now, basis: CameraBasis(azimuth: 170, altitude: 10),
                                        rotationRate: r.rotationRate, magneticAccuracy: r.level,
                                        verticalRate: r.verticalRate, headingAccuracy: r.headingAccuracy,
                                        gravity: r.gravity))
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    public func stop() {
        play?.cancel()
        play = nil
    }
}
