import Testing
import CoreGraphics
@testable import LightPlanUI

/// 29.8в.27: «Ветер» уходит из закрытого списка «Света» в раскрытый, когда «Подробно» иначе встаёт под нижнюю панель.
/// Правило решает по измеренным высотам; пересчёт на живом экране меряет `make lightfit` (нужен симулятор).
struct LightWindPlacementTests {
    private static let row: CGFloat = 35

    /// Две высоты прокрутки одного и того же списка (низ кнопки 660): высокий экран оставляет «Ветер» на месте, низкий уводит.
    @Test func tallScreenKeepsWindShortScreenMovesIt() {
        let bottom: CGFloat = 660
        // Зазор с ветром = viewport + 8 − bottom.
        #expect(LightWindPlacement.gapWithWind(buttonBottom: bottom, windRowHeight: Self.row, windMoved: false, viewport: 700) == 48)
        #expect(!LightWindPlacement.shouldMove(buttonBottom: bottom, windRowHeight: Self.row, windMoved: false, viewport: 700))
        #expect(LightWindPlacement.gapWithWind(buttonBottom: bottom, windRowHeight: Self.row, windMoved: false, viewport: 600) == -52)
        #expect(LightWindPlacement.shouldMove(buttonBottom: bottom, windRowHeight: Self.row, windMoved: false, viewport: 600))
    }

    /// Граница: зазор ровно 0 уже «под панелью» (как `gap <= 0` в `light_fit.js`), чуть больше — кнопка видна, ветер остаётся.
    @Test func gapOfZeroCountsAsUnderThePanel() {
        #expect(LightWindPlacement.shouldMove(buttonBottom: 660, windRowHeight: Self.row, windMoved: false, viewport: 652))
        #expect(!LightWindPlacement.shouldMove(buttonBottom: 660, windRowHeight: Self.row, windMoved: false, viewport: 653))
    }

    /// После переноса кнопка поднялась на высоту строки; решение считается от положения «с ветром» и не мигает туда-сюда.
    @Test func decisionDoesNotFlipAfterTheMove() {
        for viewport in stride(from: CGFloat(500), through: 800, by: 1) {
            let before = LightWindPlacement.shouldMove(buttonBottom: 660, windRowHeight: Self.row, windMoved: false, viewport: viewport)
            let after = LightWindPlacement.shouldMove(buttonBottom: 660 - Self.row, windRowHeight: Self.row, windMoved: before, viewport: viewport)
            #expect(before == after, "viewport \(viewport)")
        }
    }

    /// Числа 29.8в.26 → правило: 15 Pro Max (зазор +5,5) и 17 Pro Max (+26,5) остаются как есть, 393 pt (−74,5) и SE 3 (−221) переносят.
    @Test func measuredPhonesAfterStep26() {
        func moves(gap: CGFloat) -> Bool {
            LightWindPlacement.shouldMove(buttonBottom: 700, windRowHeight: Self.row, windMoved: false, viewport: 700 - LightWindPlacement.panelSpacing + gap)
        }
        #expect(!moves(gap: 5.5))
        #expect(!moves(gap: 26.5))
        #expect(moves(gap: -74.5))
        #expect(moves(gap: -55.5))
        #expect(moves(gap: -221))
    }
}
