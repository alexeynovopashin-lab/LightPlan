import Testing
import CoreGraphics
@testable import LightPlanUI

/// Шапка формы закреплена (Алексей 28.10): ✕ и ✓ вставлены сверху, а не лежат в потоке прокрутки.
@MainActor
struct FormBarTests {
    /// Высота вставки — прежняя высота шапки в потоке (поле 46 + кнопка 40 + поле 8): в покое заголовок не сдвинулся
    /// (снимки до и после при покое — ни одного пикселя больше 6/255).
    @Test func pinnedBarKeepsTheOldRestingLayout() {
        #expect(FormScreen.barHeight == CGFloat(46 + 40 + 8))
    }
}
