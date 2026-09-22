import Testing
import Foundation
@testable import LightPlanCore

/// Сверка темноты в произвольную дату с вебом (итерация 10, найдена
/// итерацией 9а): `hasAstroNight` и `nextAstroNight`. Эталон —
/// `Fixtures/astro_night.json`.
struct AstroNightParityTests {

    private static func date(_ iso: String) -> CivilDate {
        let p = iso.split(separator: "-").map { Int($0)! }
        return CivilDate(year: p[0], month: p[1], day: p[2])
    }

    @Test("astro_night.json: hasAstroNight — строго, вся сетка широт")
    func has() throws {
        let f = try ParityFixtures.load("astro_night.json", as: ParityFixtures.AstroNightFile.self)
        var failures = 0
        for row in f.has {
            let got = AstroNight.has(on: Self.date(row.date), latitude: row.lat, utcOffsetHours: 2)
            if got != row.has {
                failures += 1
                if failures <= 20 { Issue.record("lat \(row.lat) \(row.date): JS \(row.has), Swift \(got)") }
            }
        }
        print("hasAstroNight: \(f.has.count) проверок")
        #expect(failures == 0, "\(failures) расхождений с вебом")
    }

    @Test("astro_night.json: nextAstroNight — строго, включая «не вернётся за 190 суток»")
    func next() throws {
        let f = try ParityFixtures.load("astro_night.json", as: ParityFixtures.AstroNightFile.self)
        var failures = 0
        var neverReturns = 0
        for row in f.next {
            let got = AstroNight.next(after: Self.date(row.date), latitude: row.lat, utcOffsetHours: 2)
            let want = row.next.map(Self.date)
            if want == nil { neverReturns += 1 }
            if got != want {
                failures += 1
                if failures <= 20 {
                    Issue.record("lat \(row.lat) \(row.date): JS \(String(describing: row.next)), Swift \(String(describing: got))")
                }
            }
        }
        print("nextAstroNight: \(f.next.count) проверок, «не вернётся за 190 суток» — \(neverReturns)")
        #expect(failures == 0, "\(failures) расхождений с вебом")
    }
}
