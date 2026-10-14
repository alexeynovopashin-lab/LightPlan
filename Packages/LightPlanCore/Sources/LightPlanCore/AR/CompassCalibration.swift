import Foundation

/// Точность магнитного поля, как её отдаёт система (`CMMagneticFieldCalibrationAccuracy`): чем она выше, тем
/// лучше компас откалиброван.
public enum MagneticAccuracy: Int, Sendable, Comparable, CaseIterable {
    case uncalibrated = 0, low, medium, high

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Калибровка компаса «восьмёркой» перед первым включением AR (шаг 29.8в.2).
///
/// Шкала — настоящий показатель, а не таймер: она складывается из двух измеренных вещей и ни из чего больше.
/// Первое — точность магнитного поля от системы (не откалиброван → 0, низкая → ½, средняя и выше → 1).
/// Второе — устойчивость курса: сколько секунд подряд разброс курса за окно, за вычетом объяснённого поворотом
/// (`HeadingSteadiness.excess`), не выше допуска; полная шкала — `steadyHold` секунд. Без новых отсчётов шкала
/// стоит: время сам по себе её не двигает.
///
/// «Готово» — точность не ниже средней и курс устойчив `steadyHold` секунд. Раз достигнутое, остаётся (экран не
/// мигает на границе). Если система точность не сообщает (`nil`), первое условие считается выполненным и решает
/// одна устойчивость курса — это то самое «и/или» из слов Алексея; шкала и тогда идёт только по отсчётам.
public struct CompassCalibration: Sendable {
    public enum Phase: Sendable, Equatable {
        /// Идёт: шкала растёт по отсчётам.
        case measuring
        /// Достигнуто: точность и устойчивость.
        case ready
        /// Датчика нет — калибровать нечего (симулятор, Mac).
        case noSensor
    }

    /// Сколько секунд подряд курс должен быть устойчив.
    public static let steadyHold: TimeInterval = 1.5
    /// Точность, с которой компас считается пригодным.
    public static let requiredAccuracy: MagneticAccuracy = .medium

    public private(set) var phase: Phase = .measuring
    public private(set) var accuracy: MagneticAccuracy?
    /// С какого момента курс устойчив без перерыва; `nil` — сейчас не устойчив.
    public private(set) var steadySince: TimeInterval?
    public private(set) var steadyFor: TimeInterval = 0

    private var steadiness = HeadingSteadiness()
    private var hasReadings = false

    public init() {}

    /// Датчика нет: фаза `.noSensor`, шкала пуста, ждать нечего.
    public mutating func markNoSensor() {
        phase = .noSensor
    }

    /// Занести отсчёт. `heading` — `nil`, когда направление телефона у зенита или надира и курс не определён:
    /// такой отсчёт устойчивость сбрасывает, а точность всё равно учитывает.
    public mutating func add(time: TimeInterval, accuracy: MagneticAccuracy?, heading: Degrees?, rate: Double) {
        guard phase != .noSensor else { return }
        hasReadings = true
        self.accuracy = accuracy
        if let heading {
            steadiness.add(time: time, heading: heading, rate: rate)
            if let excess = steadiness.excess, excess <= HeadingSteadiness.tolerance {
                steadySince = steadySince ?? time
            } else {
                steadySince = nil
            }
        } else {
            steadiness.reset()
            steadySince = nil
        }
        steadyFor = steadySince.map { max(0, time - $0) } ?? 0
        if phase == .measuring, accuracySufficient, steadyFor >= Self.steadyHold {
            phase = .ready
        }
    }

    /// Точность поля уже годится (или система её не сообщает): остаётся удержать курс.
    public var accuracySufficient: Bool {
        guard let accuracy else { return true }
        return accuracy >= Self.requiredAccuracy
    }

    /// Шкала `0 … 1`: половина — точность, половина — устойчивость. `1` ровно тогда, когда «Готово».
    public var progress: Double {
        switch phase {
        case .noSensor: return 0
        case .ready: return 1
        case .measuring:
            // Отсчётов ещё не было — шкале двигаться не от чего.
            guard hasReadings else { return 0 }
            let q: Double
            switch accuracy {
            case nil: q = 1
            case .uncalibrated: q = 0
            case .low: q = 0.5
            case .medium, .high: q = 1
            }
            let s = min(1, steadyFor / Self.steadyHold)
            // До «Готово» шкала не доходит до единицы: единица — это сама готовность.
            return min(0.999, (q + s) / 2)
        }
    }

    public mutating func reset() {
        phase = .measuring
        accuracy = nil
        hasReadings = false
        steadySince = nil
        steadyFor = 0
        steadiness.reset()
    }
}
