import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Чужие календари призраками (шаг 30.5), со стороны приложения: тумблер и право, лента дня (полоса справа), неделя,
/// плашка формы, лист «Занять». Календарь телефона — `InMemoryCalendarStore`; данные чтения — в `GhostCalendarsTests`.
@MainActor
struct GhostAppTests {

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

    static let zone = ZoneID("Europe/Moscow")!
    /// Суббота, матч сына.
    static let day = CivilDate(year: 2026, month: 10, day: 24)
    static func at(_ d: CivilDate, _ m: Int) -> Date { WallTime(day: d, minutes: m).moment(in: zone).date }
    /// «На весь день» по часам телефона (в тесте — часы машины), конец — 23:59:59, как отдаёт EventKit.
    static func allDay(_ d: CivilDate, days: Int = 1) -> (start: Date, end: Date) {
        let a = Calendar.current.date(from: DateComponents(year: d.year, month: d.month, day: d.day))!
        return (a, Calendar.current.date(byAdding: .day, value: days, to: a)!.addingTimeInterval(-1))
    }
    /// Промежуток, как его пишет приложение: тире с неразрывными пробелами.
    static func span(_ a: String, _ b: String) -> String { a + "\u{00A0}–\u{00A0}" + b }

    struct Rig {
        let app: AppModel
        let store: InMemoryCalendarStore
        let memory: InMemoryGhostMemory
        let work, son, holidays: String
    }

    /// Приложение в Москве, «сегодня» — 24 октября; в календаре телефона три календаря.
    private func rig(auth: CalendarAuthorization = .allowed, mode: GhostCalendarsDefault = .allPersonal,
                     on: Bool = true, watch: Bool = false, snapshot: Snapshot = Snapshot()) async -> Rig {
        let now = ISO8601DateFormatter().date(from: "2026-10-24T08:00:00+03:00")!
        let app = AppModel(snapshot: snapshot, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: DryWeather(), now: { now })
        app.planner.pickInStrip(Self.day)
        let store = InMemoryCalendarStore(authorization: auth)
        let work = store.userAddCalendar(title: "Работа", type: .exchange, source: "Exchange")
        let son = store.userAddCalendar(title: "Сын", type: .account)
        let holidays = store.userAddCalendar(title: "Праздники", type: .subscription, source: "Подписки")
        let memory = InMemoryGhostMemory(GhostRecord(on: on))
        app.calendarSettle = .milliseconds(20)
        app.attachCalendar(store: store, memory: InMemoryCalendarMemory(), watch: watch, ghosts: memory, ghostMode: mode)
        await app.calendarChain?.value
        await app.ghostLoad?.value
        return Rig(app: app, store: store, memory: memory, work: work, son: son, holidays: holidays)
    }

    private func load(_ app: AppModel) async {
        await app.calendarChain?.value
        await app.ghostLoad?.value
    }

    // MARK: - Тумблер и право

    @Test func withoutAccessTheSwitchExplainsFirstAndOnlyThenTheSystemAsks() async {
        let r = await rig(auth: .notDetermined, on: false)
        #expect(!r.app.ghostsOn)
        r.app.setGhosts(true)
        await load(r.app)
        #expect(r.app.ghostAsk)                              // сперва объяснение
        #expect(r.store.accessRequests == 0)                 // системный запрос ещё не показан
        #expect(!r.app.ghostsOn)
        r.app.answerGhostAsk(yes: false)
        await load(r.app)
        #expect(r.store.accessRequests == 0 && !r.app.ghostsOn && !r.memory.record.on)
        r.app.setGhosts(true)
        await load(r.app)
        r.app.answerGhostAsk(yes: true)
        await load(r.app)
        #expect(r.store.accessRequests == 1)
        #expect(r.app.ghostsOn && r.memory.record.on)
    }

    @Test func refusedAccessLeavesTheSwitchOffAndAsksNothingAgain() async {
        let r = await rig(auth: .denied, on: false)
        r.app.setGhosts(true)
        await load(r.app)
        #expect(!r.app.ghostsOn && !r.app.ghostAsk && r.app.calendarNeedsSettings)
        #expect(r.store.accessRequests == 0)
    }

    @Test func accessAlreadyGivenByTheMirrorTurnsGhostsOnWithoutAsking() async {
        let r = await rig(on: false)
        r.app.setGhosts(true)
        await load(r.app)
        #expect(r.app.ghostsOn && !r.app.ghostAsk && r.store.accessRequests == 0)
    }

    @Test func switchingOffClearsEverythingInMemory() async {
        let r = await rig()
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son)
        r.app.setGhosts(false); await load(r.app)
        r.app.setGhosts(true); await load(r.app)
        #expect(r.app.ghostList.map(\.title) == ["Матч"])
        r.app.setGhosts(false)
        await load(r.app)
        #expect(r.app.ghostList.isEmpty && !r.app.ghostsOn)
        let f = PlannerFacts(app: r.app, dark: false)
        #expect(f.ghostParts(on: Self.day).isEmpty && f.ghostAllDay(on: Self.day).isEmpty)
    }

    // MARK: - Календари и режим по умолчанию

    @Test func listAndDefaultsFollowTheMode() async {
        let a = await rig(mode: .allPersonal)
        await a.app.refreshGhostFacts()
        #expect(a.app.ghostChoices.filter(\.shown).map(\.calendar.title).sorted() == ["Работа", "Сын"])
        #expect(a.app.ghostChoices.map(\.calendar.title).contains("Праздники"))            // в списке есть, но без галочки
        let n = await rig(mode: .none)
        await n.app.refreshGhostFacts()
        #expect(n.app.ghostChoices.filter(\.shown).isEmpty)
        #expect(n.app.ghostPicked == 0)
    }

    @Test func tickingACalendarShowsItsEventsAndUntickingHidesThem() async {
        let r = await rig(mode: .none)
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son)
        await r.app.reloadGhosts()
        #expect(r.app.ghostList.isEmpty)
        r.app.setGhostCalendar(r.son, shown: true)
        await load(r.app)
        #expect(r.app.ghostList.map(\.title) == ["Матч"])
        #expect(r.app.ghostChoices.first { $0.id == r.son }?.shown == true)
        r.app.setGhostCalendar(r.son, shown: false)
        await load(r.app)
        #expect(r.app.ghostList.isEmpty)
        #expect(r.memory.record.picks[r.son] == false)
    }

    // MARK: - Живое чтение

    @Test func aChangeInTheCalendarBaseBringsTheNewGhostWithoutReopening() async throws {
        let r = await rig(watch: true)
        #expect(r.app.ghostList.isEmpty)
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son)
        for _ in 0..<100 where r.app.ghostList.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(r.app.ghostList.map(\.title) == ["Матч"])
    }

    @Test func aBurstOfChangesIsOneRead() async throws {
        let r = await rig(watch: true)
        let before = r.store.eventReads
        for i in 0..<6 {
            r.store.userAdd(title: "С\(i)", start: Self.at(Self.day, 600 + i * 10), end: Self.at(Self.day, 640 + i * 10), calendarId: r.son)
        }
        for _ in 0..<100 where r.app.ghostList.count < 6 { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(r.app.ghostList.count == 6)
        // Два календаря личных → по два чтения на проход; всплеск из шести записей — один проход, а не шесть.
        #expect(r.store.eventReads - before <= 4)
    }

    @Test func walkingToADayOutsideTheWindowReadsAgainAndInsideItDoesNot() async {
        let r = await rig()
        r.store.userAdd(title: "Далеко", start: Self.at(Self.day.adding(days: 200), 600), end: Self.at(Self.day.adding(days: 200), 700), calendarId: r.son)
        let reads = r.store.eventReads
        r.app.ghostsEnsure(around: Self.day.adding(days: 20))              // внутри окна
        await load(r.app)
        #expect(r.store.eventReads == reads)
        r.app.ghostsEnsure(around: Self.day.adding(days: 200))             // за окном
        await load(r.app)
        #expect(r.store.eventReads > reads)
        #expect(r.app.ghostList.map(\.title) == ["Далеко"])
    }

    // MARK: - Лента дня

    @Test func theDayStripGetsTimedPartsAndTheAllDayBandSeparately() async {
        let r = await rig()
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 705), calendarId: r.son)
        r.store.userAdd(title: "Отпуск", start: Self.allDay(Self.day).start, end: Self.allDay(Self.day).end, calendarId: r.work, allDay: true)
        await r.app.reloadGhosts()
        let f = PlannerFacts(app: r.app, dark: false)
        let parts = f.ghostParts(on: Self.day)
        #expect(parts.map(\.ghost.title) == ["Матч"] && parts[0].start == 600 && parts[0].end == 705)
        #expect(f.ghostAllDay(on: Self.day).map(\.title) == ["Отпуск"])
        #expect(f.ghostParts(on: Self.day.adding(days: 1)).isEmpty)
    }

    @Test func ghostsDoNotEnterTheDayItemsSoNothingCanBeDraggedOrSelected() async {
        // Призрак не `DayItem`: ни выделения, ни ручек, ни удержания — у ленты для него нет даже записи.
        let r = await rig()
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son)
        await r.app.reloadGhosts()
        let f = PlannerFacts(app: r.app, dark: false)
        #expect(f.items(on: Self.day).isEmpty)
        #expect(DayLanes.layout(f.items(on: Self.day)).isEmpty)
    }

    @Test func aDayWithoutGhostsKeepsItsFullWidth() {
        #expect(GhostRail.layout([], width: 393).width == 0)
        #expect(GhostRail.layout([], width: 393) == .empty)
    }

    private func part(_ id: String, _ a: Int, _ b: Int) -> GhostPart {
        let g = Ghost(id: id, calendarId: "c", calendarTitle: "К", title: id, start: Self.at(Self.day, a), end: Self.at(Self.day, b), allDay: false)
        return GhostPart(ghost: g, start: a, end: b, fromYesterday: false, intoTomorrow: false)
    }

    @Test func oneGhostTakesOneColumnWithinTheShareOfTheStrip() {
        let rail = GhostRail.layout([part("a", 600, 700)], width: 393)
        #expect(rail.columns == 1 && rail.cells.count == 1 && !rail.cells[0].collapsed)
        // 393 pt: после черты часов (70) остаётся 323; полоса — не больше 40 % этого, колонок влезает 2 по 64,6 pt.
        #expect(GhostRail.capacity(width: 393) == 2)
        #expect(abs(rail.colWidth - 64.6) < 0.01)
        #expect(rail.width <= (393 - 70) * GhostRail.share)
        let r = rail.frame(of: rail.cells[0], width: 393)
        #expect(r.maxX <= 393 - DayLanes.gap + 0.001 && r.minX >= 393 - rail.width - 0.001)
        #expect(r.minY == DayLanes.top(600) && r.height == DayLanes.top(700) - DayLanes.top(600))
    }

    @Test func tinyGhostsKeepTheMinimumBlockHeight() {
        let rail = GhostRail.layout([part("a", 600, 605)], width: 393)
        #expect(rail.cells[0].height == DayLanes.minHeight)
    }

    @Test func twoOverlappingGhostsStandSideBySideWhenTheyFit() {
        let rail = GhostRail.layout([part("a", 600, 700), part("b", 630, 720)], width: 393)
        #expect(rail.columns == 2 && rail.cells.count == 2 && rail.cells.allSatisfy { !$0.collapsed })
        #expect(Set(rail.cells.map(\.column)) == [0, 1])
        let a = rail.frame(of: rail.cells[0], width: 393), b = rail.frame(of: rail.cells[1], width: 393)
        #expect(a.maxX <= b.minX && b.maxX <= 393)
        #expect(rail.width <= (393 - 70) * GhostRail.share + 0.001)
    }

    @Test func moreOverlappingGhostsThanColumnsCollapseIntoOnePlusN() throws {
        let parts = [part("a", 600, 700), part("b", 610, 700), part("c", 620, 700), part("d", 630, 700)]
        let rail = GhostRail.layout(parts, width: 393)             // 4 в сцепке, колонок 2
        #expect(rail.columns == 2)
        #expect(rail.cells.count == 2)
        let more = try #require(rail.cells.first { $0.collapsed })
        #expect(more.parts.count == 3 && more.column == 1)         // первый стоит сам, три схлопнулись
        #expect(rail.cells.flatMap(\.parts).count == 4)             // никто не потерян
        // Схлопнутый блок накрывает время всех трёх.
        #expect(more.top == DayLanes.top(610) && more.bottom == DayLanes.top(700))
    }

    @Test func aNarrowStripFitsOneColumnAndCollapsesEarlier() {
        #expect(GhostRail.capacity(width: 320) == 1)
        let rail = GhostRail.layout([part("a", 600, 700), part("b", 630, 720)], width: 320)
        #expect(rail.columns == 1 && rail.cells.count == 1 && rail.cells[0].collapsed && rail.cells[0].parts.count == 2)
        #expect(rail.width <= (320 - 70) * GhostRail.share + 0.001)
    }

    @Test func separateGhostsInDifferentHoursShareOneColumn() {
        let rail = GhostRail.layout([part("a", 600, 660), part("b", 840, 900), part("c", 1000, 1100)], width: 393)
        #expect(rail.columns == 1 && rail.cells.count == 3)
    }

    @Test func shootsNarrowOnlyBesideAGhostAndKeepFullWidthInOtherHours() {
        let two = GhostRail.layout([part("a", 600, 700), part("b", 630, 720)], width: 393)
        let one = GhostRail.layout([part("a", 600, 700)], width: 393)
        func band(_ a: Int, _ b: Int) -> (CGFloat, CGFloat) { (CGFloat(DayLanes.top(a)), CGFloat(DayLanes.top(b))) }
        // Утро, до призраков: полная ширина.
        #expect(two.reserve(top: band(300, 400).0, bottom: band(300, 400).1) == 0)
        #expect(one.reserve(top: band(800, 900).0, bottom: band(800, 900).1) == 0)
        // Рядом с одиночным призраком — на одну колонку; рядом с парой — на обе.
        #expect(abs(one.reserve(top: band(620, 650).0, bottom: band(620, 650).1) - one.colWidth) < 0.001)
        #expect(abs(two.reserve(top: band(640, 690).0, bottom: band(640, 690).1) - two.width) < 0.001)
        // Только рядом с левым из двух (второй ещё не начался) — всё равно обе колонки: левый стоит левее правого.
        #expect(abs(two.reserve(top: band(600, 620).0, bottom: band(600, 620).1) - two.width) < 0.001)
        // Встык — не «рядом»: блок кончается, где призрак начинается.
        #expect(one.reserve(top: band(500, 600).0, bottom: band(500, 600).1) == 0)
    }

    @Test func aTouchOnAGhostIsFoundAndAnEmptyHourIsNot() {
        let rail = GhostRail.layout([part("a", 600, 700)], width: 393)
        let r = rail.frame(of: rail.cells[0], width: 393)
        #expect(rail.hit(CGPoint(x: r.midX, y: r.midY), width: 393) != nil)
        #expect(rail.hit(CGPoint(x: 100, y: r.midY), width: 393) == nil)                  // слева — лента съёмок
        #expect(rail.hit(CGPoint(x: r.midX, y: r.maxY + 40), width: 393) == nil)          // ниже — пустой час
    }

    @Test func theSharedLaneAlgorithmStillPlacesShootsAsBefore() {
        // `DayLanes.place` вынесен из `layout` для призраков: съёмки раскладываются прежним образом.
        func item(_ a: Int, _ b: Int, _ id: String) -> DayItem {
            DayItem(kind: .shoot, start: a, end: b, fromYesterday: false, intoTomorrow: false,
                    session: Session(id: id, kind: .shoot, day: Self.day, start: a, end: b), block: nil)
        }
        let slots = DayLanes.layout([item(600, 700, "a"), item(620, 700, "b"), item(660, 720, "c"), item(900, 960, "d"),
                                     item(1020, 1080, "e"), item(1080, 1140, "f")])
        #expect(slots.map { $0?.column } == [0, 1, 2, 0, 0, 0])
        #expect(slots.map { $0?.columns } == [3, 3, 3, 1, 1, 1])                  // встык — не сцепка
    }

    // MARK: - Неделя

    @Test func theWeekListsAllDayFirstThenTimedAndCapsTheRows() async {
        let r = await rig()
        r.store.userAdd(title: "Отпуск", start: Self.allDay(Self.day).start, end: Self.allDay(Self.day).end, calendarId: r.work, allDay: true)
        for i in 0..<4 {
            r.store.userAdd(title: "С\(i)", start: Self.at(Self.day, 600 + i * 120), end: Self.at(Self.day, 660 + i * 120), calendarId: r.son)
        }
        await r.app.reloadGhosts()
        let f = PlannerFacts(app: r.app, dark: false)
        let rows = GhostWeekRows.rows(f, Self.day)
        #expect(rows.map(\.ghost.title) == ["Отпуск", "С0", "С1", "С2", "С3"])
        #expect(rows[0].time == "весь день" && rows[1].time == Self.span("10:00", "11:00"))
        #expect(GhostWeekRows.rowCap == 3)
        #expect(GhostWeekRows.rows(f, Self.day.adding(days: 1)).isEmpty)
    }

    // MARK: - Форма

    private func form(_ app: AppModel, day: CivilDate = day, start: Int, duration: Int = 60) -> EventForm {
        app.openForm(day: day, start: start, fromLight: false)
        app.form?.duration = duration
        return app.form!
    }

    @Test func theFormWarnsSoftlyAboutAGhostAndNamesCalendarEventAndTime() async throws {
        let r = await rig()
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 705), calendarId: r.son)
        await r.app.reloadGhosts()
        let f = form(r.app, start: 630, duration: 60)
        let w = try #require(r.app.formGhostWarning(f))
        #expect(w.title == "Время пересекается")
        #expect(w.message == "В это время в календаре «Сын»: Матч, " + Self.span("10:00", "11:45") + ".")
        #expect(r.app.formWarning(f)?.message == w.message)               // и в плашке формы тоже
        #expect(r.app.formSaveBlock(f) == nil)                             // и ничего не запрещает
    }

    @Test func theFormIsSilentWhenTimesOnlyTouchOrGhostsAreOff() async {
        let r = await rig()
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son)
        await r.app.reloadGhosts()
        #expect(r.app.formGhostWarning(form(r.app, start: 700, duration: 60)) == nil)       // встык
        #expect(r.app.formGhostWarning(form(r.app, start: 420, duration: 60)) == nil)       // раньше
        #expect(r.app.formGhostWarning(form(r.app, start: 620, duration: 30)) != nil)
        r.app.setGhosts(false); await load(r.app)
        #expect(r.app.formGhostWarning(form(r.app, start: 620, duration: 30)) == nil)
    }

    @Test func theFormStaysSilentTheMomentAccessIsTakenAwayEvenBeforeTheListIsRefreshed() async {
        let r = await rig()
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son)
        await r.app.reloadGhosts()
        #expect(r.app.formGhostWarning(form(r.app, start: 620, duration: 30)) != nil)
        r.app.calendarAuth = .denied                                       // право забрали в настройках iPhone, список ещё не обновился
        #expect(!r.app.ghostsOn && !r.app.ghostList.isEmpty)
        #expect(r.app.formGhostWarning(form(r.app, start: 620, duration: 30)) == nil)
        #expect(PlannerFacts(app: r.app, dark: false).ghostParts(on: Self.day).isEmpty)
    }

    @Test func theFormMentionsAnAllDayGhostAndCountsTheRest() async {
        let r = await rig()
        r.store.userAdd(title: "Отпуск жены", start: Self.allDay(Self.day).start, end: Self.allDay(Self.day).end, calendarId: r.work, allDay: true)
        await r.app.reloadGhosts()
        #expect(r.app.formGhostWarning(form(r.app, start: 600))?.message == "В этот день в календаре «Работа»: Отпуск жены.")
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son)
        await r.app.reloadGhosts()
        #expect(r.app.formGhostWarning(form(r.app, start: 620))?.message.hasSuffix("И ещё 1.") == true)
    }

    @Test func aNightShootWarnsAboutTheAllDayEventOfTheNextDay() async {
        let r = await rig()
        let next = Self.day.adding(days: 1)
        r.store.userAdd(title: "Отпуск жены", start: Self.allDay(next).start, end: Self.allDay(next).end, calendarId: r.work, allDay: true)
        await r.app.reloadGhosts()
        // Съёмка с 22:00 на четыре часа заходит за полночь — в следующие сутки, где у жены отпуск.
        #expect(r.app.formGhostWarning(form(r.app, start: 1320, duration: 240))?.message == "В этот день в календаре «Работа»: Отпуск жены.")
        // Короткая вечерняя съёмка до полуночи следующего дня не касается.
        #expect(r.app.formGhostWarning(form(r.app, start: 1200, duration: 60)) == nil)
    }

    @Test func aRealShootClashStillWinsOverTheGhostNote() async {
        var snap = Snapshot()
        snap.sessions = [Session(id: "s1", kind: .shoot, day: Self.day, start: 600, end: 720, genre: .portrait)]
        let r = await rig(snapshot: snap)
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son)
        await r.app.reloadGhosts()
        let f = form(r.app, start: 630, duration: 60)
        #expect(r.app.formWarning(f)?.message.contains("Матч") == false)
    }

    // MARK: - «Занять»

    @Test func occupyCreatesExactlyOneBusyBlockAndTheGhostStaysAGhost() async throws {
        var snap = Snapshot()
        snap.sessions = [Session(id: "s1", kind: .shoot, day: Self.day.adding(days: 3), start: 600, end: 700, genre: .portrait)]
        let r = await rig(snapshot: snap)
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 705), calendarId: r.son)
        await r.app.reloadGhosts()
        let g = try #require(r.app.ghostList.first)
        #expect(!r.app.ghostIsTaken(g))
        #expect(r.app.occupy(g))
        #expect(r.app.snapshot.blocks.count == 1 && r.app.snapshot.sessions.count == 1)
        let b = r.app.snapshot.blocks[0]
        #expect(b.kind == .busy && b.note == "Матч" && b.from == Self.day && b.start == 600 && b.duration == 105 && !b.allDay)
        #expect(r.app.ghostIsTaken(g))
        #expect(!r.app.occupy(g))                                          // второй раз — не дубль
        #expect(r.app.snapshot.blocks.count == 1)
        #expect(r.app.ghostList.count == 1)                                // сам призрак на месте
        #expect(r.store.writeCounts.saves == 0)                            // в Календарь ничего не записано (зеркало выключено)
    }

    @Test func tappingAGhostOnlyOpensTheSheetAndChangesNoData() async {
        let r = await rig()
        r.store.userAdd(title: "Матч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son)
        await r.app.reloadGhosts()
        let before = r.app.snapshot
        let g = r.app.ghostList[0]
        r.app.ghostSheet = GhostSheetTarget(ghosts: [g])
        #expect(r.app.snapshot.blocks == before.blocks && r.app.snapshot.sessions == before.sessions)
        #expect(r.app.ghostSheet?.ghosts == [g])
    }

    // MARK: - В данные не попадает

    @Test func noGhostDataEverReachesTheSnapshotOrTheDisk() async throws {
        let r = await rig()
        r.store.userAdd(title: "СекретныйМатч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: r.son,
                        location: "СекретныйСтадион", notes: "СекретныеЗаметки")
        await r.app.reloadGhosts()
        #expect(r.app.ghostList.count == 1)
        // «Занять» кладёт в данные название события — это воля человека; но не место, не заметки и не имя календаря.
        _ = r.app.occupy(r.app.ghostList[0])
        let json = String(decoding: try JSONEncoder().encode(r.app.snapshot), as: UTF8.self)
        #expect(json.contains("СекретныйМатч"))
        #expect(!json.contains("СекретныйСтадион") && !json.contains("СекретныеЗаметки") && !json.contains("Сын"))
        // До «Занять» — ни слова.
        let clean = await rig()
        clean.store.userAdd(title: "СекретныйМатч", start: Self.at(Self.day, 600), end: Self.at(Self.day, 700), calendarId: clean.son)
        await clean.app.reloadGhosts()
        #expect(!String(decoding: try JSONEncoder().encode(clean.app.snapshot), as: UTF8.self).contains("СекретныйМатч"))
        #expect(!String(decoding: (clean.memory.record.picks.description + "\(clean.memory.record.on)").utf8, as: UTF8.self).contains("СекретныйМатч"))
    }
}
