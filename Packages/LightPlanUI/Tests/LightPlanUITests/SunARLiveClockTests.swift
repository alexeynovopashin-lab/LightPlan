import Foundation
import Testing
import LightPlanCore
@testable import LightPlanUI

/// 31.9 (AR): минута AR идёт за временем, пока её не тронули; сдвинули — стоит до «↺»; фон дольше 15 минут — снова «сейчас».
@MainActor
struct SunARLiveClockTests {
    private final class MemoryFlag: ARCalibrationFlag { var seen = true }
    private final class MemoryBodies: ARBodiesSettings {
        var moon = false, milkyWay = false, stars = false, constellations = false, planets = false
    }
    /// Подставные часы: тест сам двигает «сейчас».
    private final class Clock {
        var moment: Moment
        init(_ m: Moment) { moment = m }
        func advance(_ seconds: Double) { moment = Moment(moment.date.addingTimeInterval(seconds)) }
    }

    private let tomsk = Place(latitude: 56.4846, longitude: 84.9476, zone: ZoneID(fixedOffsetHours: 7))
    private let barnaul = Place(latitude: 53.3561, longitude: 83.7636, zone: ZoneID(fixedOffsetHours: 7))
    private func moment(_ iso: String) -> Moment { Moment(ISO8601DateFormatter().date(from: iso)!) }

    /// Экран, открытый в момент `opened`, при часах `clock`.
    private func model(opened: Moment, clock: Clock, place: Place? = nil) -> SunARModel {
        SunARModel(target: SunARTarget(place: place ?? tomsk, moment: opened), source: nil, camera: nil,
                   clock: { clock.moment }, calibrationFlag: MemoryFlag(), bodies: MemoryBodies())
    }

    /// Минута места «сейчас», целая — так её ставит ход.
    private func wallMinute(_ m: SunARModel, _ clock: Clock) -> (CivilDate, Double) {
        let w = SunTrack.wallClock(of: clock.moment, in: m.place)
        return (w.day, w.minutes.rounded(.down))
    }

    @Test func openedAtNowFollowsTheMinute() {
        let clock = Clock(moment("2026-11-19T03:51:30Z"))          // 10:51:30 в Томске
        let m = model(opened: clock.moment, clock: clock)
        #expect(m.isLive)
        clock.advance(31)                                           // 10:52:01
        m.tick()
        #expect(m.minutes == 10 * 60 + 52)
        #expect(m.pickedIsNow)
        clock.advance(10 * 60)
        m.tick()
        let (day, minute) = wallMinute(m, clock)
        #expect(m.day == day && m.minutes == minute)
        #expect(m.pickedIsNow)
        #expect(!m.timebar.nowButtonVisible)
    }

    @Test func openedOnAnotherMomentStays() {
        let clock = Clock(moment("2026-11-19T06:00:00Z"))
        let m = model(opened: moment("2026-11-19T03:00:00Z"), clock: clock)
        #expect(!m.isLive)
        let before = m.minutes
        clock.advance(120)
        m.tick()
        #expect(m.minutes == before)
    }

    @Test func movedMinuteStaysUntilReset() {
        let clock = Clock(moment("2026-11-19T03:51:30Z"))
        let m = model(opened: clock.moment, clock: clock)
        m.set(minutes: 15 * 60)
        #expect(!m.isLive)
        clock.advance(5 * 60)
        m.tick()
        #expect(m.minutes == 15 * 60)
        #expect(m.timebar.nowButtonVisible)
        m.jumpToNow()
        #expect(m.isLive && m.pickedIsNow)
        clock.advance(60)
        m.tick()
        #expect(m.minutes == wallMinute(m, clock).1)
    }

    @Test func longBackgroundReturnsToNow() {
        let clock = Clock(moment("2026-11-19T03:51:30Z"))
        let m = model(opened: clock.moment, clock: clock)
        m.set(minutes: 15 * 60)
        m.sceneWentToBackground()
        clock.advance(TimebarState.staleAfterBackground + 60)
        m.sceneBecameActive()
        #expect(m.isLive)
        #expect(m.pickedIsNow)
        #expect(m.minutes == wallMinute(m, clock).1)
    }

    @Test func shortBackgroundKeepsTheMovedMinute() {
        let clock = Clock(moment("2026-11-19T03:51:30Z"))
        let m = model(opened: clock.moment, clock: clock)
        m.set(minutes: 15 * 60)
        m.sceneWentToBackground()
        clock.advance(TimebarState.staleAfterBackground - 60)
        m.sceneBecameActive()
        #expect(!m.isLive)
        #expect(m.minutes == 15 * 60)
    }

    /// Плашка перед входом задержала момент: не старше 15 минут — всё ещё «сейчас».
    @Test func openingMomentCountsAsNowFor15Minutes() {
        let now = moment("2026-11-19T06:00:00Z")
        func ago(_ s: Double) -> Moment { Moment(now.date.addingTimeInterval(-s)) }
        #expect(SunARModel.opensLive(now, now: now))
        #expect(SunARModel.opensLive(ago(TimebarState.staleAfterBackground), now: now))
        #expect(!SunARModel.opensLive(ago(TimebarState.staleAfterBackground + 1), now: now))
        #expect(!SunARModel.opensLive(ago(-120), now: now))
    }

    /// Живая минута переходит закат сама — щелчка порога нет; сдвинутая пальцем — есть.
    @Test func liveCrossingOfSunsetIsSilent() throws {
        let probe = model(opened: moment("2026-11-19T03:00:00Z"), clock: Clock(moment("2026-11-19T03:00:00Z")))
        let set = try #require(probe.solar.set)
        let clock = Clock(SunTrack.moment(day: probe.day, minutes: set - 1.5, in: tomsk))
        let m = model(opened: clock.moment, clock: clock)
        var clicks = 0
        m.thresholdHaptic = { clicks += 1 }
        m.minuteMoved()
        let before = m.sun.altitude
        clock.advance(3 * 60)
        m.tick()
        #expect(SunTrack.thresholdsCrossed(from: before, to: m.sun.altitude) > 0, "минута не перешла закат")
        m.minuteMoved()
        #expect(clicks == 0)
    }

    /// Телефон ответил позже входа: живая минута встаёт на «сейчас» нового места и идёт дальше.
    @Test func lateFixKeepsLiveTime() {
        let clock = Clock(moment("2026-11-19T03:51:30Z"))
        let m = model(opened: clock.moment, clock: clock)
        let moscow = Place(latitude: 55.7558, longitude: 37.6173, zone: ZoneID(fixedOffsetHours: 3))
        m.apply(choice: .phone(moscow, chosenFarKm: 3500))
        #expect(m.isLive)
        #expect(m.minutes == 6 * 60 + 51)                           // 06:51 в Москве
        #expect(m.pickedIsNow)
    }
}
