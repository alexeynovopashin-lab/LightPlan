import Testing
import Foundation
import LightPlanCore

/// Скорость курса при вращении телефона (шаг 29.8в.6, ревью GPT к 29.8в.3–4: из разброса курса вычиталась полная
/// угловая скорость). Эталон — разность азимутов оси камеры до и после малого поворота, посчитанная независимо
/// от формулы (Родриг на векторах «восток, север, вверх»).
struct HeadingRateTests {

    /// Матрица устройства из направления камеры: строки — оси устройства в системе «север, запад, вверх»
    /// (так их читает `CameraBasis(rotation:)`).
    static func rotation(azimuth: Double, altitude: Double, roll: Double = 0) -> DeviceRotation {
        let b = CameraBasis(azimuth: azimuth, altitude: altitude, roll: roll)
        return DeviceRotation(m11: b.right.north, m12: -b.right.east, m13: b.right.up,
                              m21: b.up.north, m22: -b.up.east, m23: b.up.up,
                              m31: -b.forward.north, m32: b.forward.east, m33: -b.forward.up)
    }

    /// Угловая скорость мира (вектор «восток, север, вверх», рад/с) в осях устройства — как её отдаёт гироскоп.
    static func deviceAxes(_ w: SkyVector, azimuth: Double, altitude: Double, roll: Double = 0) -> (x: Double, y: Double, z: Double) {
        let b = CameraBasis(azimuth: azimuth, altitude: altitude, roll: roll)
        return (w.dot(b.right), w.dot(b.up), -w.dot(b.forward))
    }

    /// Поворот вектора на угол вокруг оси (Родриг).
    static func rotate(_ v: SkyVector, about axis: SkyVector, by angle: Double) -> SkyVector {
        let n = (axis.dot(axis)).squareRoot()
        let k = SkyVector(east: axis.east / n, north: axis.north / n, up: axis.up / n)
        let c = cos(angle), s = sin(angle)
        let kv = k.cross(v), kd = k.dot(v)
        return SkyVector(east: v.east * c + kv.east * s + k.east * kd * (1 - c),
                         north: v.north * c + kv.north * s + k.north * kd * (1 - c),
                         up: v.up * c + kv.up * s + k.up * kd * (1 - c))
    }

    /// Азимутальная скорость оси камеры, °/с, по разности двух азимутов за 1 мс.
    static func numericRate(_ w: SkyVector, azimuth: Double, altitude: Double) -> Double {
        let f = SkyVector(azimuth: azimuth, altitude: altitude)
        let omega = (w.dot(w)).squareRoot()
        let dt = 0.001
        let g = Self.rotate(f, about: w, by: omega * dt)
        var d = g.horizontal.azimuth - f.horizontal.azimuth
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return abs(d) / dt
    }

    @Test("формула совпадает с разностью азимутов: разные позы и оси вращения, до высоты 70°")
    func matchesFiniteDifference() {
        let worlds = [SkyVector(east: 0, north: 0, up: 0.7), SkyVector(east: 0.5, north: 0.2, up: 0.1),
                      SkyVector(east: -0.3, north: 0.6, up: 0.4), SkyVector(east: 0.2, north: -0.7, up: -0.3)]
        for az in [10.0, 135, 250, 350] {
            for alt in [-20.0, 0, 25, 70] {
                for w in worlds {
                    let got = HeadingSteadiness.headingRate(angularVelocity: Self.deviceAxes(w, azimuth: az, altitude: alt),
                                                            rotation: Self.rotation(azimuth: az, altitude: alt))
                    let want = Self.numericRate(w, azimuth: az, altitude: alt)
                    #expect(abs(got - want) < 0.02 * max(want, 1), "az \(az) alt \(alt) w \(w): формула \(got), разность \(want)")
                }
            }
        }
    }

    @Test("крен вокруг оси камеры и наклон при горизонтальной камере курс не двигают, поворот вокруг вертикали — на полную скорость")
    func rollAndPitchDoNotMoveHeading() {
        let az = 120.0, alt = 0.0
        let rot = Self.rotation(azimuth: az, altitude: alt)
        let forward = SkyVector(azimuth: az, altitude: alt)
        let right = CameraBasis(azimuth: az, altitude: alt).right
        let deg = Double.pi / 180
        // Крен: вращение вокруг оси камеры на 90°/с.
        let roll = SkyVector(east: forward.east * 90 * deg, north: forward.north * 90 * deg, up: forward.up * 90 * deg)
        #expect(HeadingSteadiness.headingRate(angularVelocity: Self.deviceAxes(roll, azimuth: az, altitude: alt), rotation: rot) < 0.01)
        // Наклон вверх-вниз: вращение вокруг правой оси кадра на 90°/с.
        let pitch = SkyVector(east: right.east * 90 * deg, north: right.north * 90 * deg, up: right.up * 90 * deg)
        #expect(HeadingSteadiness.headingRate(angularVelocity: Self.deviceAxes(pitch, azimuth: az, altitude: alt), rotation: rot) < 0.01)
        // Поворот за солнцем: вокруг вертикали, 40°/с.
        let yaw = SkyVector(east: 0, north: 0, up: 40 * deg)
        let got = HeadingSteadiness.headingRate(angularVelocity: Self.deviceAxes(yaw, azimuth: az, altitude: alt), rotation: rot)
        #expect(abs(got - 40) < 0.05, "поворот вокруг вертикали на 40°/с дал \(got)")
    }

    @Test("телефон крутят вокруг оси камеры, а компас прыгает на 8°: полная скорость (90°/с) глушила скачок, скорость курса — нет")
    func rollMasksNothing() {
        let az = 100.0, alt = 5.0
        let rot = Self.rotation(azimuth: az, altitude: alt)
        let forward = SkyVector(azimuth: az, altitude: alt)
        let deg = Double.pi / 180
        let w = SkyVector(east: forward.east * 90 * deg, north: forward.north * 90 * deg, up: forward.up * 90 * deg)
        let axes = Self.deviceAxes(w, azimuth: az, altitude: alt)
        let total = (axes.x * axes.x + axes.y * axes.y + axes.z * axes.z).squareRoot() * 180 / Double.pi
        let heading = HeadingSteadiness.headingRate(angularVelocity: axes, rotation: rot)
        #expect(abs(total - 90) < 0.01 && heading < 1)
        var full = HeadingSteadiness(), right = HeadingSteadiness()
        for i in 0..<20 {
            let jumpy = i % 2 == 0 ? 100.0 : 108
            full.add(time: Double(i) * 0.05, heading: jumpy, rate: total)      // как было: скачок списан на крен
            right.add(time: Double(i) * 0.05, heading: jumpy, rate: heading)   // как теперь
        }
        #expect(!full.isUnsteady, "контроль: со старой скоростью скачок не виден")
        #expect(right.isUnsteady, "со скоростью курса скачок на 8° виден")
    }

    @Test("поворот за солнцем на 40°/с остаётся тихим и со скоростью курса")
    func panningStaysQuiet() {
        let az = 100.0, alt = 10.0
        let rot = Self.rotation(azimuth: az, altitude: alt)
        let rate = HeadingSteadiness.headingRate(angularVelocity: Self.deviceAxes(SkyVector(east: 0, north: 0, up: 40 * Double.pi / 180), azimuth: az, altitude: alt), rotation: rot)
        var g = HeadingSteadiness()
        for i in 0..<30 { g.add(time: Double(i) * 0.05, heading: az + 40 * Double(i) * 0.05, rate: rate) }
        #expect(!g.isUnsteady)
    }
}
