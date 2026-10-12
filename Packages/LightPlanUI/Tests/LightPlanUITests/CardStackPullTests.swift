import Testing
import Foundation
@testable import LightPlanUI

/// 29.3а: гармошка стопки — числа веба («Потянуть стопку», `beta/index.html`
/// ~28505: `sheetTravel`, `pullLen`, `spread`, `touchstart`, `dy > 6`).
/// Ожидаемые числа посчитаны по формулам веба руками, не кодом натива.
struct CardStackPullTests {

    /// Ход листа `(N−1)·44 + 74 − N·22`: на одном крае — прежние 52.
    @Test func sheetTravelByStackSize() {
        #expect(StackPull.sheetTravel(0) == 0)
        #expect(StackPull.sheetTravel(1) == 52)
        #expect(StackPull.sheetTravel(2) == 74)
        #expect(StackPull.sheetTravel(3) == 96)
        #expect(StackPull.sheetTravel(4) == 118)
        #expect(StackPull.sheetTravel(5) == 140)
        #expect(StackPull.sheetTravel(7) == 184)
    }

    /// Длина протяга `110 + max(0, N−1)·30`.
    @Test func pullLengthByStackSize() {
        #expect(StackPull.pullLength(1) == 110)
        #expect(StackPull.pullLength(2) == 140)
        #expect(StackPull.pullLength(3) == 170)
        #expect(StackPull.pullLength(4) == 200)
        #expect(StackPull.pullLength(5) == 230)
    }

    /// Край k едет на `(N−1−k)·22·p`: дальний стоит, ближний — дальше всех.
    @Test func peekOffsets() {
        #expect(StackPull.peekOffset(k: 0, n: 1, p: 1) == 0)
        #expect(StackPull.peekOffset(k: 0, n: 2, p: 1) == 22)
        #expect(StackPull.peekOffset(k: 1, n: 2, p: 1) == 0)
        #expect(StackPull.peekOffset(k: 0, n: 4, p: 0.5) == 33)
        #expect(StackPull.peekOffset(k: 2, n: 4, p: 0.5) == 11)
        #expect(StackPull.peekOffset(k: 3, n: 4, p: 0.5) == 0)
        #expect(StackPull.peekOffset(k: 0, n: 5, p: 1) == 88)
    }

    /// Доля протяга — сдвиг на длину, в пределах 0…1.
    @Test func progressClamps() {
        #expect(StackPull.progress(dy: 55, n: 1) == 0.5)
        #expect(StackPull.progress(dy: 100, n: 4) == 0.5)
        #expect(StackPull.progress(dy: -20, n: 2) == 0)
        #expect(StackPull.progress(dy: 400, n: 3) == 1)
    }

    /// Касание берётся только одним пальцем, с краями, вне «ползунков» и у
    /// не прокрученного листа (`scrollTop ≤ 2`).
    @Test func startConditions() {
        #expect(StackPull.canStart(n: 2, tuning: false, touches: 1, scrollTop: 0))
        #expect(StackPull.canStart(n: 2, tuning: false, touches: 1, scrollTop: 2))
        #expect(!StackPull.canStart(n: 2, tuning: false, touches: 1, scrollTop: 2.5))
        #expect(!StackPull.canStart(n: 2, tuning: false, touches: 1, scrollTop: 120))
        #expect(!StackPull.canStart(n: 2, tuning: true, touches: 1, scrollTop: 0))
        #expect(!StackPull.canStart(n: 0, tuning: false, touches: 1, scrollTop: 0))
        #expect(!StackPull.canStart(n: 2, tuning: false, touches: 2, scrollTop: 0))
    }

    /// Вниз больше 6 — наш; вверх больше 6 или вбок сильнее, чем вниз, — нет.
    @Test func moveVerdict() {
        #expect(StackPull.verdict(dx: 0, dy: 6) == .wait)
        #expect(StackPull.verdict(dx: 0, dy: 6.5) == .take)
        #expect(StackPull.verdict(dx: 5, dy: 7) == .take)
        #expect(StackPull.verdict(dx: 0, dy: -7) == .refuse)
        #expect(StackPull.verdict(dx: 8, dy: 3) == .refuse)
        #expect(StackPull.verdict(dx: -9, dy: 7) == .refuse)
        #expect(StackPull.verdict(dx: 4, dy: -3) == .wait)
    }
}
