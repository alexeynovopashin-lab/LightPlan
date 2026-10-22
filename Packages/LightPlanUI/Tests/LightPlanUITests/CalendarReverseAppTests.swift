import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Календарь iPhone в обе стороны (шаг 30.4), со стороны приложения: телефоны и заметки в событии, сдвиг события
/// возвращается в съёмку, событие, заведённое руками, становится черновиком. Календарь — `InMemoryCalendarStore`.
@MainActor
struct CalendarReverseAppTests {

    private struct DryWeather: WeatherSource {
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            HourlyWeather(time: [], cloud: [], temperature: [], windSpeed: [], precipitation: [], weatherCode: [])
        }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { [:] }
    }
    /// Геокодер, который знает пояс: Томск +7.
    private struct TomskGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: "Томск", region: nil, country: "Россия", zoneIdentifier: "Asia/Tomsk")
        }
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
    static let tomsk = GeoCoordinate(latitude: 56.489, longitude: 84.952)

    /// Свадьба Ирины в Москве: клиент с телефоном, пара, заметки, деньги.
    private static func snapshot() -> Snapshot {
        var snap = Snapshot()
        var w = Session(id: "w1", kind: .shoot, day: day, start: 600, end: 840, genre: .wedding)
        w.contact = "Ирина"; w.clientPhone = "8 916 123-45-67"
        w.persons = [Person(name: "Анна", phone: "+7 903 000-00-01")]
        w.notes = "Приезжать за час"
        w.rate = 80_000; w.prepay = 20_000
        w.place = "Парк"; w.placeAddress = "ул. Ленина 5"; w.latitude = 55.75; w.longitude = 37.62
        w.modifiedAt = 1_000
        snap.sessions = [w]
        return snap
    }

    private func model(_ snap: Snapshot = snapshot(), store: InMemoryCalendarStore, memory: InMemoryCalendarMemory = InMemoryCalendarMemory(),
                       geocoder: any ReverseGeocoding = SilentGeocoder(), watch: Bool = false) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-10-19T10:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: geocoder, cityLookup: NoCities(),
                           weatherSource: DryWeather(), now: { now })
        app.attachCalendar(store: store, memory: memory, watch: watch)
        return app
    }

    private func settle(_ app: AppModel) async { await app.calendarChain?.value }

    private func on(_ app: AppModel) async { app.setCalendarMirror(true); await settle(app) }

    private func event(_ store: InMemoryCalendarStore, _ title: String) -> StoredEvent? { store.allEvents.first { $0.title == title } }

    private func edit(_ store: InMemoryCalendarStore, _ id: String, _ change: @escaping (inout StoredEvent) -> Void) {
        store.userEdit(id, change)
    }

    // MARK: - Телефоны и заметки в событии

    @Test func phonesAndNotesTravelButMoneyDoesNot() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        await on(app)
        let notes = event(store, "Свадьба · Анна")?.notes
        #expect(notes == """
        Клиент: Ирина +7 916 123-45-67
        Анна: +7 903 000-00-01

        Приезжать за час
        """)
        #expect(!(notes ?? "").contains("80") && !(notes ?? "").contains("20 000"))
    }

    @Test func aChangedPhoneOrNoteRewritesTheEventOnceAndNothingMore() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        await on(app)
        app.snapshot.sessions[0].clientPhone = "8 916 000-00-00"
        app.snapshot.sessions[0].notes = "Парковка во дворе"
        app.persist(); await settle(app)
        #expect(event(store, "Свадьба · Анна")?.notes?.contains("+7 916 000-00-00") == true)
        #expect(event(store, "Свадьба · Анна")?.notes?.contains("Парковка во дворе") == true)
        let writes = store.writeCounts
        app.persist(); await settle(app)
        app.syncCalendarMirror(force: true); await settle(app)
        #expect(store.writeCounts == writes)
    }

    // MARK: - Сдвинули событие

    @Test func movingTheEventInTheCalendarMovesTheShootAndStampsTheEdit() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        await on(app)
        let e = try #require(event(store, "Свадьба · Анна"))
        edit(store, e.id) { $0 = StoredEvent(id: $0.id, calendarId: $0.calendarId, title: $0.title,
                                             start: $0.start.addingTimeInterval(2 * 3600), end: $0.end.addingTimeInterval(2 * 3600),
                                             allDay: false, offsetSeconds: $0.offsetSeconds, locationTitle: $0.locationTitle,
                                             latitude: $0.latitude, longitude: $0.longitude, url: $0.url, notes: $0.notes,
                                             modified: Date().addingTimeInterval(60)) }
        app.syncCalendarMirror(force: true); await settle(app)
        let s = app.snapshot.sessions[0]
        #expect(s.start == 720 && s.end == 960 && s.day == Self.day)               // 10:00–14:00 → 12:00–16:00
        #expect(s.modifiedAt == app.nowMs && s.modifiedAt != 1_000)                  // метка правки для обмена устройств
        #expect(s.genre == .wedding && s.contact == "Ирина" && s.notes.hasPrefix("Приезжать за час"))   // ниже — строка о сдвиге
        #expect(event(store, "Свадьба · Анна")?.start == e.start.addingTimeInterval(2 * 3600))   // событие на новом месте
        let writes = store.writeCounts
        app.syncCalendarMirror(force: true); await settle(app)
        #expect(store.writeCounts == writes)                                         // сошлось, снова ничего не пишется
    }

    @Test func aPlaceMovedToAnotherCityReadsTheTimeInTheZoneOfTheNewCity() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store, geocoder: TomskGeocoder())
        await on(app)
        let e = try #require(event(store, "Свадьба · Анна"))
        // Те же мгновения (10:00 по Москве), но точка теперь в Томске: на часах Томска это 14:00, а не 13:00 по оценке.
        edit(store, e.id) { $0 = StoredEvent(id: $0.id, calendarId: $0.calendarId, title: $0.title, start: $0.start, end: $0.end,
                                             allDay: false, offsetSeconds: $0.offsetSeconds, locationTitle: "Томск, набережная",
                                             latitude: Self.tomsk.latitude, longitude: Self.tomsk.longitude, url: $0.url,
                                             notes: $0.notes, modified: Date().addingTimeInterval(60)) }
        app.syncCalendarMirror(force: true); await settle(app)
        #expect(app.snapshot.sessions[0].start == 840)
        #expect(event(store, "Свадьба · Анна")?.start == e.start)                  // событие не сдвинулось
    }

    private static let nb = "\u{00A0}"

    /// Человек двинул событие на `hours` часов, а при `days` — ещё и на другой день.
    private func shift(_ store: InMemoryCalendarStore, _ id: String, hours: Double, at: Double = 60) {
        store.userEdit(id) { $0 = StoredEvent(id: $0.id, calendarId: $0.calendarId, title: $0.title,
                                              start: $0.start.addingTimeInterval(hours * 3600), end: $0.end.addingTimeInterval(hours * 3600),
                                              allDay: $0.allDay, offsetSeconds: $0.offsetSeconds, locationTitle: $0.locationTitle,
                                              latitude: $0.latitude, longitude: $0.longitude, url: $0.url, notes: $0.notes,
                                              modified: Date().addingTimeInterval(at)) }
    }

    // MARK: - Отметка «Время сдвинуто в календаре»

    @Test func aShootMovedInTheCalendarGetsTheSameMarkAsAFingerDragWithTheOriginalTimeKept() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        await on(app)
        let nb = Self.nb
        let e = try #require(event(store, "Свадьба · Анна"))
        shift(store, e.id, hours: 2)
        app.syncCalendarMirror(force: true); await settle(app)
        var s = app.snapshot.sessions[0]
        #expect(s.start == 720 && s.end == 960)
        #expect(s.dayMoved?.start == 600 && s.dayMoved?.end == 840 && s.dayMoved?.day == nil)
        let m = try #require(app.cardMoved(s))
        #expect(m.from == "10:00\(nb)–\(nb)14:00" && m.to == "12:00\(nb)–\(nb)16:00")
        #expect(s.notes.contains("время сдвинуто в календаре: 10:00\(nb)–\(nb)14:00 → 12:00\(nb)–\(nb)16:00"))
        #expect(s.notes.hasPrefix("Приезжать за час"))
        // Второй сдвиг: «было» остаётся исходным, а не промежуточным; строка в заметке — одна.
        shift(store, e.id, hours: 1, at: 120)
        app.syncCalendarMirror(force: true); await settle(app)
        s = app.snapshot.sessions[0]
        let again = try #require(app.cardMoved(s))
        #expect(again.from == "10:00\(nb)–\(nb)14:00" && again.to == "13:00\(nb)–\(nb)17:00")
        #expect(s.notes.components(separatedBy: "время сдвинуто в календаре").count == 2)
        // Крестик стирает отметку, и только её.
        app.clearDayMoved(id: "w1")
        #expect(app.cardMoved(app.snapshot.sessions[0]) == nil && app.snapshot.sessions[0].start == 780)
        // Вернули событие на исходное время — после крестика это новая серия, а не «возвращение».
        let back = try #require(event(store, "Свадьба · Анна"))
        shift(store, back.id, hours: -3, at: 180)
        app.syncCalendarMirror(force: true); await settle(app)
        #expect(app.snapshot.sessions[0].start == 600 && app.cardMoved(app.snapshot.sessions[0])?.from == "13:00\(nb)–\(nb)17:00")
    }

    @Test func movingItBackToTheOriginalTimeInTheCalendarClearsTheMark() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        await on(app)
        let e = try #require(event(store, "Свадьба · Анна"))
        shift(store, e.id, hours: 2)
        app.syncCalendarMirror(force: true); await settle(app)
        #expect(app.cardMoved(app.snapshot.sessions[0]) != nil)
        shift(store, e.id, hours: -2, at: 120)
        app.syncCalendarMirror(force: true); await settle(app)
        #expect(app.snapshot.sessions[0].dayMoved == nil && app.snapshot.sessions[0].notes == "Приезжать за час")
    }

    @Test func aShootMovedToAnotherDayShowsDatesInTheMark() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        await on(app)
        let e = try #require(event(store, "Свадьба · Анна"))
        shift(store, e.id, hours: 48)
        app.syncCalendarMirror(force: true); await settle(app)
        let s = app.snapshot.sessions[0]
        #expect(s.day == Self.day.adding(days: 2) && s.start == 600 && s.dayMoved?.day == Self.day)
        let m = try #require(app.cardMoved(s))
        #expect(m.from.hasPrefix("20") && m.to.hasPrefix("22") && m.from.hasSuffix("10:00\(Self.nb)–\(Self.nb)14:00"))
    }

    @Test func aChangeMadeInTheAppItselfSetsNoMark() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        await on(app)
        app.openForm(editing: "w1")
        app.form?.start = 780
        _ = try #require(app.saveForm())
        await settle(app)
        #expect(app.snapshot.sessions[0].dayMoved == nil && app.cardMoved(app.snapshot.sessions[0]) == nil)
        // И время события после этого приложение само передвинуло, а не приняло за сдвиг из Календаря.
        #expect(event(store, "Свадьба · Анна")?.start == WallTime(day: Self.day, minutes: 780).moment(utcOffsetHours: 3).date)
        #expect(app.snapshot.sessions[0].start == 780)
    }

    @Test func aMovedBusyBlockComesBackWithItsOwnMarkAndACross() async throws {
        var snap = Self.snapshot()
        var b = Block(id: "b1", kind: .off, from: Self.day.adding(days: 3)); b.allDay = true; b.days = 2
        var road = Block(id: "b2", kind: .road, from: Self.day); road.start = 600; road.duration = 120
        snap.blocks = [b, road]
        let store = InMemoryCalendarStore()
        let app = model(snap, store: store)
        await on(app)
        // Выходной на два дня сдвинули на сутки позже.
        let off = try #require(event(store, "Выходной"))
        shift(store, off.id, hours: 24)
        // Дорогу — на час.
        let r = try #require(store.allEvents.first { $0.url == CalendarPlan.url(block: "b2") })
        shift(store, r.id, hours: 1, at: 90)
        app.syncCalendarMirror(force: true); await settle(app)
        let moved = try #require(app.snapshot.blocks.first { $0.id == "b1" })
        #expect(moved.from == Self.day.adding(days: 4) && moved.days == 2 && moved.movedFrom?.from == Self.day.adding(days: 3))
        let text = try #require(app.blockMovedText(moved))
        #expect(text.hasPrefix("Время сдвинуто в календаре. Было") && text.contains("23") && text.contains("24") && text.contains("25"))
        let way = try #require(app.snapshot.blocks.first { $0.id == "b2" })
        #expect(way.start == 660 && way.duration == 120)
        #expect(app.blockMovedText(way)?.contains("10:00\(Self.nb)–\(Self.nb)12:00") == true)
        // Повторный сдвиг — «было» то же; сдвиг назад гасит отметку; крестик стирает.
        shift(store, off.id, hours: 24, at: 150)
        app.syncCalendarMirror(force: true); await settle(app)
        #expect(app.snapshot.blocks.first { $0.id == "b1" }?.movedFrom?.from == Self.day.adding(days: 3))
        shift(store, off.id, hours: -48, at: 210)
        app.syncCalendarMirror(force: true); await settle(app)
        let home = try #require(app.snapshot.blocks.first { $0.id == "b1" })
        #expect(home.from == Self.day.adding(days: 3) && home.movedFrom == nil && app.blockMovedText(home) == nil)
        app.clearBlockMoved(id: "b2")
        #expect(app.snapshot.blocks.first { $0.id == "b2" }?.movedFrom == nil)
        #expect(app.snapshot.blocks.first { $0.id == "b2" }?.start == 660)
    }

    // MARK: - Без жанра

    @Test func aShootWithoutAGenreIsCalledPhotoShootAndTheDraftKeepsItsMarkUntilFilled() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        await on(app)
        _ = handMade(store)
        app.syncCalendarMirror(force: true); await settle(app)
        var d = try #require(app.snapshot.sessions.first { $0.id != "w1" })
        let w = PlannerWords(lexicon: app.lexicon, orgs: [])
        #expect(w.typeName(d) == "Черновик")
        // Заполнили клиента, жанр оставили пустым: уже не черновик, и называется «Фотосъёмка».
        app.openForm(editing: d.id)
        app.form?.contact = "Маша"
        _ = try #require(app.saveForm())
        await settle(app)
        d = try #require(app.snapshot.sessions.first { $0.id == d.id })
        #expect(d.genre == nil && d.contact == "Маша" && !d.isCalendarDraft)
        #expect(w.typeName(d) == "Фотосъёмка")
        #expect(store.allEvents.contains { $0.title == "Фотосъёмка · Маша" })
    }

    @Test func aMovedPlaceReturnsToo() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        await on(app)
        let e = try #require(event(store, "Свадьба · Анна"))
        edit(store, e.id) { $0 = StoredEvent(id: $0.id, calendarId: $0.calendarId, title: $0.title, start: $0.start, end: $0.end,
                                             allDay: false, offsetSeconds: $0.offsetSeconds, locationTitle: "Набережная",
                                             latitude: 55.7, longitude: 37.6, url: $0.url, notes: $0.notes,
                                             modified: Date().addingTimeInterval(60)) }
        app.syncCalendarMirror(force: true); await settle(app)
        let s = app.snapshot.sessions[0]
        #expect(s.place == "Набережная" && s.latitude == 55.7 && s.longitude == 37.6)
        #expect(event(store, "Свадьба · Анна")?.locationTitle == "Набережная")
    }

    @Test func renamingOrRewritingNotesInTheCalendarChangesNothingInTheShoot() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        await on(app)
        let before = app.snapshot.sessions[0]
        let e = try #require(event(store, "Свадьба · Анна"))
        edit(store, e.id) { $0 = StoredEvent(id: $0.id, calendarId: $0.calendarId, title: "Чужое название", start: $0.start, end: $0.end,
                                             allDay: false, offsetSeconds: $0.offsetSeconds, locationTitle: $0.locationTitle,
                                             latitude: $0.latitude, longitude: $0.longitude, url: $0.url, notes: "другой текст",
                                             modified: Date().addingTimeInterval(60)) }
        app.syncCalendarMirror(force: true); await settle(app)
        #expect(app.snapshot.sessions[0] == before)                                  // запись не тронута ни байтом
        #expect(event(store, "Свадьба · Анна")?.notes?.hasPrefix("Клиент: Ирина") == true)   // а событие вернулось как у нас
        #expect(store.allEvents.count == 1)
    }

    @Test func deletingTheEventDeletesNoShootAndTheEventComesBack() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        await on(app)
        store.userDeleteEvent(store.allEvents[0].id)
        app.syncCalendarMirror(force: true); await settle(app)
        #expect(app.snapshot.sessions.count == 1)
        #expect(store.allEvents.count == 1 && store.allEvents[0].url == CalendarPlan.url(shoot: "w1"))
    }

    @Test func theAppReactsToTheCalendarChangingWithoutBeingOpenedAgain() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store, watch: true)
        await on(app)
        let e = try #require(event(store, "Свадьба · Анна"))
        edit(store, e.id) { $0 = StoredEvent(id: $0.id, calendarId: $0.calendarId, title: $0.title,
                                             start: $0.start.addingTimeInterval(3600), end: $0.end.addingTimeInterval(3600),
                                             allDay: false, offsetSeconds: $0.offsetSeconds, locationTitle: $0.locationTitle,
                                             latitude: $0.latitude, longitude: $0.longitude, url: $0.url, notes: $0.notes,
                                             modified: Date().addingTimeInterval(60)) }
        // «База изменилась» — сверка сама, через секунду тишины.
        for _ in 0..<60 where app.snapshot.sessions[0].start != 660 { try? await Task.sleep(for: .milliseconds(100)); await settle(app) }
        #expect(app.snapshot.sessions[0].start == 660)
    }

    @Test func aCalendarThatKeepsRewritingOurFieldsDoesNotMakeTheAppRewriteForever() async throws {
        // Система нормализует заметки по-своему, и событие всегда «расходится». Уведомление базы будит проход, проход
        // пишет, запись будит уведомление… Цепочка обязана оборваться сама.
        let store = InMemoryCalendarStore()
        store.setNormalizingNotes(true)
        let app = model(store: store, watch: true)
        app.calendarSettle = .milliseconds(30)
        await on(app)
        try await Task.sleep(for: .milliseconds(1200))
        await settle(app)
        let after = store.writeCounts.saves
        try await Task.sleep(for: .milliseconds(600))
        await settle(app)
        #expect(store.writeCounts.saves == after)         // остановилась
        #expect(after <= 8)                                // и не раскрутилась
        // Прошло время, и человек действительно подвинул событие — уведомление не глохнет под старым счётчиком.
        app.calendarStreakWindow = 0.2
        try await Task.sleep(for: .milliseconds(400))
        let ev = try #require(event(store, "Свадьба · Анна"))
        store.userEdit(ev.id) { $0 = StoredEvent(id: $0.id, calendarId: $0.calendarId, title: $0.title,
                                                 start: $0.start.addingTimeInterval(3600), end: $0.end.addingTimeInterval(3600),
                                                 allDay: false, offsetSeconds: $0.offsetSeconds, locationTitle: $0.locationTitle,
                                                 latitude: $0.latitude, longitude: $0.longitude, url: $0.url, notes: $0.notes,
                                                 modified: Date().addingTimeInterval(60)) }
        for _ in 0..<40 where app.snapshot.sessions[0].start != 660 { try await Task.sleep(for: .milliseconds(50)); await settle(app) }
        #expect(app.snapshot.sessions[0].start == 660)
        // Вернулись в приложение — человек рядом, проход разрешён снова.
        app.syncCalendarMirror(force: true); await settle(app)
        #expect(store.writeCounts.saves >= after + 1)
    }

    // MARK: - Черновики

    private func handMade(_ store: InMemoryCalendarStore, title: String = "Маша фотосессия", notes: String? = "в парке",
                          hour: Int = 15, location: String? = nil, lat: Double? = nil, lon: Double? = nil) -> String {
        let start = WallTime(day: Self.day.adding(days: 1), minutes: hour * 60).moment(utcOffsetHours: 3).date
        return store.userAdd(title: title, start: start, end: start.addingTimeInterval(3600), calendarId: store.allCalendars[0].id,
                             location: location, latitude: lat, longitude: lon, notes: notes)
    }

    @Test func aHandMadeEventBecomesOneDraftShootAndKeepsItsTitle() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        await on(app)
        let id = handMade(store)
        app.syncCalendarMirror(force: true); await settle(app)
        #expect(app.snapshot.sessions.count == 2)
        let d = try #require(app.snapshot.sessions.first { $0.id != "w1" })
        #expect(d.isCalendarDraft && d.kind == .shoot && d.genre == nil && d.contact.isEmpty)
        #expect(d.fromCalendar == "Маша фотосессия" && d.day == Self.day.adding(days: 1) && d.start == 900 && d.end == 960)
        #expect(d.notes == "Маша фотосессия\nв парке" && d.modifiedAt == app.nowMs)
        let ev = try #require(store.allEvents.first { $0.id == id })
        #expect(ev.url == CalendarPlan.url(shoot: d.id) && ev.title == "Маша фотосессия")      // событие получило ссылку, название осталось
        #expect(ev.notes == "Маша фотосессия\nв парке")
        #expect(store.allEvents.count == 2)
        // На планировщике — «Черновик» и текст, как его написал человек.
        let w = PlannerWords(lexicon: app.lexicon, orgs: [])
        #expect(w.typeName(d) == "Черновик" && w.clientName(d) == "Маша фотосессия")
    }

    @Test func repeatedPassesAndAReinstallMakeNoSecondDraft() async throws {
        let store = InMemoryCalendarStore()
        let memory = InMemoryCalendarMemory()
        let app = model(store: store, memory: memory)
        await on(app)
        _ = handMade(store)
        for _ in 0..<3 { app.syncCalendarMirror(force: true); await settle(app) }
        #expect(app.snapshot.sessions.count == 2 && store.allEvents.count == 2)
        // Переустановка: память устройства стёрта, данные и календарь на месте.
        app.attachCalendar(store: store, memory: InMemoryCalendarMemory())
        await settle(app)
        app.setCalendarMirror(true); await settle(app)
        app.syncCalendarMirror(force: true); await settle(app)
        #expect(app.snapshot.sessions.count == 2 && store.allEvents.count == 2 && store.allCalendars.count == 1)
    }

    @Test func movingADraftEventInTheCalendarMovesTheDraftAndFillingItMakesItAnOrdinaryShoot() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        await on(app)
        let id = handMade(store)
        app.syncCalendarMirror(force: true); await settle(app)
        let e = try #require(store.allEvents.first { $0.id == id })
        edit(store, id) { $0 = StoredEvent(id: $0.id, calendarId: $0.calendarId, title: $0.title, start: $0.start.addingTimeInterval(3600),
                                           end: $0.end.addingTimeInterval(3600), allDay: false, offsetSeconds: $0.offsetSeconds,
                                           locationTitle: nil, latitude: nil, longitude: nil, url: $0.url, notes: $0.notes,
                                           modified: Date().addingTimeInterval(60)) }
        app.syncCalendarMirror(force: true); await settle(app)
        var d = try #require(app.snapshot.sessions.first { $0.id != "w1" })
        #expect(d.start == 960 && d.isCalendarDraft)
        // Фотограф заполнил жанр и клиента: это обычная съёмка, и событие называется как все.
        d.genre = .portrait; d.contact = "Маша"
        app.snapshot.sessions[try #require(app.snapshot.sessions.firstIndex { $0.id == d.id })] = d
        app.persist(); await settle(app)
        #expect(!d.isCalendarDraft)
        #expect(store.allEvents.first { $0.id == e.id }?.title == "Портрет · Маша")
    }

    @Test func trashingADraftRemovesItsEventLikeAnyShoot() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        await on(app)
        _ = handMade(store)
        app.syncCalendarMirror(force: true); await settle(app)
        let d = try #require(app.snapshot.sessions.first { $0.id != "w1" })
        app.trashSession(id: d.id); await settle(app)
        #expect(store.allEvents.count == 1 && app.snapshot.sessions.count == 1)
    }

    @Test func eventsThatAreNotShootsStayUntouchedInTheCalendar() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store)
        await on(app)
        let cal = store.allCalendars[0].id
        let start = WallTime(day: Self.day, minutes: 600).moment(utcOffsetHours: 3).date
        let allDay = store.userAdd(title: "Отпуск", start: start, end: start.addingTimeInterval(86_400), calendarId: cal, allDay: true)
        let weekly = store.userAdd(title: "Планёрка", start: start, end: start.addingTimeInterval(3600), calendarId: cal, recurring: true)
        app.syncCalendarMirror(force: true); await settle(app)
        #expect(app.snapshot.sessions.count == 1)
        #expect(store.allEvents.contains { $0.id == allDay && $0.url == nil } && store.allEvents.contains { $0.id == weekly && $0.url == nil })
    }

    // MARK: - Пояс

    @Test func theZoneOfAShootIsLearnedBeforeItsEventIsWritten() async throws {
        // Томск по долготе — +6, на деле +7: событие стояло на час раньше, пока не открыта карточка (дефект 30.1–3).
        var snap = Self.snapshot()
        snap.sessions[0].latitude = Self.tomsk.latitude; snap.sessions[0].longitude = Self.tomsk.longitude
        let store = InMemoryCalendarStore()
        let app = model(snap, store: store, geocoder: TomskGeocoder())
        await on(app)
        let e = try #require(event(store, "Свадьба · Анна"))
        // 10:00 по Томску (+7) = 03:00 UTC.
        #expect(e.start == WallTime(day: Self.day, minutes: 600).moment(utcOffsetHours: 7).date)
        #expect(app.place.zones.zone(at: Self.tomsk)?.identifier == "Asia/Tomsk")
    }

    @Test func withoutNetworkTheEstimateStaysAndNothingBreaks() async throws {
        var snap = Self.snapshot()
        snap.sessions[0].latitude = Self.tomsk.latitude; snap.sessions[0].longitude = Self.tomsk.longitude
        let store = InMemoryCalendarStore()
        let app = model(snap, store: store, geocoder: SilentGeocoder())
        await on(app)
        #expect(event(store, "Свадьба · Анна")?.start == WallTime(day: Self.day, minutes: 600).moment(utcOffsetHours: 6).date)
    }

    @Test func aDraftWithAPlaceReadsTheEventInTheZoneOfThatPlace() async throws {
        let store = InMemoryCalendarStore()
        let app = model(store: store, geocoder: TomskGeocoder())
        await on(app)
        // 15:00 по Томску: человек заводил событие там.
        let start = WallTime(day: Self.day.adding(days: 1), minutes: 900).moment(utcOffsetHours: 7).date
        let id = store.userAdd(title: "Катя", start: start, end: start.addingTimeInterval(3600), calendarId: store.allCalendars[0].id,
                               offsetSeconds: 25_200, location: "Набережная", latitude: Self.tomsk.latitude, longitude: Self.tomsk.longitude)
        app.syncCalendarMirror(force: true); await settle(app)
        let d = try #require(app.snapshot.sessions.first { $0.id != "w1" })
        #expect(d.start == 900)                                                       // 15:00 на часах места, не 14:00
        #expect(store.allEvents.first { $0.id == id }?.start == start)                // событие не сдвинулось
    }
}
