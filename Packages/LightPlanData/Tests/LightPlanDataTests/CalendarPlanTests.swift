import Foundation
import Testing
import LightPlanCore
import LightPlanDomain
@testable import LightPlanData

/// Записи → события (шаг 30.1–2): что зеркалим, в каком поясе и с какой ссылкой (`docs/14`, `docs/16`).
@Suite struct CalendarPlanTests {

    static let day = CivilDate(year: 2026, month: 10, day: 20)
    static let moscow = ZoneID("Europe/Moscow")!
    static let tomsk = ZoneID("Asia/Tomsk")!

    static func context(zones: ZoneCache = ZoneCache(), home: ZoneID = moscow, spots: [Spot] = [], studios: [Studio] = []) -> CalendarPlan.Context {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return CalendarPlan.Context(studios: studios, spots: spots, zones: zones, homeZone: home, calendar: cal,
                                    title: { "T:" + $0.id }, blockTitle: { "B:" + $0.id })
    }

    static func shoot(_ id: String = "s1", kind: RecordKind = .shoot, start: Int = 600, end: Int? = 720) -> Session {
        Session(id: id, kind: kind, day: day, start: start, end: end)
    }

    static func utc(_ day: CivilDate, _ minutes: Int) -> Date {
        WallTime(day: day, minutes: minutes).moment(utcOffsetHours: 0).date
    }

    // MARK: - Что зеркалим

    @Test func shootsMeetingsAndBlocksAreMirroredButNotEventsFromOtherCalendars() {
        let sessions = [Self.shoot("a"), Self.shoot("m", kind: .meet), Self.shoot("e", kind: .event)]
        let blocks = [Block(id: "b", kind: .busy, from: Self.day)]
        let d = CalendarPlan.drafts(sessions: sessions, blocks: blocks, context: Self.context())
        #expect(Set(d.map(\.key)) == ["lightplan://shoot/a", "lightplan://shoot/m", "lightplan://block/b"])
    }

    @Test func theTitleComesFromTheCaller() {
        let d = CalendarPlan.drafts(sessions: [Self.shoot("a")], blocks: [Block(id: "b", kind: .off, from: Self.day)], context: Self.context())
        #expect(Set(d.map(\.title)) == ["T:a", "B:b"])
    }

    @Test func draftsComeOutInTimeOrderWhateverTheInputOrder() {
        let a = Self.shoot("a", start: 900, end: 960), b = Self.shoot("b", start: 600, end: 660)
        let d = CalendarPlan.drafts(sessions: [a, b], blocks: [], context: Self.context())
        #expect(d.map(\.key) == ["lightplan://shoot/b", "lightplan://shoot/a"])
    }

    // MARK: - Время и пояс

    @Test func aPointlessShootIsReadAtTheHomeZone() {
        let d = CalendarPlan.draft(of: Self.shoot(start: 600, end: 720), Self.context())!   // 10:00–12:00 по Москве
        #expect(d.start == Self.utc(Self.day, 7 * 60) && d.end == Self.utc(Self.day, 9 * 60))
        #expect(d.timeZoneId == "Europe/Moscow" && d.offsetSeconds == 10_800)
        #expect(!d.allDay)
    }

    @Test func aShootInAnotherCityKeepsItsOwnZoneWhateverThePhoneIsDoing() {
        var s = Self.shoot(start: 600, end: 720)
        s.latitude = 56.5; s.longitude = 84.97                                            // Томск
        var zones = ZoneCache()
        zones.remember(Self.tomsk, at: GeoCoordinate(latitude: 56.5, longitude: 84.97))
        let d = CalendarPlan.draft(of: s, Self.context(zones: zones))!
        #expect(d.start == Self.utc(Self.day, 3 * 60))                                    // 10:00 UTC+7 = 03:00Z
        #expect(d.timeZoneId == "Asia/Tomsk" && d.offsetSeconds == 25_200)
        // Телефон в другом поясе ничего не меняет: пояс в расчёте — только места съёмки и дома.
        let phoneAtTokyo = CalendarPlan.draft(of: s, Self.context(zones: zones, home: ZoneID("Asia/Tokyo")!))!
        #expect(phoneAtTokyo.start == d.start && phoneAtTokyo.timeZoneId == d.timeZoneId)
    }

    @Test func withoutTheRealZoneTheEstimateByLongitudeStillGivesAnExplicitZone() {
        var s = Self.shoot(start: 600, end: 720)
        s.latitude = 56.5; s.longitude = 84.97
        let d = CalendarPlan.draft(of: s, Self.context())!
        #expect(d.timeZoneId == "GMT+6" && d.offsetSeconds == 21_600)                     // оценка: Томск +6 вместо +7 (docs/16)
        #expect(d.timeZone.secondsFromGMT(for: d.start) == 21_600)
    }

    @Test func aShootPastMidnightEndsOnTheNextDay() {
        let d = CalendarPlan.draft(of: Self.shoot(start: 1320, end: 1560), Self.context())!   // 22:00 – 02:00
        #expect(d.end.timeIntervalSince(d.start) == 4 * 3600)
        #expect(d.end == Self.utc(Self.day.adding(days: 1), 2 * 60 - 3 * 60))
    }

    @Test func aShootWithoutEndUsesItsDurationOrTheDefaultHourAndAHalf() {
        var s = Self.shoot(start: 600, end: nil); s.duration = 45
        #expect(CalendarPlan.draft(of: s, Self.context())!.end.timeIntervalSince(CalendarPlan.draft(of: s, Self.context())!.start) == 45 * 60)
        s.duration = nil
        let d = CalendarPlan.draft(of: s, Self.context())!
        #expect(d.end.timeIntervalSince(d.start) == 90 * 60)
    }

    @Test func aBrokenEndBeforeTheStartNeverProducesAnEventThatEndsBeforeItBegins() {
        let d = CalendarPlan.draft(of: Self.shoot(start: 600, end: 540), Self.context())!
        #expect(d.end > d.start)
    }

    // MARK: - Место

    @Test func theLocationIsNameAndAddressWithCoordinates() {
        var s = Self.shoot()
        s.place = "Парк Горького"; s.placeAddress = "ул. Крымский Вал 9"; s.latitude = 55.73; s.longitude = 37.6
        let d = CalendarPlan.draft(of: s, Self.context())!
        #expect(d.locationTitle == "Парк Горького, ул. Крымский Вал 9")
        #expect(d.latitude == 55.73 && d.longitude == 37.6)
    }

    @Test func theNameIsNotRepeatedWhenTheAddressAlreadyHoldsIt() {
        var s = Self.shoot()
        s.place = "Парк"; s.placeAddress = "Парк Горького, Москва"; s.latitude = 55.7; s.longitude = 37.6
        #expect(CalendarPlan.draft(of: s, Self.context())!.locationTitle == "Парк Горького, Москва")
    }

    @Test func withoutCoordinatesOnlyTheTextOfThePlaceTravels() {
        var s = Self.shoot()
        s.placeTown = "Лобня"
        let d = CalendarPlan.draft(of: s, Self.context())!
        #expect(d.locationTitle == "Лобня" && d.latitude == nil && d.longitude == nil)
        #expect(CalendarPlan.draft(of: Self.shoot(), Self.context())!.locationTitle == nil)
    }

    @Test func aStudioShootTakesTheStudioPoint() {
        var st = Studio(id: "st1", name: "Томсон", latitude: 56.5, longitude: 84.97)
        st.address = "Набережная 7"
        var s = Self.shoot()
        s.route = [RoutePoint(start: 600, end: 700, name: "Студия", studioId: "st1", hallId: nil)]
        let d = CalendarPlan.draft(of: s, Self.context(studios: [st]))!
        #expect(d.latitude == 56.5 && d.longitude == 84.97)
        #expect(d.locationTitle?.contains("Набережная 7") == true)
    }

    // MARK: - Занятое время

    @Test func aBlockForSeveralDaysIsOneAllDayEvent() {
        var b = Block(id: "b", kind: .off, from: Self.day)
        b.allDay = true; b.days = 4
        let d = CalendarPlan.draft(of: b, Self.context())
        #expect(d.allDay && d.timeZoneId == nil)
        let cal = Self.context().calendar
        #expect(cal.dateComponents([.day, .month], from: d.start) == DateComponents(month: 10, day: 20))
        #expect(cal.dateComponents([.day, .month], from: d.end) == DateComponents(month: 10, day: 23))   // последний день включён
    }

    @Test func aBlockWithoutHoursIsAnAllDayEventToo() {
        let d = CalendarPlan.draft(of: Block(id: "b", kind: .busy, from: Self.day), Self.context())
        #expect(d.allDay)
    }

    @Test func aTimedBlockWithoutZonesIsReadAtTheHomeZone() {
        var b = Block(id: "b", kind: .busy, from: Self.day)
        b.start = 600; b.duration = 90
        let d = CalendarPlan.draft(of: b, Self.context())
        #expect(!d.allDay && d.start == Self.utc(Self.day, 7 * 60) && d.end == Self.utc(Self.day, 7 * 60 + 90))
        #expect(d.timeZoneId == "Europe/Moscow")
    }

    @Test func aFlightKeepsTheDepartureZoneAndTheRealTimeInTheAir() {
        var b = Block(id: "b", kind: .flight, from: Self.day)
        b.start = 540; b.duration = 240; b.zoneFrom = 7; b.zoneTo = 3              // 09:00 (UTC+7) → в пути четыре часа
        let d = CalendarPlan.draft(of: b, Self.context())
        #expect(d.start == Self.utc(Self.day, 2 * 60))                             // 09:00 UTC+7 = 02:00Z
        #expect(d.end.timeIntervalSince(d.start) == 4 * 3600)
        #expect(d.timeZoneId == nil && d.offsetSeconds == 25_200)
        #expect(d.timeZone.secondsFromGMT(for: d.start) == 25_200)
    }

    // MARK: - Ссылка

    @Test func theLinkBringsTheCardBack() {
        let u = CalendarPlan.url(shoot: "wm-1")
        #expect(u.absoluteString == "lightplan://shoot/wm-1")
        #expect(CalendarPlan.shootId(in: u) == "wm-1")
        #expect(CalendarPlan.shootId(in: CalendarPlan.url(block: "x")) == nil)
        #expect(CalendarPlan.shootId(in: URL(string: "https://example.com/shoot/a")!) == nil)
        #expect(CalendarPlan.shootId(in: URL(string: "lightplan://shoot")!) == nil)
    }
}
