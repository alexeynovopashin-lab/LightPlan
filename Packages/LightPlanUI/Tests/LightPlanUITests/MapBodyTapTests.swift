import CoreGraphics
import SwiftUI
import Testing
@testable import LightPlanUI

/// Светила на «Карте» и жесты холста (29.4). Замер на симуляторе: протяжка и щипок, начатые на солнце, карту не
/// двигали — цель светила (круг r 16 своим видом над холстом) забирала касание целиком. Теперь тап по светилу
/// приходит от холста (`canvasTap` → `bodyAt`), а свой вид цели ловит касание только без холста (карта вне сети).
/// Что вид цели над холстом касание больше не берёт, показывает журнал `-LPMapGestureLog` на симуляторе: юнит-тест
/// попадания UIKit (`window.hitTest`) в раннере тестов SwiftUI-цель не видит — отдаёт холсту и с целью, и без (замер).
@MainActor struct MapBodyTapTests {
    /// Окно прибора 17 Pro Max (поля 16, шапка 125, док 717) и кадр экрана.
    static let optic = CGRect(x: 16, y: 125, width: 408, height: 592)
    static let size = CGSize(width: 440, height: 956)
    static let side: CGFloat = 1100

    static func scene(sun: CGPoint? = CGPoint(x: 179, y: 250), moon: CGPoint? = nil) -> MapInstrument.Scene {
        var sc = MapInstrument.Scene()
        sc.sunAt = sun
        sc.sunHorizontal = sun.map { _ in (az: 180, alt: 34) }
        sc.moonAt = moon
        sc.moonHorizontal = moon.map { _ in (az: 120, alt: 10) }
        return sc
    }

    static func screen(_ q: CGPoint) -> CGPoint {
        let (s, ox, oy) = MapInstrumentView.fit(optic)
        return CGPoint(x: ox + q.x * s, y: oy + q.y * s)
    }

    /// Точка экрана — в точку холста (обратное `canvasTap`).
    static func canvas(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - (size.width - side) / 2, y: p.y - (size.height - side) / 2)
    }

    @Test func tapOnSunFromCanvasIsSun() {
        let at = Self.screen(CGPoint(x: 179, y: 250))
        let c = MapInstrumentView.canvasTap(Self.canvas(at), side: Self.side, size: Self.size, scene: Self.scene(),
                                            optic: Self.optic, shown: true)
        #expect(c == .tapSun(az: 180, alt: 34))
    }

    @Test func aimIsSixteenViewBoxPoints() {
        let (s, _, _) = MapInstrumentView.fit(Self.optic)
        let sun = Self.screen(CGPoint(x: 179, y: 250))
        let inside = CGPoint(x: sun.x + 15.5 * s, y: sun.y)
        let outside = CGPoint(x: sun.x + 16.5 * s, y: sun.y)
        #expect(MapInstrumentView.bodyAt(inside, scene: Self.scene(), optic: Self.optic) != nil)
        #expect(MapInstrumentView.bodyAt(outside, scene: Self.scene(), optic: Self.optic) == nil)
    }

    @Test func sunLiesAboveMoon() {
        let sc = Self.scene(sun: CGPoint(x: 179, y: 250), moon: CGPoint(x: 185, y: 250))
        let between = Self.screen(CGPoint(x: 182, y: 250))
        #expect(MapInstrumentView.bodyAt(between, scene: sc, optic: Self.optic) == .tapSun(az: 180, alt: 34))
        let moonOnly = Self.screen(CGPoint(x: 200, y: 250))
        #expect(MapInstrumentView.bodyAt(moonOnly, scene: sc, optic: Self.optic) == .tapMoon(az: 120, alt: 10))
    }

    /// Прибор погашен (маршрут, подмена низа): тап по месту солнца идёт карте.
    @Test func hiddenInstrumentLetsTapThrough() {
        let at = Self.canvas(Self.screen(CGPoint(x: 179, y: 250)))
        #expect(MapInstrumentView.canvasTap(at, side: Self.side, size: Self.size, scene: Self.scene(),
                                            optic: Self.optic, shown: false) == nil)
    }
}
