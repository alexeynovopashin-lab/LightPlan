import Testing
import Foundation
import LightPlanCore
@testable import LightPlanDomain

/// 31.4 «Туман по часам»: категория дня судит туман у заката, а то, что смотрит на утро, — туманом у рассвета (`dawnFog`):
/// оценка рассвета в виджетах и пожелание «Туман» в форме. День утреннего тумана с ясным вечером: категория `.good`, `dawnFog`.
struct FogByHourDomainTests {

    @Test("виджет: рассвет — «туман» по туману у рассвета, закат — по категории дня")
    func widgetSunrise() throws {
        let morningFog = WidgetFeed.Rating(day: "2026-11-06", score: 60, quality: .good, sunrise: 30, dawnFog: true)
        #expect(BraunIdle.quality(.sunrise, morningFog) == .fog)
        #expect(BraunIdle.quality(.sunset, morningFog) == .good)
        // Туман только к вечеру: рассвет судится своим баллом.
        let eveningFog = WidgetFeed.Rating(day: "2026-11-06", score: nil, quality: .fog, sunrise: 80, dawnFog: false)
        #expect(BraunIdle.quality(.sunrise, eveningFog) == .excellent)
        #expect(BraunIdle.quality(.sunset, eveningFog) == .fog)
        // Файл старого вида (без `dawnFog`) — как раньше: туман утра = категория дня «туман».
        let old = Data(#"{"day":"2026-11-06","score":null,"quality":"fog","sunrise":80}"#.utf8)
        let r = try JSONDecoder().decode(WidgetFeed.Rating.self, from: old)
        #expect(r.dawnFog == nil && BraunIdle.quality(.sunrise, r) == .fog)
        // Поле переживает файл.
        let back = try JSONDecoder().decode(WidgetFeed.Rating.self, from: JSONEncoder().encode(morningFog))
        #expect(back == morningFog)
    }

    @Test("форма: пожелание «Туман» сбывается туманом у рассвета; без тумана — плашка, как раньше")
    func fogWish() {
        func sky(_ q: DayQuality, dawnFog: Bool) -> WishSky {
            WishSky(quality: q, sunsetScore: 60, astroNight: true, moonLevel: 0, moonPercent: 0, moonFraction: 0.5, dawnFog: dawnFog)
        }
        #expect(WishCheck.check(.fog, sky: sky(.good, dawnFog: true), city: false) == nil)
        #expect(WishCheck.check(.fog, sky: sky(.good, dawnFog: false), city: false)?.key == "wrongWx")
        #expect(WishCheck.check(.fog, sky: sky(.fog, dawnFog: false), city: false) == nil)
        // Туман у рассвета не делает ясным «Ясно» и не сбывает «Облачно»: они судятся категорией дня, как раньше.
        #expect(WishCheck.check(.clear, sky: sky(.good, dawnFog: true), city: false)?.key == "wrongWx")
        #expect(WishCheck.check(.cloudy, sky: sky(.good, dawnFog: true), city: false) == nil)
    }
}
