import Testing
import Foundation
@testable import LightPlanDomain
import LightPlanCore

/// Итерация 26, шаг 4: тревога «прогноз переменился» (`#cdShift`) — порог
/// разницы двух снимков неба якоря. Справка — `card_reference.md`, «Тревога».
struct WeatherShiftTests {

    private func snap(_ q: DayQuality, _ sc: Int?) -> SkySnap { SkySnap(quality: q, sunset: sc) }

    @Test func sameForecastIsNoGap() {
        #expect(WeatherShift.gap(snap(.good, 60), snap(.good, 60)) == 0)
    }

    @Test func missingSnapshotIsNoGap() {
        #expect(WeatherShift.gap(nil, snap(.good, 60)) == 0)
        #expect(WeatherShift.gap(snap(.good, 60), nil) == 0)
    }

    /// Смена категории — повод всегда; дождь и туман по любую сторону — 3.
    @Test func categoryChange() {
        #expect(WeatherShift.gap(snap(.plain, nil), snap(.good, nil)) == 2)
        #expect(WeatherShift.gap(snap(.good, nil), snap(.poor, nil)) == 3)
        #expect(WeatherShift.gap(snap(.fog, nil), snap(.plain, nil)) == 3)
        #expect(WeatherShift.gap(snap(.excellent, nil), snap(.fog, nil)) == 3)
    }

    /// Балл: 19 — дрожь модели, 20 — переменился, 34 — ещё «переменился», 35 — впору переносить.
    @Test func scoreBoundaries() {
        #expect(WeatherShift.gap(snap(.good, 50), snap(.good, 69)) == 0)
        #expect(WeatherShift.gap(snap(.good, 50), snap(.good, 70)) == 2)
        #expect(WeatherShift.gap(snap(.good, 50), snap(.good, 84)) == 2)
        #expect(WeatherShift.gap(snap(.good, 50), snap(.good, 85)) == 3)
        #expect(WeatherShift.gap(snap(.good, 85), snap(.good, 50)) == 3)
    }

    /// Балл 35 поднимает «переменился» от смены категории до 3; балл 20 не
    /// опускает и не поднимает двойку.
    @Test func scoreAndCategoryCombine() {
        #expect(WeatherShift.gap(snap(.plain, 40), snap(.good, 75)) == 3)
        #expect(WeatherShift.gap(snap(.good, 40), snap(.poor, 60)) == 3)
        #expect(WeatherShift.gap(snap(.plain, 40), snap(.good, 60)) == 2)
    }

    /// Без балла хотя бы у одного — судит одна категория.
    @Test func scoreNeedsBothSides() {
        #expect(WeatherShift.gap(snap(.good, nil), snap(.good, 90)) == 0)
    }

    @Test func directionByScoreThenByCategory() {
        #expect(WeatherShift.isUp(snap(.good, 40), snap(.good, 70)))
        #expect(!WeatherShift.isUp(snap(.good, 70), snap(.good, 40)))
        // Баллы равны — ряд категорий: дождь < туман < переменно < облачно < ясно.
        #expect(WeatherShift.isUp(snap(.poor, 50), snap(.plain, 50)))
        #expect(!WeatherShift.isUp(snap(.good, nil), snap(.fog, nil)))
    }

    /// Слово — про балл, если он есть у обоих и разница не меньше 20.
    @Test func sayByScoreOnlyWhenBigEnough() {
        #expect(WeatherShift.saysScore(snap(.good, 50), snap(.good, 70)))
        #expect(!WeatherShift.saysScore(snap(.good, 50), snap(.poor, 69)))
        #expect(!WeatherShift.saysScore(snap(.good, nil), snap(.poor, 90)))
    }
}
