import Testing
import Foundation
import LightPlanCore
import LightPlanDomain
@testable import LightPlanUI

/// Эталон планировщика: `Fixtures/planner.json` собирает `Tools/parity/planner.js`
/// (`make planner`), вырезая раскладку колонок и шкалу срочности из живой беты.
/// Не сошлось — ошибка переноса, пока не доказано обратное.
@Suite struct PlannerParityTests {

    struct Ref: Decodable {
        struct Case: Decodable {
            struct Item: Decodable { let kind: String; let a: Int; let b: Int; let all: Bool }
            let items: [Item]; let col: [Int]; let cols: [Int]
        }
        struct Tone: Decodable { let theme: String; let p: Double; let rgb: [Double] }
        let hourHeight: Double
        let lanes: [Case]
        let urgency: [Tone]
    }

    static let ref: Ref = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        u.appendPathComponent("Fixtures/planner.json")
        do { return try JSONDecoder().decode(Ref.self, from: Data(contentsOf: u)) }
        catch { fatalError("нет или не читается \(u.path): \(error). Собрать: make planner") }
    }()

    @Test func lanesMatchWeb() {
        #expect(Self.ref.hourHeight == DayLanes.hourHeight)
        let day = CivilDate(year: 2026, month: 9, day: 24)
        var bad: [Int] = []
        for (n, c) in Self.ref.lanes.enumerated() {
            let items = c.items.enumerated().map { i, x -> DayItem in
                var b: Block?
                if x.kind == "busy" { var k = Block(id: "b\(i)", kind: .busy, from: day); k.allDay = x.all; b = k }
                return DayItem(kind: x.kind == "busy" ? .busy : .shoot, start: x.a, end: x.b,
                               fromYesterday: false, intoTomorrow: false, session: nil, block: b)
            }
            let l = DayLanes.layout(items)
            if l.map({ $0?.column ?? -1 }) != c.col || l.map({ $0?.columns ?? -1 }) != c.cols { bad.append(n) }
        }
        #expect(Self.ref.lanes.count == 400)
        #expect(bad.isEmpty, "разошлись дни \(bad.prefix(10))")
    }

    @Test func urgencyMatchesWeb() {
        #expect(Self.ref.urgency.count == 50)
        for t in Self.ref.urgency {
            let c = Urgency.rgb(t.p, dark: t.theme == "dark")
            #expect([c.r, c.g, c.b] == t.rgb, "\(t.theme) p=\(t.p)")
        }
    }
}
