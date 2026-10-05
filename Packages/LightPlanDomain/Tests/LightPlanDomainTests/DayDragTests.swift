import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Время события рукой на ленте дня (веб `dlTrack`, `dlCommit`). Числа — из
/// замеров беты в DECISIONS («Время события рукой на ленте дня», «Мелкие
/// находки багревью»): 38 pt на час, палец в минутах = pt / 38 × 60.
@Suite struct DayDragTests {
    let day = CivilDate(year: 2026, month: 9, day: 18)
    /// Путь пальца в минутах для `pt` точек ленты.
    func pt(_ p: Double) -> Double { p / 38 * 60 }
    func line(_ w: (Int, Int), _ n: (Int, Int)) -> String { "\(w.0)-\(w.1)→\(n.0)-\(n.1)" }

    @Test func stepIsQuarterUnlessSettingsSayHalf() {
        #expect(DayDrag.step(timeStep: 5) == 15)
        #expect(DayDrag.step(timeStep: 10) == 15)
        #expect(DayDrag.step(timeStep: 15) == 15)
        #expect(DayDrag.step(timeStep: 30) == 30)
    }

    /// Сдвиг на 38 pt — час: 14:00–16:00 → 15:00–17:00 (замер беты).
    @Test func moveByAnHourKeepsLength() {
        let r = DayDrag.track(.move, a0: 840, b0: 960, minutes: pt(38), step: 15, nest: nil)
        #expect(r == (900, 1020))
    }

    /// Привязка к сетке абсолютная, первые полшага — мёртвая зона.
    @Test func gridIsAbsoluteWithHalfStepDeadZone() {
        // 19:38 от заката: дрогнул на 5 минут — стоит.
        #expect(DayDrag.track(.move, a0: 1178, b0: 1268, minutes: 5, step: 15, nest: nil) == (1178, 1268))
        #expect(DayDrag.track(.move, a0: 1178, b0: 1268, minutes: -7.4, step: 15, nest: nil) == (1178, 1268))
        // Полшага пройдено — встаёт на сетку: 19:45, а не 19:48.
        #expect(DayDrag.track(.move, a0: 1178, b0: 1268, minutes: 10, step: 15, nest: nil) == (1185, 1275))
        #expect(DayDrag.track(.move, a0: 840, b0: 960, minutes: 7.5, step: 15, nest: nil) == (855, 975))
        // Шаг 30 в настройках: полшага — 15 минут.
        #expect(DayDrag.track(.move, a0: 840, b0: 960, minutes: 14, step: 30, nest: nil) == (840, 960))
        #expect(DayDrag.track(.move, a0: 840, b0: 960, minutes: 20, step: 30, nest: nil) == (870, 990))
        #expect(DayDrag.track(.end, a0: 840, b0: 960, minutes: 31, step: 30, nest: nil) == (840, 990))
    }

    /// Границы суток: выше полуночи не уезжает; позже 23:45 вниз не тянет назад.
    @Test func dayBounds() {
        #expect(DayDrag.track(.move, a0: 60, b0: 180, minutes: -240, step: 15, nest: nil) == (0, 120))
        // 23:50–01:00, вниз на 10 и 30 pt — стоит (было 23:45 со следом).
        #expect(DayDrag.track(.move, a0: 1430, b0: 1500, minutes: pt(10), step: 15, nest: nil) == (1430, 1500))
        #expect(DayDrag.track(.move, a0: 1430, b0: 1500, minutes: pt(30), step: 15, nest: nil) == (1430, 1500))
        // Вверх на 30 pt — 23:00–00:10.
        #expect(DayDrag.track(.move, a0: 1430, b0: 1500, minutes: pt(-30), step: 15, nest: nil) == (1380, 1450))
        // Обычное вниз до упора — начало не позже 23:45, длина та же.
        #expect(DayDrag.track(.move, a0: 1320, b0: 1380, minutes: 600, step: 15, nest: nil) == (1425, 1485))
        // Ночная 22:00–01:00 вверх на час — 21:00–24:00 (замер беты).
        #expect(DayDrag.track(.move, a0: 1320, b0: 1500, minutes: pt(-38), step: 15, nest: nil) == (1260, 1440))
        // Конец — не дальше полуночи.
        #expect(DayDrag.track(.end, a0: 1320, b0: 1380, minutes: 300, step: 15, nest: nil) == (1320, 1440))
    }

    /// Ручки: начало не обгоняет конец, конец — начало; шаг между ними остаётся.
    @Test func handlesKeepAStepApart() {
        // Нижняя +19 pt — конец 18:00 → 18:30.
        #expect(DayDrag.track(.end, a0: 1020, b0: 1080, minutes: pt(19), step: 15, nest: nil) == (1020, 1110))
        // Верхняя −38 pt — начало 17:00 → 16:00.
        #expect(DayDrag.track(.start, a0: 1020, b0: 1110, minutes: pt(-38), step: 15, nest: nil) == (960, 1110))
        // Верхняя вниз до упора — 18:15 при конце 18:30.
        #expect(DayDrag.track(.start, a0: 1020, b0: 1110, minutes: 600, step: 15, nest: nil) == (1095, 1110))
        // Нижняя вверх до упора — шаг после начала.
        #expect(DayDrag.track(.end, a0: 1020, b0: 1110, minutes: -600, step: 15, nest: nil) == (1020, 1035))
    }

    /// «Матрёшка»: непустая съёмка целиком не берётся, ручки упираются в точки
    /// ровно, даже вне шага. Точка без часа съёмку не держит.
    @Test func nestPinsAndStopsHandles() {
        var s = Session(id: "w", day: day, start: 1020, end: 1140, duration: 120)
        s.route = [RoutePoint(start: 1050, end: 1110, name: "ЗАГС")]
        #expect(DayDrag.grip(s, fromYesterday: false) == .pin)
        let nest = Nest.span(of: s)
        #expect(DayDrag.track(.start, a0: 1020, b0: 1140, minutes: 120, step: 15, nest: nest) == (1050, 1140))
        #expect(DayDrag.track(.end, a0: 1020, b0: 1140, minutes: -120, step: 15, nest: nest) == (1020, 1110))
        // Наружу — свободно и по сетке.
        #expect(DayDrag.track(.start, a0: 1020, b0: 1140, minutes: -60, step: 15, nest: nest) == (960, 1140))

        var free = Session(id: "f", day: day, start: 900, duration: 120)
        free.route = [RoutePoint(start: nil, name: "Парк")]
        #expect(DayDrag.grip(free, fromYesterday: false) == .move)
        #expect(DayDrag.grip(Session(id: "m", kind: .meet, day: day, start: 900), fromYesterday: false) == .move)
        #expect(DayDrag.grip(Session(id: "e", kind: .event, day: day, start: 900), fromYesterday: false) == .move)
    }

    /// Продолжение ночной съёмки, начатой вчера, не берётся.
    @Test func continuationFromYesterdayStays() {
        let night = Session(id: "n", day: day, start: 1320, end: 1500, duration: 180)
        #expect(DayDrag.grip(night, fromYesterday: true) == .none)
        #expect(DayDrag.grip(night, fromYesterday: false) == .move)
    }

    /// След сдвига: строка в заметке, серия — одна строка, «было» — исходное;
    /// вернули как было — строка и след снимаются. Точки маршрута стоят.
    @Test func moveLeavesOneLineAndReturnClearsIt() {
        var s = Session(id: "a", day: day, start: 840, end: 960, duration: 120)
        s.notes = "Заметка фотографа"
        s.route = [RoutePoint(start: nil, name: "Парк")]
        #expect(!DayDrag.commit(&s, start: 840, end: 960, line: line))
        #expect(s.dayMoved == nil && s.notes == "Заметка фотографа")

        #expect(DayDrag.commit(&s, start: 900, end: 1020, line: line))
        #expect(s.start == 900 && s.end == 1020 && s.duration == 120)
        #expect(s.notes == "Заметка фотографа\n840-960→900-1020")
        #expect(s.dayMoved == DayMoved(start: 840, end: 960, line: "840-960→900-1020"))

        // Второй сдвиг — та же одна строка, «было» прежнее.
        #expect(DayDrag.commit(&s, start: 930, end: 1050, line: line))
        #expect(s.notes == "Заметка фотографа\n840-960→930-1050")
        #expect(s.dayMoved?.start == 840 && s.dayMoved?.end == 960)
        #expect(s.route == [RoutePoint(start: nil, name: "Парк")])

        // Вернули как было — ни строки, ни следа.
        #expect(DayDrag.commit(&s, start: 840, end: 960, line: line))
        #expect(s.notes == "Заметка фотографа" && s.dayMoved == nil)
    }

    /// Заметку после сдвига дописали руками — старую строку не трогаем, новая ниже.
    @Test func handEditedNoteKeepsOldLine() {
        var s = Session(id: "a", day: day, start: 840, end: 960, duration: 120)
        DayDrag.commit(&s, start: 900, end: 1020, line: line)
        #expect(s.notes == "840-960→900-1020")
        s.notes += "\nклиент просил позже"
        DayDrag.commit(&s, start: 960, end: 1080, line: line)
        #expect(s.notes == "840-960→900-1020\nклиент просил позже\n840-960→960-1080")
        #expect(s.dayMoved?.line == "840-960→960-1080")
    }

    /// След погасили крестиком — новая серия начинается с нынешнего времени.
    @Test func dismissedTraceStartsANewSeries() {
        var s = Session(id: "a", day: day, start: 840, end: 960, duration: 120)
        DayDrag.commit(&s, start: 900, end: 1020, line: line)
        s.dayMoved = nil
        DayDrag.commit(&s, start: 960, end: 1080, line: line)
        #expect(s.notes == "840-960→900-1020\n900-1020→960-1080")
        #expect(s.dayMoved == DayMoved(start: 900, end: 1020, line: "900-1020→960-1080"))
    }

    /// Ручка конца у записи без `end` — конец берётся из длительности (веб `dlEndOf`).
    @Test func endFromDuration() {
        var s = Session(id: "a", day: day, start: 600, duration: 0)
        #expect(s.endMinute == 690)
        DayDrag.commit(&s, start: 600, end: 720, line: line)
        #expect(s.end == 720 && s.duration == 120 && s.dayMoved?.end == 690)
    }
}
