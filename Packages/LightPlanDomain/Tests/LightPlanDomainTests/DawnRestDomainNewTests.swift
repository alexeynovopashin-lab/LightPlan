import Testing
import Foundation
import LightPlanCore
@testable import LightPlanDomain

/// 31.6, правила на новом API (на `c7b1256b` не собирается): небо пожеланий утренней съёмки, свет карточки для «Рассвета».
struct DawnRestDomainNewTests {

    static func sky(quality: DayQuality, dawn: DayQuality, atDawn: Bool) -> WishSky {
        WishSky(quality: quality, sunsetScore: nil, astroNight: true, moonLevel: 0, moonPercent: 50, moonFraction: 0.5,
                dawnQuality: dawn, atDawn: atDawn)
    }

    /// П. 5: «Ясно», «Облачно», «Дождь» и облака под «Луной» у утренней съёмки — небом рассвета.
    @Test("пожелания погоды утренней съёмки судятся небом рассвета, вечерней — заката")
    func weatherWishesUseTheShootSky() {
        let rainyDawn = Self.sky(quality: .excellent, dawn: .poor, atDawn: true)
        #expect(WishCheck.check(.rain, sky: rainyDawn, city: false) == nil)
        #expect(WishCheck.check(.clear, sky: rainyDawn, city: false)?.sky == .poor)
        #expect(WishCheck.check(.moon, sky: rainyDawn, city: false)?.key == "moonCloud")
        let evening = Self.sky(quality: .excellent, dawn: .poor, atDawn: false)
        #expect(WishCheck.check(.rain, sky: evening, city: false)?.key == "noRain")
        #expect(WishCheck.check(.clear, sky: evening, city: false) == nil)
        #expect(WishCheck.check(.moon, sky: evening, city: false) == nil)
        // «Закат» утренней съёмки судится всё равно закатом, «Рассвет» вечерней — рассветом.
        #expect(WishCheck.check(.sunset, sky: Self.sky(quality: .poor, dawn: .excellent, atDawn: true), city: false)?.key == "noSunset")
        #expect(WishCheck.check(.sunrise, sky: Self.sky(quality: .excellent, dawn: .poor, atDawn: false), city: false)?.key == "noSunrise")
    }

    /// П. 9: «Рассвет» — то же правило, что «Закат», по утреннему окну.
    @Test("свет карточки для «Рассвета»: в золотом часе утра, мимо на N, плохое небо рассвета")
    func dawnLightCase() throws {
        let day = CivilDate(year: 2026, month: 9, day: 21)
        let morning = MorningLight(blueA: 400, goldenA: 470)
        func probe(_ start: Int, bad: Bool = false, wishes: [Wish] = [.sunrise]) -> LightCase? {
            var s = Session(id: "s", day: day, start: start, end: start + 30)
            s.wishes = wishes
            return LightCase.ofDawn(s, route: [], spots: [], studios: [], morning: { _, _ in morning }, skyIsBad: { _ in bad })
        }
        #expect(probe(420) == .inGolden(point: LightPoint(minute: 420, name: nil), window: GoldenWindow(start: 400, end: 470)))
        #expect(probe(392) == .inGolden(point: LightPoint(minute: 392, name: nil), window: GoldenWindow(start: 400, end: 470)), "допуск 10 минут")
        #expect(probe(560) == .nearGolden(point: LightPoint(minute: 560, name: nil), window: GoldenWindow(start: 400, end: 470), gap: 90))   // часы съёмки 560 и 590: ближе 560
        #expect(probe(420, bad: true) == .badSky(point: LightPoint(minute: 420, name: nil), day: day))
        #expect(probe(420, wishes: [.sunset]) == nil, "без «Рассвета» молчит")
        // «Закат» — по-прежнему только вечером.
        var s = Session(id: "s", day: day, start: 420, end: 450)
        s.wishes = [.sunrise]
        #expect(LightCase.of(s, route: [], spots: [], studios: [], evening: { _, _ in EveningLight(goldenB: 1100, blueB: 1170) },
                             skyIsBad: { _ in false }) == nil)
    }

    /// 31.6б: «Звёзды» — облаками ночи (`nightSky`), небо дня их больше не судит; ночного прогноза нет — облачность не называется.
    @Test("«Звёзды» судятся небом ночи, а не заката")
    func starsUseTheNightSky() {
        func sky(day: DayQuality, night: DayQuality?) -> WishSky {
            WishSky(quality: day, sunsetScore: nil, astroNight: true, moonLevel: 0, moonPercent: 0, moonFraction: 0.5, nightSky: night)
        }
        #expect(WishCheck.check(.stars, sky: sky(day: .poor, night: .excellent), city: false) == nil)
        #expect(WishCheck.check(.stars, sky: sky(day: .excellent, night: .poor), city: false)?.stars == [.clouds(sky: .poor)])
        #expect(WishCheck.check(.stars, sky: sky(day: .poor, night: nil), city: false) == nil)
    }
}
