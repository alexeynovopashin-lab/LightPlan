import Foundation
import Testing
import LightPlanCore
import LightPlanDomain
import UserNotifications
@testable import LightPlanData

/// Студийный час зовёт дважды (шаг 30а): числа расписания и его переписывание.
/// Сроки сверены с формулой беты `rw.to − (60 − hourMin)`, ступени — 10 и 5
/// минут до дедлайна (`STUDIO_SAY`).
@Suite struct StudioScheduleTests {

    // MARK: - Подставки

    static let day = CivilDate(year: 2026, month: 10, day: 20)
    static let studio: Studio = {
        var s = Studio(id: "st1", name: "Томсон", latitude: 56.5, longitude: 85)
        s.halls = [Studio.Hall(id: "h1", name: "Эдисон"), Studio.Hall(id: "h2", name: "Тесла")]
        return s
    }()

    /// Запись с ячейками дня: `(начало, конец)` в минутах от полуночи первого дня.
    static func session(_ id: String = "s1", cells: [(Int, Int)], hall: String? = "h1",
                        kind: RecordKind = .shoot, day: CivilDate = day) -> Session {
        var s = Session(id: id, kind: kind, day: day, start: cells.first?.0 ?? 600)
        s.route = cells.map { RoutePoint(start: $0.0, end: $0.1, name: "Студия", studioId: "st1", hallId: hall) }
        return s
    }

    /// Момент настенного времени дня съёмки при смещении +3 (Москва).
    static func at(_ minutes: Int, offset: Double = 3, day: CivilDate = day) -> Moment {
        WallTime(day: day, minutes: minutes).moment(utcOffsetHours: offset)
    }

    /// Далеко до всего: сегодня за неделю до съёмки.
    static let longAgo = at(0, day: CivilDate(year: 2026, month: 10, day: 13))

    static func notices(_ s: Session, offset: Double = 3, now: Moment = longAgo, studios: [Studio] = [studio],
                        finished: Bool = false) -> [StudioSchedule.Notice] {
        StudioSchedule.notices(for: s, studios: studios, offsetHours: offset, now: now, finished: finished)
    }

    // MARK: - Числа: час 55 минут

    @Test func oneHourCallsAtConcludingMinus15AndMinus10() {
        // 12:00–13:00: дедлайн 12:55, сигналы 12:45 и 12:50.
        let n = Self.notices(Self.session(cells: [(720, 780)]))
        #expect(n.map(\.stage) == [1, 2])
        #expect(n.map(\.fire) == [Self.at(765), Self.at(770)])
        #expect(n.map(\.deadline) == [775, 775])
        #expect(n.map(\.minutesLeft) == [10, 5])
        // Относительно конца: −15 и −10.
        #expect(n.map { 780 - Self.minute(of: $0.fire) } == [15, 10])
    }

    @Test func twoHourCallsAtOneHourFortyFiveFromStart() {
        // 12:00–14:00: первый сигнал через 1 ч 45 мин от начала, второй — через 1 ч 50 мин.
        let n = Self.notices(Self.session(cells: [(720, 840)]))
        #expect(n.map { Self.minute(of: $0.fire) - 720 } == [105, 110])
    }

    @Test func threeHoursCallsAtTwoHoursFortyFive() {
        let n = Self.notices(Self.session(cells: [(720, 900)]))
        #expect(n.map { Self.minute(of: $0.fire) - 720 } == [165, 170])
    }

    @Test func studiosOwnHourLengthMovesTheDeadline() {
        var st = Self.studio
        st.hourMinutes = 50
        let n = Self.notices(Self.session(cells: [(720, 780)]), studios: [st])
        // 780 − (60 − 50) = 770 → сигналы 760 и 765.
        #expect(n.map(\.fire) == [Self.at(760), Self.at(765)])
    }

    @Test func rentThroughMidnightCountsFromTheFirstDaysMidnight() {
        // 23:00–01:00: дедлайн 24:55 первых суток = 00:55, сигналы 00:45 и 00:50 следующего дня.
        let n = Self.notices(Self.session(cells: [(1380, 1500)]))
        #expect(n.map(\.fire) == [Self.at(1485), Self.at(1490)])
        let nextDay = CivilDate(year: 2026, month: 10, day: 21)
        #expect(n.map(\.fire) == [Self.at(45, day: nextDay), Self.at(50, day: nextDay)])
    }

    // MARK: - Пояс

    @Test func zoneOfThePlaceSetsTheInstantNotTheZoneOfThePhone() {
        // Одна и та же настенная минута: Томск (+7) наступает на четыре часа раньше Москвы (+3).
        let s = Self.session(cells: [(720, 780)])
        let msk = Self.notices(s, offset: 3), tomsk = Self.notices(s, offset: 7)
        #expect(msk.map(\.fire.milliseconds) .elementsEqual(tomsk.map { $0.fire.milliseconds + 4 * 3_600_000 }))
    }

    @Test func planDoesNotDependOnDeviceZone() {
        let s = Self.session(cells: [(720, 780)])
        let before = Self.notices(s)
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        for id in ["Pacific/Auckland", "America/Los_Angeles", "Asia/Kolkata"] {
            NSTimeZone.default = TimeZone(identifier: id)!
            #expect(Self.notices(s) == before, "пояс телефона \(id)")
        }
    }

    /// День через трое суток от настоящих часов: `nextTriggerDate()` считает от них,
    /// поэтому зашитая дата рано или поздно оказывается в прошлом и тест краснеет.
    static var soonDay: CivilDate {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let c = utc.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(3 * 86_400))
        return CivilDate(year: c.year!, month: c.month!, day: c.day!)
    }

    @Test func triggerStaysAbsoluteWhenThePhoneChangesZone() throws {
        // Момент 12:50 по Москве. Триггер строится с поясом места — и срабатывает в тот же
        // абсолютный момент, в каком бы поясе ни был телефон. Без пояса в полях (контроль)
        // он поплыл бы вместе с часами телефона: так проверка видит порчу.
        let fire = Self.at(770, offset: 3, day: Self.soonDay)
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        for id in ["Europe/Moscow", "Asia/Tokyo", "America/New_York"] {
            NSTimeZone.default = TimeZone(identifier: id)!
            let trigger = SystemNotificationCenter.trigger(fire: fire.date, offsetHours: 3)
            #expect(trigger.nextTriggerDate() == fire.date, "пояс телефона \(id)")
        }
        NSTimeZone.default = TimeZone(identifier: "Asia/Tokyo")!
        var floating = Calendar(identifier: .gregorian)
        floating.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
        let c = floating.dateComponents([.year, .month, .day, .hour, .minute], from: fire.date)
        let naive = UNCalendarNotificationTrigger(dateMatching: c, repeats: false)
        #expect(naive.nextTriggerDate() != fire.date, "контроль: без пояса в полях сигнал плывёт")
    }

    @Test func halfHourZoneKeepsTheMinute() throws {
        let fire = Self.at(770, offset: 5.5, day: Self.soonDay)
        let trigger = SystemNotificationCenter.trigger(fire: fire.date, offsetHours: 5.5)
        #expect(trigger.nextTriggerDate() == fire.date)
        #expect(trigger.dateComponents.hour == 12 && trigger.dateComponents.minute == 50)
    }

    // MARK: - Прошедшие, завершённые, не работа

    @Test func pastStagesAreNotScheduled() {
        let s = Self.session(cells: [(720, 780)])
        // 12:47 — первая ступень (12:45) прошла, вторая (12:50) впереди.
        #expect(Self.notices(s, now: Self.at(767)).map(\.stage) == [2])
        // 12:51 — обе прошли.
        #expect(Self.notices(s, now: Self.at(771)).isEmpty)
        // Ровно в момент ступени — уже не будущее.
        #expect(Self.notices(s, now: Self.at(765)).map(\.stage) == [2])
    }

    @Test func finishedShootAndNonWorkCallNobody() {
        #expect(Self.notices(Self.session(cells: [(720, 780)]), finished: true).isEmpty)
        #expect(Self.notices(Self.session(cells: [(720, 780)], kind: .meet)).isEmpty)
    }

    @Test func rentShorterThanTheFirstStageStartsAtItsBeginning() {
        // 12:00–12:12: дедлайн 12:07. Вторая ступень (12:02) после начала, первая (11:57) — до него:
        // веб молчит до начала аренды и в момент начала говорит ту ступень, что уже наступила.
        let n = Self.notices(Self.session(cells: [(720, 732)]))
        #expect(n.map(\.stage) == [1, 2])
        #expect(n.map(\.fire) == [Self.at(720), Self.at(722)])
        #expect(n.map(\.minutesLeft) == [7, 5])
        // 12:00–12:06: дедлайн 12:01 — обе ступени раньше начала, остаётся вторая на начало.
        let n2 = Self.notices(Self.session(cells: [(720, 726)]))
        #expect(n2.map(\.stage) == [2])
        #expect(n2.map(\.fire) == [Self.at(720)])
        #expect(n2.map(\.minutesLeft) == [1])
        // 12:00–12:10: вторая ступень (12:00) ровно на начале, первая раньше — сигнал один, вторая ступень.
        let n3 = Self.notices(Self.session(cells: [(720, 730)]))
        #expect(n3.map(\.stage) == [2])
        #expect(n3.map(\.fire) == [Self.at(720)])
        #expect(n3.map(\.minutesLeft) == [5])
        // 12:00–12:04: дедлайн 11:59 раньше начала — человек его не застанет, молчим.
        #expect(Self.notices(Self.session(cells: [(720, 724)])).isEmpty)
    }

    // MARK: - Ячейки и идентификаторы

    @Test func everyCellOfTheDayGetsItsOwnPair() {
        let s = Self.session(cells: [(600, 660), (840, 960)])
        let n = Self.notices(s)
        #expect(n.count == 4)
        #expect(Set(n.map(\.id)).count == 4)
        #expect(n.map(\.id) == ["lp.studio.s1.0.1", "lp.studio.s1.0.2", "lp.studio.s1.1.1", "lp.studio.s1.1.2"])
    }

    @Test func routeIndexNotSortedOrderNamesTheCell() {
        // Ячейки записаны не по порядку: номер — место в маршруте, а не по часам.
        let s = Self.session(cells: [(840, 960), (600, 660)])
        let n = Self.notices(s)
        #expect(n.map(\.id) == ["lp.studio.s1.1.1", "lp.studio.s1.1.2", "lp.studio.s1.0.1", "lp.studio.s1.0.2"])
    }

    @Test func hallNameComesFromTheCell() {
        let s = Self.session(cells: [(720, 780)], hall: "h2")
        #expect(Self.notices(s).first?.hallName == "Тесла")
        #expect(Self.notices(Self.session(cells: [(720, 780)], hall: nil)).first?.hallName == nil)
    }

    @Test func legacyRecordUsesItsOwnRentFields() {
        var s = Session(id: "old", day: Self.day, start: 720)
        s.studioId = "st1"; s.rentFrom = 720; s.rentTo = 780
        let n = Self.notices(s)
        #expect(n.map(\.id) == ["lp.studio.old.r.1", "lp.studio.old.r.2"])
        #expect(n.map(\.fire) == [Self.at(765), Self.at(770)])
    }

    @Test func cellWithoutKnownStudioIsSilent() {
        #expect(Self.notices(Self.session(cells: [(720, 780)]), studios: []).isEmpty)
    }

    // MARK: - Правка часов, продление

    @Test func editingHoursKeepsIdsAndMovesInstants() {
        let a = Self.notices(Self.session(cells: [(720, 780)]))
        let b = Self.notices(Self.session(cells: [(840, 900)]))
        #expect(a.map(\.id) == b.map(\.id))
        #expect(b.map(\.fire) == [Self.at(885), Self.at(890)])
    }

    @Test func extensionMovesTheDeadlineByTheExtension() {
        // Продление на час: конец 13:00 → 14:00, обе ступени уезжают на час.
        let a = Self.notices(Self.session(cells: [(720, 780)]))
        let b = Self.notices(Self.session(cells: [(720, 840)]))
        #expect(a.map(\.id) == b.map(\.id))
        #expect(zip(a, b).allSatisfy { $1.fire.milliseconds - $0.fire.milliseconds == 3_600_000 })
    }

    // MARK: - Потолок

    @Test func planKeepsTheNearestSixtyFour() {
        var sessions: [Session] = []
        for i in 0..<40 {
            sessions.append(Self.session("s\(i)", cells: [(720, 780)], day: CivilDate(year: 2026, month: 10, day: 20).adding(days: i)))
        }
        let plan = StudioSchedule.plan(sessions: sessions, studios: [Self.studio], now: Self.longAgo,
                                       offsetHours: { _ in 3 }, finished: { _ in false })
        #expect(plan.count == 64)
        // 80 сигналов, остались первые 32 дня.
        #expect(plan.last?.sessionId == "s31")
        #expect(plan == plan.sorted { ($0.fire, $0.id) < ($1.fire, $1.id) })
    }

    // MARK: - Минута шкалы

    /// Минута шкалы съёмки по часам +3 для момента того же дня или следующего.
    static func minute(of m: Moment) -> Int {
        let local = m.milliseconds + 3 * 3_600_000
        let base = Int64(day.daysSince1970) * 86_400_000
        return Int((local - base) / 60_000)
    }
}

// MARK: - Сверка с системой

/// Пустышка вместо `UNUserNotificationCenter`.
actor FakeCenter: NotificationCentering {
    var status: NotificationAuthorization
    var table: [String: ScheduledAlert] = [:]
    var foreign: [String] = []
    private(set) var asked = 0
    var answer = true
    private(set) var adds: [String] = []
    private(set) var removes: [String] = []

    init(status: NotificationAuthorization = .allowed) { self.status = status }

    func authorization() -> NotificationAuthorization { status }
    func requestAuthorization() -> Bool {
        asked += 1
        status = answer ? .allowed : .denied
        return answer
    }
    func pending() -> [PendingAlert] {
        table.values.map { PendingAlert(id: $0.id, signature: $0.signature) }
            + foreign.map { PendingAlert(id: $0, signature: nil) }
    }
    var refuse: Set<String> = []
    func add(_ alert: ScheduledAlert) -> Bool {
        if refuse.contains(alert.id) { return false }
        table[alert.id] = alert; adds.append(alert.id)
        return true
    }
    func setRefuse(_ ids: Set<String>) { refuse = ids }
    func remove(ids: [String]) { ids.forEach { table[$0] = nil }; foreign.removeAll { ids.contains($0) }; removes += ids }
    func setForeign(_ n: Int) { foreign = (0..<n).map { "other.\($0)" } }
    func resetLog() { adds = []; removes = [] }
}

@Suite struct NotificationSchedulerTests {

    static func alerts(_ s: Session) -> [ScheduledAlert] {
        StudioScheduleTests.notices(s).map {
            ScheduledAlert(id: $0.id, sessionId: $0.sessionId, fire: $0.fire, offsetHours: $0.offsetHours,
                           title: "t \($0.deadline)", body: "b \($0.minutesLeft)")
        }
    }

    @Test func firstSyncAddsEverythingAndSecondChangesNothing() async {
        let center = FakeCenter()
        let sched = NotificationScheduler(center: center)
        let a = Self.alerts(StudioScheduleTests.session(cells: [(720, 780)]))
        let r1 = await sched.sync(a)
        #expect(r1.added.count == 2 && r1.removed.isEmpty && r1.kept.isEmpty)
        await center.resetLog()
        let r2 = await sched.sync(a)
        #expect(r2.added.isEmpty && r2.removed.isEmpty && r2.kept.count == 2)
        #expect(await center.adds.isEmpty)
    }

    @Test func editingHoursReplacesInPlaceWithoutDuplicates() async {
        let center = FakeCenter()
        let sched = NotificationScheduler(center: center)
        await sched.sync(Self.alerts(StudioScheduleTests.session(cells: [(720, 780)])))
        let r = await sched.sync(Self.alerts(StudioScheduleTests.session(cells: [(840, 900)])))
        #expect(r.added.count == 2 && r.removed.isEmpty)
        let table = await center.table
        #expect(table.count == 2)
        #expect(table["lp.studio.s1.0.1"]?.fire == StudioScheduleTests.at(885))
    }

    @Test func removingTheCellRemovesItsRequests() async {
        let center = FakeCenter()
        let sched = NotificationScheduler(center: center)
        await sched.sync(Self.alerts(StudioScheduleTests.session(cells: [(600, 660), (840, 960)])))
        #expect(await center.table.count == 4)
        let r = await sched.sync(Self.alerts(StudioScheduleTests.session(cells: [(600, 660)])))
        #expect(Set(r.removed) == ["lp.studio.s1.1.1", "lp.studio.s1.1.2"])
        #expect(await center.table.count == 2)
        // Удалили запись целиком.
        let r2 = await sched.sync([])
        #expect(r2.removed.count == 2)
        #expect(await center.table.isEmpty)
    }

    @Test func refusedRequestIsReportedAndRetriedNotRememberedAsAdded() async {
        let center = FakeCenter()
        await center.setRefuse(["lp.studio.s1.0.2"])
        let sched = NotificationScheduler(center: center)
        let a = Self.alerts(StudioScheduleTests.session(cells: [(720, 780)]))
        let r1 = await sched.sync(a)
        #expect(r1.added == ["lp.studio.s1.0.1"] && r1.failed == ["lp.studio.s1.0.2"])
        await center.setRefuse([])
        let r2 = await sched.sync(a)
        #expect(r2.added == ["lp.studio.s1.0.2"] && r2.kept == ["lp.studio.s1.0.1"] && r2.failed.isEmpty)
    }

    @Test func foreignRequestsAreLeftAloneButCountUnderTheCeiling() async {
        let center = FakeCenter()
        await center.setForeign(60)
        let sched = NotificationScheduler(center: center)
        var sessions: [Session] = []
        for i in 0..<5 {
            sessions.append(StudioScheduleTests.session("s\(i)", cells: [(720, 780)],
                                                        day: CivilDate(year: 2026, month: 10, day: 20).adding(days: i)))
        }
        let all = sessions.flatMap(Self.alerts).sorted { ($0.fire, $0.id) < ($1.fire, $1.id) }
        let r = await sched.sync(all)
        // 64 − 60 чужих = 4 места; 10 желаемых, остались первые 4.
        #expect(r.added.count == 4 && r.dropped.count == 6)
        #expect(await center.pending().count == 64)
        await sched.clear()
        #expect(await center.table.isEmpty)
        #expect(await center.foreign.count == 60)
    }

    @Test func limitOf64IsHeldOnAFullPlan() async {
        let center = FakeCenter()
        let sched = NotificationScheduler(center: center)
        var sessions: [Session] = []
        for i in 0..<40 {
            sessions.append(StudioScheduleTests.session("s\(i)", cells: [(720, 780)],
                                                        day: CivilDate(year: 2026, month: 10, day: 20).adding(days: i)))
        }
        let notices = StudioSchedule.plan(sessions: sessions, studios: [StudioScheduleTests.studio],
                                          now: StudioScheduleTests.longAgo, offsetHours: { _ in 3 }, finished: { _ in false })
        let alerts = notices.map {
            ScheduledAlert(id: $0.id, sessionId: $0.sessionId, fire: $0.fire, offsetHours: $0.offsetHours, title: "", body: "")
        }
        let r = await sched.sync(alerts)
        #expect(r.added.count == 64 && r.dropped.isEmpty)
        #expect(await center.pending().count == 64)
    }
}

@Suite struct NotificationPresenterTests {
    @Test func openCardSuppressesTheBannerOtherwiseItIsShown() {
        #expect(NotificationPresenter.options(cardOpen: true) == [])
        #expect(NotificationPresenter.options(cardOpen: false).contains(.banner))
        #expect(NotificationPresenter.options(cardOpen: false).contains(.sound))
    }
}
