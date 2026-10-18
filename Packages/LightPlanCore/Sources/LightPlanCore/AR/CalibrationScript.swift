import Foundation

/// Подставной поток датчиков для калибровки: те же отсчёты, что даёт телефон, но по формуле. Один и тот же
/// сценарий гонят юнит-тесты (без часов и без телефона) и отладочный источник симулятора (`-LPSunARCalibScript`),
/// поэтому кадры экрана и тесты говорят о одном и том же движении.
public struct CalibrationScript: Sendable {
    public enum Motion: Sendable, Equatable {
        /// Телефон лежит в руке: шум 0,2° и дрейф гироскопа 1 °/с (ниже порога интегрирования).
        case still
        /// Быстрая дрожь на месте: ±3° с частотой около 9 Гц по всем осям, положение не меняется.
        case shake
        /// Восьмёрка с поворотом кисти: наклоны ±22°·`scale` и поворот вокруг вертикали ±40°·`scale`, период 4 с.
        case figureEight(scale: Double)
    }

    /// Что система сообщает о точности в момент `t`.
    public typealias Accuracy = @Sendable (TimeInterval) -> (degrees: Degrees?, level: MagneticAccuracy?)

    public let motion: Motion
    public let accuracy: Accuracy

    public init(motion: Motion, accuracy: @escaping Accuracy = { _ in (nil, nil) }) {
        self.motion = motion
        self.accuracy = accuracy
    }

    /// Отсчёты за `seconds` секунд с частотой `hz`, начиная с `from`.
    public func readings(from t0: TimeInterval = 0, seconds: Double, hz: Double = 30) -> [CalibrationReading] {
        let n = Int((seconds * hz).rounded())
        return (0..<n).map { reading(at: t0 + Double($0) / hz) }
    }

    public func reading(at t: TimeInterval) -> CalibrationReading {
        // Углы наклона a (влево-вправо), b (вперёд-назад), поворот вокруг вертикали yaw — и их скорости, °/с.
        let a: Double, b: Double, da: Double, db: Double, dyaw: Double
        switch motion {
        case .still:
            a = 0.2 * sin(t * 5); b = 0.2 * cos(t * 7); da = 0; db = 0; dyaw = 1
        case .shake:
            let w1 = 2 * Double.pi * 9, w2 = 2 * Double.pi * 11
            a = 3 * sin(w1 * t); b = 3 * sin(w2 * t)
            da = 3 * w1 * cos(w1 * t); db = 3 * w2 * cos(w2 * t)
            dyaw = 3 * w1 * cos(w1 * t + 1)
        case .figureEight(let s):
            let w = 2 * Double.pi / 4
            a = 22 * s * sin(w * t); da = 22 * s * w * cos(w * t)
            b = 22 * s * sin(2 * w * t); db = 22 * s * 2 * w * cos(2 * w * t)
            dyaw = 40 * s * w * cos(w * t)
        }
        let ar = a * .pi / 180, br = b * .pi / 180
        let g = PhoneVector(x: sin(ar) * cos(br), y: cos(ar) * cos(br), z: sin(br))
        let acc = accuracy(t)
        return CalibrationReading(time: t, gravity: g, verticalRate: dyaw,
                                  rotationRate: (da * da + db * db + dyaw * dyaw).squareRoot(),
                                  level: acc.level, headingAccuracy: acc.degrees)
    }
}
