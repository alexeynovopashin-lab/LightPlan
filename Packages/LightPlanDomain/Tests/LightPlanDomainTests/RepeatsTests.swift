import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Повтор съёмки: даты группы, копия и черновик (веб `repDates`, `repCopy`, `repDraft`).
@Suite struct RepeatsTests {
    func d(_ y: Int, _ m: Int, _ day: Int) -> CivilDate { CivilDate(year: y, month: m, day: day) }

    @Test func monthSkipsMissingDayInsteadOfShifting() {
        // Веб: «31 января → 31 марта → 31 мая»; пропуски в счёт не идут.
        #expect(Repeats.dates(from: d(2027, 1, 31), rule: .month, count: 3) == [d(2027, 1, 31), d(2027, 3, 31), d(2027, 5, 31)])
        #expect(Repeats.dates(from: d(2028, 2, 29), rule: .year, count: 2) == [d(2028, 2, 29), d(2032, 2, 29)])
        // 2100 не високосный: 2096 → 2104
        #expect(Repeats.dates(from: d(2096, 2, 29), rule: .year, count: 2) == [d(2096, 2, 29), d(2104, 2, 29)])
    }

    @Test func weekRulesStepByDays() {
        #expect(Repeats.dates(from: d(2026, 12, 28), rule: .week, count: 3) == [d(2026, 12, 28), d(2027, 1, 4), d(2027, 1, 11)])
        #expect(Repeats.dates(from: d(2026, 10, 3), rule: .week2, count: 2) == [d(2026, 10, 3), d(2026, 10, 17)])
        #expect(Repeats.dates(from: d(2026, 10, 31), rule: .day, count: 2) == [d(2026, 10, 31), d(2026, 11, 1)])
        #expect(Repeats.dates(from: d(2026, 11, 15), rule: .month, count: 3).last == d(2027, 1, 15))
    }

    @Test func copyDropsFactsOfOneCard() {
        var s = Session(id: "a", day: d(2026, 10, 3), start: 600, duration: 90, genre: .portrait)
        s.contact = "Ольга"; s.notes = "рано\nПеренесено с 2 окт."
        s.dayMoved = DayMoved(start: 540, end: 630, line: "\nПеренесено с 2 окт.")
        s.prepay = 2000; s.delivered = true; s.fromMeetId = "m1"; s.grewToId = "g1"
        s.questSent = Date(timeIntervalSince1970: 1_780_000_000)
        let home = RepeatHome(town: "Томск", latitude: 56.48, longitude: 84.95)
        let info = Repeat(group: "g", rule: .week, index: 2, count: 3)
        let all = Repeats.copy(s, id: "b", day: d(2026, 10, 10), info: info, blocks: Set(RepeatBlock.allCases), home: home)
        #expect(all.id == "b" && all.day == d(2026, 10, 10) && all.repeatInfo == info)
        #expect(all.contact == "Ольга" && all.notes == "рано", "строка сдвига остаётся у сдвинутой карточки")
        #expect(all.prepay == 0 && !all.delivered && all.fromMeetId == nil && all.grewToId == nil && all.questSent == nil)
        #expect(all.dayMoved == nil && all.start == 600 && all.duration == 90)

        let bare = Repeats.copy(s, id: "c", day: d(2026, 10, 17), info: info, blocks: [], home: home)
        #expect(bare.contact.isEmpty && bare.notes.isEmpty)
        #expect(bare.placeTown == "Томск" && bare.latitude == 56.48 && bare.longitude == 84.95 && bare.placeIsCity)
    }

    @Test func makeNumbersTheGroup() {
        var s = Session(id: "a", day: d(2026, 10, 3), start: 600, duration: 90, genre: .portrait)
        var n = 0
        let copies = Repeats.make(&s, rule: .week, count: 4, blocks: RepeatBlock.defaults,
                                  home: RepeatHome(town: "", latitude: 0, longitude: 0), group: "g") { n += 1; return "n\(n)" }
        #expect(s.repeatInfo == Repeat(group: "g", rule: .week, index: 1, count: 4))
        #expect(copies.map(\.id) == ["n1", "n2", "n3"] && copies.map { $0.repeatInfo!.index } == [2, 3, 4])
        #expect(Repeats.place(of: "n2", group: "g", in: [s] + copies)! == (3, 4))
        // Удалённая выпадает из счёта, номера за ней сдвигаются.
        #expect(Repeats.place(of: "n2", group: "g", in: [s, copies[0], copies[2], copies[1]].filter { $0.id != "n1" })! == (2, 3))
    }

    @Test func repeatLivesInDraftOnlyWhenChosen() throws {
        var f = EventForm.new(id: "x1", day: d(2026, 10, 3), start: 600, fromLight: false, mode: .shoot, genre: .portrait,
                              prefs: nil, light: nil)
        f.notes = "x"
        f.repeatRule = .month; f.repeatCount = 7; f.setRepeat(block: .client, on: false)
        let data = try #require(f.draftData())
        let back = try #require(EventForm.fromDraft(data))
        #expect(back.repeatRule == .month && back.repeatCount == 7 && !back.repeatBlocks.contains(.client))
        #expect(back.repeatDates.count == 7)
        // Карточка из группы повтора не выбирает — строка у неё только сведения.
        var s = f.session(orgName: nil, and: " и ")
        s.repeatInfo = Repeat(group: "g", rule: .month, index: 1, count: 7)
        #expect(!EventForm.editing(s).repeatEditable && EventForm.editing(s).repeatDates.isEmpty)
    }
}
