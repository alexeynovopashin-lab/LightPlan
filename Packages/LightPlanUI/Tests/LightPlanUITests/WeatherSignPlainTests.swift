import Testing
import LightPlanCore
@testable import LightPlanUI

/// 31.4: «Переменно» (`.plain`) без осадков рисовалось облаком с каплями — Алексей 18.11, Томск, −7°, осадков 0 мм во все часы:
/// «на улице -7, прогноз показывает дождь». Капли — только у настоящего дождя, снежинка — у снега.
struct WeatherSignPlainTests {

    @Test("«Переменно» без осадков — солнце с облаком, не капли")
    func plainIsNotRain() {
        #expect(DayQuality.plain.signIconName(nil) == "part")
        // Сутки без осадков (коды 0–3, 0 мм), закатный балл «переменно»: знак дня и знак минуты — без капель.
        let day = WeatherDay(quality: .plain, cloud: 60, sunset: 35, layers: nil, temperatureBase: -7, wind: 2,
                             windDirection: nil, gust: 0, trend: [], real: true, sky: .plain, precip: nil)
        #expect(day.signIconName != "rain")
        #expect(day.signIconName(at: 9 * 60 + 21) != "rain")
        // Капли и снежинка — только при осадках.
        #expect(DayQuality.poor.signIconName(.rain) == "rain")
        #expect(DayQuality.poor.signIconName(.snow) == "snow")
        #expect(DayQuality.poor.signIconName(nil) == "cloud")
        for q in DayQuality.allCases where q != .poor { #expect(q.signIconName(nil) != "rain", "\(q)") }
    }
}
