import Foundation
import Testing
import LightPlanCore
import LightPlanTimeline
@testable import LightPlanUI

/// 30з.6: тап по времени заката у правого основания дуги ставит ползунок на закат смотримого дня.
@MainActor
struct TimebarJumpToSunsetTests {
    private func state(lat: Double = 55.75, lon: Double = 37.62, date: CivilDate = CivilDate(year: 2026, month: 10, day: 13)) -> TimebarState {
        TimebarState(place: Place(latitude: lat, longitude: lon, zone: ZoneID(fixedOffsetHours: 3)), date: date, ribbonMode: .drum)
    }

    @Test func sliderLandsOnTheSunset() {
        let s = state()
        s.dragDome(to: s.solarDay.solarNoon)
        s.jumpToSunset()
        #expect(s.solarDay.set != nil)
        #expect(abs(s.machine.viewMinute - (s.solarDay.set ?? -1)) < 0.01)
    }

    @Test func repeatedTapStaysOnTheSunset() {
        let s = state()
        s.jumpToSunset(); let first = s.machine.viewMinute
        s.jumpToSunset()
        #expect(s.machine.viewMinute == first)
    }

    /// Полярный день: заката нет — тап ничего не двигает.
    @Test func polarDayHasNoSunsetToJumpTo() {
        let s = state(lat: 78.2, lon: 15.6, date: CivilDate(year: 2026, month: 6, day: 21))
        s.dragDome(to: s.solarDay.solarNoon)
        let before = s.machine.viewMinute
        s.jumpToSunset()
        #expect(s.machine.viewMinute == before)
    }
}
