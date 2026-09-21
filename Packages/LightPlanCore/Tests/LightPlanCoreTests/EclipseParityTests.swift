import Testing
import Foundation
import LightPlanCore

/// Затмения таблицей (итерация 9). Расчёт отвергнут трижды — сверяется не
/// формула, а данные: таблица в ресурсе пакета обязана совпасть с `ECLIPSES`
/// живой беты, а ответы `on` и `next` — с ответами веба на каждые сутки.
struct EclipseParityTests {

    /// Сутки `n` после `from` по григорианскому календарю, без зоны машины.
    static func day(_ from: CivilDate, plus n: Int) -> CivilDate {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let start = cal.date(from: DateComponents(year: from.year, month: from.month, day: from.day))!
        let c = cal.dateComponents([.year, .month, .day], from: cal.date(byAdding: .day, value: n, to: start)!)
        return CivilDate(year: c.year!, month: c.month!, day: c.day!)
    }

    @Test("Таблица в ресурсе — та же, что ECLIPSES в бете")
    func tableMatchesBeta() throws {
        let f = try ParityFixtures.load("eclipse.json", as: ParityFixtures.EclipseFile.self)
        #expect(EclipseTable.all.count == f.table.count,
                "в бете \(f.table.count) затмений, в ресурсе \(EclipseTable.all.count): веб продлил таблицу — перенести строки в Eclipse/Resources/eclipses.json")
        for (row, e) in zip(f.table, EclipseTable.all) {
            #expect(CivilDate(iso: row.d) == e.date, "дата \(row.d)")
            #expect(row.kind == e.kind.rawValue, "вид \(row.d)")
            #expect(row.where == e.whereKey, "место \(row.d)")
        }
    }

    @Test("eclipse.json: on и next на каждые сутки 2025-06-01 … 2031-02-28")
    func answersEveryDay() throws {
        let f = try ParityFixtures.load("eclipse.json", as: ParityFixtures.EclipseFile.self)
        let start = CivilDate(iso: f.sweep.from)
        var failures = 0
        for n in 0..<f.sweep.on.count {
            let d = Self.day(start, plus: n)
            func index(_ e: Eclipse?) -> Int { e.flatMap { EclipseTable.all.firstIndex(of: $0) } ?? -1 }
            let on = index(EclipseTable.on(d)), next = index(EclipseTable.next(from: d))
            if on != f.sweep.on[n] || next != f.sweep.next[n] {
                failures += 1
                if failures <= 10 { Issue.record("\(d): JS on \(f.sweep.on[n]) next \(f.sweep.next[n]), Swift on \(on) next \(next)") }
            }
        }
        #expect(failures == 0)
        #expect(f.sweep.on.contains { $0 >= 0 }, "в диапазоне есть дни с затмением — проверка не пустая")
        #expect(f.sweep.next.contains(-1), "и есть дни за краем таблицы, где ближайшего нет")
    }

    @Test("12 августа 2026 — полное затмение; 13-го — уже нет")
    func totalOf2026() {
        let e = EclipseTable.on(CivilDate(year: 2026, month: 8, day: 12))
        #expect(e?.kind == .total)
        #expect(e?.whereKey == "eclW.2026-08-12")
        #expect(EclipseTable.on(CivilDate(year: 2026, month: 8, day: 13)) == nil)
    }

    @Test("Ближайшее вперёд включает сегодняшнее, а за краем таблицы — nil")
    func nextSemantics() {
        #expect(EclipseTable.next(from: CivilDate(year: 2026, month: 8, day: 12))?.date == CivilDate(year: 2026, month: 8, day: 12))
        #expect(EclipseTable.next(from: CivilDate(year: 2026, month: 8, day: 13))?.date == CivilDate(year: 2027, month: 2, day: 6))
        #expect(EclipseTable.next(from: CivilDate(year: 2030, month: 11, day: 25))?.kind == .total)
        #expect(EclipseTable.next(from: CivilDate(year: 2030, month: 11, day: 26)) == nil)
    }

    @Test("CivilDate упорядочен по календарю, а не по строке")
    func civilDateOrder() {
        #expect(CivilDate(year: 2026, month: 12, day: 31) < CivilDate(year: 2027, month: 1, day: 1))
        #expect(CivilDate(year: 2026, month: 2, day: 28) < CivilDate(year: 2026, month: 3, day: 1))
        #expect(CivilDate(year: 2026, month: 9, day: 9) < CivilDate(year: 2026, month: 9, day: 10))
    }
}
