import Testing
import Foundation
import LightPlanCore

/// Охват движения (шаги 29.8в.8, 29.8в.8а): оси и знаки, на которых держится шкала калибровки, и то, что размашистое
/// движение рукой закрывает все пять ячеек.
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

    @Test("поворот вокруг вертикали по положению: 10° по курсу — 10° по модулю, назад — с другим знаком; наклон и крен — 0")
    func yawStepFromPose() {
        let a = CameraBasis(azimuth: 40, altitude: 10)
        let b = CameraBasis(azimuth: 50, altitude: 10)
        let ab = b.yawStep(from: a), ba = a.yawStep(from: b)
        #expect(abs(abs(ab) - 10) < 0.5 && abs(ab + ba) < 1e-9, "ab \(ab) ba \(ba)")
        #expect(abs(CameraBasis(azimuth: 40, altitude: 50).yawStep(from: a)) < 1e-9, "наклон камеры вверх вертикаль не вращает")
        let level = CameraBasis(azimuth: 40, altitude: 0)
        #expect(abs(CameraBasis(azimuth: 40, altitude: 0, roll: 25).yawStep(from: level)) < 1e-9, "крен вокруг горизонтальной оси камеры тоже")
        // Камера задрана на 10°: крен вокруг неё немного вращает и вокруг вертикали — 25° · sin 10° ≈ 4,3°.
        #expect(abs(abs(CameraBasis(azimuth: 40, altitude: 10, roll: 25).yawStep(from: a)) - 25 * sin(10 * Double.pi / 180)) < 0.3)
        // Поворот на 10° при камере, задранной на 60°, — те же 10° вокруг вертикали (курс оси камеры там «плывёт»).
        let steep = CameraBasis(azimuth: 40, altitude: 60), steepTurned = CameraBasis(azimuth: 50, altitude: 60)
        #expect(abs(abs(steepTurned.yawStep(from: steep)) - 10) < 0.5)
    }

    @Test("пять ячеек: наклоны в четыре стороны и размах поворота; каждая заполняется от мёртвой зоны до полного")
    func cellsFill() {
        var m = MotionCoverage()
        func g(_ aDeg: Double, _ bDeg: Double) -> PhoneVector {
            let a = aDeg * .pi / 180, b = bDeg * .pi / 180
            return PhoneVector(x: sin(a) * cos(b), y: cos(a) * cos(b), z: sin(b))
        }
        m.add(time: 0, gravity: g(0, 0), verticalRate: 0)
        m.add(time: 0.03, gravity: g(15.01, 0), verticalRate: 0)
        #expect(m.fill(.tiltRight) == 1 && m.fill(.tiltLeft) == 0 && m.progress > 0.19 && m.progress < 0.21)
        m.add(time: 0.06, gravity: g(0, 9.5), verticalRate: 0)
        let half = m.fill(.tiltBack) + m.fill(.tiltForward)
        #expect(abs(half - 0.5) < 0.01, "9,5° из диапазона 4…15 — половина ячейки: \(half)")
        // Поворот в одну сторону на 30°, потом назад на 60° (до −30°): размах 30, затем 60 (возврат его не уменьшает).
        for i in 1...10 { m.add(time: 0.06 + Double(i) * 0.1, gravity: g(0, 0), verticalRate: 30) }
        let after30 = m.degrees(.turn)
        #expect(abs(after30 - 30) < 0.5, "\(after30)")
        for i in 11...40 { m.add(time: 0.06 + Double(i) * 0.1, gravity: g(0, 0), verticalRate: -20) }
        #expect(abs(m.degrees(.turn) - 60) < 0.5 && m.fill(.turn) == 1, "размах \(m.degrees(.turn))")
        #expect(m.missingTilt && !m.missingTurn)
    }

    @Test("подсказки по осям: не хватает крена — «влево-вправо», не хватает наклона от себя — «вперёд-назад»")
    func axisMissing() {
        var m = MotionCoverage()
        func g(_ aDeg: Double, _ bDeg: Double) -> PhoneVector {
            let a = aDeg * .pi / 180, b = bDeg * .pi / 180
            return PhoneVector(x: sin(a) * cos(b), y: cos(a) * cos(b), z: sin(b))
        }
        m.add(time: 0, gravity: g(0, 0), verticalRate: 0)
        m.add(time: 0.03, gravity: g(20, 0), verticalRate: 0)
        m.add(time: 0.06, gravity: g(-20, 0), verticalRate: 0)
        #expect(!m.missingSide && m.missingFront)
    }

    @Test("скорость ниже порога дрейфа гироскопа не копится: 1 °/с сто секунд — нуль")
    func gyroDriftIsIgnored() {
        var m = MotionCoverage()
        for i in 0..<3000 { m.add(time: Double(i) / 30, gravity: PhoneVector(x: 0, y: 1, z: 0), verticalRate: 1) }
        #expect(m.fill(.turn) == 0 && m.progress == 0)
    }

    // MARK: - Живая рука: размашистое движение закрывает все пять ячеек

    private struct RNG {
        var s: UInt64
        mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double((s >> 33) & 0xFFFFFF) / Double(0xFFFFFF) }
        mutating func gauss() -> Double { let u = max(next(), 1e-9), v = next(); return (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v) }
    }
    private typealias Mat = [[Double]]
    private static func mul(_ a: Mat, _ b: Mat) -> Mat { (0..<3).map { i in (0..<3).map { j in (0..<3).reduce(0) { $0 + a[i][$1] * b[$1][j] } } } }
    private static func rot(_ w: (Double, Double, Double), _ dt: Double) -> Mat {
        let ang = (w.0 * w.0 + w.1 * w.1 + w.2 * w.2).squareRoot() * dt
        if ang < 1e-12 { return [[1, 0, 0], [0, 1, 0], [0, 0, 1]] }
        let n = (w.0 * dt / ang, w.1 * dt / ang, w.2 * dt / ang), c = cos(ang), s = sin(ang), t = 1 - c
        return [[t * n.0 * n.0 + c, t * n.0 * n.1 - s * n.2, t * n.0 * n.2 + s * n.1],
                [t * n.0 * n.1 + s * n.2, t * n.1 * n.1 + c, t * n.1 * n.2 - s * n.0],
                [t * n.0 * n.2 - s * n.1, t * n.1 * n.2 + s * n.0, t * n.2 * n.2 + c]]
    }

    /// Твёрдое тело, которому дают случайную угловую скорость (процесс Орнштейна — Уленбека): положение (три оси
    /// камеры в «восток, север, вверх»), сила тяжести в осях телефона и скорость вращения вокруг вертикали
    /// идут в калибровку теми же путями, что на телефоне (`gravityInPhone`, `yawStep`).
    private func wave(style wrms: Double, tau: Double, seed: Int, seconds: Double) -> (progress: Double, cells: [Double]) {
        var rng = RNG(s: UInt64(seed + 1) * 7919)
        var R: Mat = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]      // мир ← телефон (столбцы — оси телефона в мире)
        var w = (0.0, 0.0, 0.0)
        var m = MotionCoverage()
        var prev: CameraBasis?
        let dt = 1.0 / 30
        func basis(_ R: Mat) -> CameraBasis {
            CameraBasis(forward: SkyVector(east: -R[0][2], north: -R[1][2], up: -R[2][2]),
                        right: SkyVector(east: R[0][0], north: R[1][0], up: R[2][0]),
                        up: SkyVector(east: R[0][1], north: R[1][1], up: R[2][1]))
        }
        for i in 0..<Int(seconds * 30) {
            let a = exp(-dt / tau), sig = wrms * Double.pi / 180 * (1 - a * a).squareRoot()
            w = (w.0 * a + sig * rng.gauss(), w.1 * a + sig * rng.gauss(), w.2 * a + sig * rng.gauss())
            R = Self.mul(R, Self.rot(w, dt))
            let b = basis(R)
            let step = prev.map { b.yawStep(from: $0) } ?? 0
            prev = b
            m.add(time: Double(i) * dt, gravity: b.gravityInPhone, verticalRate: step / dt)
        }
        return (m.progress, MotionCoverage.Cell.allCases.map(m.fill))
    }

    @Test("шест, кисть и кувырки (по 40 взмахов по 20 с): все пять ячеек закрыты, сто процентов достижимо")
    func wavingClosesEveryCell() {
        for (style, wrms, tau) in [("кисть", 60.0, 0.4), ("шест", 150.0, 0.6), ("кувырки", 250.0, 0.8)] {
            for seed in 0..<40 {
                let r = wave(style: wrms, tau: tau, seed: seed, seconds: 20)
                #expect(r.progress == 1, "\(style) №\(seed): ячейки \(r.cells.map { String(format: "%.2f", $0) })")
            }
        }
    }
}
