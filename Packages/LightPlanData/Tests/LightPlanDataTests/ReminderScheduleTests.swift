import Foundation
import Testing
import LightPlanCore
import LightPlanDomain
import UserNotifications
@testable import LightPlanData

/// «Напоминать о съёмке» (шаг «Напоминание-1»): момент — начало по часам места минус N, кому — съёмке и встрече,
/// доля в общих 64 местах, снятие при удалении записи.
@Suite struct ReminderScheduleTests {

    static let day = CivilDate(year: 2026, month: 10, day: 28)
    /// Неделей раньше: до всего далеко.
    static let longAgo = WallTime(day: CivilDate(year: 2026, month: 10, day: 21), minutes: 0).moment(utcOffsetHours: 0)

    static func shoot(_ id: String = "s1", at minute: Int = 720, kind: RecordKind = .shoot, day: CivilDate = day) -> Session {
        var s = Session(id: id, kind: kind, day: day, start: minute)
        s.contact = "Кирилл"
        return s
    }

    static func utc(_ h: Int, _ m: Int, day: CivilDate = day) -> Moment {
        WallTime(day: day, minutes: h * 60 + m).moment(utcOffsetHours: 0)
    }

    static func notice(_ s: Session, minutes: Int = 15, offset: Double, now: Moment = longAgo) -> ReminderSchedule.Notice? {
        ReminderSchedule.notice(for: s, minutes: minutes, offsetHours: offset, now: now)
    }

    // MARK: - Момент по часам места

    @Test func fireIsStartMinusMinutesOnThePlacesClock() {
        // 12:00 в Москве (+3) = 09:00 UTC; за 15 минут — 08:45 UTC.
        #expect(Self.notice(Self.shoot(), offset: 3)?.fire == Self.utc(8, 45))
        #expect(Self.notice(Self.shoot(), minutes: 60, offset: 3)?.fire == Self.utc(8, 0))
        #expect(Self.notice(Self.shoot(), minutes: 5, offset: 3)?.fire == Self.utc(8, 55))
    }

    @Test func sameWallTimeInAnotherZoneIsAnotherInstant() {
        // Те же «12:00» договорённости: Томск +7, Нью-Йорк −4 (летнее), Индия +5:30 — три разных момента.
        #expect(Self.notice(Self.shoot(), offset: 7)?.fire == Self.utc(4, 45))
        #expect(Self.notice(Self.shoot(), offset: -4)?.fire == Self.utc(15, 45))
        #expect(Self.notice(Self.shoot(), offset: 5.5)?.fire == Self.utc(6, 15))
    }

    @Test func earlyMorningReminderFallsOnThePreviousDay() {
        // Съёмка в 00:10 — напоминание за 30 минут, в 23:40 накануне по часам места.
        let n = Self.notice(Self.shoot(at: 10), minutes: 30, offset: 3)
        #expect(n?.fire == WallTime(day: CivilDate(year: 2026, month: 10, day: 27), minutes: 23 * 60 + 40).moment(utcOffsetHours: 3))
    }

    @Test func triggerFieldsLieInThePlacesZone() throws {
        // Тот же момент на полях триггера: 11:45 по Томску с поясом +7, а не по часам телефона. Год далёкий: следующий
        // момент триггера система считает от настоящих часов.
        let n = try #require(Self.notice(Self.shoot(day: CivilDate(year: 2036, month: 10, day: 28)), offset: 7))
        let t = SystemNotificationCenter.trigger(fire: n.fire.date, offsetHours: n.offsetHours)
        #expect(t.dateComponents.hour == 11 && t.dateComponents.minute == 45 && t.dateComponents.day == 28)
        #expect(t.dateComponents.timeZone?.secondsFromGMT() == 7 * 3600)
        let next = try #require(t.nextTriggerDate(), "момент ещё впереди: \(n.fire.date)")
        #expect(Moment(next) == n.fire)
    }

    // MARK: - Кому

    @Test func shootsAndMeetingsOnly() {
        #expect(Self.notice(Self.shoot(kind: .shoot), offset: 3) != nil)
        #expect(Self.notice(Self.shoot(kind: .meet), offset: 3) != nil)
        #expect(Self.notice(Self.shoot(kind: .event), offset: 3) == nil, "чужое событие молчит")
    }

    @Test func calendarDraftAndFinishedShootAreSilent() {
        var draft = Session(id: "d1", day: Self.day, start: 720)
        draft.fromCalendar = "Кирилл"
        #expect(draft.isCalendarDraft)
        #expect(Self.notice(draft, offset: 3) == nil, "у черновика из Календаря напоминание — от самого Календаря")
        var done = Self.shoot()
        done.doneAt = 700
        #expect(Self.notice(done, offset: 3) == nil)
    }

    @Test func startedOrPassedMomentIsNotScheduled() {
        let s = Self.shoot()
        // За минуту до момента напоминания — ещё ставится.
        #expect(Self.notice(s, offset: 3, now: Self.utc(8, 44)) != nil)
        // Момент напоминания прошёл, съёмка ещё не началась — уже не ставится (система сказала бы задним числом).
        #expect(Self.notice(s, offset: 3, now: Self.utc(8, 45)) == nil)
        // Съёмка идёт.
        #expect(Self.notice(s, offset: 3, now: Self.utc(9, 30)) == nil)
    }

    @Test func offMeansNothing() {
        #expect(Self.notice(Self.shoot(), minutes: 0, offset: 3) == nil)
        #expect(ReminderSchedule.plan(sessions: [Self.shoot()], minutes: 0, now: Self.longAgo, offsetHours: { _ in 3 }).isEmpty)
    }

    @Test func planKeepsTheNearestSixteenInOrder() {
        let sessions = (0..<30).reversed().map { Self.shoot("s\($0)", day: Self.day.adding(days: $0)) }
        let plan = ReminderSchedule.plan(sessions: sessions, minutes: 15, now: Self.longAgo, offsetHours: { _ in 3 })
        #expect(plan.count == 16 && ReminderSchedule.cap == 16)
        #expect(plan.first?.id == "lp.remind.s0" && plan.last?.id == "lp.remind.s15")
        #expect(zip(plan, plan.dropFirst()).allSatisfy { $0.fire < $1.fire })
    }

    @Test func choicesAndDefaultAreTheDecisionsNumbers() {
        #expect(ReminderSchedule.choices == [0, 5, 10, 15, 30, 60] && ReminderSchedule.defaultMinutes == 15)
    }

    // MARK: - Общие 64 места

    static func reminders(_ n: Int) -> [ScheduledAlert] {
        let sessions = (0..<n).map { Self.shoot("r\($0)", day: SharedCeilingTests.start.adding(days: $0)) }
        return ReminderSchedule.plan(sessions: sessions, minutes: 15, now: Self.longAgo, offsetHours: { _ in 3 }, limit: n)
            .map { alert($0) }
    }

    static func alert(_ n: ReminderSchedule.Notice, title: String = "Кирилл · 12:00") -> ScheduledAlert {
        var a = ScheduledAlert(id: n.id, sessionId: n.sessionId, fire: n.fire, offsetHours: n.offsetHours,
                               title: title, body: "Портрет · Томсон")
        a.urgent = true
        return a
    }

    @Test func allThreeFullSplitSixteenFortyEight() async {
        let center = FakeCenter()
        let r = await NotificationScheduler(center: center).sync(
            Self.reminders(30) + SharedCeilingTests.greets(100) + SharedCeilingTests.studio(50))
        let t = await center.table
        #expect(SharedCeilingTests.count(t, "lp.remind.") == 16)
        #expect(SharedCeilingTests.count(t, "lp.greet.") == 40)
        #expect(SharedCeilingTests.count(t, "lp.studio.") == 8)
        #expect(t.count == 64 && r.dropped.count == 14 + 60 + 92)
        // Ближайшие напоминания: 16 первых дней, семнадцатого нет.
        #expect(t["lp.remind.r15"] != nil && t["lp.remind.r16"] == nil)
    }

    @Test func foreignRequestsSqueezeGreetingsNotReminders() async {
        let center = FakeCenter()
        await center.setForeign(10)
        await NotificationScheduler(center: center).sync(
            Self.reminders(30) + SharedCeilingTests.greets(100) + SharedCeilingTests.studio(50))
        let t = await center.table
        #expect(SharedCeilingTests.count(t, "lp.remind.") == 16)
        #expect(SharedCeilingTests.count(t, "lp.greet.") == 38 && SharedCeilingTests.count(t, "lp.studio.") == 0)
        #expect(await center.pending().count == 64)
    }

    @Test func fewRemindersLeaveTheirPlacesToTheStudio() async {
        let center = FakeCenter()
        await NotificationScheduler(center: center).sync(
            Self.reminders(3) + SharedCeilingTests.greets(100) + SharedCeilingTests.studio(50))
        let t = await center.table
        #expect(SharedCeilingTests.count(t, "lp.remind.") == 3 && SharedCeilingTests.count(t, "lp.studio.") == 21)
    }

    // MARK: - Правка и удаление

    @Test func deletingTheShootCancelsItsReminderOnly() async {
        let center = FakeCenter()
        let sched = NotificationScheduler(center: center)
        let both = Self.reminders(2)
        await sched.sync(both)
        #expect(await center.table.keys.sorted() == ["lp.remind.r0", "lp.remind.r1"])
        // r0 удалили: в плане его больше нет.
        let r = await sched.sync(Array(both.dropFirst()))
        #expect(r.removed == ["lp.remind.r0"] && r.kept == ["lp.remind.r1"] && r.added.isEmpty)
        #expect(await center.table.keys.sorted() == ["lp.remind.r1"])
    }

    @Test func movingTheShootReplacesTheSameRequest() async {
        let center = FakeCenter()
        let sched = NotificationScheduler(center: center)
        let s = Self.shoot("m1")
        let before = try! #require(Self.notice(s, offset: 3))
        await sched.sync([Self.alert(before)])
        // Перенесли на 14:00: тот же идентификатор, новый момент — запрос заменён, не размножен.
        let after = try! #require(Self.notice(Self.shoot("m1", at: 840), offset: 3))
        let r = await sched.sync([Self.alert(after, title: "Кирилл · 14:00")])
        #expect(r.added == ["lp.remind.m1"] && r.removed.isEmpty)
        let t = await center.table
        #expect(t.count == 1 && t["lp.remind.m1"]?.fire == Self.utc(10, 45))
    }

    @Test func turningRemindersOffClearsTheLane() async {
        let center = FakeCenter()
        let sched = NotificationScheduler(center: center)
        await sched.sync(Self.reminders(3) + SharedCeilingTests.greets(2))
        let r = await sched.sync(SharedCeilingTests.greets(2))
        let t = await center.table
        #expect(r.removed.count == 3 && SharedCeilingTests.count(t, "lp.remind.") == 0)
    }

    // MARK: - Нажатие и уровень

    @Test func tapOpensTheShootsCard() {
        #expect(NotificationPresenter.tap(id: "lp.remind.s1", info: ["session": "s1"]) == .card("s1"))
        #expect(NotificationPresenter.tap(id: "lp.remind.s1", info: [:]) == nil)
    }

    @Test func urgencyIsPartOfTheSignature() {
        let n = Self.notice(Self.shoot(), offset: 3)!
        var plain = Self.alert(n)
        plain.urgent = false
        #expect(plain.signature != Self.alert(n).signature, "сменился уровень — запрос переписывается")
    }
}
