import Foundation
import Testing
import LightPlanCore
import LightPlanTimeline
@testable import LightPlanUI

/// 31.9: часы дуги идут за временем, пока его не двигали; двинутое стоит до «↺»; после фона дольше 15 минут — снова «сейчас».
@MainActor
struct TimebarLiveClockTests {
    /// Подставные часы: тест сам двигает «сейчас».
    final class Clock: @unchecked Sendable {
        var date: Date
        init(_ date: Date) { self.date = date }
        func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
    }

    private static let zone = ZoneID(fixedOffsetHours: 3)
    private static let day = CivilDate(year: 2026, month: 11, day: 19)

    /// Момент по часам Москвы (+3): `day` `h:m:s`.
    private static func moment(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        let ms = WallTime(day: day, minutes: h * 60 + m).moment(utcOffsetHours: 3).milliseconds
        return Date(timeIntervalSince1970: Double(ms) / 1000 + Double(s))
    }

    private func state(_ clock: Clock, date: CivilDate = day) -> TimebarState {
        let s = TimebarState(place: Place(latitude: 55.75, longitude: 37.62, zone: Self.zone), date: date,
                             ribbonMode: .drum, now: { clock.date })
        s.jumpToNow()
        return s
    }

    @Test func liveFollowsTheMinute() {
        let clock = Clock(Self.moment(9, 51, 30))
        let s = state(clock)
        #expect(s.isLive)
        #expect(s.machine.viewMinute == 9 * 60 + 51)
        clock.advance(30)                               // 09:52:00 — граница минуты
        #expect(s.followNow())
        #expect(s.machine.viewMinute == 9 * 60 + 52)
        #expect(!s.nowButtonVisible)
        clock.advance(20)                               // та же минута — ничего не меняется
        #expect(!s.followNow())
        #expect(s.machine.viewMinute == 9 * 60 + 52)
    }

    /// Ход пропустили (вкладка была скрыта): живое время «↺» не зажигает, первый же ход догоняет часы.
    @Test func liveNeverLightsTheResetButton() {
        let clock = Clock(Self.moment(9, 51))
        let s = state(clock)
        clock.advance(10 * 60)
        #expect(!s.nowButtonVisible)
        s.followNow()
        #expect(s.machine.viewMinute == 10 * 60 + 1)
    }

    /// Любое движение времени человеком — время стоит, «↺» загорается за две минуты от «сейчас».
    @Test(arguments: ["dome", "show", "sunset", "sunrise", "ribbon", "slider"])
    func movedTimeStays(_ how: String) {
        let clock = Clock(Self.moment(12, 0))
        let s = state(clock)
        switch how {
        case "dome": s.dragDome(to: 15 * 60)
        case "show": s.show(day: Self.day, minute: 15 * 60)
        case "sunset": s.jumpToSunset()
        case "sunrise": s.jumpToSunrise()
        case "ribbon": s.dragRibbon(translation: -120, clipWidth: 393); s.releaseRibbon()
        default: s.dragSlider(x: 300, width: 393, thumb: 28); s.releaseSlider()
        }
        #expect(!s.isLive)
        let day = s.machine.selectedDate, minute = s.machine.viewMinute
        clock.advance(5 * 60)
        #expect(!s.followNow())
        #expect(s.machine.selectedDate == day)
        #expect(s.machine.viewMinute == minute)
        #expect(s.nowButtonVisible)
    }

    /// Касание ленты без сдвига (начало тапа) время не двигает.
    @Test func ribbonTouchWithoutMoveKeepsLive() {
        let clock = Clock(Self.moment(12, 0))
        let s = state(clock)
        s.dragRibbon(translation: 0, clipWidth: 393)
        s.releaseRibbon()
        #expect(s.isLive)
    }

    @Test func resetMakesTimeLiveAgain() {
        let clock = Clock(Self.moment(12, 0))
        let s = state(clock)
        s.dragDome(to: 15 * 60)
        clock.advance(3 * 60)
        s.jumpToNow()
        #expect(s.isLive)
        #expect(s.machine.viewMinute == 12 * 60 + 3)
        clock.advance(60)
        s.followNow()
        #expect(s.machine.viewMinute == 12 * 60 + 4)
    }

    @Test func longBackgroundReturnsToNowEvenIfMoved() {
        let clock = Clock(Self.moment(12, 0))
        let s = state(clock)
        s.dragDome(to: 15 * 60)
        s.sceneWentToBackground()
        clock.advance(TimebarState.staleAfterBackground + 60)
        s.sceneBecameActive()
        #expect(s.isLive)
        #expect(s.machine.viewMinute == 12 * 60 + 16)
    }

    @Test func shortBackgroundKeepsTheMovedTime() {
        let clock = Clock(Self.moment(12, 0))
        let s = state(clock)
        s.dragDome(to: 15 * 60)
        s.sceneWentToBackground()
        clock.advance(TimebarState.staleAfterBackground - 60)
        s.sceneBecameActive()
        #expect(!s.isLive)
        #expect(s.machine.viewMinute == 15 * 60)
    }

    /// Живое время после короткого фона сразу догоняет часы.
    @Test func shortBackgroundCatchesUpLiveTime() {
        let clock = Clock(Self.moment(12, 0))
        let s = state(clock)
        s.sceneWentToBackground()
        clock.advance(10 * 60)
        s.sceneBecameActive()
        #expect(s.isLive)
        #expect(s.machine.viewMinute == 12 * 60 + 10)
    }

    /// Возврат без ухода в фон (только «неактивно»: центр уведомлений) двинутое время не сбрасывает.
    @Test func activeWithoutBackgroundKeepsMovedTime() {
        let clock = Clock(Self.moment(12, 0))
        let s = state(clock)
        s.dragDome(to: 15 * 60)
        clock.advance(TimebarState.staleAfterBackground * 2)
        s.sceneBecameActive()
        #expect(!s.isLive)
        #expect(s.machine.viewMinute == 15 * 60)
    }

    @Test func liveFlipsTheDayAtMidnight() {
        let clock = Clock(Self.moment(23, 59, 30))
        let s = state(clock)
        #expect(s.machine.viewMinute == 23 * 60 + 59)
        clock.advance(31)                               // 00:00:01 следующего дня
        #expect(s.followNow())
        let next = Self.day.adding(days: 1)
        #expect(s.machine.selectedDate == next)
        #expect(s.machine.viewMinute == 0)
        #expect(s.todayInPlace == next)
        #expect(abs((s.nowMinute ?? -1) - 1.0 / 60) < 1e-6)   // 00:00:01 на шкале нового дня
        #expect(abs(s.solarDay.solarNoon - SolarDay(date: next, place: s.place).solarNoon) < 1e-9)
    }

    /// Двинутое время в полночь остаётся на своём дне.
    @Test func movedTimeKeepsItsDayAtMidnight() {
        let clock = Clock(Self.moment(23, 50))
        let s = state(clock)
        s.dragDome(to: 22 * 60)
        clock.advance(20 * 60)
        s.followNow()
        #expect(s.machine.selectedDate == Self.day)
        #expect(s.machine.viewMinute == 22 * 60)
    }

    @Test func tickWakesOnTheMinuteBoundary() {
        let d = Self.moment(9, 51, 30)
        #expect(abs(TimebarState.secondsToNextMinute(after: d) - 30.05) < 1e-6)
        #expect(abs(TimebarState.secondsToNextMinute(after: Self.moment(9, 52)) - 60.05) < 1e-6)
    }
}
