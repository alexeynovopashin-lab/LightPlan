import Testing
import CoreGraphics
@testable import LightPlanUI

/// 29.8в.26: список «Света» поднят на `domeTuck` под дугой — «Подробно» не уходит под нижнюю панель.
/// Зазор кнопка/панель в точках меряет `make lightfit` (нужен симулятор); здесь — то, что держит число.
struct LightScreenDomeTuckTests {
    /// Слово Алексея 21.10: 22 pt из пустой полосы под дугой.
    @Test func tuckIsTwentyTwo() {
        #expect(LightScreenView.domeTuck == 22)
    }

    /// У веба от горизонта до рамки купола 240 − 196 = 44 pt и ещё 2 pt поля до подписи. Подпись не должна подойти к
    /// линии горизонта ближе 20 pt (дуга и её концевые точки стоят на этой линии).
    @Test func labelStaysClearOfHorizon() {
        let strip = CGFloat(DomeGeometry.viewHeight - DomeGeometry.horizonY) + 2
        #expect(strip == 46)
        #expect(strip - LightScreenView.domeTuck >= 20)
    }

    /// Рамка купола не укорочена: показание (124 от верха) и перетаскивание светила считаются от неё.
    @Test func domeFrameKeepsWebHeight() {
        #expect(DomeView.height == 240)
    }
}
