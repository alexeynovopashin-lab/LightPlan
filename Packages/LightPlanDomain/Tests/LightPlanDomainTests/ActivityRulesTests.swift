import Testing
import Foundation
@testable import LightPlanDomain
import LightPlanCore

/// Шаг 30б.3: когда экран активности есть и что с ним делать — начало, конец, «Завершить», длинный день («Продлевать»).
struct ActivityRulesTests {

    private let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    private func tsk(_ h: Int, _ min: Int = 0, day: Int = 24) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: min))!.addingTimeInterval(-7 * 3600)
    }
    private func ms(_ d: Date) -> Int64 { Moment(d).milliseconds }
    private func shoot(_ a: Date, _ b: Date, id: String = "s1", open: Bool = false) -> WidgetFeed.Shoot {
        WidgetFeed.Shoot(id: id, start: ms(a), end: ms(b), open: open, title: "Свадьба")
    }
    private func feed(_ s: [WidgetFeed.Shoot]) -> WidgetFeed { WidgetFeed(place: tomsk, shoots: s) }

    // MARK: Что идёт

    @Test func aShootIsWantedFromItsStartToItsEnd() {
        let f = feed([shoot(tsk(12), tsk(22))])
        #expect(ActivityRules.wanted(in: f, at: tsk(11, 59)) == nil)
        #expect(ActivityRules.wanted(in: f, at: tsk(12))?.id == "s1")
        #expect(ActivityRules.wanted(in: f, at: tsk(21, 59))?.id == "s1")
        #expect(ActivityRules.wanted(in: f, at: tsk(22)) == nil)
    }

    @Test func finishingByHandEndsIt() {
        // «Завершить»: конец съёмки становится минутой нажатия (так его пишет лента виджета), и она больше не идёт.
        let f = feed([shoot(tsk(12), tsk(15, 10))])
        #expect(ActivityRules.wanted(in: f, at: tsk(15, 11)) == nil)
        let open = feed([shoot(tsk(12), tsk(22), open: true)])
        #expect(ActivityRules.wanted(in: open, at: tsk(23))?.id == "s1", "незакрытая вручную идёт, пока не нажмут")
    }

    @Test func aShootThePersonSwipedAwayIsNotStartedAgain() {
        let f = feed([shoot(tsk(12), tsk(22))])
        #expect(ActivityRules.wanted(in: f, at: tsk(15), dismissed: ["s1"]) == nil)
        #expect(ActivityRules.wanted(in: f, at: tsk(15), dismissed: ["other"])?.id == "s1")
    }

    // MARK: Длинный день

    @Test func aDayLongerThanEightHoursIsLong() {
        #expect(ActivityRules.isLongDay(shoot(tsk(12), tsk(22)), at: tsk(15)))
        #expect(!ActivityRules.isLongDay(shoot(tsk(12), tsk(20)), at: tsk(15)), "ровно 8 часов система ещё держит")
        #expect(!ActivityRules.isLongDay(shoot(tsk(12), tsk(19)), at: tsk(15)))
        #expect(ActivityRules.isLongDay(shoot(tsk(12), tsk(20, 1)), at: tsk(15)))
        #expect(ActivityRules.isLongDay(shoot(tsk(12), tsk(15), open: true), at: tsk(21)), "незакрытая растёт вместе с часами")
        #expect(!ActivityRules.isLongDay(shoot(tsk(12), tsk(15), open: true), at: tsk(15)))
    }

    // MARK: Решение

    private func run(_ id: String = "s1", since: Date) -> ActivityRules.Run { .init(shootId: id, startedAt: since) }

    @Test func nothingRunningAndNothingShownDoesNothing() {
        #expect(ActivityRules.decide(run: nil, wanted: nil, reason: .change, now: tsk(10)) == .none)
    }

    @Test func aShootStartsTheActivityAndItsEndTakesItAway() {
        let s = shoot(tsk(12), tsk(22))
        #expect(ActivityRules.decide(run: nil, wanted: s, reason: .foreground, now: tsk(12, 5)) == .start)
        #expect(ActivityRules.decide(run: run(since: tsk(12, 5)), wanted: nil, reason: .change, now: tsk(22, 5)) == .end)
    }

    @Test func aChangeOfDataJustUpdates() {
        let s = shoot(tsk(12), tsk(22))
        #expect(ActivityRules.decide(run: run(since: tsk(12, 5)), wanted: s, reason: .change, now: tsk(15)) == .update)
    }

    @Test func aLongDayIsRestartedOnEveryReturnToTheApp() {
        let long = shoot(tsk(12), tsk(22))
        #expect(ActivityRules.decide(run: run(since: tsk(12, 5)), wanted: long, reason: .foreground, now: tsk(15)) == .restart)
        // Двойное «вернулись» в течение минуты плашкой не мигает.
        #expect(ActivityRules.decide(run: run(since: tsk(15)), wanted: long, reason: .foreground, now: tsk(15, 0).addingTimeInterval(30)) == .update)
        #expect(ActivityRules.decide(run: run(since: tsk(15)), wanted: long, reason: .foreground, now: tsk(15, 1)) == .restart)
    }

    @Test func aShortDayIsNeverRestarted() {
        let short = shoot(tsk(12), tsk(18))
        #expect(ActivityRules.decide(run: run(since: tsk(12, 5)), wanted: short, reason: .foreground, now: tsk(15)) == .update)
    }

    @Test func anotherShootReplacesTheActivity() {
        let next = shoot(tsk(13), tsk(16), id: "s2")
        #expect(ActivityRules.decide(run: run("s1", since: tsk(12)), wanted: next, reason: .change, now: tsk(13, 5)) == .restart)
    }
}
