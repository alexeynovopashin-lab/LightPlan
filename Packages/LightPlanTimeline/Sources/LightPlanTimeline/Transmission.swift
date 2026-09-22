import Foundation

/// Передача разряда: сутки и время — два разряда одного механизма, как в
/// одометре. Младший переполняется и толкает старший
/// (`light_plan:Light_Plan/DECISIONS.md`, «Передача разряда»).
///
/// Порт `Spikes/TimebarSpike/App/Transmission.swift` (итерация 3, снята на
/// живом телефоне с чехлом) без изменений. Числа из веба, выверены пальцем —
/// в настройки не выносятся: довод Алексея — выверенная тактильная механика
/// одинакова у всех, иначе первый же расстроит её под себя и решит, что
/// прибор такой и есть.
public struct Transmission: Sendable, Equatable {

    /// Порог срыва.
    public static let need = 34.0
    /// Скорость взвода от одного удержания, единиц в секунду.
    public static let dwellRate = 32.0
    /// Ход яруса на полном взводе, pt.
    public static let strainMax = 6.0
    /// Зона у края, где взвод разрешено начинать, pt. 28, а не 14: бортик
    /// чехла съедает крайние пиксели раньше, чем палец дойдёт до стекла.
    public static let edgeZone = 28.0
    /// Стравливание: накопленное уходит к нулю за это время, секунды.
    public static let bleed = 0.2

    private static let squash = 4.5
    private static let thumbBase = 26.0

    /// Накопленный взвод со знаком. Знак — сторона суток.
    public private(set) var raw = 0.0
    /// Куда давит палец: +1 конец суток, -1 начало, 0 не давит.
    public private(set) var side = 0
    /// Один срыв за одно усилие. После срыва палец всё ещё лежит на упоре, и
    /// без этого флага взвод копился бы заново: на живом телефоне за одно
    /// удержание дата ушла на три дня разом. Снимается только отпусканием —
    /// как у настоящего механизма, где рукоятку надо взять заново.
    public private(set) var spent = false

    public init() {}

    public enum Outcome: Equatable, Sendable {
        /// Ничего не копится.
        case idle
        /// Взвод идёт, перерисовать натяжение.
        case winding
        /// Порог взят, дата уходит в эту сторону.
        case fire(Int)
    }

    /// Взяли рукоятку.
    public mutating func grab() {
        spent = false
        raw = 0
        side = 0
    }

    /// Отпустили: следующий срыв снова доступен, накопленное стравливается.
    public mutating func release() {
        spent = false
        side = 0
    }

    /// Палец ведёт. `side` уже посчитан вызывающим: значение на упоре **и**
    /// палец в зоне у края. Одного упора мало — иначе взвод копился бы у
    /// всякого, кто просто доехал до края и замер, разглядывая экран.
    public mutating func drag(dx: Double, side newSide: Int) -> Outcome {
        guard !spent else { return .idle }
        guard newSide != 0 else {
            side = 0
            return .idle
        }
        if side != newSide {
            raw = 0
            side = newSide
        }
        // Движение наружу добавляет к удержанию; внутрь — не отнимает.
        if dx * Double(newSide) > 0 { raw += dx }
        return reached() ? .fire(newSide) : .winding
    }

    /// Упершийся палец двигать уже некуда, а довести дело до конца он должен.
    public mutating func dwell(dt: Double) -> Outcome {
        guard !spent, side != 0 else { return .idle }
        raw += Double(side) * Self.dwellRate * dt
        return reached() ? .fire(side) : .winding
    }

    /// Срыв случился: держим значение на месте до нового касания.
    public mutating func fired() {
        spent = true
        raw = 0
        side = 0
    }

    /// Стравливание, кубическое затухание к нулю. `k` — доля времени.
    public mutating func bleed(from w0: Double, k: Double) {
        raw = w0 * pow(1 - min(max(k, 0), 1), 3)
    }

    public mutating func reset() {
        raw = 0
        side = 0
    }

    private func reached() -> Bool { abs(raw) >= Self.need }

    // MARK: - Как это выглядит

    /// Доля взвода, 0…1.
    public var progress: Double { min(abs(raw) / Self.need, 1) }

    /// Сдвиг яруса. Ход не линейный: к порогу механизм упирается.
    public var strain: Double {
        Double(side.signum()) * Self.strainMax * (1 - pow(1 - progress, 1.8))
    }

    /// Ползунок сплющивается: уже и выше.
    public var thumbWidth: Double { Self.thumbBase - progress * Self.squash }
    public var thumbHeight: Double { Self.thumbBase + progress * Self.squash * 0.7 }

    /// Конец дорожки разогревается. Квадрат — чтобы зарево вспыхивало к концу,
    /// а не светило с первого пикселя.
    public var heat: Double { progress * progress * 0.55 }
}
