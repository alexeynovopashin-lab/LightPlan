import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Съёмки в Календаре iPhone (шаг 30.1–3), со стороны приложения: тумблер, названия, правки данных, сверка при
/// возврате, отказ в доступе. Календарь телефона — `InMemoryCalendarStore`.
@MainActor
struct CalendarMirrorAppTests {

    private struct DryWeather: WeatherSource {
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            HourlyWeather(time: [], cloud: [], temperature: [], windSpeed: [], precipitation: [], weatherCode: [])
        }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { [:] }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    static let day = CivilDate(year: 2026, month: 10, day: 20)

    /// Свадьба Ирины в парке, встреча без жанра и выходной на два дня.
    private static func snapshot() -> Snapshot {
        var snap = Snapshot()
        var wedding = Session(id: "w1", kind: .shoot, day: day, start: 600, end: 840, genre: .wedding)
        wedding.contact = "Ирина"
        wedding.place = "Парк"; wedding.placeAddress = "ул. Ленина 5"; wedding.latitude = 55.75; wedding.longitude = 37.62
        var meet = Session(id: "m1", kind: .meet, day: day.adding(days: 1), start: 900, end: 960, genre: .portrait)
        meet.contact = "Олег"
        var off = Block(id: "b1", kind: .off, from: day.adding(days: 3))
        off.allDay = true; off.days = 2
        snap.sessions = [wedding, meet]
        snap.blocks = [off]
        return snap
    }

    private func model(_ snap: Snapshot = snapshot(), store: InMemoryCalendarStore?, memory: InMemoryCalendarMemory = InMemoryCalendarMemory()) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-10-19T10:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: DryWeather(), now: { now })
        if let store { app.attachCalendar(store: store, memory: memory) }
        return app
    }

    private func settle(_ app: AppModel) async { await app.calendarChain?.value }

    // MARK: - Названия

    @Test func titlesPutTheGenreFirstThenTheClient() {
        let app = model(store: nil)
        #expect(app.calendarTitle(of: app.snapshot.sessions[0]) == "Свадьба · Ирина")
        #expect(app.calendarTitle(of: app.snapshot.sessions[1]) == "Встреча · портрет · Олег")
        #expect(app.calendarTitle(of: app.snapshot.blocks[0]) == "Выходной")
        var noGenre = Session(id: "x", kind: .shoot, day: Self.day, start: 600)
        #expect(app.calendarTitle(of: noGenre) == "Съёмка")
        noGenre.contact = "Анна"
        #expect(app.calendarTitle(of: noGenre) == "Съёмка · Анна")
        var note = Block(id: "n", kind: .road, from: Self.day); note.note = "В Тверь"
        #expect(app.calendarTitle(of: note) == "В Тверь")
    }

    // MARK: - Включение и зеркало

    @Test func turningTheSwitchOnAsksAccessCreatesTheCalendarAndMirrorsEveryRecord() async {
        let store = InMemoryCalendarStore(authorization: .notDetermined)
        let app = model(store: store)
        await settle(app)
        #expect(store.accessRequests == 0)                       // при запуске не спрашиваем
        #expect(!app.calendarMirrorOn)
        app.setCalendarMirror(true)
        await settle(app)
        #expect(store.accessRequests == 1)
        #expect(app.calendarMirrorOn)
        #expect(store.allCalendars.map(\.title) == ["Light Plan"])
        #expect(store.allEvents.map(\.title).sorted() == ["Выходной", "Встреча · портрет · Олег", "Свадьба · Ирина"].sorted())
        let wedding = store.allEvents.first { $0.title == "Свадьба · Ирина" }!
        #expect(wedding.url == CalendarPlan.url(shoot: "w1"))
        #expect(wedding.locationTitle == "Парк, ул. Ленина 5")
        #expect(app.calendarSources.map(\.id) == ["icloud", "local"] && app.calendarSourceId == "icloud")
    }

    @Test func savingAChangedRecordUpdatesItsEventAndTrashingRemovesIt() async {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        app.setCalendarMirror(true)
        await settle(app)
        let id = store.allEvents.first { $0.title == "Свадьба · Ирина" }!.id
        let was = store.allEvents.first { $0.id == id }!.start

        app.snapshot.sessions[0].start += 60; app.snapshot.sessions[0].end = 900
        app.persist()
        await settle(app)
        let moved = store.allEvents.first { $0.id == id }
        #expect(moved != nil && moved!.start == was.addingTimeInterval(3600))     // то же событие, час спустя
        #expect(store.allEvents.count == 3)

        app.trashSession(id: "w1")
        await settle(app)
        #expect(store.allEvents.map(\.title).contains("Свадьба · Ирина") == false)
        #expect(store.allEvents.count == 2)

        app.restoreSession(id: "w1")                                              // вернули из корзины — событие снова
        await settle(app)
        #expect(store.allEvents.map(\.title).contains("Свадьба · Ирина"))
        #expect(store.allEvents.count == 3)
    }

    @Test func aNewBlockAndItsRemovalFollowToo() async {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        app.setCalendarMirror(true)
        await settle(app)
        var b = Block(id: "b2", kind: .busy, from: Self.day); b.start = 600; b.duration = 90
        app.saveBlock(b)
        await settle(app)
        #expect(store.allEvents.count == 4)
        app.removeBlock(id: "b2")
        await settle(app)
        #expect(store.allEvents.count == 3)
    }

    @Test func dataEditsThatChangeNothingInTheCalendarWriteNothing() async {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        app.setCalendarMirror(true)
        await settle(app)
        let before = store.writeCounts
        app.snapshot.sessions[0].notes = "позвонить за день"           // заметки в календарь не ездят
        app.persist()
        await settle(app)
        app.persist()
        await settle(app)
        #expect(store.writeCounts == before)
    }

    // MARK: - Сверка при возврате в приложение

    @Test func comingBackToTheAppRestoresAnEventDeletedByHand() async {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        app.setCalendarMirror(true)
        await settle(app)
        store.userDeleteEvent(store.allEvents.first { $0.title == "Свадьба · Ирина" }!.id)
        #expect(store.allEvents.count == 2)
        app.syncCalendarMirror(force: true)                      // RootView: scenePhase == .active
        await settle(app)
        #expect(store.allEvents.count == 3)
        #expect(store.allEvents.filter { $0.title == "Свадьба · Ирина" }.count == 1)
    }

    @Test func aCalendarDeletedByHandAsksBeforeComingBack() async {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        app.setCalendarMirror(true)
        await settle(app)
        store.userDeleteCalendar(store.allCalendars[0].id)
        app.syncCalendarMirror(force: true)
        await settle(app)
        #expect(app.calendarGoneAsk)
        #expect(store.allCalendars.isEmpty)                      // молча не заводим

        app.answerCalendarGone(yes: true)
        await settle(app)
        #expect(!app.calendarGoneAsk && app.calendarMirrorOn)
        #expect(store.allCalendars.count == 1 && store.allEvents.count == 3)
    }

    @Test func sayingNoToTheQuestionSwitchesTheMirrorOffForGood() async {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        app.setCalendarMirror(true)
        await settle(app)
        store.userDeleteCalendar(store.allCalendars[0].id)
        app.syncCalendarMirror(force: true)
        await settle(app)
        app.answerCalendarGone(yes: false)
        await settle(app)
        #expect(!app.calendarMirrorOn && !app.calendarWanted)
        app.persist(); await settle(app)
        #expect(store.allCalendars.isEmpty)
    }

    @Test func ifTheCalendarCannotBeRemovedTheSwitchStaysOnAndTheRowSaysSo() async {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        app.setCalendarMirror(true)
        await settle(app)
        store.setFailingCalendarRemoval(true)
        store.setFailingWrites(true)
        app.setCalendarMirror(false)
        await settle(app)
        #expect(app.calendarOffFailed && app.calendarMirrorOn)   // не «выключено» поверх оставшихся событий
        store.setFailingCalendarRemoval(false)
        store.setFailingWrites(false)
        app.setCalendarMirror(false)
        await settle(app)
        #expect(!app.calendarOffFailed && !app.calendarMirrorOn && store.allCalendars.isEmpty)
    }

    // MARK: - Отказ в доступе

    @Test func refusalLeavesTheSwitchOffExplainsWhyAndBreaksNothing() async {
        let store = InMemoryCalendarStore(authorization: .notDetermined, willGrant: false)
        let app = model(store: store)
        let before = app.snapshot
        app.setCalendarMirror(true)
        await settle(app)
        #expect(!app.calendarMirrorOn)
        #expect(app.calendarNeedsSettings)                       // строка ведёт в настройки iPhone
        #expect(store.allCalendars.isEmpty && store.allEvents.isEmpty)
        // Приложение живёт как жило: данные целы, правки идут, ничего не падает.
        app.snapshot.sessions[0].start += 30
        app.persist()
        await settle(app)
        #expect(app.snapshot.sessions.count == before.sessions.count)
        #expect(store.accessRequests == 1)                       // второй раз не спрашиваем
        app.setCalendarMirror(true)
        await settle(app)
        #expect(store.accessRequests == 1)                       // отказали — второй раз система не спрашивает
        #expect(!app.calendarMirrorOn)
    }

    @Test func accessTakenAwayLaterSwitchesTheToggleOffButKeepsTheWish() async {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        app.setCalendarMirror(true)
        await settle(app)
        store.setAuthorization(.denied)
        app.syncCalendarMirror(force: true)
        await settle(app)
        #expect(!app.calendarMirrorOn && app.calendarNeedsSettings && app.calendarWanted)
        let writes = store.writeCounts
        app.snapshot.sessions[0].start += 30; app.persist(); await settle(app)
        #expect(store.writeCounts == writes)
        store.setAuthorization(.allowed)
        app.syncCalendarMirror(force: true)
        await settle(app)
        #expect(app.calendarMirrorOn)
        #expect(store.allEvents.count == 3)                      // ни дубля, ни потери
    }

    // MARK: - Учётная запись

    @Test func choosingAnotherAccountMovesTheCalendarThere() async {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        app.setCalendarMirror(true)
        await settle(app)
        app.setCalendarSource("local")
        await settle(app)
        #expect(app.calendarSourceId == "local" && app.calendarSourceTitle == "На моём iPhone")
        #expect(store.allCalendars.map(\.sourceId) == ["local"] && store.allEvents.count == 3)
    }

    // MARK: - Ссылка из события

    @Test func tappingTheEventOpensTheShootButNeverAForeignOrVanishedOne() {
        let app = model(store: nil)
        #expect(app.openShootLink(CalendarPlan.url(shoot: "w1")))
        #expect(app.cardId == "w1")
        #expect(!app.openShootLink(CalendarPlan.url(shoot: "gone")))
        #expect(!app.openShootLink(URL(string: "lightplan://quest?ans=abc")!))
        #expect(!app.openShootLink(CalendarPlan.url(block: "b1")))
    }

    @Test func withoutACalendarEverythingStaysQuiet() async {
        let app = model(store: nil)
        app.setCalendarMirror(true)
        app.persist()
        await settle(app)
        #expect(!app.calendarAvailable && !app.calendarMirrorOn)
    }
}
