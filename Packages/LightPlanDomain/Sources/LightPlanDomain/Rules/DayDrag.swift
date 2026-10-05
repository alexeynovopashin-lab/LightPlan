import Foundation

/// Время события рукой на ленте дня (веб `dlTrack`, `dlCommit`; DECISIONS
/// «Время события рукой на ленте дня», 18 сентября 2026). Удержание поднимает
/// событие, палец ведёт время с шагом в четверть часа; у выделенного — ручки
/// начала и конца. Здесь — только числа: шаг, сетка, пределы суток,
/// «матрёшка» и след сдвига в записи. Палец и прокрутка — в `LightPlanUI`.
public enum DayDrag {

    /// Что ведёт палец: событие целиком, ручку начала (верхнюю) или конца (нижнюю).
    public enum Mode: Sendable, Hashable { case move, start, end }

    /// Как запись берётся на ленте (веб `dlGrip`).
    public enum Grip: Sendable, Hashable {
        /// Не берётся: занятость (замок) и продолжение ночной съёмки из вчера.
        case none
        /// Пустая: удержание поднимает, палец переносит целиком.
        case move
        /// Непустая съёмка («матрёшка»): целиком не переносится — удержание
        /// сразу даёт веер и ручки, ручки упираются в точки.
        case pin
    }

    /// Шаг пальца (веб `dlStep`): 15 минут, 30 — если в настройках шаг 30.
    /// Пять минут — это 3 pt на часе в 38, пальцем не попасть; точные минуты
    /// правятся в форме.
    public static func step(timeStep: Int) -> Int { timeStep == 30 ? 30 : 15 }

    /// Берётся ли запись этих суток. `fromYesterday` — кусок записи, начатой
    /// вчера: её начало лежит в других сутках.
    public static func grip(_ s: Session, fromYesterday: Bool) -> Grip {
        if fromYesterday { return .none }
        return Nest.span(of: s) == nil ? .move : .pin
    }

    /// Время под пальцем (веб `dlTrack`). `a0`, `b0` — начало и конец записи до
    /// жеста (конец может уходить за полночь), `minutes` — путь пальца в
    /// минутах ленты (pt / высота часа × 60). Привязка к сетке абсолютная, как
    /// в календаре iOS, но первые полшага — мёртвая зона: дрогнувший палец не
    /// превращает 19:38 от заката в 19:45.
    public static func track(_ mode: Mode, a0: Int, b0: Int, minutes d: Double, step st: Int,
                             nest: NestSpan?) -> (start: Int, end: Int) {
        var a = a0, b = b0
        guard abs(d) >= Double(st) / 2 else { return (a, b) }
        func sn(_ m: Double) -> Int { Int((m / Double(st) + 0.5).rounded(.down)) * st }
        func clamp(_ x: Int, _ lo: Int, _ hi: Int) -> Int { min(max(x, lo), hi) }
        switch mode {
        case .move:
            // Верхний предел — не раньше собственного начала: событие с 23:50 при
            // уводе вниз упиралось бы в 23:45 и ехало вверх, против пальца.
            a = clamp(sn(Double(a0) + d), 0, max(a0, 1440 - st))
            b = a + (b0 - a0)
        case .start:
            a = clamp(sn(Double(a0) + d), 0, max(a0, b0 - st))
        case .end:
            b = clamp(sn(Double(b0) + d), min(b0, a0 + st), 1440)
        }
        // Край непустой съёмки не заходит внутрь содержимого: ручка встаёт ровно
        // на начало первой точки или конец последней, даже вне шага.
        if let nest, mode == .start { a = nest.clampStart(a) }
        if let nest, mode == .end { b = nest.clampEnd(b) }
        return (a, b)
    }

    /// Записать сдвиг в запись (веб `dlCommit`). `false` — время не изменилось.
    ///
    /// След: `dayMoved` хранит время до первого сдвига серии и строку,
    /// дописанную в заметку. Пока строка стоит последней в заметке, следующий
    /// сдвиг её переписывает — серия даёт одну строку, «было» остаётся
    /// исходным. Вернули как было — строка вынимается, след снимается: сдвига
    /// не случилось. Заметку, которую после сдвига дописали руками, не трогаем:
    /// новая строка встаёт ниже. Точки маршрута и часы аренды не двигаются.
    ///
    /// `line` строит строку заметки из «было» и «стало» (минуты от полуночи
    /// первого дня) — слова и часы у интерфейса.
    @discardableResult
    public static func commit(_ s: inout Session, start a: Int, end b: Int,
                              line: (_ was: (Int, Int), _ now: (Int, Int)) -> String) -> Bool {
        let a0 = s.start, b0 = s.endMinute
        if a == a0 && b == b0 { return false }
        let mv = s.dayMoved ?? DayMoved(start: a0, end: b0)
        var notes = s.notes
        if let old = mv.line, !old.isEmpty, notes.hasSuffix(old) {
            notes = String(notes.dropLast(old.count))
            while notes.hasSuffix("\n") { notes.removeLast() }
        }
        s.start = a
        s.end = b
        s.duration = b - a
        if a == mv.start && b == mv.end {
            s.dayMoved = nil
        } else {
            let text = line((mv.start, mv.end), (a, b))
            notes = notes.isEmpty ? text : notes + "\n" + text
            s.dayMoved = DayMoved(start: mv.start, end: mv.end, line: text)
        }
        s.notes = notes
        return true
    }
}
