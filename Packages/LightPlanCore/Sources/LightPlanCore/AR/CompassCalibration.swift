import Foundation

/// Точность магнитного поля, как её отдаёт система (`CMMagneticFieldCalibrationAccuracy`): чем она выше, тем
/// лучше компас откалиброван. Четыре ступени без градусов — градусы даёт `CLHeading.headingAccuracy`.
public enum MagneticAccuracy: Int, Sendable, Comparable, CaseIterable {
    case uncalibrated = 0, low, medium, high

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Один отсчёт для калибровки: положение и вращение телефона (гироскоп и акселерометр) и то, что система
/// сообщает о точности компаса.
public struct CalibrationReading: Sendable {
    public let time: TimeInterval
    /// Куда в осях телефона смотрит «вверх» мира (`CameraBasis.gravityInPhone`).
    public let gravity: PhoneVector
    /// Скорость вращения вокруг вертикали со знаком, °/с (гироскоп).
    public let verticalRate: Double
    /// Модуль угловой скорости, °/с.
    public let rotationRate: Double
    /// Ступень точности поля (`CMDeviceMotion.magneticField.accuracy`).
    public let level: MagneticAccuracy?
    /// Погрешность курса в градусах (`CLHeading.headingAccuracy`); отрицательная — курс недействителен.
    public let headingAccuracy: Degrees?

    public init(time: TimeInterval, gravity: PhoneVector, verticalRate: Double, rotationRate: Double,
                level: MagneticAccuracy? = nil, headingAccuracy: Degrees? = nil) {
        self.time = time
        self.gravity = gravity
        self.verticalRate = verticalRate
        self.rotationRate = rotationRate
        self.level = level
        self.headingAccuracy = headingAccuracy
    }
}

/// Что система сообщает о точности компаса сейчас. Приложение само магнитометр не калибрует — это делает iOS по
/// движению телефона; здесь только то, что она ответила.
public struct CompassAccuracy: Sendable, Equatable {
    /// Погрешность курса, градусы; `nil` — система не сказала или курс недействителен.
    public let degrees: Degrees?
    /// Ступень поля; `nil` — не сообщается.
    public let level: MagneticAccuracy?

    public init(degrees: Degrees?, level: MagneticAccuracy?) {
        self.degrees = degrees.flatMap { $0 >= 0 ? $0 : nil }
        self.level = level
    }

    /// Система сообщила хоть что-то.
    public var isKnown: Bool { degrees != nil || level != nil }

    /// Точность не хуже порога. Градусы, если есть, решают одни; без них — ступень поля не ниже `levelFloor`.
    /// Не сообщает вовсе — не годится: подтвердить нечем.
    public var isAcceptable: Bool {
        if let degrees { return degrees <= CompassCalibration.requiredDegrees }
        if let level { return level >= CompassCalibration.requiredLevel }
        return false
    }
}

/// Калибровка компаса «восьмёркой» (шаги 29.8в.2, 29.8в.8).
///
/// Шкала — **охват движения** (`MotionCoverage`): наклоны и повороты телефона, измеренные по гироскопу и положению,
/// и ничего больше. Неподвижный телефон держит её на нуле сколько угодно, тряска на месте её почти не двигает,
/// время её не двигает. Точность компаса шкалу не двигает вовсе: её показывает система, и она показана отдельно.
///
/// «Готово» — охват полный **и** точность от системы не хуже порога. Раз достигнутое остаётся. Охват полный, а
/// точность осталась хуже порога дольше `settle` секунд отсчётов — `.notImproved`: честный ответ «движение сделано,
/// компас лучше не стал»; если система позже ответит лучше, фаза перейдёт в `.ready` сама.
/// Калибровка сама не заканчивается: ни перехода, ни таймаута — выходит только человек кнопкой.
public struct CompassCalibration: Sendable {
    public enum Phase: Sendable, Equatable {
        /// Идёт: шкала растёт по движению.
        case measuring
        /// Охват полный, ждём ответа системы о точности (первые `settle` секунд).
        case checking
        /// Охват полный, точность не хуже порога.
        case ready
        /// Охват полный, а точность осталась хуже порога: «Ещё раз».
        case notImproved
        /// Датчика нет — калибровать нечего (симулятор, Mac).
        case noSensor
    }

    /// Чего недостаёт движению, когда шкала стоит дольше `stallBeforeHint`.
    public enum Hint: Sendable, Equatable {
        case tiltMore, turnMore, slower
    }

    /// Порог точности: погрешность курса не больше этого, градусы. Подобран по документации, не по железу:
    /// `CLHeading.headingAccuracy` — максимальная погрешность; ±15° — граница, которую берут как «курс пригоден»,
    /// и четверть горизонтального поля зрения камеры (≈ 60°). Лучше система в поле нередко и не обещает; пересмотреть
    /// после замера на телефоне.
    public static let requiredDegrees: Degrees = 15
    /// Если градусов нет, а ступень поля есть: не ниже средней (как было в 29.8в.2).
    public static let requiredLevel: MagneticAccuracy = .medium
    /// Сколько секунд отсчётов после полного охвата ждать ответа системы, прежде чем сказать «не стало лучше».
    public static let settle: TimeInterval = 3
    /// Шкала стоит дольше этого — показать подсказку, чего недостаёт, секунды отсчётов.
    public static let stallBeforeHint: TimeInterval = 4
    /// Прибавка шкалы меньше этой не считается движением.
    static let growthStep: Double = 0.005
    /// Быстрее этого (сглаженно) — «двигайте медленнее», °/с.
    public static let tooFast: Double = 120

    public private(set) var phase: Phase = .measuring
    public private(set) var coverage = MotionCoverage()
    /// Точность при входе (первая сообщённая) и сейчас.
    public private(set) var entryAccuracy: CompassAccuracy?
    public private(set) var accuracy: CompassAccuracy?

    private var hasReadings = false
    private var lastTime: TimeInterval = 0
    private var lastGrowth: TimeInterval = 0
    private var lastProgress: Double = 0
    private var coveredAt: TimeInterval?
    private var smoothedRate: Double = 0

    public init() {}

    /// Датчика нет: фаза `.noSensor`, шкала пуста, ждать нечего.
    public mutating func markNoSensor() {
        phase = .noSensor
    }

    public mutating func add(_ r: CalibrationReading) {
        guard phase != .noSensor else { return }
        if !hasReadings {
            hasReadings = true
            lastGrowth = r.time
        } else if r.time > lastTime {
            smoothedRate += (r.rotationRate - smoothedRate) * min(1, (r.time - lastTime) / 0.5)
        }
        lastTime = r.time

        let now = CompassAccuracy(degrees: r.headingAccuracy, level: r.level)
        accuracy = now
        if entryAccuracy == nil, now.isKnown { entryAccuracy = now }

        coverage.add(time: r.time, gravity: r.gravity, verticalRate: r.verticalRate)
        let p = coverage.progress
        if p >= lastProgress + Self.growthStep {
            lastProgress = p
            lastGrowth = r.time
        }

        if phase == .ready { return }
        guard coverage.isComplete else { phase = .measuring; return }
        let done = coveredAt ?? r.time
        coveredAt = done
        if now.isAcceptable {
            phase = .ready
        } else {
            phase = r.time - done >= Self.settle ? .notImproved : .checking
        }
    }

    /// Шкала `0 … 1`: охват движения. Без отсчётов — 0.
    public var progress: Double {
        switch phase {
        case .noSensor: return 0
        default: return hasReadings ? coverage.progress : 0
        }
    }

    /// «Готово» доступно.
    public var canFinish: Bool { phase == .ready }

    /// Подсказка, пока шкала стоит; `nil` — рано или нечего подсказать.
    public var hint: Hint? {
        guard phase == .measuring, hasReadings, lastTime - lastGrowth >= Self.stallBeforeHint else { return nil }
        if smoothedRate > Self.tooFast { return .slower }
        if coverage.missingTilt { return .tiltMore }
        if coverage.missingTurn { return .turnMore }
        return nil
    }

    public mutating func reset() {
        phase = .measuring
        coverage = MotionCoverage()
        entryAccuracy = nil
        accuracy = nil
        hasReadings = false
        lastTime = 0
        lastGrowth = 0
        lastProgress = 0
        coveredAt = nil
        smoothedRate = 0
    }
}
