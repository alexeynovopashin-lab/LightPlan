import Testing
import SwiftUI
import LightPlanCore
@testable import LightPlanUI

/// 28к.5: дуга светлой темы, вариант Г1 «тонкая» (DECISIONS 13.11). Числа листа `light_arc_2026-11-13/build.py`: толщина 2,4 pt у вершины
/// → 4,0 pt у оснований (ровно по углу), слои от оси 0,46 / 0,76 / 1,0 / 2,1 / 4,6 толщины, цвет по высоте солнца.
@MainActor
struct DomeArcG1Tests {
    private let place = Place(latitude: 53.3481, longitude: 83.7798, zone: ZoneID(fixedOffsetHours: 7))
    private func sun(_ m: Int, _ d: Int) -> SolarDay { SolarDay(date: CivilDate(year: 2026, month: m, day: d), place: place) }

    // MARK: Толщина

    @Test func thicknessGrowsEvenlyFromApexToFoot() {
        #expect(ArcG1.thickness(atAngle: 90) == 2.4)
        #expect(ArcG1.thickness(atAngle: 0) == 4.0)
        #expect(ArcG1.thickness(atAngle: 180) == 4.0)
        #expect(abs(ArcG1.thickness(atAngle: 45) - 3.2) < 1e-12)       // середина пути — середина толщины
        #expect(abs(ArcG1.thickness(atAngle: 135) - 3.2) < 1e-12)
        var last = ArcG1.thickness(atAngle: 90)
        for a in stride(from: 88.0, through: 0, by: -2) {              // к основанию только шире
            let w = ArcG1.thickness(atAngle: a)
            #expect(w > last); last = w
        }
    }

    /// Контур каждого слоя у вершины: ширина слоя = доля × 2,4 pt (по верху ограничивающего прямоугольника: вершина стоит на cy − ry).
    @Test func layerOutlinesAtTheApexMatchTheSheet() {
        let apex = DomeGeometry.cy - DomeGeometry.ry
        let layers: [(String, Double, Double)] = [
            ("жила", ArcG1.coreShare, 1.104), ("переход", ArcG1.peachShare, 1.824), ("кромка", ArcG1.edgeShare, 2.4),
            ("плотное", ArcG1.denseShare, 5.04), ("мягкое", ArcG1.softShare, 11.04),
        ]
        for (name, share, width) in layers {
            let box = ArcG1.outline(scale: share).boundingRect
            #expect(abs(Double(box.minY) - (apex - width / 2)) < 0.005, "\(name): верх контура")
        }
        // Ножки: ширина кромки у основания — 4,0 pt (контур доходит до горизонта и по бокам на 2,0 pt от оси).
        let foot = ArcG1.outline(scale: 1).boundingRect
        #expect(abs(Double(foot.minX) - (DomeGeometry.cx - DomeGeometry.rx - 2.0)) < 0.005)
        #expect(abs(Double(foot.maxX) - (DomeGeometry.cx + DomeGeometry.rx + 2.0)) < 0.005)
    }

    // MARK: Цвет по высоте солнца

    @Test func whitenessFollowsTheSunHeight() {
        #expect(ArcG1.goldenBelow == 6 && ArcG1.whiteFrom == 30 && ArcG1.whiteShareOfMax == 0.8)   // стартовые числа, их правит Алексей
        #expect(ArcG1.whiteness(elevation: -5, dayMax: 60) == 0)
        #expect(ArcG1.whiteness(elevation: 6, dayMax: 60) == 0)           // «ниже 6° — оранжевая»
        #expect(ArcG1.whiteness(elevation: 30, dayMax: 60) == 1)          // «с 30° — белая»
        #expect(ArcG1.whiteness(elevation: 45, dayMax: 60) == 1)
        #expect(abs(ArcG1.whiteness(elevation: 18, dayMax: 60) - 0.5) < 1e-12)   // середина 6…30 — ровно пол-белого
        // Зима: полдень 13°, верх — 0,8 от него (10,4°), а не 30°.
        #expect(ArcG1.whiteness(elevation: 10.4, dayMax: 13) == 1)
        #expect(ArcG1.whiteness(elevation: 8.2, dayMax: 13) > 0.4 && ArcG1.whiteness(elevation: 8.2, dayMax: 13) < 0.6)
        // День, где солнце не поднимается выше золотой границы: не делит на ноль и не переворачивается.
        let low = ArcG1.whiteness(elevation: 5, dayMax: 4)
        #expect(low == 0)
        var last = -1.0
        for e in stride(from: -10.0, through: 70, by: 2.5) {
            let w = ArcG1.whiteness(elevation: e, dayMax: 60)
            #expect(w >= last); last = w
        }
    }

    @Test func summerAndWinterRampsInBarnaul() {
        let summer = ArcG1.whiteRamp(for: sun(6, 21)), winter = ArcG1.whiteRamp(for: sun(12, 21))
        #expect(summer.count == 41 && winter.count == 41)
        #expect(summer[0] == 0 && summer[40] == 0 && winter[0] == 0 && winter[40] == 0)   // у горизонта оранжевая
        #expect(summer[20] == 1 && winter[20] == 1)                                        // вершина белая и летом, и зимой
        // Те же дни на листе (`build.py`: `white(SUMMER|WINTER, i/40)`, упрощённая формула склонения): совпадают до 0,06 летом и до 0,12 зимой —
        // приложение берёт точное солнце на реальную дату и дугу от восхода с рефракцией (−0,833°), лист — склонение ±23,44° и геометрический
        // горизонт; зимой день короток, и тот же сдвиг по времени даёт больший сдвиг белизны.
        let sheetSummer: [Int: Double] = [4: 0.188, 6: 0.612, 8: 0.963, 10: 1.0]
        let sheetWinter: [Int: Double] = [6: 0.026, 8: 0.464, 10: 0.9, 12: 1.0]
        for (i, w) in sheetSummer { #expect(abs(summer[i] - w) < 0.06, "лето, отсчёт \(i): \(summer[i]) против \(w)") }
        for (i, w) in sheetWinter { #expect(abs(winter[i] - w) < 0.12, "зима, отсчёт \(i): \(winter[i]) против \(w)") }
        #expect(summer[8] > winter[8])                                                     // летом дуга белеет раньше по ходу дня
        for i in 0..<20 { #expect(summer[i] <= summer[i + 1] && winter[i] <= winter[i + 1]) }
        for i in 0...40 { #expect(abs(summer[i] - summer[40 - i]) < 0.02) }                // день почти симметричен
    }

    @Test func gradientsStandWhereTheArcStands() {
        let ramp = ArcG1.whiteRamp(for: sun(6, 21))
        let g = ArcG1.gradient(ramp, from: ArcG1.orange, to: ArcG1.cream)
        #expect(g.stops.count == 41)
        #expect(g.stops.first?.location == 0 && g.stops.last?.location == 1)
        #expect(abs(g.stops[20].location - 0.5) < 1e-12)
        for i in 1..<41 { #expect(g.stops[i].location > g.stops[i - 1].location) }
        // Стоп по X дуги: час идёт по углу, положение — (1 − cos) / 2.
        #expect(abs(g.stops[10].location - (1 - cos(.pi / 4)) / 2) < 1e-12)
        #expect(ArcG1.RGB.mix(ArcG1.orange, ArcG1.white, 0) == ArcG1.orange)
        #expect(ArcG1.RGB.mix(ArcG1.orange, ArcG1.white, 1) == ArcG1.white)
        #expect(ArcG1.RGB.mix(ArcG1.orange, ArcG1.white, 0.5) == ArcG1.RGB(248, 201, 148))   // (240+255)/2 = 247.5 → 248 и т. д.
    }

    // MARK: В кадре

    private func frame(sun: SolarDay) throws -> (w: Int, h: Int, data: [UInt8]) {
        let view = Canvas { context, _ in ArcG1.paint(&context, sun: sun) }.frame(width: 390, height: 250)
        let r = ImageRenderer(content: view)
        r.scale = 1
        let cg = try #require(r.uiImage?.cgImage)
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try #require(CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return (w, h, data)
    }

    @Test func arcIsDrawnAboveTheHorizonOnly() throws {
        let f = try frame(sun: sun(6, 21))
        func alpha(_ x: Int, _ y: Int) -> Int { Int(f.data[(y * f.w + x) * 4 + 3]) }
        let cx = Int(DomeGeometry.cx), apex = Int(DomeGeometry.cy - DomeGeometry.ry)
        #expect(alpha(cx, apex) == 255)                      // вершина: жила и кромка непрозрачны
        #expect(alpha(cx, apex - 3) > 0)                     // свечение выше кромки
        #expect(alpha(cx, apex + 30) == 0)                   // под дугой пусто
        for y in Int(DomeGeometry.horizonY)..<f.h { for x in stride(from: 0, to: f.w, by: 7) { #expect(alpha(x, y) == 0) } }
    }
}
