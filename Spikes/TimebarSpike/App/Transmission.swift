import Foundation

/// Передача разряда: сутки и время — два разряда одного механизма, как в
/// одометре. Младший переполняется и толкает старший
/// (`light_plan:Light_Plan/DECISIONS.md`, «Передача разряда»).
///
/// Чистая механика без SwiftUI: её можно считать в тестах и она переедет в
/// `LightPlanTimeline`, когда прототип ответит «да».
///
/// Числа перенесены из веба без правки (`beta/index.html`, `WIND_NEED` и
/// соседи). Они выверены на живом телефоне с чехлом, и в настройки их не
/// выносят: довод Алексея — выверенная тактильная механика одинакова у всех,
/// иначе первый же расстроит её под себя и решит, что прибор такой и есть.
struct Transmission {

    /// Порог срыва.
    static let need = 34.0
    /// Скорость взвода от одного удержания, единиц в секунду.
    static let dwellRate = 32.0
    /// Ход яруса на полном взводе, pt.
    static let strainMax = 6.0
    /// Зона у края, где взвод разрешено начинать, pt. 28, а не 14: бортик
    /// чехла съедает крайние пиксели раньше, чем палец дойдёт до стекла.
    static let edgeZone = 28.0
    /// Стравливание: накопленное уходит к нулю за это время.
    static let bleed = 0.2

    private static let squash = 4.5
    private static let thumbBase = 26.0

    /// Накопленный взвод со знаком. Знак — сторона суток.
    private(set) var raw = 0.0
    /// Куда давит палец: +1 конец суток, -1 начало, 0 не давит.
    private(set) var side = 0
    /// Один срыв за одно усилие. После срыва палец всё ещё лежит на упоре, и
    /// без этого флага взвод копился бы заново: на живом телефоне за одно
    /// удержание дата ушла на три дня разом. Снимается только отпусканием —
    /// как у настоящего механизма, где рукоятку надо взять заново.
    private(set) var spent = false

    enum Outcome: Equatable {
        /// Ничего не копится.
        case idle
        /// Взвод идёт, перерисовать натяжение.
        case winding
        /// Порог взят, дата уходит в эту сторону.
        case fire(Int)
    }

    /// Взяли рукоятку.
    mutating func grab() {
        spent = false
        raw = 0
        side = 0
    }

    /// Отпустили: следующий срыв снова доступен, накопленное стравливается.
    mutating func release() {
        spent = false
        side = 0
    }

    /// Палец ведёт. `side` уже посчитан вызывающим: значение на упоре **и**
    /// палец в зоне у края. Одного упора мало — иначе взвод копился бы у
    /// всякого, кто просто доехал до края и замер, разглядывая экран.
    mutating func drag(dx: Double, side newSide: Int) -> Outcome {
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
    mutating func dwell(dt: Double) -> Outcome {
        guard !spent, side != 0 else { return .idle }
        raw += Double(side) * Self.dwellRate * dt
        return reached() ? .fire(side) : .winding
    }

    /// Срыв случился: держим значение на месте до нового касания.
    mutating func fired() {
        spent = true
        raw = 0
        side = 0
    }

    /// Стравливание, кубическое затухание к нулю. `k` — доля времени.
    mutating func bleed(from w0: Double, k: Double) {
        raw = w0 * pow(1 - min(max(k, 0), 1), 3)
    }

    mutating func reset() {
        raw = 0
        side = 0
    }

    private func reached() -> Bool { abs(raw) >= Self.need }

    // MARK: - Как это выглядит

    /// Доля взвода, 0…1.
    var progress: Double { min(abs(raw) / Self.need, 1) }

    /// Сдвиг яруса. Ход не линейный: к порогу механизм упирается.
    var strain: Double {
        Double(side.signum()) * Self.strainMax * (1 - pow(1 - progress, 1.8))
    }

    /// Ползунок сплющивается: уже и выше.
    var thumbWidth: Double { Self.thumbBase - progress * Self.squash }
    var thumbHeight: Double { Self.thumbBase + progress * Self.squash * 0.7 }

    /// Конец дорожки разогревается. Квадрат — чтобы зарево вспыхивало к концу,
    /// а не светило с первого пикселя.
    var heat: Double { progress * progress * 0.55 }
}
