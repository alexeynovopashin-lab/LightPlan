import Foundation
import Testing
import LightPlanCore
import LightPlanDomain
@testable import LightPlanData

/// Чужие календари призраками (шаг 30.5): какие календари показываются, что читается, как призрак ложится в сутки,
/// как находится наложение. Календарь телефона — `InMemoryCalendarStore`; настоящий
/// EventKit — `Tools/calendar_sim.py`.
@Suite struct GhostCalendarsTests {

    static let zone = ZoneID("Asia/Tomsk")!
    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tomsk")!
        return c
    }
    static let day = CivilDate(year: 2026, month: 10, day: 24)       // суббота

    /// Момент: день и минуты по часам Томска.
    static func at(_ d: CivilDate, _ minutes: Int) -> Date { WallTime(day: d, minutes: minutes).moment(in: zone).date }
    static func range(_ from: CivilDate, days: Int) -> (Date, Date) { (at(from, 0), at(from.adding(days: days), 0)) }

    struct Rig {
        let store: InMemoryCalendarStore
        let memory = InMemoryGhostMemory()
        let mirrorMemory = InMemoryCalendarMemory()
        let ghosts: GhostCalendars
        let work, son, birthdays, holidays: String

        init(mode: GhostCalendarsDefault = .allPersonal, on: Bool = true, auth: CalendarAuthorization = .allowed) {
            let store = InMemoryCalendarStore(authorization: auth)
            self.store = store
            work = store.userAddCalendar(title: "Работа", type: .exchange, source: "Exchange")
            son = store.userAddCalendar(title: "Сын", type: .account, source: "iCloud")
            birthdays = store.userAddCalendar(title: "Дни рождения", type: .birthday, source: "Контакты")
            holidays = store.userAddCalendar(title: "Праздники России", type: .subscription, source: "Подписки")
            memory.record = GhostRecord(on: on)
            ghosts = GhostCalendars(store: store, mirrorMemory: mirrorMemory, memory: memory, mode: mode, calendar: GhostCalendarsTests.cal)
        }
        func titles(_ gs: [Ghost]) -> [String] { gs.map(\.title) }
        func week() async -> [Ghost] {
            let (a, b) = GhostCalendarsTests.range(GhostCalendarsTests.day.adding(days: -3), days: 14)
            return await ghosts.ghosts(from: a, to: b)
        }
    }

    // MARK: - Какие календари

    @Test func theShippedDefaultIsAllPersonal() {
        #expect(GhostPolicy.ghostCalendarsDefault == .allPersonal)
    }

    @Test func allPersonalShowsPersonalCalendarsOnlyAndNeverLightPlan() async {
        let r = Rig(mode: .allPersonal)
        let light = r.store.userAddCalendar(title: "Light Plan", type: .account)
        let shown = await r.ghosts.choices().filter(\.shown).map(\.calendar.title).sorted()
        #expect(shown == ["Работа", "Сын"])                                      // не праздники, не дни рождения
        let all = await r.ghosts.choices().map(\.calendar.title).sorted()
        #expect(all == ["Дни рождения", "Праздники России", "Работа", "Сын"])   // «Light Plan» в списке нет совсем
        #expect(!all.contains("Light Plan"))
        _ = light
    }

    @Test func noneShowsNothingUntilThePersonTicks() async {
        let r = Rig(mode: .none)
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son)
        #expect(await r.ghosts.choices().filter(\.shown).isEmpty)
        #expect(await r.week().isEmpty)
        await r.ghosts.setShown(r.son, true)
        #expect(r.titles(await r.week()) == ["Матч"])
        #expect(await r.ghosts.choices().filter(\.shown).map(\.calendar.title) == ["Сын"])
    }

    @Test func aTickOrUntickOfThePersonBeatsEitherDefault() async {
        let a = Rig(mode: .allPersonal)
        await a.ghosts.setShown(a.work, false)
        await a.ghosts.setShown(a.holidays, true)
        #expect(await a.ghosts.choices().filter(\.shown).map(\.calendar.title).sorted() == ["Праздники России", "Сын"])
        let n = Rig(mode: .none)
        await n.ghosts.setShown(n.work, true)
        await n.ghosts.setShown(n.work, nil)                                      // вернуть решение режиму
        #expect(await n.ghosts.choices().filter(\.shown).isEmpty)
    }

    @Test func aNewCalendarFollowsTheDefaultButAnOldPickStays() async {
        let r = Rig(mode: .allPersonal)
        await r.ghosts.setShown(r.son, false)
        let daughter = r.store.userAddCalendar(title: "Дочь", type: .account)
        let shown = await r.ghosts.choices().filter(\.shown).map(\.calendar.id)
        #expect(shown.contains(daughter))
        #expect(!shown.contains(r.son))
    }

    @Test func ourOwnCalendarIsNeverAGhostByTitleOrByTheMirrorsId() async {
        let r = Rig()
        let byTitle = r.store.userAddCalendar(title: "Light Plan", type: .account)          // прежний после переустановки
        let renamed = r.store.userAddCalendar(title: "Съёмки", type: .account)              // календарь зеркала, но назван иначе
        var rec = CalendarMirrorRecord(); rec.calendarId = renamed
        r.mirrorMemory.record = rec
        await r.ghosts.setShown(byTitle, true)                                              // даже если ткнули насильно
        for id in [byTitle, renamed] {
            r.store.userAdd(title: "Моя съёмка", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: id)
        }
        #expect(await r.ghosts.choices().map(\.calendar.id).allSatisfy { $0 != byTitle && $0 != renamed })
        #expect(await r.week().isEmpty)
    }

    @Test func onlyADeclinedInviteIsHiddenEveryOtherAnswerStaysAGhost() async {
        let r = Rig()
        func add(_ title: String, _ invite: InviteResponse?, _ m: Int) {
            r.store.userAdd(title: title, start: Self.at(Self.day, m), end: Self.at(Self.day, m + 30), calendarId: r.work, invite: invite)
        }
        add("Отклонил", .declined, 600)
        add("Под вопросом", .tentative, 660)
        add("Не ответил", .pending, 720)
        add("Принял", .accepted, 780)
        add("Без приглашения", nil, 840)                 // своё событие или организатор: ответа нет
        #expect(r.titles(await r.week()) == ["Под вопросом", "Не ответил", "Принял", "Без приглашения"])
        // Отклонённое пропало и с ленты дня.
        #expect(GhostDay.timed(on: Self.day, zone: Self.zone, ghosts: await r.week()).map(\.ghost.title) == ["Под вопросом", "Не ответил", "Принял", "Без приглашения"])
    }

    @Test func aDeclinedRepeatingEventIsHiddenInEveryOccurrenceAndOverlapIgnoresIt() async {
        let r = Rig()
        r.store.userAdd(title: "Отклонённый кружок", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son,
                        repeating: .init(everyDays: 1, count: 3), invite: .declined)
        let ghosts = await r.week()
        #expect(ghosts.isEmpty)
        #expect(GhostOverlap.find(start: Self.at(Self.day, 620), end: Self.at(Self.day, 640), day: Self.day, in: ghosts).isEmpty)
    }

    @Test func ourOwnEventsAreSkippedEvenInSomeoneElsesCalendar() async {
        let r = Rig()
        r.store.userAdd(title: "Свадьба · Ирина", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.work,
                        url: CalendarPlan.url(shoot: "w1"))
        r.store.userAdd(title: "Отозвано", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.work, cancelled: true)
        r.store.userAdd(title: "Совещание", start: Self.at(Self.day, 800), end: Self.at(Self.day, 860), calendarId: r.work,
                        url: URL(string: "https://zoom.example/j/1"))
        #expect(r.titles(await r.week()) == ["Совещание"])
    }

    // MARK: - Права и выключатель

    @Test func switchedOffReadsNothingAndTouchesNothing() async {
        let r = Rig(on: false)
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son)
        #expect(await r.week().isEmpty)
        #expect(r.store.eventReads == 0)
        #expect(r.store.accessRequests == 0)
    }

    @Test func withoutAccessThereAreNoGhostsAndNoCalendars() async {
        let r = Rig(auth: .denied)
        #expect(await r.week().isEmpty)
        #expect(await r.ghosts.choices().isEmpty)
        #expect(r.store.accessRequests == 0)             // читатель сам права не просит
    }

    @Test func theChoiceSurvivesAMirrorSwitchOff() async {
        // Выбор лежит отдельно от памяти зеркала: выключение зеркала стирает её запись, но не его.
        let r = Rig()
        await r.ghosts.setShown(r.son, false)
        let mirror = CalendarMirror(store: r.store, memory: r.mirrorMemory)
        _ = await mirror.enable()
        _ = await mirror.disable()
        #expect(r.memory.record.picks[r.son] == false)
        #expect(r.memory.record.on)
    }

    // MARK: - События

    @Test func aTimedEventKeepsOnlyTitleTimePlaceAndCalendarName() async {
        let r = Rig()
        r.store.userAdd(title: "  Матч  ", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son,
                        url: URL(string: "https://secret.example/x"), location: "Стадион\nЛенина 5", notes: "пароль 12345, придёт Пётр")
        let g = try! #require(await r.week().first)
        #expect(g.title == "Матч")
        #expect(g.calendarTitle == "Сын")
        #expect(g.location == "Стадион, Ленина 5")
        #expect(g.start == Self.at(Self.day, 600) && g.end == Self.at(Self.day, 700))
        #expect(!g.allDay)
        // Заметки и ссылка чужого события в призрак не попадают совсем.
        let dump = String(reflecting: g)
        #expect(!dump.contains("пароль") && !dump.contains("secret.example") && !dump.contains("Пётр"))
        // …и уже слой календаря отдаёт призраку не `StoredEvent`, а `GhostEvent`: в нём заметок и ссылки нет вовсе.
        let raw = await r.store.ghostEvents(calendarId: r.son, from: Self.range(Self.day, days: 1).0, to: Self.range(Self.day, days: 2).1)
        let rawDump = String(reflecting: raw)
        #expect(raw.count == 1 && !rawDump.contains("пароль") && !rawDump.contains("secret.example") && !rawDump.contains("Пётр"))
    }

    @Test func anAnswerThatArrivesAfterAFlushNeverPutsStaleEventsBackInTheCache() async {
        let r = Rig()
        r.store.userAdd(title: "Старый", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.work)
        // Первым читается «Работа» (учётные записи по алфавиту: Exchange раньше iCloud). Чтение остановлено посреди ответа: снимок базы уже снят, отдать его ещё не успели.
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        r.store.setReadGate {
            entered.continuation.yield()
            for await _ in release.stream { break }
        }
        let (a, b) = Self.range(Self.day.adding(days: -3), days: 14)
        let first = Task { await r.ghosts.ghosts(from: a, to: b) }
        for await _ in entered.stream { break }
        // Пока оно ждёт: человек добавил событие, база сказала «изменилась», кэш сброшен.
        r.store.setReadGate(nil)
        r.store.userAdd(title: "Новый", start: Self.at(Self.day, 800), end: Self.at(Self.day, 900), calendarId: r.work)
        await r.ghosts.invalidate()
        release.continuation.yield()
        _ = await first.value                                        // старый ответ вернулся — этому вызову он годится
        #expect(r.titles(await r.ghosts.ghosts(from: a, to: b)) == ["Старый", "Новый"])      // а кэш его не запомнил
    }

    @Test func aShootThatRunsPastMidnightMeetsTheAllDayEventOfTheNextDay() {
        let next = Self.day.adding(days: 1)
        let g = Ghost(id: "2", calendarId: "c", calendarTitle: "Семья", title: "Отпуск", start: Self.at(next, 0),
                      end: Self.at(next, 1439), allDay: true, firstDay: next, lastDay: next)
        let a = Self.at(Self.day, 22 * 60), b = Self.at(next, 2 * 60)
        #expect(GhostOverlap.find(start: a, end: b, day: Self.day, in: [g]).isEmpty)                     // только день начала — не видно
        #expect(GhostOverlap.find(start: a, end: b, day: Self.day, through: next, in: [g]).map(\.title) == ["Отпуск"])
        #expect(GhostOverlap.find(start: a, end: b, day: Self.day, through: Self.day, in: [g]).isEmpty)
    }

    @Test func anAllDayEventCoversItsDaysWhicheverWayTheEndIsWritten() async {
        let r = Rig()
        let d0 = Self.day
        // EventKit: конец последнего дня — 23:59:59.
        r.store.userAdd(title: "Отпуск мужа", start: Self.at(d0, 0), end: Self.at(d0.adding(days: 2), 1439).addingTimeInterval(59),
                        calendarId: r.work, allDay: true)
        // Другие источники: конец — полночь следующего дня.
        r.store.userAdd(title: "Каникулы", start: Self.at(d0.adding(days: 5), 0), end: Self.at(d0.adding(days: 7), 0),
                        calendarId: r.work, allDay: true)
        let gs = await r.week()
        let vacation = try! #require(gs.first { $0.title == "Отпуск мужа" })
        #expect(vacation.allDay && vacation.firstDay == d0 && vacation.lastDay == d0.adding(days: 2))
        let camp = try! #require(gs.first { $0.title == "Каникулы" })
        #expect(camp.firstDay == d0.adding(days: 5) && camp.lastDay == d0.adding(days: 6))   // 7-й день уже не он
        #expect(GhostDay.allDay(on: d0.adding(days: 1), ghosts: gs).map(\.title) == ["Отпуск мужа"])
        #expect(GhostDay.allDay(on: d0.adding(days: 3), ghosts: gs).isEmpty)
        #expect(GhostDay.allDay(on: d0.adding(days: 6), ghosts: gs).map(\.title) == ["Каникулы"])
        #expect(GhostDay.allDay(on: d0.adding(days: 7), ghosts: gs).isEmpty)
        // «На весь день» не лежит на ленте часов.
        #expect(GhostDay.timed(on: d0, zone: Self.zone, ghosts: gs).isEmpty)
    }

    @Test func aNightEventIsClippedToEachDay() async {
        let r = Rig()
        r.store.userAdd(title: "Ночная смена", start: Self.at(Self.day, 22 * 60), end: Self.at(Self.day.adding(days: 1), 6 * 60), calendarId: r.work)
        let gs = await r.week()
        let first = try! #require(GhostDay.timed(on: Self.day, zone: Self.zone, ghosts: gs).first)
        #expect(first.start == 1320 && first.end == 1440 && !first.fromYesterday && first.intoTomorrow)
        let second = try! #require(GhostDay.timed(on: Self.day.adding(days: 1), zone: Self.zone, ghosts: gs).first)
        #expect(second.start == 0 && second.end == 360 && second.fromYesterday && !second.intoTomorrow)
        #expect(GhostDay.timed(on: Self.day.adding(days: 2), zone: Self.zone, ghosts: gs).isEmpty)
        #expect(GhostDay.timed(on: Self.day.adding(days: -1), zone: Self.zone, ghosts: gs).isEmpty)
    }

    @Test func aPointEventGetsAPartAndAnEventEndingAtMidnightDoesNotLeakIntoTheNextDay() async {
        let r = Rig()
        r.store.userAdd(title: "Напоминание", start: Self.at(Self.day, 900), end: Self.at(Self.day, 900), calendarId: r.work)
        r.store.userAdd(title: "До полуночи", start: Self.at(Self.day, 1380), end: Self.at(Self.day.adding(days: 1), 0), calendarId: r.work)
        let gs = await r.week()
        let today = GhostDay.timed(on: Self.day, zone: Self.zone, ghosts: gs)
        #expect(today.map(\.ghost.title) == ["Напоминание", "До полуночи"])
        #expect(today[0].start == 900 && today[0].end == 900)
        #expect(!today[1].intoTomorrow)
        #expect(GhostDay.timed(on: Self.day.adding(days: 1), zone: Self.zone, ghosts: gs).isEmpty)
    }

    @Test func aRepeatingEventExpandsOnlyInsideTheRange() async {
        let r = Rig()
        // Кружок по вторникам и пятницам заменён ежедневным: пять вхождений подряд с 24-го.
        r.store.userAdd(title: "Кружок", start: Self.at(Self.day, 1020), end: Self.at(Self.day, 1080), calendarId: r.son,
                        repeating: .init(everyDays: 1, count: 5))
        let all = await r.week()
        #expect(all.count == 5)
        #expect(Set(all.map(\.id)).count == 5)                                  // у вхождений один идентификатор события, ключи разные
        let (a, b) = Self.range(Self.day.adding(days: 2), days: 2)               // только 26-е и 27-е
        let two = await r.ghosts.ghosts(from: a, to: b)
        #expect(two.count == 2)
        #expect(two.map(\.start) == [Self.at(Self.day.adding(days: 2), 1020), Self.at(Self.day.adding(days: 3), 1020)])
        #expect(await r.ghosts.ghosts(from: Self.range(Self.day.adding(days: 30), days: 5).0, to: Self.range(Self.day.adding(days: 30), days: 5).1).isEmpty)
    }

    // MARK: - Кэш и перемены в базе

    @Test func theSameRangeIsReadOnceAndAgainAfterABaseChange() async {
        let r = Rig()
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son)
        _ = await r.week()
        let first = r.store.eventReads
        _ = await r.week()
        #expect(r.store.eventReads == first)                                      // тот же отрезок — из кэша
        // Человек добавил событие в Календаре: база сказала «изменилась», кэш сбросили — новое видно.
        let stream = r.store.changes()
        let heard = Task { for await _ in stream { return true }; return false }
        r.store.userAdd(title: "Ещё матч", start: Self.at(Self.day, 800), end: Self.at(Self.day, 900), calendarId: r.son)
        #expect(await heard.value)
        await r.ghosts.invalidate()
        #expect(r.titles(await r.week()) == ["Матч", "Ещё матч"])
        #expect(r.store.eventReads > first)
    }

    @Test func ticksAndSwitchDropTheCache() async {
        let r = Rig()
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son)
        #expect(r.titles(await r.week()) == ["Матч"])
        await r.ghosts.setShown(r.son, false)
        #expect(await r.week().isEmpty)
        await r.ghosts.setShown(r.son, true)
        await r.ghosts.setOn(false)
        #expect(await r.week().isEmpty)
    }

    // MARK: - Наложение (форма)

    @Test func overlapMeansSharedTimeNotMerelyTouching() {
        let g = Ghost(id: "1", calendarId: "c", calendarTitle: "Сын", title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), allDay: false)
        func hit(_ a: Int, _ b: Int) -> Bool { !GhostOverlap.find(start: Self.at(Self.day, a), end: Self.at(Self.day, b), day: Self.day, in: [g]).isEmpty }
        #expect(hit(650, 750))          // край внутри
        #expect(hit(540, 720))          // съёмка накрывает матч
        #expect(hit(620, 640))          // съёмка внутри матча
        #expect(!hit(500, 600))         // встык — не наложение
        #expect(!hit(700, 800))
        #expect(!hit(300, 400))
    }

    @Test func anAllDayGhostWarnsOnItsDaysOnly() {
        let g = Ghost(id: "2", calendarId: "c", calendarTitle: "Семья", title: "Отпуск", start: Self.at(Self.day, 0),
                      end: Self.at(Self.day.adding(days: 1), 0), allDay: true, firstDay: Self.day, lastDay: Self.day.adding(days: 1))
        let in1 = GhostOverlap.find(start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), day: Self.day, in: [g])
        #expect(in1.map(\.title) == ["Отпуск"])
        let out = GhostOverlap.find(start: Self.at(Self.day.adding(days: 3), 600), end: Self.at(Self.day.adding(days: 3), 700),
                                    day: Self.day.adding(days: 3), in: [g])
        #expect(out.isEmpty)
    }

    @Test func overlapListsTimedGhostsFirstThenAllDay() {
        let timed = Ghost(id: "t", calendarId: "c", calendarTitle: "Работа", title: "Планёрка", start: Self.at(Self.day, 600), end: Self.at(Self.day, 660), allDay: false)
        let whole = Ghost(id: "a", calendarId: "c", calendarTitle: "Семья", title: "Отпуск", start: Self.at(Self.day, 0),
                          end: Self.at(Self.day, 1439), allDay: true, firstDay: Self.day, lastDay: Self.day)
        let found = GhostOverlap.find(start: Self.at(Self.day, 630), end: Self.at(Self.day, 700), day: Self.day, in: [whole, timed])
        #expect(found.map(\.title) == ["Планёрка", "Отпуск"])
    }

    @Test func overlapIsComparedByMomentsNotByWallClockOfDifferentZones() {
        // Матч 10:00–11:00 в Томске (+7) = 03:00–04:00 UTC. Съёмка в Москве (+3) 06:30–07:30 по Москве = 03:30–04:30 UTC.
        let moscow = ZoneID("Europe/Moscow")!
        let g = Ghost(id: "m", calendarId: "c", calendarTitle: "Сын", title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 660), allDay: false)
        let a = WallTime(day: Self.day, minutes: 6 * 60 + 30).moment(in: moscow).date
        let b = WallTime(day: Self.day, minutes: 7 * 60 + 30).moment(in: moscow).date
        #expect(!GhostOverlap.find(start: a, end: b, day: Self.day, in: [g]).isEmpty)
        // Та же «настенная» 10:00–11:00 в Москве — это уже 14:00–15:00 по Томску: не наложение.
        let c = WallTime(day: Self.day, minutes: 600).moment(in: moscow).date
        let d = WallTime(day: Self.day, minutes: 660).moment(in: moscow).date
        #expect(GhostOverlap.find(start: c, end: d, day: Self.day, in: [g]).isEmpty)
    }

    // MARK: - Память

    @Test func theRecordReadsOldAndPartialJSON() throws {
        let empty = try JSONDecoder().decode(GhostRecord.self, from: Data("{}".utf8))
        #expect(empty == GhostRecord())
        let some = try JSONDecoder().decode(GhostRecord.self, from: Data(#"{"on":true,"picks":{"a":false}}"#.utf8))
        #expect(some.on && some.picks == ["a": false])
    }

    @Test func theDeviceMemoryKeepsTheRecordAcrossInstances() {
        let suite = "ghost-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        DeviceGhostMemory(defaults: d).record = GhostRecord(on: true, picks: ["x": true])
        #expect(DeviceGhostMemory(defaults: d).record == GhostRecord(on: true, picks: ["x": true]))
    }

    @Test func ghostsNeverRideInTheSnapshotOrTheMirror() async {
        // Призрак — не запись: ни в снимке данных, ни в событиях нашего календаря его нет.
        let r = Rig()
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son)
        _ = await r.week()
        let mirror = CalendarMirror(store: r.store, memory: r.mirrorMemory)
        _ = await mirror.enable()
        _ = await mirror.sync([])
        let ours = r.store.allEvents.filter { $0.calendarId == r.mirrorMemory.record.calendarId }
        #expect(ours.isEmpty)
        #expect(r.store.writeCounts.saves == 0)
        #expect(r.store.allEvents.filter { $0.title == "Матч" }.count == 1)       // чужое событие осталось одним и тем же
    }
}
