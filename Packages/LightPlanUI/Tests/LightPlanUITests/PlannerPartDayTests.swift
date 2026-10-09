import Testing
import CoreGraphics
import LightPlanCore
@testable import LightPlanUI

private func d(_ y: Int, _ m: Int, _ day: Int) -> CivilDate { CivilDate(year: y, month: m, day: day) }

/// Разрез месяца при входе в день (29.2а) и сброс направления въезда ленты дня (аудит C2).
@Suite struct PlannerPartDayTests {

    // MARK: машина

    @Test func cutGoesThroughPhasesInBetaOrder() {
        var m = PartDayMachine()
        #expect(m.phase == .idle && !m.showsLayer && !m.stripHidden)
        let run = m.cut()
        #expect(m.phase == .cut && m.showsLayer && m.stripHidden)    // снимки легли, лента дат спрятана
        m.tick(at: 100, run: run)                                     // без старта часы не идут
        #expect(m.phase == .cut)
        m.go(at: 5)                                                   // ленты дат нет — не летим
        #expect(m.phase == .cut)
        m.lay()
        m.go(at: 10)
        #expect(m.phase == .moving && m.stripHidden)
        m.tick(at: 10.279, run: run)
        #expect(m.phase == .moving)                                   // до 280 мс ленты нет
        m.tick(at: 10.28, run: run)
        #expect(m.phase == .revealed && m.showsLayer && !m.stripHidden)
        m.tick(at: 10.399, run: run)
        #expect(m.phase == .revealed)
        m.tick(at: 10.40, run: run)
        #expect(m.phase == .idle && !m.showsLayer)                    // в 400 мс снимков нет
    }

    @Test func tapInTheMiddleEndsAtOnce() {
        var m = PartDayMachine()
        let run = m.cut()
        m.lay()
        m.go(at: 0)
        m.tick(at: 0.1, run: run)
        m.interrupt()                                                 // касание посреди
        #expect(m.phase == .idle && !m.showsLayer && !m.stripHidden)
        m.tick(at: 0.3, run: run)                                     // таймеры прерванного ничего не открывают
        #expect(m.phase == .idle)
        m.go(at: 0.35)                                                // и старт без реза — тоже
        #expect(m.phase == .idle)
    }

    @Test func newCutIgnoresOldTimers() {
        var m = PartDayMachine()
        let first = m.cut()
        m.lay()
        m.go(at: 0)
        let second = m.cut()                                          // выход и новый вход, пока первый шёл
        #expect(second == first + 1 && m.phase == .cut && !m.laid)    // рамка ленты прошлого разреза не в счёт
        m.lay()
        m.go(at: 1)
        m.tick(at: 1.39, run: first)
        #expect(m.phase == .moving)
        m.tick(at: 1.3, run: second)
        #expect(m.phase == .revealed)
    }

    // MARK: запасной срок (ревью GPT к 29.2а)

    @Test func lateWithoutStripEntersStill() {
        var m = PartDayMachine()
        let run = m.cut()
        let flies = m.late()
        #expect(!flies && m.phase == .idle && !m.showsLayer && !m.stripHidden)    // слоя нет: ячейки не гаснут на месте
        m.lay()
        m.go(at: 0.1)                                                 // поздняя рамка ленты разреза уже не стартует
        m.tick(at: 0.5, run: run)
        #expect(m.phase == .idle)
    }

    @Test func lateWithStripStillFlies() {
        var m = PartDayMachine()
        m.cut()
        m.lay()
        let flies = m.late()
        #expect(flies)                                                // лента есть — летим
        m.go(at: 0)
        #expect(m.phase == .moving)
        var live = PartDayMachine()
        live.cut(stripLive: true)                                     // из ленты года, когда под ней уже день
        let liveFlies = live.late()
        #expect(live.laid && liveFlies)
        var idle = PartDayMachine()
        let idleFlies = idle.late()
        #expect(!idleFlies && idle.phase == .idle)                    // без разреза срок ничего не делает
    }

    @Test func yearEntryRunsTheSameMachine() {
        var m = PartDayMachine()
        let run = m.cut()                                             // тап по числу ленты: снимки, лента закрыта, день под ними
        #expect(m.showsLayer && m.stripHidden)
        m.lay()
        m.go(at: 2)
        m.tick(at: 2.2, run: run)
        m.interrupt()                                                 // касание посреди — сразу конечный кадр
        #expect(m.phase == .idle && !m.showsLayer && !m.stripHidden)
        let again = m.cut(stripLive: true)
        m.go(at: 3)                                                   // лента дня уже стояла — старт без её отчёта
        m.tick(at: 3.28, run: again)
        #expect(m.phase == .revealed)
        m.tick(at: 3.4, run: again)
        #expect(m.phase == .idle)
    }

    // MARK: числа беты

    @Test func curvesMatchCss() {
        let ease = PartDayTiming.fadeCurve, move = PartDayTiming.moveCurve
        // Эталон — решение тех же кривых делением пополам (100 шагов), 4 знака.
        for (x, y) in [(0.1, 0.0948), (0.25, 0.4085), (0.5, 0.8024), (0.75, 0.9605)] {
            #expect(abs(ease.y(atX: x) - y) < 1e-4)
        }
        for (x, y) in [(0.1, 0.0259), (0.25, 0.2366), (0.5, 0.7756), (0.75, 0.9594)] {
            #expect(abs(move.y(atX: x) - y) < 1e-4)
        }
        #expect(move.y(atX: -1) == 0 && move.y(atX: 2) == 1)
    }

    @Test func framesFadeHalvesThenCellsThenOpenStrip() {
        let f = PartDayTiming.frame
        #expect(f(0) == .init(move: 0, halves: 1, cells: 1, stripShown: false))
        #expect(abs(f(0.17).move - 0.7756) < 1e-4)                    // середина пути — кривая (0.4, 0, 0.2, 1)
        #expect(f(0.24).halves == 1 && f(0.25).halves < 1)            // половины гаснут с 240 мс
        #expect(f(0.25).cells == 1 && f(0.27).cells < 1)              // ячейки — с 260 мс
        #expect(!f(0.279).stripShown && f(0.28).stripShown)           // лента дат — в 280 мс
        #expect(f(0.34).move == 1 && f(0.34).halves == 0)             // половины ушли и погасли
        #expect(f(0.36).cells == 0)
    }

    @Test func geometryFollowsRowAndStrip() {
        let row = CGRect(x: 20, y: 347, width: 400, height: 58)
        let cells = PartDayGeometry.cells(row: row)
        #expect(cells.count == 7 && cells[0].minX == 20 && abs(cells[6].maxX - 420) < 1e-9)
        #expect(abs(cells[1].minX - cells[0].maxX - MonthMetrics.colGap) < 1e-9)
        let strip = CGRect(x: 16, y: 130, width: 408, height: 72)
        let dates = PartDayGeometry.dates(strip: strip)
        #expect(abs(dates[6].maxX - 424) < 1e-9 && abs(dates[1].minX - dates[0].maxX - 2) < 1e-9)
        // Половины уходят за край экрана с запасом 12 pt.
        let h = PartDayGeometry.halves(row: row, screen: CGRect(x: 0, y: 0, width: 440, height: 872))
        #expect(h.up == -359 && h.down == 479)
        // Ячейка встаёт ровно на дату: в конце пути её рамка — рамка даты.
        let fly = PartDayGeometry.fly(cells[3], dates[3])
        let end = PartDayGeometry.rect(cells[3], fly, at: 1)
        #expect(abs(end.minX - dates[3].minX) < 1e-9 && abs(end.minY - dates[3].minY) < 1e-9)
        #expect(abs(end.width - dates[3].width) < 1e-9 && abs(end.height - dates[3].height) < 1e-9)
        #expect(PartDayGeometry.rect(cells[3], fly, at: 0) == cells[3])
    }

    @Test func yearRowCutsTheTappedWeek() {
        // Октябрь 2026: 1-е — четверг, три пустых клетки впереди, 31 день. Сетка 392 pt — клетка 56, строки через 3.
        let grid = CGRect(x: 24, y: 300, width: 392, height: 5 * 56 + 4 * 3)
        let first = PartDayGeometry.yearRow(grid: grid, day: d(2026, 10, 2))
        #expect(first.row == CGRect(x: 24, y: 300, width: 392, height: 56))
        #expect(first.days == [nil, nil, nil, d(2026, 10, 1), d(2026, 10, 2), d(2026, 10, 3), d(2026, 10, 4)])
        let mid = PartDayGeometry.yearRow(grid: grid, day: d(2026, 10, 14))
        #expect(abs(mid.row.minY - (300 + 2 * 59)) < 1e-9 && mid.days.first == d(2026, 10, 12) && mid.days.last == d(2026, 10, 18))
        let last = PartDayGeometry.yearRow(grid: grid, day: d(2026, 10, 31))   // неполная последняя неделя
        #expect(abs(last.row.minY - (300 + 4 * 59)) < 1e-9)
        #expect(last.days == [d(2026, 10, 26), d(2026, 10, 27), d(2026, 10, 28), d(2026, 10, 29), d(2026, 10, 30), d(2026, 10, 31), nil])
        let cells = PartDayGeometry.cells(row: mid.row, gap: 0)       // колонки ленты — без зазора
        #expect(abs(cells[0].width - 56) < 1e-9 && cells[1].minX == cells[0].maxX && abs(cells[6].maxX - 416) < 1e-9)
    }

    @Test func yearDayTapEntersDayWithoutSideSlide() {
        var s = PlannerState(today: d(2026, 9, 23))
        s.setScope(.day)
        s.step(1)                                                     // лента открыта из дня, где только что листали
        #expect(s.dayShift == 1)
        s.enterDay(d(2026, 12, 5))                                    // commit входа из ленты
        #expect(s.scope == .day && s.selected == d(2026, 12, 5) && s.month == d(2026, 12, 1) && s.dayShift == 0)
    }

    // MARK: вход и направление въезда

    @Test func secondTapAndFanEnterSelectedDay() {
        var s = PlannerState(today: d(2026, 9, 23))
        #expect(s.entersDay(on: d(2026, 9, 23)))
        #expect(!s.entersDay(on: d(2026, 9, 24)))                     // первый тап по другому числу — выбор
        var other = s
        other.tapMonthCell(d(2026, 9, 30))                            // выбрано 30-е,
        other.step(1)                                                 // месяц листнули на октябрь: 30 сентября — в его первой строке
        #expect(!other.entersDay(on: d(2026, 9, 30)))                 // тап по выбранному чужому дню — листание, не вход
        s.enterSelectedDay()
        #expect(s.scope == .day && s.selected == d(2026, 9, 23) && s.month == d(2026, 9, 1))
        #expect(!s.entersDay(on: d(2026, 9, 23)))                     // в дне — не вход
    }

    @Test func dayShiftDiesAfterEveryEntry() {
        var s = PlannerState(today: d(2026, 9, 23))
        s.setScope(.day)
        _ = s.pickInStrip(d(2026, 9, 24))
        #expect(s.dayShift == 1)
        s.setScope(.month)                                            // ушли в месяц — направление гаснет
        #expect(s.dayShift == 0)
        s.setScope(.day)
        s.step(-1)
        #expect(s.dayShift == -1)
        s.goToday(d(2026, 9, 23))                                     // «↺ сегодня» въезда не даёт
        #expect(s.dayShift == 0)
        s.step(1)
        s.setScope(.month)
        _ = s.tapMonthCell(s.selected)                                // второй тап — вход без бокового въезда
        #expect(s.scope == .day && s.dayShift == 0)
        s.step(1)
        s.setScope(.month)
        s.enterSelectedDay()
        #expect(s.dayShift == 0)
        s.setScope(.week)
        s.step(1)
        #expect(s.dayShift == 0)
    }
}
