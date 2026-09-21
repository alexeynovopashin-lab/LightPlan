import Testing
import Foundation
@testable import LightPlanUI

/// Итерация 14: словарь. Каталог `Localizable.xcstrings` собран
/// `Tools/lang2xcstrings.js` из `beta/lang.js`; эталон — `Fixtures/lang.json`,
/// то, что `LANG` веба отдаёт по каждому ключу и языку.
///
/// Каталог компилирует Xcode: SwiftPM на хосте (`swift test`) его не
/// собирает (замерено 21.09.2026 — в ресурсах остаётся сырой JSON, папок
/// `xx.lproj` нет). Поэтому эти тесты идут только через `xcodebuild test`,
/// а на хосте отключены — с пометкой, а не молчанием.
@Suite(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
struct LexiconParityTests {

    static let codes = ["ru", "en", "en-GB", "en-US", "es", "ja", "zh"]

    @Test func everyKeyEveryLanguageMatchesWeb() throws {
        let f = try TextFixtures.load("lang.json", as: TextFixtures.LangFile.self)
        var tally = Tally("строки")
        for code in Self.codes {
            let lex = Lexicon(code)
            let want = try #require(f.langs[code])
            for (i, key) in f.keys.enumerated() {
                tally.check(code, lex.t(key), want.t[i], key)
            }
        }
        #expect(tally.total == 0, Comment(rawValue: tally.report))
        #expect(tally.checked == Self.codes.count * f.meta.keys)
    }

    @Test func pluralWordsAgreeWithWeb() throws {
        let f = try TextFixtures.load("lang.json", as: TextFixtures.LangFile.self)
        var tally = Tally("склонение")
        for code in Self.codes {
            let lex = Lexicon(code)
            let want = try #require(f.langs[code])
            for key in f.pluralKeys {
                let p = try #require(want.plural[key])
                tally.check(code + " sep", lex.sep(key), p.sep, key)
                for (i, n) in f.meta.n.enumerated() {
                    tally.check(code + " word", lex.word(key, n), p.word[i], "\(key)×\(n)")
                    tally.check(code + " count", lex.count(key, n), p.count[i], "\(key)×\(n)")
                    tally.check(code + " index", String(lex.index(n)), String(p.index[i]), "\(n)")
                }
            }
        }
        #expect(tally.total == 0, Comment(rawValue: tally.report))
    }

    @Test func substitutionByName() throws {
        let f = try TextFixtures.load("lang.json", as: TextFixtures.LangFile.self)
        var tally = Tally("подстановка")
        for code in Self.codes {
            let lex = Lexicon(code)
            let want = try #require(f.langs[code])
            for (key, vars) in f.substVars {
                tally.check(code, lex.t(key, vars), want.subst[key] ?? "", key)
            }
        }
        #expect(tally.total == 0, Comment(rawValue: tally.report))
        // Имени нет среди подставляемых — остаётся как было
        #expect(Lexicon.substitute("a {x} b {y}", ["x": "1"]) == "a 1 b {y}")
        #expect(Lexicon.substitute("{ x} {я} {}", ["x": "1", "я": "2"]) == "{ x} {я} {}")
    }

    @Test func languageQuestionsMatchWeb() throws {
        let f = try TextFixtures.load("lang.json", as: TextFixtures.LangFile.self)
        for code in Self.codes {
            let want = try #require(f.langs[code])
            #expect(Lexicon.has(code) == want.has, "has(\(code))")
            #expect(Lexicon.known(code) == want.known, "known(\(code))")
        }
        #expect(Lexicon.chain("en-US") == ["en-US", "en"])
        #expect(Lexicon.chain("ru") == ["ru", "en"])
        #expect(Lexicon.chain("en") == ["en"])
    }

    /// Порт `langcheck.js`. Основы ru и en совпадают ключ в ключ; заготовки
    /// (es, ja, zh) полны; в говоре нет ключа, которого нет в основе — такой
    /// молча никогда не сработает.
    @Test func dictionaryComposition() throws {
        let f = try TextFixtures.load("lang.json", as: TextFixtures.LangFile.self)
        let lex = Lexicon("ru")
        for code in ["ru", "en", "es", "ja", "zh"] {
            let missing = f.keys.filter { !lex.defines($0, language: code) }
            #expect(missing.isEmpty, "\(code): не хватает \(missing.count): \(missing.prefix(5))")
        }
        let enUS = f.keys.filter { lex.defines($0, language: "en-US") }
        #expect(enUS.count == 5, "en-US: \(enUS.count) отличий от en, ждали 5")
        #expect(f.keys.filter { lex.defines($0, language: "en-GB") }.isEmpty, "en-GB хранит только отличия и пуст")
        #expect(f.meta.keys == 1542)
    }

    /// «Пропавший ключ падает в английский, а не показывает сам ключ.»
    /// Настоящий каталог полон, поэтому проверка идёт на маленьком, тестовом.
    @Test func missingKeyFallsBackToEnglish() {
        let ru = Lexicon("ru", bundle: .module)
        #expect(ru.t("test.both") == "both-ru")
        #expect(ru.t("test.onlyEn") == "only-en", "ключа нет в ru — берётся английский, не сам ключ")
        #expect(Lexicon("ja", bundle: .module).t("test.onlyEn") == "only-en")
        #expect(Lexicon("en-US", bundle: .module).t("test.onlyEnUS") == "color")
        #expect(Lexicon("en-GB", bundle: .module).t("test.onlyEnUS") == "colour", "британский — основа")
        #expect(ru.t("test.nowhere") == "test.nowhere", "нет нигде — сам ключ, пропажа видна на экране")
    }
}

/// Скомпилирован ли каталог в ресурсы: есть ли у пакета папка `ru.lproj`.
let catalogCompiled: Bool = Bundle.module.path(forResource: "ru", ofType: "lproj") != nil
