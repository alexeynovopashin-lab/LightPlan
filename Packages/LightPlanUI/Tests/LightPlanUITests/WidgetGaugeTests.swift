import Testing
import SwiftUI
import Foundation
import LightPlanDomain
import LightPlanCore
#if os(iOS)
import UIKit

/// Столбик оценки с числом внутри (28.10, «при нуле шкала похожа на презерватив»): ширина по самому широкому числу, линза целиком в трубке при 0 и
/// 100, контраст числа с линзой по пикселям в двух темах, строка оценки и время заката слева не наезжают на трубку, картинки состояний.
@MainActor
struct WidgetGaugeTests {

    private static let H = 116.0
    private static let lensRGB = (246.0, 243.0, 236.0)

    private struct Pixels {
        let w: Int, h: Int, scale: Double
        let data: [UInt8]
        func rgb(_ x: Double, _ y: Double) -> (Double, Double, Double) {
            let ix = min(w - 1, max(0, Int((x * scale).rounded(.down)))), iy = min(h - 1, max(0, Int((y * scale).rounded(.down))))
            let o = (iy * w + ix) * 4
            return (Double(data[o]), Double(data[o + 1]), Double(data[o + 2]))
        }
    }

    private func render<V: View>(_ v: V, scale: Double = 4) throws -> Pixels {
        let r = ImageRenderer(content: v)
        r.scale = scale
        let cg = try #require(r.uiImage?.cgImage)
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try #require(CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Pixels(w: w, h: h, scale: scale, data: data)
    }

    /// Столбик на подложке темы, 40 × 130 pt, трубка стоит в (7, 7).
    private func alone(_ score: Int, dark: Bool) -> some View {
        let pal = BraunPalette(dark: dark)
        return BraunGauge(pal: pal, score: score, height: Self.H)
            .offset(x: 7, y: 7)
            .frame(width: 40, height: 130, alignment: .topLeading)
            .background(pal.bg)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.widgetFlatGlass, true)
    }

    private func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double { abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) }

    /// WCAG: относительная яркость и контраст двух sRGB-цветов 0…255.
    private func lum(_ c: (Double, Double, Double)) -> Double {
        func f(_ v: Double) -> Double { let s = v / 255; return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(c.0) + 0.7152 * f(c.1) + 0.0722 * f(c.2)
    }
    private func contrast(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let (x, y) = (lum(a), lum(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    // MARK: Размеры

    /// Трубка 25 (была 18): «100» 10 semibold = 20,04 pt, линза 22 × 14, зазор до стенки 1,5. Правый край 154 остался.
    @Test func theTubeIsAsWideAsTheWidestNumberNeeds() {
        let text = BraunText.width("100", size: BraunGauge.numberSize, semibold: true, mono: true)
        #expect(abs(text - 20.04) < 0.05, "«100»: \(text)")
        #expect(BraunGauge.lensWidth(score: 100) == 22, "линза «100»: \(BraunGauge.lensWidth(score: 100))")
        #expect(BraunGauge.lensWidth(score: 100) + 2 * BraunGauge.lensInset <= BraunGauge.width)
        #expect(BraunGauge.width == 25 && BraunGauge.x + BraunGauge.width == 154)
        for s in 0...100 {
            let t = BraunText.width("\(s)", size: BraunGauge.numberSize, semibold: true, mono: true)
            #expect(t <= BraunGauge.lensWidth(score: s) - 1.9, "\(s): число \(t) в линзе \(BraunGauge.lensWidth(score: s))")
        }
    }

    /// Линза целиком в трубке на любом балле; при 0 у дна, при 100 у верха, в середине — на уровне заливки.
    @Test func theLensStaysInsideTheTube() {
        for s in 0...100 {
            let cy = BraunGauge.lensCenterY(score: s, height: Self.H), half = BraunGauge.lensHeight / 2
            #expect(cy - half >= BraunGauge.lensInset - 1e-9 && cy + half <= Self.H - BraunGauge.lensInset + 1e-9, "\(s): линза \(cy - half)…\(cy + half)")
        }
        #expect(BraunGauge.lensCenterY(score: 0, height: Self.H) == Self.H - 1.5 - 7)
        #expect(BraunGauge.lensCenterY(score: 100, height: Self.H) == 1.5 + 7)
        #expect(BraunGauge.lensCenterY(score: 50, height: Self.H) == 58)
    }

    /// По пикселям: линза (светлая) в колонке по центру трубки лежит там, где говорит формула, в обеих темах, при 0, 12, 45, 67, 100.
    @Test func theLensIsDrawnWhereTheFormulaSaysItIs() throws {
        for dark in [true, false] {
            for s in [0, 12, 45, 67, 100] {
                let px = try render(alone(s, dark: dark))
                let cx = 7 + BraunGauge.width / 2, cy = BraunGauge.lensCenterY(score: s, height: Self.H), half = BraunGauge.lensHeight / 2
                // Сверху и снизу линзы (мимо цифр, 3,4 pt от середины): пиксель — цвет линзы; в 1 pt выше кромки — нет.
                for y in [7 + cy - half + 1.5, 7 + cy + half - 1.5] {
                    #expect(dist(px.rgb(cx, y), Self.lensRGB) <= 60, "\(dark ? "тёмная" : "светлая") \(s): линза должна быть в y \(y), там \(px.rgb(cx, y))")
                }
                for y in [7 + cy - half - 1.5, 7 + cy + half + 1.5] where y > 7 && y < 7 + Self.H {
                    #expect(dist(px.rgb(cx, y), Self.lensRGB) > 60, "\(dark ? "тёмная" : "светлая") \(s): за кромкой линзы (y \(y)) светлого быть не должно")
                }
            }
        }
    }

    // MARK: Контраст

    /// Число (17,17,17) на линзе: пиксель линзы в обеих темах и на всех 101 баллах (под линзой синяя, сиреневая и янтарная заливка, дорожка).
    @Test func theNumberReadsOnTheLensInBothThemes() throws {
        let ink = (17.0, 17.0, 17.0)
        for dark in [true, false] {
            var worst = (ratio: Double.infinity, score: -1)
            for s in 0...100 {
                let px = try render(alone(s, dark: dark), scale: 4)
                let cx = 7 + BraunGauge.width / 2, cy = 7 + BraunGauge.lensCenterY(score: s, height: Self.H)
                // Фон под числом: пиксели линзы над цифрами и под ними (мимо кромки и мимо штрихов).
                let samples = [(cx, cy - 5.2), (cx, cy + 5.2)]
                for (x, y) in samples {
                    let bg = px.rgb(x, y)
                    let r = contrast(ink, bg)
                    if r < worst.ratio { worst = (r, s) }
                }
            }
            print("GAUGE-CONTRAST \(dark ? "dark" : "light") worst \(String(format: "%.2f", worst.ratio)):1 at score \(worst.score)")
            #expect(worst.ratio >= 4.5, "\(dark ? "тёмная" : "светлая"): контраст числа с линзой \(worst.ratio) на балле \(worst.score)")
        }
    }

    // MARK: Колонка слева

    /// Столбик стал шире — слева ничего не наезжает на него: строка оценки (до x 36 + `ratingWidth`) и время заката / завтрашнего рассвета
    /// (x 50 + ширина) кончаются раньше левой стенки трубки. 24 ч и 12 ч, 338 и 364.
    @Test func theLeftColumnStopsBeforeTheTube() throws {
        let words = WidgetFeed.Words()
        for key in [WidgetFeed.Words.Key.skyRise, .skySet] {
            for q in DayQuality.allCases {
                let t = words[key].replacingOccurrences(of: "{t}", with: words.sky(q))
                for icon in [true, false] {
                    let fit = BraunIdleContent.ratingFit(t, icon: icon)
                    #expect(fit.x + BraunText.width(t, size: fit.size, semibold: false) <= BraunGauge.x - 1 + 1e-9, "«\(t)» \(fit.size) pt, знак \(fit.icon)")
                }
            }
        }
        for t in ["17:02", "05:56", "12:52", "5:56 PM", "12:56 PM"] {
            let size = [22.0, 20, 18, 16].first { BraunText.width(t, size: $0, semibold: true, mono: true, tracking: -0.3) <= BraunGauge.x - 2 - 50 } ?? 16
            #expect(50 + BraunText.width(t, size: size, semibold: true, mono: true, tracking: -0.3) <= BraunGauge.x - 2 + 1e-9, "\(t) \(size) pt")
        }
    }

    // MARK: Снимки

    private static let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    private static func at(_ h: Int, day d: Int = 25) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))!.addingTimeInterval(-7 * 3600)
    }
    private static func quality(_ s: Int) -> DayQuality { s >= 80 ? .excellent : s >= 60 ? .good : s >= 35 ? .plain : s >= 15 ? .poor : .fog }

    /// Средний вид «Д» в 14:00 (оценивается закат) с заданным баллом.
    private func medium(_ score: Int, dark: Bool, _ p: CGSize, hour: Int = 14) -> some View {
        let rating = WidgetFeed.Rating(day: "2026-10-25", score: score, quality: Self.quality(score), sunrise: score)
        let f = WidgetFeed(place: Self.tomsk, shoots: [], forecast: [rating], lang: "ru", clock12: false).frame(at: Self.at(hour))
        return BraunIdleView(frame: f, alpha: false)
            .frame(width: p.width, height: p.height)
            .background(BraunPalette(dark: dark).bg)
            .clipShape(RoundedRectangle(cornerRadius: BraunPlate.cornerRadius(plateHeight: p.height), style: .continuous))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.widgetFlatGlass, true)
            .environment(\.widgetFrozenTimer, true)
            .environment(\.widgetFlatGlass, true)
    }

    /// Каталог `$LP_GAUGE_DIR` (по умолчанию `light_plan:Light_Plan/docs/widget_gauge_2026-10-28`, если папка заведена): `gauge_states_<тема>.png` —
    /// столбики 0 / 12 / 45 / 67 / 100 крупно; `medium_gauge_<размер>_<тема>.png` — целый средний вид на тех же баллах.
    @Test func writesTheGaugePicturesWhenAsked() throws {
        let dir = ProcessInfo.processInfo.environment["LP_GAUGE_DIR"]
            ?? "/Users/alexey/Documents/workspace/10_projects/light_plan/Light_Plan/docs/widget_gauge_2026-10-28"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let scores = [0, 12, 45, 67, 100]
        func write<V: View>(_ v: V, _ name: String, scale: Double) throws {
            let r = ImageRenderer(content: v)
            r.scale = scale
            let png = try #require(r.uiImage?.pngData())
            try png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
        for dark in [true, false] {
            let tone = dark ? "dark" : "light"
            let strip = HStack(alignment: .top, spacing: 18) {
                ForEach(scores, id: \.self) { s in
                    VStack(spacing: 6) {
                        alone(s, dark: dark)
                        Text("\(s)").font(.system(size: 11, weight: .medium)).foregroundStyle(dark ? .white : .black)
                    }
                }
            }
            .padding(14).background(BraunPalette(dark: dark).bg)
            try write(strip, "gauge_states_\(tone)", scale: 5)
            for (tag, size) in [("pro", CGSize(width: 364, height: 170)), ("regular", CGSize(width: 338, height: 158))] {
                let grid = VStack(spacing: 12) {
                    ForEach(scores, id: \.self) { s in
                        VStack(spacing: 4) {
                            medium(s, dark: dark, size)
                            Text("оценка заката \(s) · \(tag) \(Int(size.width)) × \(Int(size.height)) · \(dark ? "тёмная" : "светлая")")
                                .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white)
                        }
                    }
                }
                .padding(14).background(Color(red: 0.36, green: 0.35, blue: 0.33))
                try write(grid, "medium_gauge_\(tag)_\(tone)", scale: 2)
            }
        }
    }
}
#endif
