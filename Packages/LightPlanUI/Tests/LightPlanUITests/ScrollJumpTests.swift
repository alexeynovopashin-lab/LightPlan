import Testing
import CoreGraphics
import LightPlanDomain
@testable import LightPlanUI

/// Общая кнопка прыжка по длинной странице (Алексей, 28.10): вид мудборда сохранён, правило показа — одно на все экраны.
struct ScrollJumpTests {
    /// Галерея мудборда была 40 pt, `ink4`, поля 20 / 24; папка — 38 pt, `ink3`, поля 24 / 24 (снимки до и после: разница 0).
    @Test func looksKeepTheMoodboardNumbers() {
        let g = ScrollJump.Look.standard, f = ScrollJump.Look.folder
        #expect(g.size == 40 && !g.strong && g.trailing == 20 && g.bottom == 24)
        #expect(f.size == 38 && f.strong && f.trailing == 24 && f.bottom == 24)
    }

    /// Кнопка нужна, когда прокрутки не меньше 0,6 окна; от начала ведёт вниз, за серединой — вверх.
    @Test func ruleIsTheMoodboardOne() {
        #expect(!Moodboard.jumpVisible(scrollable: 515, screen: 860))
        #expect(Moodboard.jumpVisible(scrollable: 516, screen: 860))
        #expect(Moodboard.jumpGoesDown(offset: 0, scrollable: 1000))
        #expect(!Moodboard.jumpGoesDown(offset: 600, scrollable: 1000))
    }

    /// Полоса под прокруткой съедает 56 pt окна, но правило считается по окну без неё: на пороге полоса не мигает,
    /// кнопка не прячется и не появляется от того, что сама сжала окно.
    @Test func stripDoesNotFlickerAtTheThreshold() {
        #expect(ScrollJump.stripHeight == 56)
        for content in stride(from: 1200 as CGFloat, through: 1500, by: 1) {
            // Без полосы окно 860; с полосой то же окно показано как 804 — ответ тот же.
            #expect(ScrollJump.stripVisible(content: content, container: 860, shown: false)
                    == ScrollJump.stripVisible(content: content, container: 860 - ScrollJump.stripHeight, shown: true))
        }
        #expect(!ScrollJump.stripVisible(content: 1375, container: 860, shown: false))   // 515 < 0,6 · 860
        #expect(ScrollJump.stripVisible(content: 1376, container: 860, shown: false))
    }
}
