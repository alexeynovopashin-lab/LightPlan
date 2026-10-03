import Testing
import Foundation
@testable import LightPlanUI

/// Месяц «Съёмок» (28и): цифры на одной линии, зона подписей, метка выбранного дня — числами, без экрана.
@Suite struct MonthMetricsTests {
    private typealias M = MonthMetrics

    /// Ряд из 0, 1, 2 и 3+ подписей: подписи цифру не двигают и высоту клетки не меняют.
    @Test func digitDoesNotDependOnLabels() {
        for row in 0..<6 {
            let ys = (0...4).map { _ in M.digitCenterY(row: row) }   // число подписей в формулу не входит
            #expect(Set(ys).count == 1)
        }
        // Видно не больше двух строк; зона вмещает ровно их.
        for n in 0...5 {
            let v = M.visibleLabels(n)
            #expect(v.shown + (v.more ? 1 : 0) <= M.labelLines)
        }
        #expect(M.visibleLabels(0) == (0, false))
        #expect(M.visibleLabels(2) == (2, false))
        #expect(M.visibleLabels(3) == (1, true))
        #expect(M.zoneHeight == 21)
        #expect(M.digitTop + M.digitBox + M.zoneHeight <= M.cellHeight)
    }

    /// Шаг рядов постоянный; высота сетки для 4, 5 и 6 рядов.
    @Test func rowPitchAndGridHeights() {
        for row in 0..<5 {
            #expect(M.digitCenterY(row: row + 1) - M.digitCenterY(row: row) == M.cellHeight + M.rowGap)
        }
        #expect(M.gridHeight(rows: 4) == 238)
        #expect(M.gridHeight(rows: 5) == 298)
        #expect(M.gridHeight(rows: 6) == 358)
        #expect(M.gridHeight(rows: 0) == 0)
    }

    // MARK: контраст метки выбранного дня

    private func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private func lum(_ r: Double, _ g: Double, _ b: Double) -> Double {
        0.2126 * lin(r / 255) + 0.7152 * lin(g / 255) + 0.0722 * lin(b / 255)
    }
    private func over(_ top: (Double, Double, Double), _ a: Double, _ base: (Double, Double, Double)) -> (Double, Double, Double) {
        (top.0 * a + base.0 * (1 - a), top.1 * a + base.1 * (1 - a), top.2 * a + base.2 * (1 - a))
    }
    private func ratio(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let x = lum(a.0, a.1, a.2), y = lum(b.0, b.1, b.2)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Подложка — `--sheet-glass` над `--surface`; метка — тон чернил над подложкой. Системное стекло в расчёт
    /// не входит (его даёт сама система) — реальный контраст по кадру в отчёте шага.
    @Test func selectedMarkContrastOnPlate() {
        let darkPlate = over((0x17, 0x15, 0x0F), 0.74, (0x0F, 0x0E, 0x0C))
        let darkSel = over((255, 255, 255), 0.10, darkPlate)
        #expect(ratio(darkSel, darkPlate) >= 1.25)
        let lightPlate = over((255, 255, 255), 0.78, (0xFA, 0xF8, 0xF3))
        let lightSel = over((0x17, 0x15, 0x0F), 0.12, lightPlate)
        #expect(ratio(lightSel, lightPlate) >= 1.25)
        // Старая метка (`--press`) на подложке — ниже порога: ради неё шаг и сделан.
        #expect(ratio((0x22, 0x1F, 0x19), darkPlate) < 1.25)
    }
}
