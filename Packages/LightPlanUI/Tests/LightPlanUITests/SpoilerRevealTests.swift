import Testing
import CoreGraphics
@testable import LightPlanUI

/// «Подробно» (29.2г): список раскрывается под кнопкой по числам беты, а не выезжает от верха окна.
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
}
