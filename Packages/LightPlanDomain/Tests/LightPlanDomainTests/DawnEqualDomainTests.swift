import Testing
import Foundation
import LightPlanCore
@testable import LightPlanDomain

/// 31.5: пожелание «Рассвет» судится рассветом, как «Закат» — закатом (Алексей 18.11: «закаты и рассветы равнозначны»).
struct DawnWishTests {

    static func sky(day: DayQuality?, sunset: Int? = nil, sunrise: Int? = nil, dawn: DayQuality? = nil) -> WishSky {
        WishSky(quality: day, sunsetScore: sunset, astroNight: true, moonLevel: nil, moonPercent: nil, moonFraction: 0.5,
                sunriseScore: sunrise, dawnQuality: dawn)
    }

    @Test("тусклый рассвет — тот же порог 50, что у заката; слова — свои")
    func dullDawnIsTheSameThresholdAsADullSunset() {
        let c = WishCheck.check(.sunrise, sky: Self.sky(day: .excellent, sunset: 90, sunrise: 40), city: false)
        #expect(c?.key == "dullSunrise" && c?.params["score"] == "40")
        #expect(WishCheck.check(.sunrise, sky: Self.sky(day: .excellent, sunset: 90, sunrise: 50), city: false) == nil)
        // Зеркало: тот же день глазами «Заката».
        #expect(WishCheck.check(.sunset, sky: Self.sky(day: .excellent, sunset: 40, sunrise: 90), city: false)?.key == "dullSunset")
    }

    @Test("рассвета без балла судит небо рассвета, а не заката")
    func dawnSkyNotTheSunsetSky() {
        // Дождь утром, вечер сухой: день (окно заката) — не «плохо», рассвет — «плохо».
        #expect(WishCheck.check(.sunrise, sky: Self.sky(day: .good, dawn: .poor), city: false)?.key == "noSunrise")
        #expect(WishCheck.check(.sunrise, sky: Self.sky(day: .good, dawn: .poor), city: false)?.sky == .poor)
        // Дождь вечером, утро сухое — «Рассвету» он не помеха (на main — «Рассвета не будет»).
        #expect(WishCheck.check(.sunrise, sky: Self.sky(day: .poor, dawn: .good), city: false) == nil)
        // Неба рассвета нет (старые вызовы) — как было: по дню.
        #expect(WishCheck.check(.sunrise, sky: Self.sky(day: .poor), city: false)?.key == "noSunrise")
    }
}

/// 31.5: слово неба рассвета в виджетах — небом рассвета (`dawnQuality`), как слово заката — категорией дня.
struct DawnWidgetTests {
    @Test("дождь у восхода — «серо» у рассвета, вечер не задет; файл старого вида — как было")
    func rainAtDawnGreysTheDawnWord() throws {
        let r = WidgetFeed.Rating(day: "2026-11-18", score: 70, quality: .good, sunrise: 80, dawnFog: false, dawnQuality: .poor)
        #expect(BraunIdle.quality(.sunrise, r) == .poor)
        #expect(BraunIdle.quality(.sunset, r) == .good)
        let old = WidgetFeed.Rating(day: "2026-11-18", score: 70, quality: .good, sunrise: 80, dawnFog: false)
        #expect(BraunIdle.quality(.sunrise, old) == .excellent)
        // Файл без поля читается (виджет старой сборки и новое приложение — или наоборот).
        let json = try JSONEncoder().encode(old)
        #expect(try JSONDecoder().decode(WidgetFeed.Rating.self, from: json).dawnQuality == nil)
        let back = try JSONDecoder().decode(WidgetFeed.Rating.self, from: JSONEncoder().encode(r))
        #expect(back.dawnQuality == "poor")
    }
}
