import Testing
import Foundation
@testable import LightPlanUI

/// Шаг 28в: строка «Сборка · <ветка> · <коммит> · <дата>» внизу «Настроек».
@MainActor
struct BuildInfoTests {
    private let stamp: [String: Any] = ["LPBuildBranch": "main", "LPBuildSha": "a8ee911", "LPBuildDate": "2026-10-01"]
    private let template = "Сборка · {branch} · {sha} · {date}"
    private let unknown = "Сборка · неизвестна"

    @Test func lineShowsBranchShaAndShortDate() {
        let line = BuildInfo.line(BuildInfo(info: stamp), template: template, unknown: unknown)
        #expect(line == "Сборка · main · a8ee911 · 01.10")
    }

    @Test func branchWithSlashAndDirtyMarkStayAsWritten() {
        var s = stamp; s["LPBuildBranch"] = "wt/28v"; s["LPBuildSha"] = "a8ee911+"
        #expect(BuildInfo.line(BuildInfo(info: s), template: template, unknown: unknown) == "Сборка · wt/28v · a8ee911+ · 01.10")
    }

    @Test func noKeysOrNoInfoMeansUnknown() {
        #expect(BuildInfo(info: nil) == nil)
        #expect(BuildInfo(info: [:]) == nil)
        #expect(BuildInfo.line(BuildInfo(info: [:]), template: template, unknown: unknown) == "Сборка · неизвестна")
    }

    @Test func anyEmptyOrMissingKeyMeansUnknown() {
        for key in ["LPBuildBranch", "LPBuildSha", "LPBuildDate"] {
            var empty = stamp; empty[key] = "  "
            #expect(BuildInfo(info: empty) == nil, "пустой \(key)")
            var missing = stamp; missing[key] = nil
            #expect(BuildInfo(info: missing) == nil, "нет \(key)")
        }
    }

    @Test func oddDateStaysAsIs() {
        var s = stamp; s["LPBuildDate"] = "вчера"
        #expect(BuildInfo(info: s)?.shortDay == "вчера")
    }

    /// Слова строки лежат в каталоге: на хосте он не скомпилирован — тогда `xcodebuild test`.
    @Test(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
    func catalogHasTheWordsInEveryLanguage() {
        let info = BuildInfo(info: stamp)
        #expect(BuildInfo.line(info, Lexicon("ru")) == "Сборка · main · a8ee911 · 01.10")
        #expect(BuildInfo.line(nil, Lexicon("ru")) == "Сборка · неизвестна")
        for code in ["en", "es", "ja", "zh"] {
            let l = BuildInfo.line(info, Lexicon(code))
            #expect(l.contains("a8ee911") && l.contains("01.10") && !l.contains("{"), "\(code): \(l)")
            #expect(BuildInfo.line(nil, Lexicon(code)) != "set.buildUnknown", "\(code): нет слова")
        }
    }

    /// В буфер уходит строка, что на экране; сам буфер в тесте не трогаем — у тестового хоста нет права.
    @Test(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
    func tapCopiesTheLineOnScreen() {
        var copied: [String] = []
        BuildInfo.copyLine(BuildInfo(info: stamp), Lexicon("ru")) { copied.append($0) }
        BuildInfo.copyLine(nil, Lexicon("ru")) { copied.append($0) }
        #expect(copied == ["Сборка · main · a8ee911 · 01.10", "Сборка · неизвестна"])
    }
}
