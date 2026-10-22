import Foundation
import Testing
@testable import LightPlanData

/// Обратная сторона зеркала (шаг 30.4): что человек сделал в Календаре и возвращается в записи. Время и место
/// возвращаются, название и заметки — нет; событие, заведённое руками, предлагается стать черновиком.
/// Подставка — `InMemoryCalendarStore`; настоящий EventKit — `Tools/calendar_sim.py`.
@Suite struct CalendarReverseTests {

    typealias Rig = CalendarMirrorTests.Rig
    static let t0 = CalendarMirrorTests.t0

    /// Часы подставки, которые тест двигает сам: «раньше» и «позже» у правок событий.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var now: Date
        init(_ d: Date) { now = d }
        func set(_ d: Date) { lock.lock(); now = d; lock.unlock() }
        func read() -> Date { lock.lock(); defer { lock.unlock() }; return now }
    }

    struct Bench {
        let store: InMemoryCalendarStore
        let memory = InMemoryCalendarMemory()
        let mirror: CalendarMirror
        let clock = Clock(CalendarReverseTests.t0)
        init() {
            let c = clock
            store = InMemoryCalendarStore(clock: { c.read() })
            mirror = CalendarMirror(store: store, memory: memory)
        }
        static func on() async -> Bench { let b = Bench(); _ = await b.mirror.enable(); return b }
        func pass(_ drafts: [EventDraft]) async -> CalendarMirror.Report {
            guard case .synced(let r) = await mirror.sync(drafts, now: CalendarReverseTests.t0) else { Issue.record("sync did not finish"); return .init() }
            return r
        }
    }

    /// Человек сдвинул событие на `hours` часов, время правки — `at`.
    static func move(_ b: Bench, _ id: String, hours: Double, at: Date) {
        b.clock.set(at)
        b.store.userEdit(id) { e in
            e = StoredEvent(id: e.id, calendarId: e.calendarId, title: e.title, start: e.start.addingTimeInterval(hours * 3600),
                            end: e.end.addingTimeInterval(hours * 3600), allDay: e.allDay, offsetSeconds: e.offsetSeconds,
                            locationTitle: e.locationTitle, latitude: e.latitude, longitude: e.longitude, url: e.url,
                            notes: e.notes, modified: at, recurring: e.recurring)
        }
    }

    static func later(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    // MARK: - Подвинули событие

    @Test func aMovedEventIsHandedBackToTheRecordAndNotRewritten() async {
        let b = await Bench.on()
        let d = CalendarMirrorTests.draft("a")
        _ = await b.pass([d])
        let id = b.store.allEvents[0].id
        Self.move(b, id, hours: 2, at: Self.later(60))
        let writes = b.store.writeCounts
        let rep = await b.pass([d])
        #expect(rep.incoming.count == 1)
        guard case .moved(let key, let event)? = rep.incoming.first else { Issue.record("no move"); return }
        #expect(key == d.key && event.id == id && event.start == d.start.addingTimeInterval(7200))
        #expect(rep.updated == 0 && b.store.writeCounts == writes)                 // календарь не тронут
        #expect(b.store.allEvents[0].start == d.start.addingTimeInterval(7200))
    }

    @Test func onceTheRecordFollowsTheEventThePassesSettleWithNothingLeftToDo() async {
        let b = await Bench.on()
        let d = CalendarMirrorTests.draft("a")
        _ = await b.pass([d])
        Self.move(b, b.store.allEvents[0].id, hours: 2, at: Self.later(60))
        _ = await b.pass([d])
        // Приложение приняло сдвиг: запись теперь с тем же временем, что и событие.
        let moved = CalendarMirrorTests.draft("a", hours: 26)
        let rep = await b.pass([moved])
        #expect(rep.incoming.isEmpty && rep.updated == 0 && rep.kept == 1)
        let again = await b.pass([moved])
        #expect(again.kept == 1 && again.incoming.isEmpty)
    }

    @Test func aMovedPlaceComesBackToo() async {
        let b = await Bench.on()
        let d = CalendarMirrorTests.draft("a")
        _ = await b.pass([d])
        b.store.userEdit(b.store.allEvents[0].id) { e in
            e = StoredEvent(id: e.id, calendarId: e.calendarId, title: e.title, start: e.start, end: e.end, allDay: false,
                            offsetSeconds: e.offsetSeconds, locationTitle: "Студия на Мира", latitude: 56.4, longitude: 84.9,
                            url: e.url, notes: e.notes, modified: Self.later(60))
        }
        let rep = await b.pass([d])
        guard case .moved(_, let event)? = rep.incoming.first else { Issue.record("no move"); return }
        #expect(event.locationTitle == "Студия на Мира")
    }

    @Test func aChangeMadeInTheAppIsAnOrdinaryOneWayUpdate() async {
        let b = await Bench.on()
        _ = await b.pass([CalendarMirrorTests.draft("a")])
        let rep = await b.pass([CalendarMirrorTests.draft("a", hours: 30)])
        #expect(rep.updated == 1 && rep.incoming.isEmpty)
        #expect(b.store.allEvents[0].start == CalendarMirrorTests.draft("a", hours: 30).start)
    }

    @Test func bothSidesMovedTheLaterEditWins() async {
        // Приложение: правка записи в 10:00 (mt); Календарь: правка события после неё → событие.
        let rec = Self.t0.timeIntervalSince1970 * 1000 + 10_000
        var d = CalendarMirrorTests.draft("a", hours: 30); d.recordModified = Int64(rec)
        let b = await Bench.on()
        _ = await b.pass([CalendarMirrorTests.draft("a")])
        Self.move(b, b.store.allEvents[0].id, hours: 5, at: Self.later(20))          // позже записи (+20 с против +10 с)
        let rep = await b.pass([d])
        #expect(rep.incoming.count == 1 && rep.updated == 0)

        // А если запись правили позже, чем событие, — запись.
        let c = await Bench.on()
        _ = await c.pass([CalendarMirrorTests.draft("a")])
        Self.move(c, c.store.allEvents[0].id, hours: 5, at: Self.later(5))           // раньше записи
        let rep2 = await c.pass([d])
        #expect(rep2.incoming.isEmpty && rep2.updated == 1)
        #expect(c.store.allEvents[0].start == d.start)
    }

    @Test func withoutAMemoryOfTheLastMeetingTheRecordWinsSoAStaleEventNeverRollsTheShootBack() async {
        // Переустановка: календарь прежний, память пуста (отпечатка нет).
        let b = await Bench.on()
        _ = await b.pass([CalendarMirrorTests.draft("a")])
        Self.move(b, b.store.allEvents[0].id, hours: 2, at: Self.later(60))
        let fresh = InMemoryCalendarMemory()
        let mirror = CalendarMirror(store: b.store, memory: fresh)
        _ = await mirror.enable()
        guard case .synced(let rep) = await mirror.sync([CalendarMirrorTests.draft("a")], now: Self.t0) else { Issue.record("no sync"); return }
        #expect(rep.incoming.isEmpty && rep.updated == 1)
        #expect(b.store.allEvents[0].start == CalendarMirrorTests.draft("a").start)
    }

    @Test func aRefusedMoveIsDismissedSoItIsNotOfferedForever() async {
        let b = await Bench.on()
        let d = CalendarMirrorTests.draft("a")
        _ = await b.pass([d])
        Self.move(b, b.store.allEvents[0].id, hours: 2, at: Self.later(60))
        let first = await b.pass([d])
        guard case .moved(let key, let event)? = first.incoming.first else { Issue.record("no move"); return }
        await b.mirror.dismiss(key: key, event: event)
        let second = await b.pass([d])
        #expect(second.incoming.isEmpty && second.updated == 1)                    // событие вернулось к записи
        #expect(b.store.allEvents[0].start == d.start)
    }

    // MARK: - Событие, заведённое руками

    @Test func aHandMadeEventInOurCalendarIsOfferedAsADraftUntilItIsAdopted() async {
        let b = await Bench.on()
        _ = await b.pass([CalendarMirrorTests.draft("a")])
        let cal = b.store.allCalendars[0].id
        let mine = b.store.userAdd(title: "Маша фотосессия", start: Self.t0.addingTimeInterval(7200),
                                   end: Self.t0.addingTimeInterval(10_800), calendarId: cal, notes: "в парке")
        let rep = await b.pass([CalendarMirrorTests.draft("a")])
        #expect(rep.incoming.map { if case .created(let e) = $0 { e.id } else { "" } } == [mine])
        // Пока не связано, предлагается снова — но событие не тронуто и не удвоено.
        let again = await b.pass([CalendarMirrorTests.draft("a")])
        #expect(again.incoming.count == 1 && b.store.allEvents.count == 2)
        // Связали с новой записью: событие получает ссылку и больше не предлагается.
        await b.mirror.adopt(eventId: mine, key: CalendarPlan.url(shoot: "new").absoluteString)
        var nd = CalendarMirrorTests.draft("new", "Маша фотосессия", hours: 2, long: 1)
        nd.notes = "Маша фотосессия\nв парке"
        let linked = await b.pass([CalendarMirrorTests.draft("a"), nd])
        #expect(linked.incoming.isEmpty && linked.created == 0 && linked.updated == 1)
        #expect(b.store.allEvents.count == 2)
        #expect(b.store.allEvents.first { $0.id == mine }?.url == nd.url)
        let settled = await b.pass([CalendarMirrorTests.draft("a"), nd])
        #expect(settled.kept == 2 && settled.incoming.isEmpty)
    }

    @Test func eventsThatAreNotShootsAreLeftAlone() async {
        let b = await Bench.on()
        let cal = b.store.allCalendars[0].id
        let s = Self.t0, e = Self.t0.addingTimeInterval(3600)
        b.store.userAdd(title: "День рождения", start: s, end: s.addingTimeInterval(86_400), calendarId: cal, allDay: true)
        b.store.userAdd(title: "Планёрка", start: s, end: e, calendarId: cal, recurring: true)
        b.store.userAdd(title: "Командировка", start: s, end: s.addingTimeInterval(30 * 3600), calendarId: cal)
        let rep = await b.pass([])
        #expect(rep.incoming.isEmpty)
        #expect(b.store.allEvents.count == 3)                                       // и не тронуты
        #expect(b.store.writeCounts.removes == 0)
    }

    @Test func otherCalendarsAreNeverRead() async {
        let b = await Bench.on()
        let other = try! await b.store.createCalendar(title: "Работа", sourceId: "local")
        b.store.userAdd(title: "Чужое", start: Self.t0, end: Self.t0.addingTimeInterval(3600), calendarId: other.id)
        let rep = await b.pass([])
        #expect(rep.incoming.isEmpty)
    }

    @Test func aHandMadeEventFarAheadIsFoundWithinThreeYears() async {
        let b = await Bench.on()
        let cal = b.store.allCalendars[0].id
        b.store.userAdd(title: "Через два года", start: Self.t0.addingTimeInterval(2 * 366 * 86_400),
                        end: Self.t0.addingTimeInterval(2 * 366 * 86_400 + 3600), calendarId: cal)
        #expect(await b.pass([]).incoming.count == 1)
    }

    // MARK: - Календарь «Light Plan» после переустановки

    @Test func aCalendarWithOurEventsAndAHandMadeOneIsAdoptedAfterAReinstallNotDuplicated() async {
        let b = await Bench.on()
        _ = await b.pass([CalendarMirrorTests.draft("a")])
        b.store.userAdd(title: "Маша", start: Self.t0, end: Self.t0.addingTimeInterval(3600), calendarId: b.store.allCalendars[0].id)
        let mirror = CalendarMirror(store: b.store, memory: InMemoryCalendarMemory())      // память стёрта
        _ = await mirror.enable()
        #expect(b.store.allCalendars.count == 1)
        guard case .synced(let rep) = await mirror.sync([CalendarMirrorTests.draft("a")], now: Self.t0) else { Issue.record("no sync"); return }
        #expect(rep.created == 0 && rep.kept == 1 && rep.incoming.count == 1)
    }

    @Test func aUsersOwnCalendarNamedLightPlanWithoutOurLinksIsStillNotAdopted() async {
        let store = InMemoryCalendarStore()
        let own = try! await store.createCalendar(title: "Light Plan", sourceId: "icloud")
        store.userAdd(title: "Мои дела", start: Self.t0, end: Self.t0.addingTimeInterval(3600), calendarId: own.id)
        let mirror = CalendarMirror(store: store, memory: InMemoryCalendarMemory())
        _ = await mirror.enable()
        #expect(store.allCalendars.count == 2)                                      // завели свой, чужой не взяли
        #expect(await mirror.record.calendarId != own.id)
    }

    // MARK: - Заметки события

    @Test func notesTravelWithTheEventAndAHandEditOfThemSnapsBack() async {
        let b = await Bench.on()
        var d = CalendarMirrorTests.draft("a")
        d.notes = "Клиент: Ирина +7 916 123-45-67\n\nПриезжать за час"
        _ = await b.pass([d])
        #expect(b.store.allEvents[0].notes == d.notes)
        b.store.userEdit(b.store.allEvents[0].id) { e in
            e = StoredEvent(id: e.id, calendarId: e.calendarId, title: e.title, start: e.start, end: e.end, allDay: false,
                            offsetSeconds: e.offsetSeconds, locationTitle: e.locationTitle, latitude: e.latitude,
                            longitude: e.longitude, url: e.url, notes: "переписал руками", modified: Self.later(30))
        }
        let rep = await b.pass([d])
        #expect(rep.updated == 1 && rep.incoming.isEmpty)
        #expect(b.store.allEvents[0].notes == d.notes)
    }

    @Test func unchangedNotesDoNotRewriteTheEvent() async {
        let b = await Bench.on()
        var d = CalendarMirrorTests.draft("a"); d.notes = "Клиент: Ирина +7 916 123-45-67"
        _ = await b.pass([d])
        let writes = b.store.writeCounts
        let rep = await b.pass([d])
        #expect(rep.kept == 1 && b.store.writeCounts == writes)
    }

    @Test func aChangedPhoneRewritesTheNotes() async {
        let b = await Bench.on()
        var d = CalendarMirrorTests.draft("a"); d.notes = "Клиент: Ирина +7 916 123-45-67"
        _ = await b.pass([d])
        d.notes = "Клиент: Ирина +7 916 000-00-00"
        let rep = await b.pass([d])
        #expect(rep.updated == 1)
        #expect(b.store.allEvents[0].notes == d.notes)
    }

    // MARK: - Память устройства

    @Test func aMemoryWrittenBeforeThisStepStillReadsAndKeepsTheMirrorOn() throws {
        let old = #"{"wanted":true,"calendarId":"cal-1","sourceId":"icloud","links":{"lightplan://shoot/a":"ev-2"}}"#
        let r = try JSONDecoder().decode(CalendarMirrorRecord.self, from: Data(old.utf8))
        #expect(r.wanted && r.calendarId == "cal-1" && r.links.count == 1 && r.facts.isEmpty)
    }

    @Test func factsSurviveTheDeviceMemoryRoundTrip() throws {
        var r = CalendarMirrorRecord()
        r.wanted = true
        r.facts["k"] = EventFacts(draft: CalendarMirrorTests.draft("a"))
        let back = try JSONDecoder().decode(CalendarMirrorRecord.self, from: JSONEncoder().encode(r))
        #expect(back == r)
    }
}
