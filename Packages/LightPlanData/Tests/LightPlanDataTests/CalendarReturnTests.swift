import Foundation
import Testing
import LightPlanCore
import LightPlanDomain
@testable import LightPlanData

/// Что из Календаря возвращается в запись и что едет в событие заметками (шаг 30.4).
@Suite struct CalendarReturnTests {

    typealias P = CalendarPlanTests
    static let day = P.day
    static let words = CalendarNotes.Words(client: "Клиент", contact: "Контакт", phone: "Телефон")
    static let ru = TelCountry.of("RU") ?? TelCountry.fallback

    /// Событие по часам Москвы (+3): `start` и `end` — минуты суток `day`.
    static func event(start: Int, end: Int, day: CivilDate = day, offset: Double = 3, location: String? = nil,
                      lat: Double? = nil, lon: Double? = nil, title: String = "Что-то", notes: String? = nil,
                      url: URL? = nil, allDay: Bool = false, recurring: Bool = false) -> StoredEvent {
        let s = WallTime(day: day, minutes: start).moment(utcOffsetHours: offset).date
        let e = WallTime(day: day, minutes: end).moment(utcOffsetHours: offset).date
        return StoredEvent(id: "ev", calendarId: "cal", title: title, start: s, end: e, allDay: allDay,
                           offsetSeconds: Int(offset * 3600), locationTitle: location, latitude: lat, longitude: lon,
                           url: url, notes: notes, modified: nil, recurring: recurring)
    }

    // MARK: - Заметки

    @Test func phonesComeFirstThenTheNotes() {
        var s = P.shoot()
        s.contact = "Ирина"; s.clientPhone = "8 916 123-45-67"
        s.persons = [Person(name: "Анна", phone: "+7 903 000-00-01"), Person(name: "Игорь", phone: "")]
        s.orderPerson = "Мария"; s.orderPhone = "+7 495 111-22-33"
        s.notes = "Приезжать за час.\nПарковка во дворе."
        let t = CalendarNotes.text(of: s, country: Self.ru, words: Self.words)
        #expect(t == """
        Клиент: Ирина +7 916 123-45-67
        Анна: +7 903 000-00-01
        Контакт: Мария +7 495 111-22-33

        Приезжать за час.
        Парковка во дворе.
        """)
    }

    @Test func moneyAndDocumentsNeverTravel() {
        var s = P.shoot()
        s.rate = 50_000; s.prepay = 10_000; s.expense = 3_000; s.brief = "ТЗ секретное"
        s.docs = [Attachment(source: .link, name: "Договор.pdf", url: "https://example.com/d")]
        s.contact = "Ирина"; s.clientPhone = "+7 916 123-45-67"
        let t = CalendarNotes.text(of: s, country: Self.ru, words: Self.words) ?? ""
        #expect(t == "Клиент: Ирина +7 916 123-45-67")
        #expect(!t.contains("50") && !t.contains("Договор") && !t.contains("ТЗ"))
    }

    @Test func aPhoneTypedInTheContactLineIsNotRepeatedInTheName() {
        var s = P.shoot()
        s.contact = "Ирина · +7 916 123-45-67"; s.clientPhone = "+7 916 123-45-67"
        #expect(CalendarNotes.text(of: s, country: Self.ru, words: Self.words) == "Клиент: Ирина +7 916 123-45-67")
    }

    @Test func aPersonWithoutANameIsLabelledWithThePhoneWord() {
        var s = P.shoot()
        s.persons = [Person(name: "", phone: "+7 903 000-00-01")]
        #expect(CalendarNotes.text(of: s, country: Self.ru, words: Self.words) == "Телефон: +7 903 000-00-01")
    }

    @Test func nothingToSayMeansNoNotes() {
        #expect(CalendarNotes.text(of: P.shoot(), country: Self.ru, words: Self.words) == nil)
        var s = P.shoot(); s.notes = "  \n "
        #expect(CalendarNotes.text(of: s, country: Self.ru, words: Self.words) == nil)
    }

    @Test func notesOnlyWithoutPhones() {
        var s = P.shoot(); s.notes = "Платье красное"
        #expect(CalendarNotes.text(of: s, country: Self.ru, words: Self.words) == "Платье красное")
    }

    @Test func theSameDataGivesTheSameBytes() {
        var s = P.shoot(); s.contact = "Ирина"; s.clientPhone = "8 916 123-45-67"; s.notes = "заметка"
        let a = CalendarNotes.text(of: s, country: Self.ru, words: Self.words)
        let b = CalendarNotes.text(of: s, country: Self.ru, words: Self.words)
        #expect(a == b && a != nil)
    }

    @Test func theDraftCarriesTheNotesAndTheRecordMark() {
        var ctx = P.context()
        ctx.notes = { _ in "N" }
        var s = P.shoot(); s.modifiedAt = 123
        let d = CalendarPlan.draft(of: s, ctx)!
        #expect(d.notes == "N" && d.recordModified == 123)
    }

    // MARK: - Подвинули событие

    @Test func movingTheEventMovesTheShootInItsOwnZone() {
        let s = P.shoot(start: 600, end: 720)                                             // 10:00–12:00 по Москве
        let out = CalendarPlan.applying(Self.event(start: 900, end: 1020), to: s, P.context())!   // 15:00–17:00
        #expect(out.day == Self.day && out.start == 900 && out.end == 1020 && out.duration == 120)
    }

    @Test func aShootInTomskReadsTheEventInTomskHoursNotThePhonesHours() {
        var s = P.shoot(start: 600, end: 720)
        s.latitude = 56.489; s.longitude = 84.952
        var zones = ZoneCache(); zones.remember(P.tomsk, at: GeoCoordinate(latitude: 56.489, longitude: 84.952))
        let ctx = P.context(zones: zones)
        // 15:00 по Томску (+7) — это 11:00 по Москве.
        let e = Self.event(start: 15 * 60, end: 16 * 60, offset: 7)
        let out = CalendarPlan.applying(e, to: s, ctx)!
        #expect(out.start == 900 && out.end == 960)
    }

    @Test func movingPastMidnightKeepsTheMinutesOfTheFirstDay() {
        let s = P.shoot(start: 1200, end: 1320)                                           // 20:00–22:00
        let e = StoredEvent(id: "ev", calendarId: "c", title: "t",
                            start: WallTime(day: Self.day, minutes: 22 * 60).moment(utcOffsetHours: 3).date,
                            end: WallTime(day: Self.day, minutes: 26 * 60).moment(utcOffsetHours: 3).date,
                            allDay: false, offsetSeconds: 10_800, locationTitle: nil, latitude: nil, longitude: nil, url: nil)
        let out = CalendarPlan.applying(e, to: s, P.context())!
        #expect(out.day == Self.day && out.start == 1320 && out.end == 1560 && out.duration == 240)
    }

    @Test func movingToAnotherDayChangesTheDay() {
        let s = P.shoot(start: 600, end: 720)
        let next = Self.day.adding(days: 2)
        let out = CalendarPlan.applying(Self.event(start: 600, end: 720, day: next), to: s, P.context())!
        #expect(out.day == next && out.start == 600)
    }

    @Test func anUnchangedEventChangesNothing() {
        let s = P.shoot(start: 600, end: 720)
        #expect(CalendarPlan.applying(Self.event(start: 600, end: 720), to: s, P.context()) == nil)
    }

    @Test func aShootWithoutAnExplicitEndIsNotRewrittenWhenOnlyThePlaceMoves() {
        var s = P.shoot(start: 600, end: nil)                                             // конец по умолчанию, +90 минут
        s.place = "Парк"
        let out = CalendarPlan.applying(Self.event(start: 600, end: 690, location: "Набережная"), to: s, P.context())!
        #expect(out.place == "Набережная" && out.end == s.end && out.duration == s.duration)
    }

    @Test func aNewPlaceReplacesThePlaceButNotTheTitleNotesOrClient() {
        var s = P.shoot(start: 600, end: 720)
        s.place = "Парк"; s.placeAddress = "ул. Ленина 5"; s.latitude = 56.5; s.longitude = 84.97
        s.contact = "Ирина"; s.notes = "заметка"; s.genre = .wedding
        let e = Self.event(start: 600, end: 720, location: "Набережная\nул. Мира 1", lat: 56.4, lon: 84.9, title: "переименовал", notes: "другой текст")
        let out = CalendarPlan.applying(e, to: s, P.context())!
        #expect(out.place == "Набережная, ул. Мира 1" && out.placeAddress == "" && out.latitude == 56.4 && out.longitude == 84.9)
        #expect(out.contact == "Ирина" && out.notes == "заметка" && out.genre == .wedding)
    }

    @Test func aLocationTheEventLostClearsThePoint() {
        var s = P.shoot(start: 600, end: 720)
        s.place = "Парк"; s.latitude = 56.5; s.longitude = 84.97
        let out = CalendarPlan.applying(Self.event(start: 600, end: 720), to: s, P.context())!
        #expect(out.place == "" && out.latitude == nil && out.longitude == nil)
    }

    @Test func aStudioIsABookingSoOnlyTheTimeComesBack() {
        var studio = Studio(id: "st1", name: "Томсон", latitude: 55.75, longitude: 37.62)
        studio.address = "Москва"
        var s = P.shoot(start: 600, end: 720)
        s.studioId = "st1"; s.place = "Томсон"; s.latitude = 55.75; s.longitude = 37.62
        let ctx = P.context(studios: [studio])
        let out = CalendarPlan.applying(Self.event(start: 660, end: 780, location: "Другое место", lat: 1, lon: 2), to: s, ctx)!
        #expect(out.place == "Томсон" && out.latitude == 55.75)
        #expect(out.start == 660 && out.end == 780)
    }

    @Test func busyTimeAndAllDayEventsAreNotReturned() {
        let ev = Self.event(start: 600, end: 720, allDay: true)
        #expect(CalendarPlan.applying(ev, to: P.shoot(), P.context()) == nil)
        #expect(CalendarPlan.applying(Self.event(start: 660, end: 780), to: P.shoot(kind: .event), P.context()) == nil)
    }

    // MARK: - Подвинули занятое время

    static func block(allDay: Bool = false, days: Int = 1, start: Int? = nil, duration: Int? = nil, zoneFrom: Double? = nil) -> Block {
        var b = Block(id: "b1", kind: .off, from: day)
        b.allDay = allDay; b.days = days; b.start = start; b.duration = duration; b.zoneFrom = zoneFrom
        return b
    }

    /// Событие «на весь день» по дням телефона (часы Москвы, как у `P.context`): конец — как читает его EventKit, 23:59:59.
    static func allDayEvent(from a: CivilDate, to z: CivilDate) -> StoredEvent {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let s = cal.date(from: DateComponents(year: a.year, month: a.month, day: a.day))!
        let e = cal.date(from: DateComponents(year: z.year, month: z.month, day: z.day, hour: 23, minute: 59, second: 59))!
        return StoredEvent(id: "ev", calendarId: "c", title: "Выходной", start: s, end: e, allDay: true, offsetSeconds: 0,
                           locationTitle: nil, latitude: nil, longitude: nil, url: nil)
    }

    @Test func anAllDayBlockMovedInTheCalendarKeepsItsLengthInDaysFromTheEvent() {
        let b = Self.block(allDay: true, days: 2)                                            // 20–21 октября
        let out = CalendarPlan.applying(Self.allDayEvent(from: Self.day.adding(days: 3), to: Self.day.adding(days: 5)), to: b, P.context())!
        #expect(out.from == Self.day.adding(days: 3) && out.days == 3 && out.allDay)          // растянули: 23–25
        #expect(CalendarPlan.applying(Self.allDayEvent(from: Self.day, to: Self.day.adding(days: 1)), to: b, P.context()) == nil)   // как было
    }

    @Test func aTimedBlockMovedInTheCalendarMovesItsHoursInTheHomeZone() {
        let b = Self.block(start: 600, duration: 120)                                        // 10:00–12:00 по Москве
        let out = CalendarPlan.applying(Self.event(start: 900, end: 1050), to: b, P.context())!
        #expect(out.from == Self.day && out.start == 900 && out.duration == 150)
        let next = CalendarPlan.applying(Self.event(start: 540, end: 600, day: Self.day.adding(days: 1)), to: b, P.context())!
        #expect(next.from == Self.day.adding(days: 1) && next.start == 540 && next.duration == 60)
    }

    @Test func aFlightKeepsTheDepartureZone() {
        let b = Self.block(start: 540, duration: 240, zoneFrom: 7)                           // 09:00 по Томску
        let e = Self.event(start: 15 * 60, end: 16 * 60, offset: 7)                          // подвинули на 15:00 по Томску
        let out = CalendarPlan.applying(e, to: b, P.context())!
        #expect(out.start == 900 && out.duration == 60 && out.zoneFrom == 7)
    }

    @Test func aBlockEventOfTheOtherKindIsNotTakenBack() {
        // «На весь день» стало событием по часам — перепишется как у нас.
        #expect(CalendarPlan.applying(Self.event(start: 600, end: 660), to: Self.block(allDay: true), P.context()) == nil)
        #expect(CalendarPlan.applying(Self.allDayEvent(from: Self.day, to: Self.day), to: Self.block(start: 600, duration: 60), P.context()) == nil)
        #expect(CalendarPlan.applying(Self.event(start: 660, end: 720, recurring: true), to: Self.block(start: 600, duration: 60), P.context()) == nil)
    }

    @Test func allDayFactsCompareByDaysSoAnEventThatEndsAt235959IsNotSeenAsMovedEveryPass() {
        let ev = Self.allDayEvent(from: Self.day, to: Self.day.adding(days: 1))
        let cal = Calendar.current
        let draft = EventDraft(title: "Выходной", start: ev.start, end: cal.startOfDay(for: ev.end), allDay: true,
                               url: CalendarPlan.url(block: "b1"))
        #expect(EventFacts(event: ev).isClose(to: EventFacts(draft: draft)))
    }

    // MARK: - Черновик

    @Test func aHandMadeEventBecomesADraftShoot() {
        let e = Self.event(start: 900, end: 960, location: "Парк", lat: 55.75, lon: 37.62, title: "  Маша фотосессия ", notes: "в парке")
        let s = CalendarPlan.newDraft(from: e, id: "n1", modifiedAt: 99, P.context())!
        #expect(s.id == "n1" && s.kind == .shoot && s.genre == nil && s.contact.isEmpty)
        #expect(s.fromCalendar == "Маша фотосессия" && s.isCalendarDraft)
        #expect(s.day == Self.day && s.start == 900 && s.end == 960 && s.duration == 60)
        #expect(s.place == "Парк" && s.latitude == 55.75 && s.longitude == 37.62)
        #expect(s.notes == "Маша фотосессия\nв парке")
        #expect(s.modifiedAt == 99)
    }

    @Test func theDraftReadsTheEventInTheZoneOfItsPlaceSoTheMirrorWouldWriteTheSameInstants() {
        var zones = ZoneCache(); zones.remember(P.tomsk, at: GeoCoordinate(latitude: 56.489, longitude: 84.952))
        let ctx = P.context(zones: zones)
        let e = Self.event(start: 15 * 60, end: 16 * 60, offset: 7, location: "Парк", lat: 56.489, lon: 84.952)   // 15:00 по Томску
        let s = CalendarPlan.newDraft(from: e, id: "n", modifiedAt: 1, ctx)!
        #expect(s.start == 900)                                                           // 15:00 на часах места съёмки
        let back = CalendarPlan.draft(of: s, ctx)!
        #expect(back.start == e.start && back.end == e.end)                               // и обратно — те же мгновения
    }

    @Test func aDraftWithoutAPlaceUsesTheHomeZone() {
        let e = Self.event(start: 900, end: 960)
        let s = CalendarPlan.newDraft(from: e, id: "n", modifiedAt: 1, P.context())!
        #expect(s.start == 900 && s.latitude == nil)
    }

    @Test func anotherLinkOfTheEventIsKeptInTheNotes() {
        let e = Self.event(start: 900, end: 960, title: "Звонок", url: URL(string: "https://zoom.us/j/1"))
        #expect(CalendarPlan.newDraft(from: e, id: "n", modifiedAt: 1, P.context())!.notes == "Звонок\nhttps://zoom.us/j/1")
    }

    @Test func eventsThatCannotBeAShootGiveNoDraft() {
        let c = P.context()
        #expect(CalendarPlan.newDraft(from: Self.event(start: 0, end: 1440, allDay: true), id: "n", modifiedAt: 1, c) == nil)
        #expect(CalendarPlan.newDraft(from: Self.event(start: 600, end: 660, recurring: true), id: "n", modifiedAt: 1, c) == nil)
        #expect(CalendarPlan.newDraft(from: Self.event(start: 0, end: 30 * 60), id: "n", modifiedAt: 1, c) == nil)
    }

    @Test func aDraftStopsBeingOneOnceTheGenreOrTheClientIsFilled() {
        var s = Session(id: "n", kind: .shoot, day: Self.day, start: 600)
        s.fromCalendar = "Маша"
        #expect(s.isCalendarDraft)
        var withGenre = s; withGenre.genre = .portrait
        var withClient = s; withClient.contact = "Маша"
        #expect(!withGenre.isCalendarDraft && !withClient.isCalendarDraft)
        #expect(!Session(id: "x", kind: .shoot, day: Self.day, start: 600).isCalendarDraft)   // не из Календаря
    }

    @Test func theMarkSurvivesTheSnapshotRoundTripAndAnOlderSnapshotReadsWithoutIt() throws {
        var s = Session(id: "n", kind: .shoot, day: Self.day, start: 600)
        s.fromCalendar = "Маша"
        let back = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(s))
        #expect(back.fromCalendar == "Маша" && back.extra["calTitle"] == nil)
        let plain = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(Session(id: "p", kind: .shoot, day: Self.day, start: 600)))
        #expect(plain.fromCalendar == nil)
    }
}
