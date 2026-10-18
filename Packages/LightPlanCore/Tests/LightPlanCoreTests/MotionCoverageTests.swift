import Testing
import Foundation
import LightPlanCore

/// Охват движения (шаг 29.8в.8): оси и знаки, на которых держится шкала калибровки.
struct MotionCoverageTests {

    @Test("«вверх» мира в осях телефона: прямо у горизонта — вдоль верхнего края; камера в зенит — в экран")
    func gravityAxes() {
        let level = CameraBasis(azimuth: 40, altitude: 0).gravityInPhone
        #expect(abs(level.x) < 1e-9 && abs(level.y - 1) < 1e-9 && abs(level.z) < 1e-9)
        let skyward = CameraBasis(azimuth: 40, altitude: 90).gravityInPhone
        #expect(abs(skyward.z + 1) < 1e-9, "камера смотрит вверх — «вверх» мира уходит назад через экран: \(skyward)")
        let rolled = CameraBasis(azimuth: 40, altitude: 0, roll: 30).gravityInPhone
        #expect(abs(abs(rolled.x) - 0.5) < 1e-6, "крен 30° — боковая составляющая sin 30°: \(rolled)")
    }

    @Test("поворот вокруг вертикали со знаком: стоя вертикально поворот вокруг «верха» телефона — вся скорость")
    func verticalRateSign() {
        // Телефон стоит экраном к себе: «вверх» мира — вдоль оси y устройства (m23 = 1).
        let upright = DeviceRotation(m11: 1, m12: 0, m13: 0, m21: 0, m22: 0, m23: 1, m31: 0, m32: 1, m33: 0)
        let ccw = HeadingSteadiness.verticalRate(angularVelocity: (0, 0.5, 0), rotation: upright)
        let cw = HeadingSteadiness.verticalRate(angularVelocity: (0, -0.5, 0), rotation: upright)
        #expect(abs(ccw - 0.5 * 180 / Double.pi) < 1e-9 && abs(cw + ccw) < 1e-9)
        let pitch = HeadingSteadiness.verticalRate(angularVelocity: (0.5, 0, 0), rotation: upright)
        #expect(pitch == 0, "наклон вперёд-назад вокруг вертикали не поворачивает")
    }

    @Test("шесть ячеек: наклоны в четыре стороны и повороты в две; каждая заполняется от мёртвой зоны до полного")
    func cellsFill() {
        var m = MotionCoverage()
        func g(_ aDeg: Double, _ bDeg: Double) -> PhoneVector {
            let a = aDeg * .pi / 180, b = bDeg * .pi / 180
            return PhoneVector(x: sin(a) * cos(b), y: cos(a) * cos(b), z: sin(b))
        }
        m.add(time: 0, gravity: g(0, 0), verticalRate: 0)
        m.add(time: 0.03, gravity: g(15.01, 0), verticalRate: 0)
        #expect(m.fill(.tiltRight) == 1 && m.fill(.tiltLeft) == 0 && m.progress > 0.16 && m.progress < 0.17)
        m.add(time: 0.06, gravity: g(0, 9.5), verticalRate: 0)
        let half = m.fill(.tiltBack) + m.fill(.tiltForward)
        #expect(abs(half - 0.5) < 0.01, "9,5° из диапазона 4…15 — половина ячейки: \(half)")
        // Поворот вправо на 35° за секунду: 35 °/с × 1 с, шагами по 0,1 с.
        for i in 1...10 { m.add(time: 0.06 + Double(i) * 0.1, gravity: g(0, 0), verticalRate: 35) }
        #expect(m.fill(.turnRight) == 1 && m.fill(.turnLeft) == 0)
        #expect(m.missingTilt && m.missingTurn)
    }

    @Test("скорость ниже порога дрейфа гироскопа не копится: 1 °/с сто секунд — нуль")
    func gyroDriftIsIgnored() {
        var m = MotionCoverage()
        for i in 0..<3000 { m.add(time: Double(i) / 30, gravity: PhoneVector(x: 0, y: 1, z: 0), verticalRate: 1) }
        #expect(m.fill(.turnRight) == 0 && m.progress == 0)
    }
}
