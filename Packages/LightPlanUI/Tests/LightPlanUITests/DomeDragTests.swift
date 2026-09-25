import CoreGraphics
import Testing
import LightPlanCore
@testable import LightPlanUI

/// Светило пальцем по куполу (итерация 19в): ось жеста, точка на дуге,
/// минута. Сам распознаватель UIKit без пальца не проверить — его проверили
/// протяжкой в симуляторе (DECISIONS, 19в); здесь то, что он спрашивает.
struct DomeDragTests {

    // MARK: - Ось по первому движению

    /// Вертикаль — прокрутка страницы, светило не трогается. Порча оси
    /// (вертикаль тянет солнце) валит этот тест.
    @Test func verticalGoesToScrollNotToTheSun() {
        #expect(DomeDrag.axis(dx: 2, dy: 12) == .scroll)
        #expect(DomeDrag.axis(dx: -3, dy: -9) == .scroll)
        #expect(DomeDrag.axis(dx: 7, dy: -7) == .scroll)   // поровну — прокрутка
    }

    @Test func horizontalDragsTheSun() {
        #expect(DomeDrag.axis(dx: 12, dy: 2) == .drag)
        #expect(DomeDrag.axis(dx: -9, dy: 4) == .drag)
    }

    /// Касание без движения само светило не двигает: до 6 pt ось не решена.
    @Test func touchBelowThresholdDecidesNothing() {
        #expect(DomeDrag.axis(dx: 5.9, dy: 0) == .pending)
        #expect(DomeDrag.axis(dx: -5, dy: 5) == .pending)
        #expect(DomeDrag.axis(dx: 0, dy: 0) == .pending)
    }

    // MARK: - Точка на дуге

    private let g = DomeGeometry.self

    @Test func arcEndsAndZenith() throws {
        #expect(try #require(DomeDrag.fraction(at: CGPoint(x: g.cx - g.rx, y: g.cy))) == 0)
        #expect(try #require(DomeDrag.fraction(at: CGPoint(x: g.cx + g.rx, y: g.cy))) == 1)
        #expect(abs(try #require(DomeDrag.fraction(at: CGPoint(x: g.cx, y: g.cy - g.ry))) - 0.5) < 1e-12)
    }

    /// Ниже горизонта больше 8 — строки под куполом, не дуга.
    @Test func belowHorizonIsNotOurs() {
        #expect(DomeDrag.fraction(at: CGPoint(x: g.cx, y: g.cy + 8.5)) == nil)
        #expect(DomeDrag.fraction(at: CGPoint(x: g.cx, y: g.cy + 7.5)) != nil)
    }

    /// Чуть ниже горизонта слева — восход, справа — закат. Веб прижимает
    /// отрицательный угол к нулю, и слева у него выходил закат.
    @Test func justBelowHorizonStaysOnItsSide() {
        #expect(DomeDrag.fraction(at: CGPoint(x: g.cx - 100, y: g.cy + 4)) == 0)
        #expect(DomeDrag.fraction(at: CGPoint(x: g.cx + 100, y: g.cy + 4)) == 1)
    }

    /// Рамка 440×240 (17 Pro Max): холст вписан с полями по 25, палец на
    /// левом конце нарисованной дуги — это восход, а не доля ширины рамки.
    @Test func fingerLandsOnTheDrawnArc() throws {
        let size = CGSize(width: 440, height: 240)
        let left = DomeDrag.viewPoint(CGPoint(x: 25 + g.cx - g.rx, y: g.cy), in: size)
        #expect(abs(left.x - (g.cx - g.rx)) < 1e-9)
        #expect(try #require(DomeDrag.fraction(at: left)) == 0)
    }

    // MARK: - Минута

    @Test func minuteFollowsTheArcAndStaysInTheDay() {
        #expect(DomeDrag.minute(fraction: 0, arcStart: 400, arcEnd: 1100, mint: 0, maxt: 1440) == 400)
        #expect(DomeDrag.minute(fraction: 0.5, arcStart: 400, arcEnd: 1100, mint: 0, maxt: 1440) == 750)
        #expect(DomeDrag.minute(fraction: 0.3337, arcStart: 400, arcEnd: 1100, mint: 0, maxt: 1440) == 634)
        // Луна: дуга выходит за окно суток — минута прижата к окну.
        #expect(DomeDrag.minute(fraction: 1, arcStart: 1200, arcEnd: 1900, mint: 10, maxt: 1450) == 1450)
    }
}
