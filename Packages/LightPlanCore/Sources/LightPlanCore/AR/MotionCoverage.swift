import Foundation

/// Вектор в осях телефона: `x` — вправо по экрану, `y` — к верхнему краю, `z` — из экрана на себя.
public struct PhoneVector: Sendable, Equatable {
    public let x, y, z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x; self.y = y; self.z = z
    }

    public func dot(_ o: PhoneVector) -> Double { x * o.x + y * o.y + z * o.z }

    public func cross(_ o: PhoneVector) -> PhoneVector {
        PhoneVector(x: y * o.z - z * o.y, y: z * o.x - x * o.z, z: x * o.y - y * o.x)
    }

    public var length: Double { dot(self).squareRoot() }

    public func scaled(_ k: Double) -> PhoneVector { PhoneVector(x: x * k, y: y * k, z: z * k) }

    public func minus(_ o: PhoneVector) -> PhoneVector { PhoneVector(x: x - o.x, y: y - o.y, z: z - o.z) }

    public var unit: PhoneVector? {
        let l = length
        return l > 1e-9 ? scaled(1 / l) : nil
    }
}

public extension CameraBasis {
    /// Куда в осях телефона смотрит «вверх» мира (против силы тяжести). Строится из положения телефона, которое
    /// система считает по акселерометру и гироскопу, магнитометр здесь не участвует: скачок поля не двигает его.
    /// Камера смотрит вдоль `−z` телефона, поэтому `z` — минус компонента `forward`.
    var gravityInPhone: PhoneVector {
        PhoneVector(x: right.up, y: up.up, z: -forward.up)
    }
}

public extension CameraBasis {
    /// Поворот вокруг вертикали между положением `previous` и этим, градусы со знаком (против часовой стрелки
    /// сверху — плюс). Считается из тех же осей камеры, по которым рисуется дуга, поэтому не зависит от знаков и
    /// осей, в которых система отдаёт угловую скорость: поворот, который видит дуга, видит и калибровка.
    ///
    /// Оси устройства в мире «восток, север, вверх» — столбцы `[right | up | −forward]`; приращение
    /// `ΔR = R · Rᵀ_prev`, поворот вокруг вертикали — `(ΔR₁₀ − ΔR₀₁) / 2` (для малых углов — синус угла).
    func yawStep(from previous: CameraBasis) -> Double {
        func columns(_ b: CameraBasis) -> [[Double]] {
            let x = b.right, y = b.up, z = SkyVector(east: -b.forward.east, north: -b.forward.north, up: -b.forward.up)
            return [[x.east, y.east, z.east], [x.north, y.north, z.north], [x.up, y.up, z.up]]
        }
        let n = columns(self), p = columns(previous)
        func d(_ i: Int, _ j: Int) -> Double { (0..<3).reduce(0) { $0 + n[i][$1] * p[j][$1] } }
        return asin(max(-1, min(1, (d(1, 0) - d(0, 1)) / 2))) * 180 / .pi
    }
}

/// Скорость поворота вокруг вертикали для калибровки из двух источников, которые должны согласиться.
public enum VerticalRate {
    /// `gyro` — проекция скорости гироскопа на вертикаль (`HeadingSteadiness.verticalRate`), `pose` — шаг положения
    /// телефона (`CameraBasis.yawStep` / dt). Положение привязано к магнитному северу: когда компас уточняет север,
    /// его поправка попадает в `pose` и без вращения телефона (ревью GPT к 29.8в.8а). Гироскоп магнитного севера не
    /// знает. Поэтому берётся меньшая по модулю из двух, знак — общий; не согласны по знаку — это поправка, а не
    /// поворот: 0. Поправка не может записать в шкалу больше поворота, чем видел гироскоп.
    public static func agreed(gyro: Double, pose: Double) -> Double {
        guard gyro * pose > 0 else { return 0 }
        return gyro > 0 ? min(gyro, pose) : max(gyro, pose)
    }
}

/// Охват движения при калибровке компаса (шаги 29.8в.8, 29.8в.8а).
///
/// Магнитометру нужно побывать в разных положениях: тогда система видит поле по всем сторонам телефона и вычитает
/// из него собственный магнетизм корпуса. Поэтому шкала растёт не от времени и не от курса, а от того, куда
/// телефон реально отклонился, и считается из двух вещей, которые не зависят от магнитометра:
///
/// 1. **Наклоны** — направление силы тяжести в осях телефона. Точка отсчёта — положение в первом отсчёте; от неё
///    телефон должен отклониться по двум осям экрана в обе стороны: вперёд/назад и влево/вправо (четыре ячейки,
///    каждая закрыта наклоном `tiltFull` в её сторону).
/// 2. **Поворот вокруг вертикали** — размах накопленного поворота (наибольшее минус наименьшее значение), одна
///    ячейка, закрыта размахом `turnFull`. Это шаг положения телефона, а не курс из компаса: курс сам неверен, пока
///    компас не откалиброван, и скачком поля его можно «повернуть» без движения. Размах, а не «30° влево и 30°
///    вправо от начала» (29.8в.8): на подставных взмахах руки (шест, кисть, кувырки; 100 прогонов каждого) такие две
///    ячейки не закрывались в 8–15 % прогонов — накопленный поворот уходит в одну сторону, и обратной стороны
///    не набирается; у Алексея шкала стояла на 92 % = пять ячеек из шести закрыты, одна на половине.
///
/// Каждая ячейка заполняется линейно от `deadband` до полного значения; в пределах `deadband` отклонение — шум
/// датчиков и дрожь руки и ячейку не двигает. Заполнение только растёт (рекорд отклонения), назад не идёт.
/// Шкала — среднее заполнение пяти ячеек. Время шкалу не двигает: без новых отсчётов с отклонением она стоит.
public struct MotionCoverage: Sendable {
    /// Планки (29.8в.8б): естественная восьмёрка закрывает все пять ячеек за 5–8 с. Прежние 15° и 40° не давали:
    /// на подставной восьмёрке с наклоном ±12° и поворотом ±16° шкала вставала на 74 % навсегда, у Алексея потолок был
    /// 92 %. Нижний край — шум и ходьба: дрожь ±3° не двигает шкалу, походка (наклон ±5°, поворот ±8°) даёт 22 %.
    /// Наклон, закрывающий ячейку, градусы.
    public static let tiltFull: Double = 10
    /// Ниже этого наклона — шум и дрожь, градусы.
    public static let tiltDeadband: Double = 4
    /// Размах поворота вокруг вертикали, закрывающий ячейку, градусы.
    public static let turnFull: Double = 28
    public static let turnDeadband: Double = 6
    /// Скорость вращения вокруг вертикали ниже этой считается дрейфом нуля гироскопа и не интегрируется, °/с.
    public static let yawRateFloor: Double = 1.5
    /// Пропуск между отсчётами длиннее этого (остановка датчика) в интеграл не берётся, секунды.
    static let maxStep: TimeInterval = 0.2

    public enum Cell: Int, CaseIterable, Sendable {
        case tiltForward, tiltBack, tiltLeft, tiltRight, turn

        public var isTilt: Bool { self != .turn }
    }

    /// Рекорды отклонения по ячейкам, градусы.
    private var best = [Double](repeating: 0, count: Cell.allCases.count)
    private var rest: PhoneVector?
    private var axisU: PhoneVector?
    private var axisV: PhoneVector?
    private var yaw: Double = 0
    private var yawLow: Double = 0
    private var yawHigh: Double = 0
    private var lastTime: TimeInterval?

    public init() {}

    public mutating func add(time: TimeInterval, gravity: PhoneVector, verticalRate: Double) {
        guard let g = gravity.unit else { return }
        if rest == nil {
            rest = g
            // Оси наклона: правая сторона экрана и перпендикуляр к ней; если телефон стоит на боку — верхний край.
            let ex = PhoneVector(x: 1, y: 0, z: 0), ey = PhoneVector(x: 0, y: 1, z: 0)
            let seed = abs(ex.dot(g)) < 0.9 ? ex : ey
            if let u = seed.minus(g.scaled(seed.dot(g))).unit {
                axisU = u
                axisV = g.cross(u)
            }
        }
        if let g0 = rest, let u = axisU, let v = axisV {
            // Угол в плоскости (g0, ось): знак — в какую сторону ушёл телефон.
            let along = g.dot(g0)
            let a = atan2(g.dot(u), along) * 180 / .pi
            let b = atan2(g.dot(v), along) * 180 / .pi
            // `u` смотрит вправо по экрану, `v` — к «вперёд/назад»: имена ячеек условны, важно, что оба направления.
            raise(.tiltRight, a)
            raise(.tiltLeft, -a)
            raise(.tiltForward, b)
            raise(.tiltBack, -b)
        }
        if let last = lastTime, time > last, time - last <= Self.maxStep {
            let rate = abs(verticalRate) >= Self.yawRateFloor ? verticalRate : 0
            yaw += rate * (time - last)
            yawLow = min(yawLow, yaw)
            yawHigh = max(yawHigh, yaw)
            best[Cell.turn.rawValue] = yawHigh - yawLow
        }
        lastTime = time
    }

    private mutating func raise(_ cell: Cell, _ value: Double) {
        if value > best[cell.rawValue] { best[cell.rawValue] = value }
    }

    /// Заполнение ячейки `0 … 1`.
    public func fill(_ cell: Cell) -> Double {
        let (dead, full) = cell.isTilt ? (Self.tiltDeadband, Self.tiltFull) : (Self.turnDeadband, Self.turnFull)
        return min(1, max(0, (best[cell.rawValue] - dead) / (full - dead)))
    }

    /// Шкала `0 … 1`: среднее заполнение пяти ячеек.
    public var progress: Double {
        Cell.allCases.map(fill).reduce(0, +) / Double(Cell.allCases.count)
    }

    /// Все пять ячеек закрыты.
    public var isComplete: Bool { Cell.allCases.allSatisfy { fill($0) >= 1 } }

    /// Накопленное отклонение ячейки, градусы (наклон в её сторону или размах поворота): для журнала отладки.
    public func degrees(_ cell: Cell) -> Double { best[cell.rawValue] }

    /// Чего не хватает. Оси экрана: «влево-вправо» — крен (ячейки `tiltLeft`, `tiltRight`), «вперёд-назад» — наклон
    /// от себя и на себя (`tiltForward`, `tiltBack`); подсказка называет ось, а не сторону — какая из сторон «вперёд»,
    /// зависит от того, как телефон держали в первом отсчёте.
    public var missingSide: Bool { fill(.tiltLeft) < 1 || fill(.tiltRight) < 1 }
    public var missingFront: Bool { fill(.tiltForward) < 1 || fill(.tiltBack) < 1 }
    public var missingTurn: Bool { fill(.turn) < 1 }
    public var missingTilt: Bool { missingSide || missingFront }
}
