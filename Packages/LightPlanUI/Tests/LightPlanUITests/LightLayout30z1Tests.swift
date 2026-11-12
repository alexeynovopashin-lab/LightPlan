import Foundation
import Testing
import LightPlanCore
import LightPlanTimeline
@testable import LightPlanUI

/// 30з.1: цифры шкалы ползунка и левое основание дуги после заката.
@MainActor
struct LightLayout30z1Tests {
    private func state() -> TimebarState {
        let zone = ZoneID(fixedOffsetHours: 7)   // Томск
        return TimebarState(place: Place(latitude: 56.49, longitude: 84.95, zone: zone),
                            date: CivilDate(year: 2026, month: 11, day: 12), ribbonMode: .drum)
    }

    /// Окно ±12 ч от истинного полудня: левого «0» нет, цифра = час по модулю 24, полночь — «0» там, где час 24.
    @Test func digitsAreTheHourOfTheTickModulo24() {
        let day = SolarDay(date: CivilDate(year: 2026, month: 11, day: 12), place: Place(latitude: 56.49, longitude: 84.95, zone: ZoneID(fixedOffsetHours: 7)))
        let hours = RulerDigits.hours(mint: day.mint, maxt: day.maxt)
        #expect(hours.first.map { $0 * 60 >= Int(day.mint.rounded(.up)) } == true)
        #expect(hours == hours.sorted() && hours.allSatisfy { $0 % 3 == 0 })
        let labels = hours.map(RulerDigits.label)
        #expect(labels == ["3", "6", "9", "12", "15", "18", "21", "0"], "\(labels) mint=\(day.mint) maxt=\(day.maxt)")
    }

    /// До заката основание слева — сегодняшний рассвет; после — настоящий завтрашний, не «сегодняшний + 24 ч».
    @Test func leftBaseTakesTomorrowsSunriseAfterSunset() {
        let s = state()
        let place = Place(latitude: 56.49, longitude: 84.95, zone: ZoneID(fixedOffsetHours: 7))
        let today = SolarDay(date: CivilDate(year: 2026, month: 11, day: 12), place: place)
        let tomorrow = SolarDay(date: CivilDate(year: 2026, month: 11, day: 13), place: place)
        s.show(day: CivilDate(year: 2026, month: 11, day: 12), minute: 12 * 60)
        if case .time(_, let m) = s.baseRiseEdge { #expect(m == today.rise) } else { Issue.record("no time at noon") }
        s.show(day: CivilDate(year: 2026, month: 11, day: 12), minute: (today.set ?? 0) + 30)
        if case .time(_, let m) = s.baseRiseEdge { #expect(m == tomorrow.rise) } else { Issue.record("no time after sunset") }
        // Отсчёт беты ночью: сегодняшний рассвет + 1440 − t; настоящий завтрашний от него отстаёт на суточный сдвиг рассвета.
        let shift = (tomorrow.rise ?? 0) - (today.rise ?? 0)
        #expect(shift > 0 && shift < 5, "shift \(shift) min")
    }
}
