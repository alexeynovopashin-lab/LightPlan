import Foundation
import Testing
@testable import LightPlanData

/// Зеркало съёмок в календарь телефона (шаг 30.1–3): одно направление, правда в Light Plan.
/// Подставка — `InMemoryCalendarStore`; настоящий EventKit — в `Tools/calendar_probe/` и в прогоне на симуляторе.
@Suite struct CalendarMirrorTests {

    // MARK: - Подставки

    static let t0 = Date(timeIntervalSince1970: 1_792_000_000)   // 2026-10-14 ~ 17:46 UTC

    static func draft(_ id: String, _ title: String = "Свадьба · Ирина", hours: Double = 24, long: Double = 3,
                      place: String? = "Парк, ул. Ленина 5") -> EventDraft {
        EventDraft(title: title, start: t0.addingTimeInterval(hours * 3600), end: t0.addingTimeInterval((hours + long) * 3600),
                   timeZoneId: "Asia/Tomsk", offsetSeconds: 25_200, locationTitle: place, latitude: place == nil ? nil : 56.5,
                   longitude: place == nil ? nil : 84.97, url: CalendarPlan.url(shoot: id))
    }

    struct Rig {
        let store: InMemoryCalendarStore
        let memory: InMemoryCalendarMemory
        let mirror: CalendarMirror
        init(auth: CalendarAuthorization = .allowed, willGrant: Bool = true) {
            store = InMemoryCalendarStore(authorization: auth, willGrant: willGrant)
            memory = InMemoryCalendarMemory()
            mirror = CalendarMirror(store: store, memory: memory)
        }
        /// Включено и разрешено, календарь заведён.
        static func on() async -> Rig {
            let r = Rig()
            _ = await r.mirror.enable()
            return r
        }
        func report(_ drafts: [EventDraft], now: Date = CalendarMirrorTests.t0) async -> CalendarMirror.Report {
            guard case .synced(let r) = await mirror.sync(drafts, now: now) else { Issue.record("sync did not finish"); return .init() }
            return r
        }
    }

    // MARK: - Свой календарь и источник

    @Test func enablingAsksOnceAndCreatesTheCalendarInThePhonesDefaultAccount() async {
        let r = Rig(auth: .notDetermined)
        let out = await r.mirror.enable()
        #expect(out == .synced(.init()))
        #expect(r.store.accessRequests == 1)
        let cal = r.store.allCalendars
        #expect(cal.map(\.title) == ["Light Plan"])
        #expect(cal.first?.sourceId == "icloud")        // по умолчанию телефона, а не «первая попавшаяся»
        #expect(await r.mirror.record.calendarId == cal.first?.id)
        #expect(await r.mirror.record.wanted)
    }

    @Test func theCalendarIsNotCreatedTwice() async {
        let r = await Rig.on()
        _ = await r.mirror.enable()
        _ = await r.mirror.enable()
        #expect(r.store.allCalendars.count == 1)
    }

    @Test func aReinstalledAppTakesItsOldCalendarBackInsteadOfCreatingASecond() async {
        // Бесплатная подпись: приложение переставляют раз в семь дней, память на устройстве стирается, а календарь
        // «Light Plan» со своими событиями в телефоне остаётся.
        let r = await Rig.on()
        let drafts = [Self.draft("a"), Self.draft("b", hours: 48)]
        _ = await r.report(drafts)
        let ids = Set(r.store.allEvents.map(\.id))
        let freshMemory = InMemoryCalendarMemory()
        let again = CalendarMirror(store: r.store, memory: freshMemory)
        _ = await again.enable()
        #expect(r.store.allCalendars.count == 1)
        guard case .synced(let rep) = await again.sync(drafts, now: Self.t0) else { Issue.record("no sync"); return }
        #expect(rep.created == 0 && rep.kept == 2)
        #expect(Set(r.store.allEvents.map(\.id)) == ids)
    }

    @Test func aChosenAccountWinsOverTheDefault() async {
        let r = Rig()
        _ = await r.mirror.enable(sourceId: "local")
        #expect(r.store.allCalendars.first?.sourceId == "local")
    }

    @Test func changingTheAccountMovesEveryEventAndLeavesNoOldCalendar() async {
        let r = await Rig.on()
        _ = await r.report([Self.draft("a"), Self.draft("b", hours: 48)])
        let old = r.store.allCalendars[0].id
        let out = await r.mirror.moveCalendar(to: "local")
        #expect(out == .synced(.init()))
        #expect(r.store.allCalendars.map(\.sourceId) == ["local"])
        #expect(r.store.allCalendars[0].id != old)
        #expect(r.store.allEvents.isEmpty)               // старые ушли вместе со старым календарём
        let rep = await r.report([Self.draft("a"), Self.draft("b", hours: 48)])
        #expect(rep.created == 2)
        #expect(Set(r.store.allEvents.map(\.calendarId)) == [r.store.allCalendars[0].id])
    }

    @Test func anAccountThatRefusesCalendarsKeepsTheOldOneInPlace() async {
        let r = await Rig.on()
        _ = await r.report([Self.draft("a")])
        r.store.setSourceRefusing("local", true)
        let out = await r.mirror.moveCalendar(to: "local")
        guard case .failed = out else { Issue.record("expected failure, got \(out)"); return }
        #expect(r.store.allCalendars.map(\.sourceId) == ["icloud"])
        #expect(r.store.allEvents.count == 1)
        let rep = await r.report([Self.draft("a")])
        #expect(rep.kept == 1)                          // старая связь жива
    }

    @Test func disablingRemovesTheCalendarAndForgetsEverything() async {
        let r = await Rig.on()
        _ = await r.report([Self.draft("a")])
        await r.mirror.disable()
        #expect(r.store.allCalendars.isEmpty)
        #expect(r.store.allEvents.isEmpty)
        let rec = await r.mirror.record
        #expect(!rec.wanted && rec.calendarId == nil && rec.links.isEmpty)
    }

    // MARK: - Создать, сдвинуть, убрать

    @Test func everyRecordBecomesOneEventWithOurFields() async {
        let r = await Rig.on()
        let d = Self.draft("a")
        let rep = await r.report([d])
        #expect(rep.created == 1)
        let e = try! #require(r.store.allEvents.first)
        #expect(e.title == "Свадьба · Ирина")
        #expect(e.start == d.start && e.end == d.end)
        #expect(e.offsetSeconds == 25_200)               // пояс места съёмки проставлен явно
        #expect(e.locationTitle == "Парк, ул. Ленина 5" && e.latitude == 56.5 && e.longitude == 84.97)
        #expect(e.url == CalendarPlan.url(shoot: "a"))
        #expect(e.calendarId == r.store.allCalendars[0].id)
    }

    @Test func movingAShootMovesItsEventInsteadOfAddingAnother() async {
        let r = await Rig.on()
        _ = await r.report([Self.draft("a")])
        let id = r.store.allEvents[0].id
        let rep = await r.report([Self.draft("a", hours: 30)])
        #expect(rep.updated == 1 && rep.created == 0)
        #expect(r.store.allEvents.count == 1)
        #expect(r.store.allEvents[0].id == id)
        #expect(r.store.allEvents[0].start == Self.t0.addingTimeInterval(30 * 3600))
    }

    @Test func deletingAShootRemovesItsEventAndTheLink() async {
        let r = await Rig.on()
        _ = await r.report([Self.draft("a"), Self.draft("b", hours: 48)])
        let rep = await r.report([Self.draft("b", hours: 48)])
        #expect(rep.removed == 1 && rep.kept == 1)
        #expect(r.store.allEvents.map(\.url) == [CalendarPlan.url(shoot: "b")])
        #expect(await r.mirror.record.links.keys.sorted() == [CalendarPlan.url(shoot: "b").absoluteString])
    }

    @Test func aShootBroughtBackFromTheBinGetsItsEventAgain() async {
        let r = await Rig.on()
        _ = await r.report([Self.draft("a")])
        _ = await r.report([])
        #expect(r.store.allEvents.isEmpty)
        let rep = await r.report([Self.draft("a")])
        #expect(rep.created == 1 && r.store.allEvents.count == 1)
    }

    // MARK: - Повторные проходы не плодят события

    @Test func aSecondRunWithTheSameDataWritesNothing() async {
        let r = await Rig.on()
        let drafts = (0..<5).map { Self.draft("s\($0)", hours: Double(24 * $0 + 24)) }
        _ = await r.report(drafts)
        let before = r.store.writeCounts
        for _ in 0..<3 {
            let rep = await r.report(drafts)
            #expect(rep == .init(created: 0, updated: 0, removed: 0, kept: 5, failed: 0))
        }
        #expect(r.store.writeCounts == before)
        #expect(r.store.allEvents.count == 5)
    }

    @Test func concurrentRunsNeverCreateTwins() async {
        let r = await Rig.on()
        let drafts = (0..<4).map { Self.draft("s\($0)", hours: Double(24 * $0 + 24)) }
        await withTaskGroup(of: Void.self) { g in
            for _ in 0..<24 { g.addTask { _ = await r.mirror.sync(drafts, now: Self.t0) } }
        }
        #expect(r.store.allEvents.count == 4)
    }

    @Test func aLostMemoryAdoptsTheEventsByTheirLinkInsteadOfDuplicating() async {
        let r = await Rig.on()
        let drafts = [Self.draft("a"), Self.draft("b", hours: 48)]
        _ = await r.report(drafts)
        let ids = Set(r.store.allEvents.map(\.id))
        var rec = r.memory.record
        rec.links = [:]                                  // другой телефон, переустановка, стёртые данные
        r.memory.record = rec
        let rep = await r.report(drafts)
        #expect(rep.created == 0 && rep.kept == 2)
        #expect(Set(r.store.allEvents.map(\.id)) == ids)
    }

    @Test func twinsOfOneRecordAreCollapsedToOne() async {
        let r = await Rig.on()
        let d = Self.draft("a")
        _ = await r.report([d])
        let cal = r.store.allCalendars[0].id
        r.store.userAdd(title: d.title, start: d.start, end: d.end, calendarId: cal, url: d.url)   // двойник
        #expect(r.store.allEvents.count == 2)
        let rep = await r.report([d])
        #expect(rep.removed == 1)
        #expect(r.store.allEvents.count == 1)
    }

    // MARK: - Сверка при открытии

    @Test func anEventDeletedByHandInTheCalendarComesBackOnTheNextPass() async {
        let r = await Rig.on()
        let drafts = [Self.draft("a"), Self.draft("b", hours: 48)]
        _ = await r.report(drafts)
        let victim = r.store.allEvents.first { $0.url == CalendarPlan.url(shoot: "a") }!
        r.store.userDeleteEvent(victim.id)
        #expect(r.store.allEvents.count == 1)
        let rep = await r.report(drafts)
        #expect(rep.created == 1 && rep.kept == 1)
        #expect(r.store.allEvents.count == 2)
        #expect(r.store.allEvents.contains { $0.url == CalendarPlan.url(shoot: "a") && $0.title == "Свадьба · Ирина" })
    }

    @Test func anEventMovedByHandSnapsBackToTheRecord() async {
        let r = await Rig.on()
        let d = Self.draft("a")
        _ = await r.report([d])
        let id = r.store.allEvents[0].id
        r.store.userEdit(id) { $0 = StoredEvent(id: $0.id, calendarId: $0.calendarId, title: "Что-то другое",
                                                start: $0.start.addingTimeInterval(7200), end: $0.end.addingTimeInterval(7200),
                                                allDay: false, offsetSeconds: $0.offsetSeconds, locationTitle: nil,
                                                latitude: nil, longitude: nil, url: $0.url) }
        let rep = await r.report([d])
        #expect(rep.updated == 1)
        #expect(r.store.allEvents[0].title == d.title && r.store.allEvents[0].start == d.start)
        #expect(r.store.allEvents[0].id == id)
    }

    @Test func anEventWhoseLinkWasErasedIsStillFoundByItsStoredId() async {
        let r = await Rig.on()
        let d = Self.draft("a")
        _ = await r.report([d])
        let id = r.store.allEvents[0].id
        r.store.userEdit(id) { $0 = StoredEvent(id: $0.id, calendarId: $0.calendarId, title: $0.title, start: $0.start,
                                                end: $0.end, allDay: false, offsetSeconds: $0.offsetSeconds,
                                                locationTitle: $0.locationTitle, latitude: $0.latitude,
                                                longitude: $0.longitude, url: nil) }
        let rep = await r.report([d])
        #expect(rep.updated == 1 && rep.created == 0)
        #expect(r.store.allEvents.count == 1 && r.store.allEvents[0].url == d.url)
    }

    @Test func aPersonalEventInOurCalendarIsLeftAlone() async {
        let r = await Rig.on()
        _ = await r.report([Self.draft("a")])
        let mine = r.store.userAdd(title: "14:00 встреча", start: Self.t0, end: Self.t0.addingTimeInterval(3600),
                                   calendarId: r.store.allCalendars[0].id)
        _ = await r.report([])
        _ = await r.report([Self.draft("a")])
        #expect(r.store.allEvents.first { $0.id == mine }?.title == "14:00 встреча")
        #expect(r.store.allEvents.count == 2)
    }

    @Test func aMovedEventOutsideOurCalendarIsNotTouchedAndTheRecordGetsAFreshOne() async {
        let r = await Rig.on()
        let d = Self.draft("a")
        _ = await r.report([d])
        let id = r.store.allEvents[0].id
        r.store.userEdit(id) { $0 = StoredEvent(id: $0.id, calendarId: "elsewhere", title: $0.title, start: $0.start, end: $0.end,
                                                allDay: false, offsetSeconds: $0.offsetSeconds, locationTitle: nil,
                                                latitude: nil, longitude: nil, url: $0.url) }
        let rep = await r.report([d])
        #expect(rep.created == 1)
        #expect(r.store.allEvents.first { $0.id == id }?.calendarId == "elsewhere")   // чужой календарь — не наш
    }

    @Test func aDeletedCalendarIsNotSilentlyRecreatedButAsksFirst() async {
        let r = await Rig.on()
        let drafts = [Self.draft("a")]
        _ = await r.report(drafts)
        r.store.userDeleteCalendar(r.store.allCalendars[0].id)
        let out = await r.mirror.sync(drafts, now: Self.t0)
        #expect(out == .calendarGone)
        #expect(r.store.allCalendars.isEmpty)           // молча не заводим
        #expect(await r.mirror.sync(drafts, now: Self.t0) == .calendarGone)
        let back = await r.mirror.recreateCalendar()
        #expect(back == .synced(.init()))
        let rep = await r.report(drafts)
        #expect(rep.created == 1 && r.store.allEvents.count == 1)
    }

    // MARK: - Отказ в разрешении

    @Test func deniedAccessBreaksNothingAndCreatesNothing() async {
        let r = Rig(auth: .notDetermined, willGrant: false)
        let out = await r.mirror.enable()
        #expect(out == .noAccess(.denied))
        #expect(await r.mirror.enable() == .noAccess(.denied))   // повторное нажатие
        #expect(r.store.accessRequests == 1)                      // система спрашивает один раз, мы — тоже
        #expect(r.store.allCalendars.isEmpty && r.store.allEvents.isEmpty)
        let rec = await r.mirror.record
        #expect(!rec.wanted && rec.calendarId == nil)
        // Зеркало не включено — проход молчит и ничего не пишет.
        #expect(await r.mirror.sync([Self.draft("a")], now: Self.t0) == .synced(.init()))
        #expect(r.store.writeCounts == (0, 0))
    }

    @Test func accessTakenAwayLaterLeavesEverythingAsItWasAndResumesWhenReturned() async {
        let r = await Rig.on()
        let drafts = [Self.draft("a"), Self.draft("b", hours: 48)]
        _ = await r.report(drafts)
        r.store.setAuthorization(.denied)
        let writes = r.store.writeCounts
        #expect(await r.mirror.sync([Self.draft("a")], now: Self.t0) == .noAccess(.denied))
        #expect(r.store.writeCounts == writes)           // ни записи, ни удаления
        #expect(await r.mirror.record.links.count == 2)  // связи целы: вернётся право — продолжим без дублей
        r.store.setAuthorization(.allowed)
        let rep = await r.report(drafts)
        #expect(rep.kept == 2 && rep.created == 0)
        #expect(r.store.allEvents.count == 2)
    }

    @Test func aWriteOnlyGrantIsNotEnoughAndIsTreatedAsDenied() async {
        // Под «только записью» (проверено на iOS 26.5) календарь не завести и событие не найти.
        let r = Rig(auth: .denied)
        #expect(await r.mirror.enable() == .noAccess(.denied))
    }

    @Test func failedWritesAreRetriedOnTheNextPass() async {
        let r = await Rig.on()
        let drafts = [Self.draft("a"), Self.draft("b", hours: 48)]
        r.store.setFailingWrites(true)
        let bad = await r.report(drafts)
        #expect(bad.failed == 2 && bad.created == 0)
        r.store.setFailingWrites(false)
        let good = await r.report(drafts)
        #expect(good.created == 2 && good.failed == 0)
        #expect(r.store.allEvents.count == 2)
    }

    @Test func aFailedMoveKeepsTheLinkSoTheEventIsNotDuplicated() async {
        let r = await Rig.on()
        _ = await r.report([Self.draft("a")])
        r.store.setFailingWrites(true)
        _ = await r.report([Self.draft("a", hours: 30)])
        r.store.setFailingWrites(false)
        let rep = await r.report([Self.draft("a", hours: 30)])
        #expect(rep.updated == 1 && rep.created == 0 && r.store.allEvents.count == 1)
    }
}
