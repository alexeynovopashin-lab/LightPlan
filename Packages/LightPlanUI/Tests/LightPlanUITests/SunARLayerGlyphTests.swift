import Testing
import SwiftUI
import Foundation
@testable import LightPlanUI

/// Знаки слоёв «Созвездия» / «Планеты» / «Млечный Путь» в списке «Слоёв» (шаг 29.8в.16): рамка знака, толщина линии,
/// узнаваемые части (семь звёзд ковша, два круга орбит, две ветви спирали) и крупный лист для сверки глазами.
@MainActor
struct SunARLayerGlyphTests {

    private func render<V: View>(_ view: V, scale: CGFloat) -> CGImage? {
        let r = ImageRenderer(content: view)
        r.scale = scale
        return r.cgImage
    }

    /// Рамка непрозрачных пикселей знака на прозрачном фоне, в единицах холста 24 × 24, — `scale` точек на единицу.
    private func extent<V: View>(_ glyph: V, scale: CGFloat = 8) -> CGRect? {
        guard let img = render(glyph.frame(width: 24, height: 24), scale: scale),
              let data = img.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let w = img.width, h = img.height, bpp = img.bitsPerPixel / 8
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where bytes[y * img.bytesPerRow + x * bpp + (bpp - 1)] > 24 || bytes[y * img.bytesPerRow + x * bpp] > 24 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= 0 else { return nil }
        let k = CGFloat(scale)
        return CGRect(x: CGFloat(minX) / k, y: CGFloat(minY) / k, width: CGFloat(maxX - minX + 1) / k, height: CGFloat(maxY - minY + 1) / k)
    }

    @Test("знаки слоёв занимают рамку 3…21 холста 24 × 24 (как `stars` библиотеки: 3,6…20,4) и не выходят за него")
    func glyphsFillTheFrame() throws {
        let glyphs: [(String, AnyView)] = [("ковш", AnyView(DipperGlyph())), ("солнечная система", AnyView(SolarSystemGlyph())),
                                           ("галактика", AnyView(GalaxyGlyph()))]
        for (name, g) in glyphs {
            let e = try #require(extent(g), "\(name): знак пуст")
            print(String(format: "ARLAY знак %@: рамка x %.1f…%.1f, y %.1f…%.1f, размах %.1f × %.1f pt", name, e.minX, e.maxX, e.minY, e.maxY, e.width, e.height))
            #expect(e.minX >= 1.5 && e.minY >= 1.5 && e.maxX <= 22.5 && e.maxY <= 22.5, "\(name): знак вылезает из холста: \(e)")
            #expect(max(e.width, e.height) >= 17 && max(e.width, e.height) <= 21.5, "\(name): размах \(max(e.width, e.height)) pt вне 17…21,5")
        }
    }

    @Test("ковш — семь звёзд, рукоятка и чаша связаны; система — солнце, две орбиты, две планеты; галактика — две ветви и ядро")
    func partsAreThere() {
        #expect(SunARLayerGlyph.dipper.count == 7)
        // Чаша — четыре последние звезды (Мегрец, Фекда, Мерак, Дубхе); рукоятка — первые три до Мегреца.
        let bowl = Array(SunARLayerGlyph.dipper.suffix(4))
        #expect(bowl[0].x < bowl[3].x && bowl[1].y > bowl[0].y && bowl[2].y > bowl[3].y, "чаша не четырёхугольник: \(bowl)")
        #expect(SunARLayerGlyph.orbits.count == 2 && SunARLayerGlyph.bodies.count == 2)
        for b in SunARLayerGlyph.bodies {
            let c = SunARLayerGlyph.bodyCenter(b), s = SunARLayerGlyph.systemCenter
            #expect(abs(hypot(c.x - s.x, c.y - s.y) - SunARLayerGlyph.orbits[b.orbit]) < 0.01, "планета сошла с орбиты")
        }
        #expect(SunARLayerGlyph.sunRadius < SunARLayerGlyph.orbits[0] - 2, "солнце упёрлось в первую орбиту")
        // Ветви спирали начинаются по разные стороны от ядра и не входят в него.
        let a = SunARLayerGlyph.armPoint(arm: 0, t: 0), b = SunARLayerGlyph.armPoint(arm: 1, t: 0)
        let c = SunARLayerGlyph.galaxyCenter
        #expect(hypot(a.x - b.x, a.y - b.y) > 2 * SunARLayerGlyph.coreRadius, "ветви начинаются в ядре")
        #expect(hypot(a.x - c.x, a.y - c.y) > SunARLayerGlyph.coreRadius + SunARLayerGlyph.line / 2 - 0.2)
        let tip = SunARLayerGlyph.armPoint(arm: 0, t: 1)
        #expect(abs(tip.x - c.x) <= SunARLayerGlyph.armOuter + 0.01 && abs(tip.y - c.y) <= SunARLayerGlyph.armOuter + 0.01)
        #expect(SunARLayerGlyph.line >= 1.5 && SunARLayerGlyph.line <= 1.6, "линия \(SunARLayerGlyph.line) вне 1,5…1,6")
    }

    /// Лист для глаз: три знака крупно (×8) и в натуральную величину (×3, как на экране) на тёмном и светлом стекле.
    /// Путь — в переменной `LP_GLYPH_SHEET` (нет — лист не пишется).
    @Test("лист знаков: ×8 и в натуральную величину, тёмное и светлое стекло")
    func sheet() throws {
        func row(_ bg: Color) -> some View {
            VStack(spacing: 12) {
                HStack(spacing: 24) {
                    DipperGlyph().scaleEffect(8).frame(width: 192, height: 192)
                    SolarSystemGlyph().scaleEffect(8).frame(width: 192, height: 192)
                    GalaxyGlyph().scaleEffect(8).frame(width: 192, height: 192)
                }
                HStack(spacing: 24) {
                    DipperGlyph().frame(width: 28, height: 28)
                    SolarSystemGlyph().frame(width: 28, height: 28)
                    GalaxyGlyph().frame(width: 28, height: 28)
                    StarsToggleIcon()
                    MoonToggleIcon(illuminated: 0.5, waxing: true)
                }
            }
            .padding(20).frame(width: 700).background(bg)
        }
        let sheet = VStack(spacing: 0) {
            row(Color(red: 0.16, green: 0.18, blue: 0.22))
            row(Color(red: 0.55, green: 0.60, blue: 0.68))
        }
        let img = try #require(render(sheet, scale: 2))
        #expect(img.width > 1000)
        if let path = ProcessInfo.processInfo.environment["LP_GLYPH_SHEET"] ?? UserDefaults.standard.string(forKey: "LP_GLYPH_SHEET") {
            let r = ImageRenderer(content: sheet); r.scale = 2
            if let png = r.uiImage?.pngData() { try png.write(to: URL(fileURLWithPath: path)); print("ARLAY лист знаков: \(path)") }
        }
    }
}
