import Testing
import Foundation
import SwiftUI
@testable import LightPlanUI

/// 28к.2: варианты светлой темы живут только под флагом. Без `-LPLightVariant` вариант не выбран, каждый светлый
/// токен `Palette` идёт через `lt(…)` со своим прежним числом (тогда `lt` отдаёт ровно `Color(hex:alpha:)`), а таблица
/// варианта называет только существующие токены — опечатка в имени молча оставила бы цвет прежним.
/// Что экран без флага пиксель в пиксель прежний, доказано кадрами (`docs/light_theme_2026-11/variants/README.md`).
struct LightVariantTests {
    private static let source: String = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/LightPlanUI/Theme/Palette.swift").standardizedFileURL
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    /// Имена токенов, у которых светлое значение — число через `lt(…)`.
    private static var lightTokens: Set<String> {
        let re = try! NSRegularExpression(pattern: #"public var (\w+): Color \{ dark \? Color\(hex: [^)]*\) : lt\(0x"#)
        let s = source
        return Set(re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap {
            Range($0.range(at: 1), in: s).map { String(s[$0]) }
        })
    }

    @Test func noFlagNoVariant() {
        #expect(UserDefaults.standard.string(forKey: "LPLightVariant") == nil)
        #expect(LightVariant.current == nil)
        #expect(LightVariant.lit(Palette(.light)) == nil)
    }

    @Test func everyLightTokenGoesThroughTheVariantHook() {
        #expect(!Self.source.isEmpty)
        // 92 токена веба (справка 28к.1, § 2): все светлые значения — через `lt`, ни одного `Color(hex:)` мимо.
        #expect(Self.lightTokens.count == 92)
        #expect(!Self.source.contains(" : Color(hex:"))
    }

    @Test(arguments: LightVariant.allCases)
    func variantNamesOnlyRealTokens(_ v: LightVariant) {
        let unknown = Set(v.table.keys).subtracting(Self.lightTokens)
        #expect(unknown.isEmpty, "\(v.rawValue): нет таких токенов — \(unknown.sorted())")
    }

    @Test func darkThemeIsNeverTouched() {
        // Подмена — только в светлой ветке: тёмная палитра не зовёт `lt`.
        let darkPart = Self.source.components(separatedBy: "\n").filter { $0.contains("public var") && $0.contains("dark ?") }
            .map { $0.components(separatedBy: " : lt(").first ?? "" }
        #expect(darkPart.allSatisfy { !$0.contains("lt(") })
    }
}
