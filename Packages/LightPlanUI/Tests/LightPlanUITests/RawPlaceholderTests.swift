import Testing
import Foundation
@testable import LightPlanUI

/// Сырая подстановка на экране: `Lexicon.substitute` оставляет незнакомое `{имя}` как написано, поэтому
/// слово, где язык держит имя, которого Swift не передаёт, показывает «{name}» человеку. Swift пишется по
/// русскому слову, так что опасен именно слот, которого нет в ru (24.10: `light.waitedSunset`, `week.wx` zh).
@Suite(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
struct RawPlaceholderTests {

    static let langs = ["ru", "en", "es", "ja", "zh"]

    /// Строка погоды раскрытого дня недели: облачность и ветер, на zh без «{cond}» (`Tools/lang_fixes.json`).
    @Test func weekWeatherLineInEveryLanguage() {
        let want = [
            "ru": "облачность 40% · ветер 5 м/с",
            "en": "cloud 40% · wind 5 m/s",
            "es": "nubosidad 40% · viento 5 m/s",
            "ja": "雲量40% · 風5 m/s",
            "zh": "云量40%·风速5米/秒",
        ]
        for lang in Self.langs {
            let line = PlannerWeekBody.wxLine(Lexicon(lang), cloud: 40, wind: 5)
            #expect(line == want[lang], "\(lang)")
            #expect(!line.contains("{"), "\(lang): сырая подстановка в «\(line)»")
        }
    }

    /// Слоты, которых нет в ru, но Swift их передаёт — сверено с местом вызова.
    static let passed: Set<String> = [
        "light.waitedSunset en", "light.waitedSunset es", "light.waitedSunset ja", "light.waitedSunset zh",  // name(p), как у веба
        "rep.payFirst zh", "rep.sum zh", "rep.sumMore zh",  // голое число `k` рядом с `n`
    ]

    /// Ни у одного ключа (веба и `lang_native.json`) язык не держит слот, которого нет в ru, — кроме `passed`.
    @Test func noLanguageHasASlotRussianLacks() throws {
        let f = try TextFixtures.load("lang.json", as: TextFixtures.LangFile.self)
        let url = TextFixtures.root.appendingPathComponent("Tools/lang_native.json")
        let native = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: Any]])
        let plural = Set(f.pluralKeys)
        let keys = Set(f.keys).union(native["ru", default: [:]].keys).subtracting(plural)
        let re = try NSRegularExpression(pattern: #"\{[A-Za-z_][A-Za-z0-9_]*\}"#)
        func slots(_ s: String) -> Set<String> {
            let ns = s as NSString
            return Set(re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) })
        }
        let ru = Lexicon("ru")
        var bad: [String] = []
        for lang in Self.langs.dropFirst() {
            let lex = Lexicon(lang)
            for key in keys.sorted() {
                let extra = slots(lex.t(key)).subtracting(slots(ru.t(key)))
                if !extra.isEmpty && !Self.passed.contains("\(key) \(lang)") {
                    bad.append("\(key) \(lang) \(extra.sorted())")
                }
            }
        }
        #expect(bad.isEmpty, "лишние слоты: \(bad)")
        #expect(keys.count > 1500)
    }
}
