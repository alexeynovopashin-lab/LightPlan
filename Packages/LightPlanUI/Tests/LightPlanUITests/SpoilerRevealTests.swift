import Testing
import CoreGraphics
@testable import LightPlanUI

/// «Подробно» (29.2г, 29.2г-2): числа раскрытия — из беты; кнопка закреплена над панелью, список растёт вверх над ней
/// и не выше низа шапки.
struct SpoilerRevealTests {
    @Test func betaNumbers() {
        #expect(SpoilerReveal.maxHeight == 1600)
        #expect(SpoilerReveal.revealDuration == 0.5)
        #expect(SpoilerReveal.chevronDuration == 0.35)
    }

    /// `max-height` обрезает список, но не растягивает: пока он 0 — виден 0, дальше растёт до высоты списка и там стоит.
    @Test func visibleHeightClipsToNaturalHeight() {
        #expect(SpoilerReveal.visibleHeight(natural: 900, reveal: 0) == 0)
        #expect(SpoilerReveal.visibleHeight(natural: 900, reveal: 400) == 400)
        #expect(SpoilerReveal.visibleHeight(natural: 900, reveal: 1600) == 900)
        #expect(SpoilerReveal.visibleHeight(natural: 0, reveal: 1600) == 0)
    }

    @Test func chevronTurnsClockwiseFromDownToUp() {
        #expect(SpoilerReveal.chevronAngle(expanded: false) == 90)
        #expect(SpoilerReveal.chevronAngle(expanded: true) == 270)
    }

    /// Список не вырастает выше места над кнопкой (дальше прокручивается сам), но и не растягивается до него.
    @Test func visibleHeightStopsAtRoomAboveButton() {
        #expect(SpoilerReveal.visibleHeight(natural: 900, reveal: 1600, limit: 500) == 500)
        #expect(SpoilerReveal.visibleHeight(natural: 300, reveal: 1600, limit: 500) == 300)
        #expect(SpoilerReveal.visibleHeight(natural: 900, reveal: 200, limit: 500) == 200)
        #expect(SpoilerReveal.visibleHeight(natural: 900, reveal: 1600, limit: 0) == 0)
    }

    /// Место для списка — от низа шапки с просветом 8 до верха кнопки; кнопка выше шапки (экран ещё не измерен) — места нет.
    @Test func roomIsBetweenHeaderAndButton() {
        #expect(SpoilerReveal.headerGap == 8)
        #expect(SpoilerReveal.listLimit(buttonTop: 700, headerBottom: 150) == 542)
        #expect(SpoilerReveal.listLimit(buttonTop: 100, headerBottom: 150) == 0)
        #expect(SpoilerReveal.listLimit(buttonTop: 0, headerBottom: 0) == 0)
    }
}
