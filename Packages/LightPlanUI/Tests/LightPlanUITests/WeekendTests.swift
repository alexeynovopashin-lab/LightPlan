import Testing
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import LightPlanCore
@testable import LightPlanUI

/// Выходные в календаре (Алексей 28.10): суббота и воскресенье янтарные в месяце, неделе, дне и сетке формы.
@Suite struct WeekendTests {
    private func d(_ y: Int, _ m: Int, _ day: Int) -> CivilDate { CivilDate(year: y, month: m, day: day) }

    @Test func weekendIsSaturdayAndSunday() {
        // 21–27 сентября 2026: пн … вс.
        let flags = (21...27).map { PlannerState.isWeekend(d(2026, 9, $0)) }
        #expect(flags == [false, false, false, false, false, true, true])
        #expect(PlannerState.isWeekend(d(1970, 1, 3)) && PlannerState.isWeekend(d(1970, 1, 4)))   // сб, вс
        #expect(!PlannerState.isWeekend(d(1969, 12, 31)))
    }

    private func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private func lum(_ c: (Double, Double, Double)) -> Double { 0.2126 * lin(c.0 / 255) + 0.7152 * lin(c.1 / 255) + 0.0722 * lin(c.2 / 255) }
    private func ratio(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let x = lum(a), y = lum(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    private func over(_ top: (Double, Double, Double), _ a: Double, _ base: (Double, Double, Double)) -> (Double, Double, Double) {
        (top.0 * a + base.0 * (1 - a), top.1 * a + base.1 * (1 - a), top.2 * a + base.2 * (1 - a))
    }
    #if canImport(UIKit)
    private func rgb(_ c: Color) -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r * 255), Double(g * 255), Double(b * 255))
    }
    #endif

    /// Янтарь выходного ≥ 4,5:1 к фону страницы, листу и подложке месяца в обеих темах.
    @Test func weekendInkHoldsContrast() {
        #if canImport(UIKit)
        for scheme in [ColorScheme.dark, .light] {
            let pal = Palette(scheme)
            let ink = rgb(pal.weekend)
            let bg = rgb(pal.bg), surface = rgb(pal.surface)
            let plate = scheme == .dark ? over((0x17, 0x15, 0x0F), 0.74, bg) : over((255, 255, 255), 0.78, bg)
            for (name, base) in [("bg", bg), ("surface", surface), ("plate", plate)] {
                #expect(ratio(ink, base) >= 4.5, "\(scheme) \(name): \(ratio(ink, base))")
            }
            // Не серый: заметно теплее обычных чернил.
            #expect(ink.0 - ink.2 >= 60)
        }
        #endif
    }
}
