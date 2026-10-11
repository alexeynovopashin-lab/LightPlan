import Testing
import SwiftUI
@testable import LightPlanUI

/// 29.2е: «Уменьшение движения» гасит и листание дня (раньше — только месяц и неделю).
@MainActor
struct FlipMotionTests {
    @Test func dayDoesNotSlideWhenMotionIsReduced() {
        #expect(PlannerDayBody.flipMotion(day: true, still: true) == nil)
    }

    @Test func monthAndWeekDoNotSlideWhenMotionIsReduced() {
        #expect(PlannerDayBody.flipMotion(day: false, still: true) == nil)
    }

    @Test func dayStillSlidesWhenMotionIsNotReduced() {
        #expect(PlannerDayBody.flipMotion(day: true, still: false) == PlannerDayBody.slide)
    }
}
