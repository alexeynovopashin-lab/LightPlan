import Testing
import SwiftUI
import LightPlanCore
import LightPlanDomain
import LightPlanData
@testable import LightPlanUI

/// Пульт «Съёмок» и стопки дня (30и.4, 30и.5, 30и.8).
@MainActor
struct PlannerConsoleTests {
    // MARK: Пульт

    /// Набор кнопок: пока полоса мудборда ниже середины окна — «Съёмка · Встреча · Занять», выше — «Подборка · Референс».
    @Test func buttonsFollowTheMoodboardStrip() {
        #expect(ConsoleMetrics.set(stripTop: 900, window: 800) == .calendar)
        #expect(ConsoleMetrics.set(stripTop: 401, window: 800) == .calendar)
        #expect(ConsoleMetrics.set(stripTop: 399, window: 800) == .moodboard)
        #expect(ConsoleMetrics.set(stripTop: -200, window: 800) == .moodboard)
        #expect(ConsoleMetrics.set(stripTop: 0, window: 0) == .calendar, "окно не измерено — набор календаря")
    }

    /// Числа пульта: строка 40, поле 6, плашка 52, с зазором 60; «Наверх» над пультом, запас низа ленты — кнопка с отступом.
    @Test func consoleNumbers() {
        #expect(ConsoleMetrics.row == 40)
        #expect(ConsoleMetrics.plate == 52)
        #expect(ConsoleMetrics.height == 60)
        #expect(ConsoleMetrics.jumpLook.bottom == 68)
        #expect(ScrollJump.reserve(ConsoleMetrics.jumpLook) == 108)
        #expect(ScrollJump.reserve(ConsoleMetrics.jumpLook) >= ConsoleMetrics.height, "последняя строка не прячется под пультом")
    }

    // MARK: Стопка дня

    private let day = CivilDate(year: 2026, month: 11, day: 14)

    private func shoot(_ id: String, _ min: Int, kind: RecordKind = .shoot) -> Session {
        Session(id: id, kind: kind, day: day, start: min, duration: 60)
    }

    private func items(_ list: [Session]) -> [DayItem] {
        DayItem.items(on: day, sessions: list, blocks: [], eventsLayer: true)
    }

    /// Одна съёмка — строка; две и больше — стопка на месте первой; веер раскрыт — строки на местах; встреча остаётся строкой.
    @Test func stackStartsFromTwoShoots() {
        let one = items([shoot("a", 600)])
        #expect(PlannerDayList.entries(one, fanned: false).count == 1)
        if case .row = PlannerDayList.entries(one, fanned: false)[0] {} else { Issue.record("одна съёмка должна остаться строкой") }

        let two = items([shoot("a", 600), shoot("b", 900), shoot("c", 1140)])
        let stacked = PlannerDayList.entries(two, fanned: false)
        #expect(stacked.count == 1)
        if case .stack(let its, _) = stacked[0] { #expect(its.count == 3) } else { Issue.record("три съёмки — одна стопка") }
        #expect(PlannerDayList.entries(two, fanned: true).count == 3, "веер: все три строки")

        let mixed = items([shoot("a", 600), shoot("m", 700, kind: .meet), shoot("b", 900)])
        let e = PlannerDayList.entries(mixed, fanned: false)
        #expect(e.count == 2, "стопка из двух съёмок и строка встречи")
        if case .stack(let its, _) = e[0] { #expect(its.count == 2) } else { Issue.record("стопка стоит на месте первой съёмки") }
    }

    // MARK: Строка → карточка

    /// Плашка растёт 0 → 1, содержимое карточки проявляется во второй половине пути, слова строки гаснут в первой.
    @Test func growthCurvesAreMonotoneAndMeetAtTheEnds() {
        #expect(CardGrowReveal.contentOpacity(0) == 0)
        #expect(CardGrowReveal.contentOpacity(1) == 1)
        #expect(CardGrowReveal.ghostOpacity(0) == 1)
        #expect(CardGrowReveal.ghostOpacity(1) == 0)
        var last: CGFloat = -1
        for i in 0...20 { let v = CardGrowReveal.contentOpacity(CGFloat(i) / 20); #expect(v >= last); last = v }
        // Слова строки уже погасли, когда содержимое ещё не проявилось: в середине нет двух накладок.
        #expect(CardGrowReveal.ghostOpacity(CardGrowReveal.contentFrom) <= 0.3)
    }
}
