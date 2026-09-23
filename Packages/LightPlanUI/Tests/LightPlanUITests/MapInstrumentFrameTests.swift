import CoreGraphics
import Foundation
import SwiftUI
import Testing
import LightPlanCore
@testable import LightPlanUI

/// Замер кадра прибора карты при движении ползунка (итерация 20а, риск плана:
/// облако Млечного Пути — 697 точек — и путь пересчитываются на каждый шаг).
///
/// Худший случай экрана: «Астро», ночь, все слои. Сутки (путь солнца, луна,
/// трек ядра) считаются раз на день, как в `MapDayCache`; на шаг ползунка —
/// только `MapInstrument.scene`. Рисование меряется отдельно: `ImageRenderer`
/// растрирует тот же `Canvas` процессором в 3× — это верхняя граница, на
/// телефоне `Canvas` рисует видеокарта.
struct MapInstrumentFrameTests {

    static func astroNight() -> (MapInstrument.Input, MapInstrument.Day) {
        let date = CivilDate(year: 2026, month: 9, day: 23)
        let place = Place(latitude: 53.3548, longitude: 83.7698, zone: ZoneID("Asia/Barnaul")!)
        let solar = SolarDay(date: date, place: place)
        var layers = MapLayers()
        layers.mw = true
        let clock = ClockText(language: "ru", preference: .h24)
        let input = MapInstrument.Input(
            date: date, minute: 1380, solar: solar, place: place, layers: layers, pro: true, lightTheme: false,
            chip: .drag, clock: { clock.fmt($0) }, cardinals: ["С", "В", "Ю", "З"])
        return (input, MapInstrument.Day(date: date, place: place, solar: solar))
    }

    /// Кадр ProMotion — 8,3 мс; сцене отдаём не больше половины.
    static let sceneBudgetMs = 4.0
    /// Процессор — не видеокарта, но и он укладывается в кадр ProMotion.
    static let drawCeilingMs = 8.3

    /// Непрозрачных точек в картинке.
    static func inkedPixels(_ image: CGImage) -> Int {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return stride(from: 3, to: buf.count, by: 4).reduce(0) { $0 + (buf[$1] > 0 ? 1 : 0) }
    }

    @Test func sceneFitsHalfAFrameWhileScrubbing() {
        var (input, day) = Self.astroNight()
        let clock = ContinuousClock()
        var worst = Duration.zero, total = Duration.zero, steps = 0
        // Вечер и ночь поминутно — ползунок тащат через закат в темноту.
        for m in stride(from: 1080.0, through: 1439, by: 1) {
            input.minute = m
            let t = clock.measure { _ = MapInstrument.scene(input, day: day) }
            worst = max(worst, t); total += t; steps += 1
        }
        let mean = total / steps
        let ms = { (d: Duration) in Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000 }
        print("MapInstrumentFrameTests: сцена, \(steps) шагов — в среднем \(ms(mean)) мс, худший \(ms(worst)) мс")
        #expect(ms(mean) < Self.sceneBudgetMs, "сцена в среднем \(ms(mean)) мс")
    }

    @MainActor @Test func canvasDrawFitsAFrame() throws {
        var (input, day) = Self.astroNight()
        func renderer(_ minute: Double) -> ImageRenderer<some View> {
            input.minute = minute
            let scene = MapInstrument.scene(input, day: day)
            let r = ImageRenderer(content: Canvas { ctx, _ in
                ctx.scaleBy(x: 408 / 358, y: 408 / 358)
                for el in scene.elements { MapInstrumentView.draw(el, in: &ctx) }
            }
            .frame(width: 408, height: 388))
            r.scale = 3
            return r
        }
        _ = renderer(1379).cgImage   // первый кадр — шрифты и кэши
        let clock = ContinuousClock()
        var total = Duration.zero, worst = Duration.zero
        let frames = 30
        // Рендерер кэширует картинку: каждый кадр — своя минута и свой рендерер,
        // мерится только растрирование.
        var last: CGImage?
        for i in 0..<frames {
            let r = renderer(1380 + Double(i))
            let t = clock.measure { last = r.cgImage }
            total += t; worst = max(worst, t)
        }
        // Быстрый пустой кадр ничего не доказывает: прибор должен быть нарисован.
        #expect(Self.inkedPixels(try #require(last)) > 20_000)
        let ms = { (d: Duration) in Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000 }
        print("MapInstrumentFrameTests: рисование процессором в 3×, \(frames) кадров — в среднем \(ms(total / frames)) мс, "
              + "худший \(ms(worst)) мс")
        #expect(ms(total / frames) < Self.drawCeilingMs, "рисование \(ms(total / frames)) мс")
    }
}
