import Testing
import Foundation
import SwiftUI
import LightPlanCore
@testable import LightPlanUI

/// Малые движения «Съёмок» (29.2в): числа беты и направление листания — без экрана.
@Suite struct MotionTests {
    // MARK: листание сбоку

    @Test func restIsOneSheet() {
        let s = FlipTrack.sheets(at: 7, width: 400)
        #expect(s == [FlipTrack.Sheet(index: 7, x: 0, lead: true)])
        #expect(FlipTrack.sheets(at: 7.9999, width: 400).map(\.index) == [8])
    }

    /// Вперёд (позиция растёт): прежняя страница уходит влево, новая въезжает справа; сумма разрыва — ровно ширина.
    @Test func forwardEntersFromRight() {
        let s = FlipTrack.sheets(at: 7.25, width: 400)
        #expect(s.map(\.index) == [7, 8])
        #expect(s[0].x == -100 && s[1].x == 300)
        #expect(s[1].x - s[0].x == 400)
        #expect(FlipTrack.direction(from: 7, to: 8) == 1)
    }

    /// Назад: тот же ряд кадров задом наперёд — страница 7 (новая) въезжает слева, 8 уходит вправо.
    @Test func backwardEntersFromLeft() {
        let s = FlipTrack.sheets(at: 7.75, width: 400)   // 8 → 7 на трети пути
        #expect(s.map(\.index) == [7, 8])
        #expect(s[0].x == -300 && s[1].x == 100)
        #expect(FlipTrack.direction(from: 8, to: 7) == -1)
        #expect(FlipTrack.direction(from: 8, to: 8) == 0)
    }

    @Test func jumpsDoNotSlide() {
        #expect(!FlipTrack.jumps(from: 7, to: 8))
        #expect(!FlipTrack.jumps(from: 7, to: 6))
        #expect(FlipTrack.jumps(from: 7, to: 9))
    }

    @Test func heightFollowsPageHeights() {
        let h: (Int) -> CGFloat? = { $0 == 7 ? 298 : $0 == 8 ? 358 : nil }
        #expect(FlipTrack.height(at: 7, of: h) == nil)
        #expect(FlipTrack.height(at: 7.5, of: h) == 328)
        #expect(FlipTrack.height(at: 8.5, of: h) == nil)   // страница 9 неизвестна — берётся высота большей
    }

    @Test func pageNumbersRoundTrip() {
        for (y, m) in [(2026, 1), (2026, 9), (2026, 12), (2027, 1)] {
            let d = CivilDate(year: y, month: m, day: 1)
            #expect(FlipTrack.monthStart(FlipTrack.monthIndex(d)) == d)
        }
        #expect(FlipTrack.monthIndex(CivilDate(year: 2026, month: 10, day: 1)) - FlipTrack.monthIndex(CivilDate(year: 2026, month: 9, day: 1)) == 1)
        // Неделя: любой день недели даёт номер понедельника; следующая неделя — на единицу больше.
        let wed = CivilDate(year: 2026, month: 9, day: 23)
        let w = FlipTrack.weekIndex(wed)
        #expect(FlipTrack.weekStart(w) == CivilDate(year: 2026, month: 9, day: 21))
        #expect(FlipTrack.weekIndex(wed.adding(days: 7)) == w + 1)
        #expect(FlipTrack.weekIndex(wed.adding(days: -2)) == w)
        #expect(PlannerState.grid(of: CivilDate(year: 2026, month: 10, day: 1)).count == 35)
    }

    // MARK: дыхание кольца

    @Test func ringBreathNumbers() {
        #expect(abs(RingBreath.opacity(at: 0) - 1) < 1e-9)
        #expect(abs(RingBreath.opacity(at: 1.8) - 0.55) < 1e-6)
        #expect(abs(RingBreath.opacity(at: 3.6) - 1) < 1e-6)
        #expect(abs(RingBreath.opacity(at: 3.6 * 7 + 1.8) - 0.55) < 1e-6)
        // ease-in-out: у краёв медленнее, чем линейно; середина полупериода — ровно 0,775.
        #expect(RingBreath.opacity(at: 0.45) > 1 - 0.45 * 0.25)
        #expect(abs(RingBreath.opacity(at: 0.9) - 0.775) < 1e-6)
        for i in 0..<360 {
            let o = RingBreath.opacity(at: Double(i) / 100)
            #expect(o >= 0.55 - 1e-9 && o <= 1 + 1e-9)
        }
    }

    // MARK: сводка дня

    @Test func foldGeometryEnds() {
        let open = FoldGeometry.frames(t: 0, width: 400)
        #expect(open.bar == CGRect(x: 4, y: 9, width: 392, height: 38))
        #expect(open.chevron == CGRect(x: 356, y: 9, width: 40, height: 38))
        #expect(open.main == CGRect(x: 4, y: 9, width: 352, height: 38))
        #expect(open.height == 47)
        let shut = FoldGeometry.frames(t: 1, width: 400)
        #expect(shut.bar == CGRect(x: 356, y: -10.5, width: 40, height: 22))
        #expect(shut.main.width == 0)
        #expect(shut.height == 1)
        #expect(shut.line == CGRect(x: -20, y: 0, width: 440, height: 1))
        // Правый край плашки стоит на месте весь путь.
        for t in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(FoldGeometry.frames(t: t, width: 400).bar.maxX == 396)
        }
        // Середина пути — посередине.
        #expect(FoldGeometry.frames(t: 0.5, width: 400).bar.width == 216)
    }

    // MARK: веер видов

    @Test func scopeInPoses() {
        let a = ScopeIn.pose(0)
        #expect(a.scale == 0.94 && a.opacity == 0)
        #expect(abs(a.dy - (-10 * 0.06 - 6)) < 1e-9 && abs(a.dx - 20 * 0.06) < 1e-9)
        let b = ScopeIn.pose(1)
        #expect(b == ScopeIn.Pose(scale: 1, dx: 0, dy: 0, opacity: 1))
        let still = ScopeIn.pose(0.3, still: true)
        #expect(still.scale == 1 && still.dy == 0 && still.opacity == 0.3)
    }

    // MARK: вкладка

    @Test func riseNumbers() {
        #expect(RiseEffect.pose(0).dy == 8 && RiseEffect.pose(0).opacity == 0)
        #expect(RiseEffect.pose(1).dy == 0 && RiseEffect.pose(1).opacity == 1)
        #expect(Motion.riseShift == 8)
    }
}
