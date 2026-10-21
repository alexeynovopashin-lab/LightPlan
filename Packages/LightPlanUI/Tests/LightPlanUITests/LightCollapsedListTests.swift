import Testing
import CoreGraphics
@testable import LightPlanUI

/// 29.8в.27: необязательные строки закрытого списка «Света» («Тени», «Небо», «Ветер») в «Астро» стоят, пока кнопка «Запланировать съёмку»
/// помещается над панелью; возвращаются по очереди «Тени» → «Небо» → «Ветер». «Просто» — все на месте. Зазоры в точках меряет `make lightfit`.
struct LightCollapsedListTests {
    private static let row: CGFloat = 35
    private static let heights = [row, row, row]

    /// Запас (высота прокрутки − низ «Подробно» без строк − кнопка съёмки) → число вернувшихся строк. Запасы — из замера 29.8в.27:
    /// 393×852 → 11, 402×874 → 30, 15 Pro Max → 91, 17 Pro Max → 112 (низ «Подробно» без строк = 500, кнопка 38).
    @Test func spareDecidesHowManyRowsComeBack() {
        func fit(spare: CGFloat) -> Int {
            LightCollapsedList.fitCount(visibleHeight: 500 + 38 + spare, spoilerBottom: 500, shownRowsHeight: 0, actionHeight: 38, rowHeights: Self.heights)
        }
        #expect(fit(spare: 11) == 0)
        #expect(fit(spare: 30) == 0)
        #expect(fit(spare: 34.9) == 0)
        #expect(fit(spare: 35) == 1)
        #expect(fit(spare: 91) == 2)
        #expect(fit(spare: 104.9) == 2)
        #expect(fit(spare: 112) == 3)
        #expect(fit(spare: -5) == 0)
    }

    /// После показа строк «Подробно» опустилось на их высоту; решение считается от положения «без строк» и не мигает.
    @Test func decisionDoesNotFlipOnceRowsAreShown() {
        for spare in stride(from: CGFloat(-10), through: 150, by: 1) {
            let first = LightCollapsedList.fitCount(visibleHeight: 538 + spare, spoilerBottom: 500, shownRowsHeight: 0, actionHeight: 38, rowHeights: Self.heights)
            let shownHeight = CGFloat(first) * Self.row
            let again = LightCollapsedList.fitCount(visibleHeight: 538 + spare, spoilerBottom: 500 + shownHeight, shownRowsHeight: shownHeight,
                                                    actionHeight: 38, rowHeights: Self.heights)
            #expect(first == again, "spare \(spare)")
        }
    }

    @Test func rowsComeBackInTheirOnScreenOrder() {
        #expect(LightCollapsedList.shown(astro: true, fit: 0, hasForecast: true).isEmpty)
        #expect(LightCollapsedList.shown(astro: true, fit: 1, hasForecast: true) == [.shadow])
        #expect(LightCollapsedList.shown(astro: true, fit: 2, hasForecast: true) == [.shadow, .sky])
        #expect(LightCollapsedList.shown(astro: true, fit: 3, hasForecast: true) == [.shadow, .sky, .wind])
        #expect(LightCollapsedList.shown(astro: true, fit: 9, hasForecast: true) == [.shadow, .sky, .wind])
    }

    /// Без прогноза у экрана только «Тени» (небо и ветер — из прогноза).
    @Test func withoutForecastOnlyShadowExists() {
        #expect(LightCollapsedList.present(hasForecast: false) == [.shadow])
        #expect(LightCollapsedList.shown(astro: true, fit: 3, hasForecast: false) == [.shadow])
    }

    @Test func simpleAlwaysShowsEverything() {
        #expect(LightCollapsedList.shown(astro: false, fit: 0, hasForecast: true) == [.shadow, .sky, .wind])
        #expect(LightCollapsedList.shown(astro: false, fit: 0, hasForecast: false) == [.shadow])
    }
}
