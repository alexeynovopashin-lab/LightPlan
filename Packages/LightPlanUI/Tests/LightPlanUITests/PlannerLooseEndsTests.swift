import Testing
import SwiftUI
import Foundation
@testable import LightPlanUI

/// 30.2, хвост 3 (Алексей 30.10: «берем 2»): значок поиска в шапке ленты года — чернила, как в «Съёмках» (был латунный).
@MainActor
struct PlannerLooseEndsTests {
    private func sourceDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LightPlanUI/Screens/Planner")
    }

    private func source(_ name: String) throws -> String {
        try String(contentsOf: sourceDir().appendingPathComponent(name), encoding: .utf8)
    }

    // MARK: - 3. Цвет значка поиска

    /// Три значка шапки одного вида: «+» и статистика — латунь, поиск — чернила; в «Съёмках» и в ленте года одинаково.
    @Test func theSearchGlyphIsInkInBothHeaders() throws {
        func searchColour(_ file: String, _ call: String) throws -> String? {
            let src = try source(file)
            guard let r = src.range(of: call) else { return nil }
            let tail = src[r.upperBound...]
            return tail.prefix(60).components(separatedBy: CharacterSet(charactersIn: ",)")).first.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        #expect(try searchColour("PlannerScreenView.swift", "action(.search, ") == "pal.ink")
        #expect(try searchColour("PlannerYearView.swift", "OverlayIconButton(kind: .search, color: ") == "pal.ink")
        // Остальные кнопки ленты не тронуты.
        #expect(try searchColour("PlannerYearView.swift", "OverlayIconButton(kind: .add, color: ") == "pal.brass")
        #expect(try searchColour("PlannerYearView.swift", "OverlayIconButton(kind: .stats, color: ") == "pal.brass")
    }

    /// Чернила держат ≥ 4,5 : 1 на странице и на подложке шапки в обеих темах (значок — единственная графика кнопки).
    @Test(arguments: [false, true]) func inkGlyphContrastOnTheHeader(_ dark: Bool) {
        func lum(_ c: Color) -> Double {
            var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
            UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
            func lin(_ v: CGFloat) -> Double { let x = Double(v); return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
        func ratio(_ a: Color, _ b: Color) -> Double { let (x, y) = (lum(a), lum(b)); return (max(x, y) + 0.05) / (min(x, y) + 0.05) }
        let pal = Palette(dark ? .dark : .light)
        #expect(ratio(pal.ink, pal.surface) >= 4.5, "ink на странице, dark=\(dark): \(ratio(pal.ink, pal.surface))")
        #expect(ratio(pal.ink, pal.bar) >= 4.5, "ink на шапке, dark=\(dark): \(ratio(pal.ink, pal.bar))")
    }
}
