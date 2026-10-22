import Foundation
import Testing
import LightPlanCore
@testable import LightPlanDomain

/// Подвинули в Календаре iPhone (шаг 30.4): отметка «время сдвинуто» с днём, блок помнит, каким был, и запись без жанра
/// остаётся без жанра, пока его не выбрали.
@Suite struct CalendarMoveTests {
    let day = CivilDate(year: 2026, month: 10, day: 20)
    let line: (_ was: (Int, Int), _ now: (Int, Int)) -> String = { "\($0.0)-\($0.1)→\($1.0)-\($1.1)" }

    // MARK: - Сдвиг на другой день

    @Test func movingToAnotherDayLeavesTheSameKindOfTraceWithTheOldDay() {
        var s = Session(id: "a", day: day, start: 840, end: 960, duration: 120)
        #expect(DayDrag.commit(&s, day: day.adding(days: 2), start: 900, end: 1020, line: line))
        #expect(s.day == day.adding(days: 2) && s.start == 900 && s.end == 1020)
        #expect(s.dayMoved == DayMoved(start: 840, end: 960, line: "840-960→900-1020", day: day))
        // Повторный сдвиг: «было» — исходное и по времени, и по дню.
        #expect(DayDrag.commit(&s, day: day.adding(days: 3), start: 960, end: 1080, line: line))
        #expect(s.dayMoved == DayMoved(start: 840, end: 960, line: "840-960→960-1080", day: day))
        #expect(s.notes == "840-960→960-1080")                                 // одна строка, не две
    }

    @Test func movingOnlyTheDayCountsAsAMove() {
        var s = Session(id: "a", day: day, start: 840, end: 960, duration: 120)
        #expect(DayDrag.commit(&s, day: day.adding(days: 1), start: 840, end: 960, line: line))
        #expect(s.dayMoved?.day == day && s.day == day.adding(days: 1))
    }

    @Test func bringingItBackToTheOldDayAndHoursClearsTheTrace() {
        var s = Session(id: "a", day: day, start: 840, end: 960, duration: 120)
        s.notes = "заметка"
        DayDrag.commit(&s, day: day.adding(days: 1), start: 900, end: 1020, line: line)
        #expect(DayDrag.commit(&s, day: day, start: 840, end: 960, line: line))
        #expect(s.dayMoved == nil && s.notes == "заметка" && s.day == day)
    }

    @Test func theDragOnTheRibbonStillNeverTouchesTheDay() {
        var s = Session(id: "a", day: day, start: 840, end: 960, duration: 120)
        DayDrag.commit(&s, start: 900, end: 1020, line: line)
        #expect(s.day == day && s.dayMoved?.day == nil)
    }

    @Test func theTraceDayRoundTripsAndAnOldTraceReadsWithoutIt() throws {
        let m = DayMoved(start: 1, end: 2, line: "x", day: day)
        #expect(try JSONDecoder().decode(DayMoved.self, from: JSONEncoder().encode(m)) == m)
        let old = try JSONDecoder().decode(DayMoved.self, from: Data(#"{"a":600,"b":660,"line":"x"}"#.utf8))
        #expect(old.day == nil && old.start == 600)
    }

    // MARK: - Блок помнит, каким был

    @Test func aBlockRemembersWhatItWasAndForgetsWhenBroughtBack() throws {
        var b = Block(id: "b", kind: .off, from: day); b.allDay = true; b.days = 2
        var was = BlockMoved(from: b.from, allDay: true, days: 2, start: nil, duration: nil)
        #expect(was.matches(b))
        b.movedFrom = was
        b.from = day.adding(days: 3)
        #expect(!was.matches(b))
        let back = try JSONDecoder().decode(Block.self, from: JSONEncoder().encode(b))
        #expect(back == b && back.movedFrom == was)
        b.from = day
        was = try #require(b.movedFrom)
        #expect(was.matches(b))
        let plain = try JSONDecoder().decode(Block.self, from: JSONEncoder().encode(Block(id: "p", kind: .busy, from: day)))
        #expect(plain.movedFrom == nil)
    }

    // MARK: - Запись без жанра

    @Test func aRecordWithoutAGenreStaysWithoutOneThroughTheFormUntilTheGenreIsPicked() {
        var s = Session(id: "n", kind: .shoot, day: day, start: 600, end: 660)
        s.fromCalendar = "Маша"
        var f = EventForm.editing(s)
        #expect(f.genreUnset)
        f.notes = "правка"
        let kept = f.session(orgName: nil, and: " и ")
        #expect(kept.genre == nil && kept.subGenre == nil && kept.notes == "правка" && kept.fromCalendar == "Маша")
        f.pick(.portrait)
        #expect(!f.genreUnset && f.session(orgName: nil, and: " и ").genre == .portrait)
        // Выбор того жанра, что форма показывала по умолчанию, — тоже выбор.
        var g = EventForm.editing(s)
        g.pick(.portrait)
        #expect(g.session(orgName: nil, and: " и ").genre == .portrait)
    }

    @Test func aRecordWithAGenreIsNotUnset() {
        let s = Session(id: "n", kind: .shoot, day: day, start: 600, end: 660, genre: .family)
        #expect(!EventForm.editing(s).genreUnset)
    }
}
