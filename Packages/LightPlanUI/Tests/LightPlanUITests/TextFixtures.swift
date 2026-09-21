import Foundation

/// Загрузчик фикстур текста: `Fixtures/lang.json` и `Fixtures/format.json`.
/// Собирает `Tools/parity/lang.js` (`make lang`). Лежат в корне репозитория,
/// рядом с остальными фикстурами паритета.
enum TextFixtures {

    static var root: URL {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        return u
    }

    static func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = root.appendingPathComponent("Fixtures").appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "TextFixtures", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "нет фикстуры \(name). Собрать: make lang (в корне \(root.path))"])
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    // MARK: lang.json

    struct Plural: Decodable {
        let word: [String]
        let count: [String]
        let sep: String
        let index: [Int]
    }

    struct LangCode: Decodable {
        let t: [String]
        let plural: [String: Plural]
        let subst: [String: String]
        let has: Bool
        let known: Bool
    }

    struct LangFile: Decodable {
        struct Meta: Decodable { let keys: Int; let plural: Int; let n: [Int] }
        let meta: Meta
        let keys: [String]
        let pluralKeys: [String]
        let substVars: [String: [String: String]]
        let langs: [String: LangCode]
    }

    // MARK: format.json

    struct Clock: Decodable {
        let is12: Bool
        let fmt: [String]
        let hm24: [String]
        let fmtHTML: [String]
        let range: [String]
    }

    struct Months: Decodable { let title: [String]; let abbr: [String] }

    struct Numbers: Decodable { let plain: [String]; let d0: [String]; let d2: [String] }

    struct FormatLang: Decodable {
        let dates: [String: [String]]
        let months: Months
        let wdRow: String
        let clock: [String: Clock]
        let number: Numbers
        let money: [String: [String]]
        let sign: [String: String]
    }

    struct FormatFile: Decodable {
        struct Meta: Decodable { let cut: String; let icu: String; let cldr: String }
        struct Temp: Decodable { let c: [Int]; let f: [Int] }
        let meta: Meta
        let days: [String]
        let minutes: [Double?]
        let rangeEnds: [Double?]
        let numIn: [Double]
        let moneyIn: [Double]
        let tempIn: [Double]
        let currencies: [String]
        let langs: [String: FormatLang]
        let temp: Temp
    }
}

/// Собирает расхождения по именованной сетке и печатает итог: сколько
/// проверено, сколько разошлось и первые примеры. Тест падает на первом же
/// расхождении, но в отчёте видна вся картина, а не одна строка.
struct Tally {
    let name: String
    private(set) var checked = 0
    private(set) var bad: [String: [String]] = [:]

    init(_ name: String) { self.name = name }

    mutating func check(_ group: String, _ got: String, _ want: String, _ at: @autoclosure () -> String) {
        checked += 1
        guard got != want else { return }
        bad[group, default: []].append("\(at()): «\(got)» вместо «\(want)»")
    }

    var total: Int { bad.values.reduce(0) { $0 + $1.count } }

    var report: String {
        var s = "\(name): проверок \(checked), расхождений \(total)"
        for (g, v) in bad.sorted(by: { $0.key < $1.key }) {
            s += "\n  \(g): \(v.count) — " + v.prefix(3).joined(separator: " · ")
        }
        return s
    }
}
