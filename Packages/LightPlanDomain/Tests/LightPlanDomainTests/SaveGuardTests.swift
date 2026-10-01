import Testing
import Foundation
import LightPlanCore
@testable import LightPlanDomain

/// Съёмку нельзя сохранить на занятое время (слово Алексея 01.10: «занято — это занято, я не хочу случайно поставить
/// съёмку на время, которое занято концертом дочери или поездкой»).
@Suite struct SaveGuardTests {

    private struct Utc: ZoneResolving {
        func utcOffsetHours(latitude: Double, longitude: Double, on day: CivilDate) -> Double { 0 }
    }
    private let ctx = ClashContext(zones: Utc(), appOffsetHours: 0, travel: { _, _ in .unavailable }, travelThreshold: 30, eventsLayer: true)
    private static let d = CivilDate(year: 2026, month: 10, day: 10)

    /// «Концерт дочери» 18:00–21:00 десятого.
    private func concert(kind: BlockKind = .busy) -> Block {
        var b = Block(id: "b1", kind: kind, from: Self.d)
        b.note = "Концерт дочери"
        b.start = 1080
        b.duration = 180
        return b
    }

    private func form(start: Int, minutes: Int, day: CivilDate = SaveGuardTests.d) -> EventForm {
        var f = EventForm.new(id: "n", day: day, start: start, fromLight: true, genre: .portrait, light: nil, step: 5)
        f.start = start     // пресет жанра переставляет время — ставим руками
        f.duration = minutes
        return f
    }

    private func verdict(_ f: EventForm, _ blocks: [Block]) -> SaveGuard.Verdict {
        SaveGuard.verdict(f, blocks: blocks, context: ctx, point: nil)
    }

    @Test func formWithoutDateCannotBeSaved() {
        var f = form(start: 600, minutes: 60)
        #expect(verdict(f, []) == .ok, "обычная новая форма сохраняется")
        f.dayUnset = true
        #expect(verdict(f, []) == .noDate)
        f.setStart(minute: 660)
        #expect(verdict(f, []) == .noDate, "время дату не называет")
        f.setStart(day: Self.d)
        #expect(verdict(f, []) == .ok && !f.dayUnset, "выбор даты снимает запрет")
    }

    @Test func shootOverlappingBusyTimeIsRefusedAndNamesIt() {
        let v = verdict(form(start: 1050, minutes: 60), [concert()])
        guard case .busy(let hit) = v else { Issue.record("ждали запрет, вышло \(v)"); return }
        #expect(hit.blockIndex == 0 && !hit.allDay && hit.from == 1080 && hit.to == 1260, "«Концерт дочери» 18:00–21:00")
    }

    @Test func boundariesTouchingAreFreeOverlapByAMinuteIsNot() {
        let b = [concert()]
        #expect(verdict(form(start: 1020, minutes: 60), b) == .ok, "кончается ровно в 18:00 — свободно")
        #expect(verdict(form(start: 1260, minutes: 60), b) == .ok, "начинается ровно в 21:00 — свободно")
        #expect(verdict(form(start: 1020, minutes: 61), b) != .ok, "на минуту заходит в занятое")
        #expect(verdict(form(start: 1259, minutes: 60), b) != .ok, "на минуту раньше конца занятого")
        #expect(verdict(form(start: 1100, minutes: 30), b) != .ok, "целиком внутри")
        #expect(verdict(form(start: 960, minutes: 400), b) != .ok, "накрывает занятое")
    }

    @Test func wholeDayAndOtherDaysAndKinds() {
        var vac = Block(id: "v", kind: .off, from: CivilDate(year: 2026, month: 10, day: 9))
        vac.allDay = true
        vac.days = 3
        #expect(verdict(form(start: 600, minutes: 60), [vac]) != .ok, "отпуск 9–11 держит весь десятый")
        #expect(verdict(form(start: 600, minutes: 60, day: CivilDate(year: 2026, month: 10, day: 12)), [vac]) == .ok, "двенадцатого свободно")
        #expect(verdict(form(start: 1100, minutes: 60), [concert(kind: .road)]) == .ok, "своя дорога — не запрет, остаётся предупреждением")
        #expect(verdict(form(start: 1100, minutes: 60), [concert(kind: .flight)]) == .ok)
        #expect(verdict(form(start: 1100, minutes: 60), [concert(kind: .off)]) != .ok, "«Выходной» по часам — тоже занято")
    }

    @Test func meetingMayStandOnBusyTime() {
        var f = form(start: 1100, minutes: 60)
        f.mode = .meet
        #expect(verdict(f, [concert()]) == .ok, "запрет — для съёмки, не для разговора")
    }

    @Test func repeatCopyOnBusyDayIsRefusedWithItsDate() {
        var f = form(start: 600, minutes: 60)
        f.repeatRule = .week
        f.repeatCount = 3
        var blk = Block(id: "v", kind: .busy, from: CivilDate(year: 2026, month: 10, day: 17))
        blk.allDay = true
        let v = verdict(f, [blk])
        guard case .busy(let hit) = v else { Issue.record("копия на занятом дне должна быть запрещена: \(v)"); return }
        #expect(hit.day == CivilDate(year: 2026, month: 10, day: 17))
    }

    @Test func editingWithoutMovingTimeIsNotBlockedByLaterBusy() {
        var s = Session(id: "s", kind: .shoot, day: Self.d, start: 1100, end: 1160, duration: 60, genre: .portrait)
        s.contact = "Ира"
        var f = EventForm.editing(s)
        f.notes = "подправил заметку"
        #expect(verdict(f, [concert()]) == .ok, "время не трогали — съёмка, что стояла, не запрещается")
        f.setStart(minute: 1110)
        #expect(verdict(f, [concert()]) != .ok, "сдвинул время внутрь занятого — запрет")
        f.setStart(minute: 600)
        #expect(verdict(f, [concert()]) == .ok, "увёл на свободное — можно")
    }

    @Test func shootGrownFromMeetIsAlwaysChecked() {
        var meet = Session(id: "m", kind: .meet, day: Self.d, start: 600, end: 660, duration: 60, genre: .portrait)
        meet.contact = "Ира"
        var f = EventForm.editing(MeetGrow.draft(from: meet, shootId: "s", day: Self.d, start: 1100, duration: 60))
        f.growFrom = "m"
        #expect(verdict(f, [concert()]) != .ok)
    }
}
