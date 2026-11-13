import Testing
import SwiftUI
import LightPlanCore
@testable import LightPlanUI

/// 28к.4 (слово Алексея 13.11: «звёзды „Астро“ — чёрные в светлой теме, фон не затемняется»): небо на нажатии «Астро» рисуется
/// в кадр и читается по пикселям. Светлая — звёзды чёрные, прозрачность вне звёзд нулевая (затемнения .42 нет); тёмная — как было:
/// латунные звёзды и затемнение. Кадр берётся на 1,0 с жизни слоя (звёзды зажглись, слой ещё не гаснет: `as-veil` держит до 72 %).
@MainActor
struct AstroSkyLightTests {
    private struct Pixels {
        let w: Int, h: Int
        let data: [UInt8]
        func rgba(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let o = (y * w + x) * 4
            return (Int(data[o]), Int(data[o + 1]), Int(data[o + 2]), Int(data[o + 3]))
        }
    }

    private func frame(_ scheme: ColorScheme) throws -> Pixels {
        let scene = AstroSky.scene(days: AstroSky.days(of: Date(timeIntervalSince1970: 1_790_000_000)), latitude: 53.35, longitude: 83.75, moon: nil)
        // Ширина и высота — поле неба 200 × 430 (`AstroSky.fieldWidth/fieldHeight`), масштаб 1: одна клетка — одна точка.
        let view = AstroSkyView(scene: scene, start: Date().addingTimeInterval(-1.0))
            .frame(width: 200, height: 430)
            .environment(\.colorScheme, scheme)
        let r = ImageRenderer(content: view)
        r.scale = 1
        let cg = try #require(r.uiImage?.cgImage)
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try #require(CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Pixels(w: w, h: h, data: data)
    }

    @Test func lightSkyHasNoVeilAndBlackStars() throws {
        let p = try frame(.light)
        // Фон: во всех четырёх углах полностью прозрачно — серой плёнки .42 нет.
        for (x, y) in [(0, 0), (p.w - 1, 0), (0, p.h - 1), (p.w - 1, p.h - 1)] { #expect(p.rgba(x, y).a == 0, "угол \(x),\(y)") }
        // Звёзды: пиксели с заметной непрозрачностью — чёрные (премультиплицированные каналы нули), и они есть.
        var inked = 0
        for y in 0..<p.h { for x in 0..<p.w {
            let c = p.rgba(x, y)
            if c.a > 60 { inked += 1; #expect(c.r == 0 && c.g == 0 && c.b == 0, "звезда не чёрная в \(x),\(y): \(c)") }
        } }
        #expect(inked > 20, "звёзд не видно: \(inked)")
    }

    @Test func darkSkyKeepsItsVeilAndBrassStars() throws {
        let p = try frame(.dark)
        // Затемнение: угол чёрный с прозрачностью ≈ 0,42 × veil (на 1,0 с veil = 1: слой держится целиком).
        let corner = p.rgba(0, 0)
        #expect(corner.a > 90 && corner.a < 125, "затемнение \(corner)")
        #expect(corner.r == 0 && corner.g == 0 && corner.b == 0)
        // Звёзды — латунь #E2A44C: красный канал ярче синего.
        var brass = 0
        for y in 0..<p.h { for x in 0..<p.w { let c = p.rgba(x, y); if c.a > 200 && c.r > c.b + 40 { brass += 1 } } }
        #expect(brass > 10, "латунных звёзд не видно: \(brass)")
    }
}
