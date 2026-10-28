import Testing
import LightPlanCore
@testable import LightPlanDomain

private func d(_ y: Int, _ m: Int, _ day: Int) -> CivilDate { CivilDate(year: y, month: m, day: day) }

/// Начало недели (Алексей 28.10): понедельник — умолчание веба, воскресенье и суббота — по выбору.
@Suite struct WeekStartTests {

    /// Четверг 24.09.2026 и его неделя при каждом начале.
    @Test func startOfWeek() {
        let thu = d(2026, 9, 24)
        #expect(WeekStart.monday.start(of: thu) == d(2026, 9, 21))
        #expect(WeekStart.sunday.start(of: thu) == d(2026, 9, 20))
        #expect(WeekStart.saturday.start(of: thu) == d(2026, 9, 19))
        // Сам первый день и последний день недели.
        #expect(WeekStart.monday.start(of: d(2026, 9, 27)) == d(2026, 9, 21))   // воскресенье — конец недели
        #expect(WeekStart.sunday.start(of: d(2026, 9, 27)) == d(2026, 9, 27))   // воскресенье — начало
        #expect(WeekStart.saturday.start(of: d(2026, 9, 26)) == d(2026, 9, 26))
        #expect(WeekStart.monday.start(of: d(1969, 12, 31)) == d(1969, 12, 29))
        #expect(WeekStart.sunday.start(of: d(1969, 12, 31)) == d(1969, 12, 28))
    }

    @Test func weeksAreSevenConsecutiveDays() {
        for ws in WeekStart.allCases {
            let w = ws.week(of: d(2026, 12, 31))
            #expect(w.count == 7)
            #expect(w.first == ws.start(of: d(2026, 12, 31)))
            #expect(w.contains(d(2026, 12, 31)))
            for i in 1..<7 { #expect(w[i] == w[i - 1].adding(days: 1)) }
            #expect(WeekStart.weekday(w[0]) == ws.first)
        }
    }

    /// Сетка месяца — целые недели; месяц, начинающийся в первый день недели, не получает хвоста спереди.
    @Test func monthGrid() {
        // Сентябрь 2026: 1-е — вторник, 30-е — среда.
        let m = d(2026, 9, 1)
        let mon = WeekStart.monday.grid(of: m)
        #expect(mon.first == d(2026, 8, 31) && mon.last == d(2026, 10, 4) && mon.count == 35)
        let sun = WeekStart.sunday.grid(of: m)
        #expect(sun.first == d(2026, 8, 30) && sun.last == d(2026, 10, 3) && sun.count == 35)
        let sat = WeekStart.saturday.grid(of: m)
        #expect(sat.first == d(2026, 8, 29) && sat.last == d(2026, 10, 2) && sat.count == 35)
        // Февраль 2026: 1-е — воскресенье, 28-е — суббота.
        let feb = d(2026, 2, 1)
        #expect(WeekStart.sunday.grid(of: feb).count == 28)                      // ровно четыре недели
        #expect(WeekStart.sunday.grid(of: feb).first == feb)
        #expect(WeekStart.monday.grid(of: feb).first == d(2026, 1, 26))
        #expect(WeekStart.monday.grid(of: feb).count == 35)
        for ws in WeekStart.allCases { #expect(ws.grid(of: m).count % 7 == 0) }
    }

    /// Выходные — сб и вс, с какого дня ни считай.
    @Test func weekendIsFixed() {
        for ws in WeekStart.allCases {
            let flags = ws.week(of: d(2026, 9, 23)).map(WeekStart.isWeekend)
            #expect(flags.filter { $0 }.count == 2)
        }
        #expect(WeekStart.monday.week(of: d(2026, 9, 23)).map(WeekStart.isWeekend) == [false, false, false, false, false, true, true])
        #expect(WeekStart.sunday.week(of: d(2026, 9, 23)).map(WeekStart.isWeekend) == [true, false, false, false, false, false, true])
        #expect(WeekStart.saturday.week(of: d(2026, 9, 23)).map(WeekStart.isWeekend) == [true, true, false, false, false, false, false])
    }

    @Test func headerOrderAndBlanks() {
        #expect(WeekStart.monday.weekdayOrder == [1, 2, 3, 4, 5, 6, 0])
        #expect(WeekStart.sunday.weekdayOrder == [0, 1, 2, 3, 4, 5, 6])
        #expect(WeekStart.saturday.weekdayOrder == [6, 0, 1, 2, 3, 4, 5])
        // 1 сентября 2026 — вторник.
        #expect(WeekStart.monday.leadingBlanks(year: 2026, month: 9) == 1)
        #expect(WeekStart.sunday.leadingBlanks(year: 2026, month: 9) == 2)
        #expect(WeekStart.saturday.leadingBlanks(year: 2026, month: 9) == 3)
    }

    /// Номера недель ленты листания: туда и обратно, соседние недели — соседние номера, через 1970 год тоже.
    @Test func weekIndexRoundTrips() {
        for ws in WeekStart.allCases {
            for day in [d(1969, 12, 31), d(1970, 1, 1), d(1970, 1, 7), d(2026, 9, 23), d(2027, 1, 1)] {
                let i = ws.index(of: day)
                #expect(ws.start(index: i) == ws.start(of: day))
                #expect(ws.index(of: ws.start(index: i + 1)) == i + 1)
                #expect(ws.index(of: ws.start(index: i).adding(days: -1)) == i - 1)
            }
        }
        // Понедельник — как было у ленты: 21.09.2026 — неделя 2026-09-21.
        #expect(WeekStart.monday.start(index: WeekStart.monday.index(of: d(2026, 9, 23))) == d(2026, 9, 21))
    }

    @Test func choiceResolvesAgainstSystem() {
        #expect(WeekStartChoice.standard == .mon)
        #expect(WeekStartChoice.mon.resolved(systemFirstWeekday: 1) == .monday)    // выбор сильнее системы
        #expect(WeekStartChoice.sun.resolved(systemFirstWeekday: 2) == .sunday)
        #expect(WeekStartChoice.sat.resolved(systemFirstWeekday: 2) == .saturday)
        #expect(WeekStartChoice.auto.resolved(systemFirstWeekday: 1) == .sunday)   // США
        #expect(WeekStartChoice.auto.resolved(systemFirstWeekday: 2) == .monday)   // Россия, Европа
        #expect(WeekStartChoice.auto.resolved(systemFirstWeekday: 7) == .saturday) // Ближний Восток
        #expect(WeekStartChoice.auto.resolved(systemFirstWeekday: 6) == .monday)   // нет такой сетки — понедельник
    }
}
