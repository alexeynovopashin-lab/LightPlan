import Testing
import Foundation
@testable import LightPlanDomain

/// 30и.13: правила большого виджета (Б2) — слова оценки, призрак светила, запасные слова.
struct WidgetBigTests {
    @Test func scoreWordsFollowTheThresholdsOfTheLightScreen() {
        let w = WidgetFeed.Words()
        #expect(BigWidget.scoreWord(75, w) == "красивый" && BigWidget.scoreWord(74, w) == "с цветом")
        #expect(BigWidget.scoreWord(50, w) == "с цветом" && BigWidget.scoreWord(49, w) == "спокойный")
        #expect(BigWidget.scoreWord(28, w) == "спокойный" && BigWidget.scoreWord(27, w) == "серый")
        #expect(BigWidget.scoreLine(34, w) == "спокойный · 34 / 100")
        #expect(BigWidget.scoreLine(nil, w) == nil, "оценки нет — строки нет, числа не выдумываются")
    }

    @Test func theAppsWordWinsOverTheFallback() {
        var w = WidgetFeed.Words()
        w.table["score.calm"] = "calm"
        #expect(BigWidget.scoreWord(30, w) == "calm")
        #expect(BigWidget.phaseWord(.astroNight, w) == "НОЧЬ" && BigWidget.phaseWord(.evening, w) == "ВЕЧЕРЕЕТ")
    }

    @Test func aBodyBelowTheHorizonIsAGhostNotAGapAndFadesDeep() {
        #expect(BigWidget.ghostOpacity(elevation: 5) == 0, "над горизонтом призрака нет")
        #expect(BigWidget.ghostOpacity(elevation: -3) == 1, "на −3° пятно в полную плотность (как `DomeGeometry.deepOf`)")
        #expect(BigWidget.ghostOpacity(elevation: -1.5) == 0.5, "на полпути гаснущего диска — половина")
        #expect(abs(BigWidget.ghostOpacity(elevation: -30) - 2.0 / 3.0) < 1e-9, "глубокой ночью не ниже пола 2/3")
    }
}
