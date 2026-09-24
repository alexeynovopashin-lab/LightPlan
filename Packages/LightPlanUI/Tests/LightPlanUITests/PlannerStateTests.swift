import Testing
import LightPlanCore
import LightPlanDomain
@testable import LightPlanUI

private func d(_ y: Int, _ m: Int, _ day: Int) -> CivilDate { CivilDate(year: y, month: m, day: day) }

@Suite struct PlannerStateTests {

    @Test func opensOnMonthAndToday() {
        let s = PlannerState(today: d(2026, 9, 24))
        #expect(s.scope == .month)
        #expect(s.selected == d(2026, 9, 24))
        #expect(s.month == d(2026, 9, 1))
        #expect(!s.isAway(from: d(2026, 9, 24)))
    }

    @Test func weekStartsOnMonday() {
        #expect(PlannerState.weekday(d(2026, 9, 24)) == 4)          // четверг
        #expect(PlannerState.weekStart(d(2026, 9, 24)) == d(2026, 9, 21))
        #expect(PlannerState.weekStart(d(2026, 9, 27)) == d(2026, 9, 21)) // воскресенье — конец недели
        #expect(PlannerState.weekStart(d(2026, 9, 21)) == d(2026, 9, 21))
        #expect(PlannerState.weekStart(d(1969, 12, 31)) == d(1969, 12, 29))
    }

    @Test func monthGridIsWholeWeeks() {
        var s = PlannerState(today: d(2026, 9, 24))
        #expect(s.monthGrid.first == d(2026, 8, 31))
        #expect(s.monthGrid.last == d(2026, 10, 4))
        #expect(s.monthGrid.count == 35)
        s.step(-7)                                                   // февраль 2026: с 1-го по 28-е, с понедельника
        #expect(s.month == d(2026, 2, 1))
        #expect(s.monthGrid.first == d(2026, 1, 26))
        #expect(s.monthGrid.count == 35)
        #expect(PlannerState.addMonths(d(2026, 1, 1), -1) == d(2025, 12, 1))
        #expect(PlannerState.addMonths(d(2026, 12, 1), 1) == d(2027, 1, 1))
    }

    @Test func stepFollowsScope() {
        var s = PlannerState(today: d(2026, 9, 30))
        s.step(1)                                   // месяц: день стоит, листается месяц
        #expect(s.selected == d(2026, 9, 30) && s.month == d(2026, 10, 1))
        let r1 = s.consumeDayShift()
        #expect(r1 == 0)
        s.setScope(.week)                            // масштабы синхронны по выбранному дню
        #expect(s.month == d(2026, 9, 1))
        s.step(1)
        #expect(s.selected == d(2026, 10, 7) && s.month == d(2026, 10, 1))
        s.setScope(.day)
        s.step(-1)
        #expect(s.selected == d(2026, 10, 6))
        let r2 = s.consumeDayShift()
        #expect(r2 == -1)
        let r2b = s.consumeDayShift()
        #expect(r2b == 0)                            // читается один раз
    }

    @Test func monthCellTapSelectsThenEntersDay() {
        var s = PlannerState(today: d(2026, 9, 24))
        let r3 = s.tapMonthCell(d(2026, 9, 10))
        #expect(!r3)
        #expect(s.selected == d(2026, 9, 10) && s.scope == .month)
        let r4 = s.tapMonthCell(d(2026, 9, 10))
        #expect(r4)
        #expect(s.scope == .day)
        var t = PlannerState(today: d(2026, 9, 24))
        let r9 = t.tapMonthCell(d(2026, 10, 2))
        #expect(!r9)                                 // день соседнего месяца перелистывает
        #expect(t.month == d(2026, 10, 1))
        t.step(-1)                                    // месяц ушёл, выбранный день — нет
        let r10 = t.tapMonthCell(d(2026, 10, 2))
        #expect(!r10)                                // в сентябре 2 октября — «чужой», второго тапа нет
        #expect(t.scope == .month)
    }

    @Test func stripTapSetsDirection() {
        var s = PlannerState(today: d(2026, 9, 24))
        s.setScope(.day)
        let r5 = s.pickInStrip(d(2026, 9, 21))
        #expect(r5)
        let r6 = s.consumeDayShift()
        #expect(r6 == -1)
        let r7 = s.pickInStrip(d(2026, 9, 21))
        #expect(!r7)
        let r8 = s.consumeDayShift()
        #expect(r8 == 0)
        #expect(s.isAway(from: d(2026, 9, 24)))
        s.goToday(d(2026, 9, 24))
        #expect(!s.isAway(from: d(2026, 9, 24)))
    }

    @Test func weekRowOpensOneAtATime() {
        var s = PlannerState(today: d(2026, 9, 24))
        s.setScope(.week)
        s.tapWeekRow(d(2026, 9, 22))
        #expect(s.weekOpen == d(2026, 9, 22))
        s.tapWeekRow(d(2026, 9, 23))
        #expect(s.weekOpen == d(2026, 9, 23) && s.selected == d(2026, 9, 23))
        s.tapWeekRow(d(2026, 9, 23))
        #expect(s.weekOpen == nil)
        s.tapWeekRow(d(2026, 9, 25))
        s.step(1)
        #expect(s.weekOpen == nil)
    }
}

@Suite struct DayLanesTests {

    private func shoot(_ id: String, _ day: CivilDate, _ start: Int, _ dur: Int) -> Session {
        var s = Session(id: id, kind: .shoot, day: day, start: start)
        s.duration = dur
        return s
    }

    @Test func overlapChainSharesColumns() {
        let day = d(2026, 9, 24)
        // A 10:00–12:00, B 11:00–13:00, C 12:30–13:30: A и C в одной колонке.
        let items = DayItem.items(on: day, sessions: [shoot("a", day, 600, 120), shoot("b", day, 660, 120),
                                                      shoot("c", day, 750, 60)], blocks: [], eventsLayer: false)
        let lanes = DayLanes.layout(items)
        #expect(lanes.map { $0?.column } == [0, 1, 0])
        #expect(lanes.map { $0?.columns } == [2, 2, 2])
    }

    @Test func shortNeighboursSplitByMinHeight() {
        let day = d(2026, 9, 24)
        // Две по 10 минут с разницей 10 минут: по времени не пересекаются,
        // но блок не ниже 34 pt — встают в две колонки.
        let items = DayItem.items(on: day, sessions: [shoot("a", day, 600, 10), shoot("b", day, 620, 10)],
                                  blocks: [], eventsLayer: false)
        #expect(DayLanes.layout(items).map { $0?.column } == [0, 1])
    }

    @Test func allDayBusyIsBackground() {
        let day = d(2026, 9, 24)
        var off = Block(id: "v", kind: .off, from: d(2026, 9, 23))
        off.allDay = true; off.days = 3
        let items = DayItem.items(on: day, sessions: [shoot("a", day, 600, 60)], blocks: [off], eventsLayer: false)
        #expect(items.map(\.kind) == [.busy, .shoot])
        let lanes = DayLanes.layout(items)
        #expect(lanes[0] == nil)
        #expect(lanes[1]?.columns == 1)
    }

    @Test func nightShootGivesTailToNextDay() {
        let day = d(2026, 9, 24)
        let s = shoot("n", day, 22 * 60, 5 * 60)
        let next = DayItem.items(on: day.adding(days: 1), sessions: [s], blocks: [], eventsLayer: false)
        #expect(next.count == 1)
        #expect(next[0].start == 0 && next[0].end == 180 && next[0].fromYesterday)
    }

    @Test func eventsHiddenWithoutLayer() {
        let day = d(2026, 9, 24)
        let e = Session(id: "e", kind: .event, day: day, start: 600)
        #expect(DayItem.items(on: day, sessions: [e], blocks: [], eventsLayer: false).isEmpty)
        #expect(DayItem.items(on: day, sessions: [e], blocks: [], eventsLayer: true).count == 1)
    }

    @Test func urgencyScaleMatchesWebStops() {
        #expect(Urgency.rgb(0, dark: true) == (239, 234, 224))
        #expect(Urgency.rgb(0.8, dark: true) == (226, 164, 76))
        #expect(Urgency.rgb(0.25, dark: true) == (236, 221, 173))   // lerp и округление веба
        #expect(Urgency.rgb(2, dark: false) == (138, 63, 34))
        #expect(Urgency.color(.noTerm, dark: true) == Urgency.grey)
        #expect(Urgency.color(.ahead, dark: false) == (23, 21, 15))
    }
}
