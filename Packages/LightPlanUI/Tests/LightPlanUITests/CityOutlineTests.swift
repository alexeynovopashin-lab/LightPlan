import Testing
import CoreGraphics
@testable import LightPlanUI

/// 30и.6: линия города на листе «Откуда вы работаете» — пять путей, один непрерывный росчерк слева направо в рамке 320 × 70.
struct CityOutlineTests {
    @Test func everyOutlineIsOneStrokeInsideTheBox() {
        for outline in CityOutline.allCases {
            #expect(outline.svg.filter { $0 == "M" }.count == 1, "\(outline): путь не одним росчерком")
            let pts = outline.points
            #expect(pts.count > 20, "\(outline)")
            #expect(pts.first?.x == 4, "\(outline) начинается не у левого края")
            #expect(pts.last?.x == 316, "\(outline) кончается не у правого края")
            for p in pts {
                #expect(p.x >= 0 && p.x <= 320 && p.y >= 0 && p.y <= 70, "\(outline): точка \(p) вне рамки")
            }
            // Слева направо: x по пути не уходит назад дальше чем на дугу купола (ширина маленькой луковицы ≤ 12 pt).
            var back: CGFloat = 0, maxX: CGFloat = 0
            for p in pts { maxX = max(maxX, p.x); back = max(back, maxX - p.x) }
            #expect(back <= 0.001, "\(outline): путь идёт назад на \(back)")
        }
    }

    @Test func eachCityHasItsOwnLine() {
        let paths = Set(CityOutline.allCases.map(\.svg))
        #expect(paths.count == CityOutline.allCases.count)
    }

    @Test func namesPickTheirOutline() {
        #expect(CityOutline.of(city: "Москва") == .moscow)
        #expect(CityOutline.of(city: "Moscow") == .moscow)
        #expect(CityOutline.of(city: "Санкт-Петербург") == .petersburg)
        #expect(CityOutline.of(city: "Saint Petersburg") == .petersburg)
        #expect(CityOutline.of(city: "Новосибирск") == .novosibirsk)
        #expect(CityOutline.of(city: "томск") == .tomsk)
        #expect(CityOutline.of(city: "Tomsk") == .tomsk)
        // Остальные — общий; «Томская» и «Новосибирская область» — не города.
        #expect(CityOutline.of(city: "Барнаул") == .generic)
        #expect(CityOutline.of(city: "Томская область") == .generic)
        #expect(CityOutline.of(city: "") == .generic)
    }

    @Test func drawsOverOneAndTwoTenthsSeconds() {
        #expect(CityOutline.drawDuration == 1.2)
    }
}
