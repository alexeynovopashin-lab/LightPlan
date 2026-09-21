import Foundation
import Testing
@testable import LightPlanUI

/// Подбор знака точки против ответов веба (`ICONS.pointSign`).
///
/// Корпус собирает `Tools/icons2assets.js` из самих правил: каждая альтернатива
/// каждой регулярки в шести обрамлениях, плюс место и студия. Тест способен
/// падать: испорченная граница слова или пропущенная диакритика роняет его
/// с названием, знаком веба и знаком Swift.
struct PointSignParityTests {

    private struct Corpus: Decodable {
        struct Meta: Decodable { let count: Int; let rules: Int }
        let meta: Meta
        let cases: [[Cell]]
    }

    /// Строка корпуса — смесь строк и чисел: `[название, место, студия, знак, знак по словарю]`.
    private enum Cell: Decodable {
        case s(String), n(Int)
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if let i = try? c.decode(Int.self) { self = .n(i) } else { self = .s(try c.decode(String.self)) }
        }
        var string: String { if case .s(let s) = self { return s } else { return "" } }
        var int: Int { if case .n(let n) = self { return n } else { return 0 } }
    }

    private static func load() throws -> Corpus {
        var u = URL(fileURLWithPath: #filePath)
        u.deleteLastPathComponent()
        u.appendPathComponent("point_sign.json")
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: u))
    }

    @Test func ruleCountMatchesWeb() throws {
        let corpus = try Self.load()
        #expect(PointSign.ruleCount == corpus.meta.rules)
    }

    @Test func everyCaseMatchesWeb() throws {
        let corpus = try Self.load()
        #expect(corpus.cases.count == corpus.meta.count)
        var failures: [String] = []
        for c in corpus.cases {
            let name = c[0].string, place = c[1].string, studio = c[2].int == 1
            let screen = PointSign.name(for: name, place: place.isEmpty ? nil : place, studio: studio)
            let all = PointSign.name(for: name, place: place.isEmpty ? nil : place, studio: studio, all: true)
            if screen != c[3].string || all != c[4].string {
                failures.append("«\(name)» / «\(place)» studio=\(studio): веб \(c[3].string)/\(c[4].string), Swift \(screen)/\(all)")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) из \(corpus.cases.count) разошлись; первые: \(failures.prefix(12).joined(separator: "\n"))")
    }

    /// Каждое имя, на которое ведёт правило, нарисовано: словарь не ссылается в пустоту.
    @Test func everyRuleTargetIsDrawn() {
        let undrawn = Set(IconLibrary.pointWords.map(\.sign)).filter { IconLibrary.common[$0] == nil }
        #expect(undrawn.isEmpty, "не нарисовано: \(undrawn.sorted())")
    }
}
