import Testing
import SwiftUI
import Foundation
import LightPlanDomain
import LightPlanCore
#if os(iOS)
import UIKit

/// Красный флажок Braun у окошка «осталось свадьбы» (Алексей 30.10): он сам левый край окошка — вплотную, без подложки между ними, и ростом с
/// окошко, а не выше на блик. Замер по пикселям отрисованного вида (а не по числам Domain): флажок ищется по цвету, видимое окошко — по отличию
/// от подложки в колонке справа от цифр.
@MainActor
struct WidgetFlagFlushTests {

    struct Px {
        let w: Int, h: Int, scale: Double
        let data: [UInt8]
        func at(_ ix: Int, _ iy: Int) -> (r: Int, g: Int, b: Int) {
            let ix = min(w - 1, max(0, ix)), iy = min(h - 1, max(0, iy))
            let o = (iy * w + ix) * 4
            return (Int(data[o]), Int(data[o + 1]), Int(data[o + 2]))
        }
        func pt(_ x: Double, _ y: Double) -> (r: Int, g: Int, b: Int) { at(Int((x * scale).rounded(.down)), Int((y * scale).rounded(.down))) }
    }

    private func render<V: View>(_ v: V, size: CGSize, dark: Bool, scale: Double) throws -> Px {
        let pal = BraunPalette(dark: dark)
        let view = v.frame(width: size.width, height: size.height).background(pal.bg)
            .clipShape(RoundedRectangle(cornerRadius: BraunPlate.cornerRadius(plateHeight: size.height), style: .continuous))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.widgetFrozenTimer, true).environment(\.widgetFlatGlass, true)
        let r = ImageRenderer(content: view)
        r.scale = scale
        let cg = try #require(r.uiImage?.cgImage)
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try #require(CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Px(w: w, h: h, scale: scale, data: data)
    }

    /// Что нашлось на картинке (pt): рамка красного, видимое окошко и сколько пикселей подложки легло между ними.
    struct Found {
        var flagX0 = 0.0, flagX1 = 0.0, flagY0 = 0.0, flagY1 = 0.0
        var windowTop = 0.0, windowBottom = 0.0
        /// По строкам флажка: пиксели подложки в двух пикселях правее последнего красного — щель.
        var plateAfterFlag = 0
        var rowsChecked = 0
    }

    private func isRed(_ c: (r: Int, g: Int, b: Int), _ strict: Bool = false) -> Bool { c.r - c.g > (strict ? 90 : 60) && c.r - c.b > 40 }

    private func find(_ px: Px, width w: Double, dark: Bool) -> Found {
        var f = Found()
        let s = px.scale
        // Флажок: красные пиксели справа сверху, там, где окошко.
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for iy in Int(8 * s)..<Int(44 * s) { for ix in Int((w - 130) * s)..<px.w where isRed(px.at(ix, iy)) {
            minX = min(minX, ix); maxX = max(maxX, ix); minY = min(minY, iy); maxY = max(maxY, iy)
        } }
        guard maxX >= 0 else { return f }
        f.flagX0 = Double(minX) / s; f.flagX1 = Double(maxX + 1) / s; f.flagY0 = Double(minY) / s; f.flagY1 = Double(maxY + 1) / s
        // Видимое окошко — колонка в 4 pt от его правого края (цифры кончаются дальше): от подложки сверху отличается тело, снизу ещё и светлая кромка.
        let plate = px.pt(w - 16 - 4, 13)
        func diff(_ c: (r: Int, g: Int, b: Int)) -> Int { max(abs(c.r - plate.r), abs(c.g - plate.g), abs(c.b - plate.b)) }
        let col = Int((w - 16 - 4) * s)
        let rows = Int(13 * s)..<Int(38 * s)
        if let top = rows.first(where: { diff(px.at(col, $0)) >= 12 }) { f.windowTop = Double(top) / s }
        var windowBottom = 34.0
        if let bottom = rows.last(where: { diff(px.at(col, $0)) >= 6 }) { f.windowBottom = Double(bottom + 1) / s; windowBottom = f.windowBottom }
        // Щель: правее последнего красного пикселя строки сразу идёт окошко (или красный с ним пополам), а не подложка. Крайние строки пропущены — у них край;
        // нижние 2 pt тоже: светлая кромка окошка там проходит через цвет подложки, и пиксель окошка от неё не отличить.
        for iy in (minY + 1)..<min(maxY, Int((windowBottom - 2) * s)) {
            guard let last = (minX...maxX).last(where: { isRed(px.at($0, iy), true) }) else { continue }
            f.rowsChecked += 1
            for ix in (last + 1)...(last + 2) {
                let c = px.at(ix, iy)
                if !isRed(c) && max(abs(c.r - plate.r), abs(c.g - plate.g), abs(c.b - plate.b)) < 8 { f.plateAfterFlag += 1 }
            }
        }
        return f
    }

    private func check(_ f: Found, _ tag: String, scale: Double) {
        let px1 = 1.0 / scale + 1e-9
        #expect(f.rowsChecked > 20, "\(tag): флажок не найден (строк \(f.rowsChecked))")
        #expect(f.plateAfterFlag == 0, "\(tag): между флажком и окошком видна подложка — \(f.plateAfterFlag) пикселей")
        #expect(abs(f.flagY0 - f.windowTop) <= px1, "\(tag): верх флажка \(f.flagY0), верх окошка \(f.windowTop)")
        #expect(abs(f.flagY1 - f.windowBottom) <= px1, "\(tag): низ флажка \(f.flagY1), низ окошка \(f.windowBottom)")
    }

    private static let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    private static func tsk(_ h: Int, _ m: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }
    /// Свадьба 12:00–24:30 без маршрута (форма Б): в окошке «9:12:00», «10:00:00», «0:45:00» → «45:00», 12-часовые часы.
    private static func bare(_ h: Int, _ m: Int, clock12: Bool = false) -> WidgetFrame {
        let wedding = WidgetFeed.Shoot(id: "w", start: Moment(tsk(12)).milliseconds, end: Moment(tsk(24, 30)).milliseconds, title: "Свадьба", genre: "wedding", names: "Анна и Игорь")
        return WidgetFeed(place: tomsk, shoots: [wedding], forecast: [.init(day: "2026-10-25", score: 62, quality: .good)], lang: clock12 ? "en" : "ru", clock12: clock12).frame(at: tsk(h, m))
    }

    private static let sizes: [(String, CGSize)] = [("364", CGSize(width: 364, height: 170)), ("338", CGSize(width: 338, height: 158))]

    /// Форма Б: красная полоса — левый край окошка; вплотную и по росту видимого окошка, в обеих темах, на двух плашках, на 2×, 3× и 4×, при часах из одной,
    /// двух цифр, с минутами и 12-часовых.
    @Test func theBareFlagIsTheWindowsLeftEdgeAndItsHeight() throws {
        let cases: [(String, WidgetFrame)] = [("9:12:00", Self.bare(15, 18)), ("10:30:00", Self.bare(14, 0)), ("45:00", Self.bare(23, 45)), ("12ч 9:12:00", Self.bare(15, 18, clock12: true))]
        for (name, size) in Self.sizes { for dark in [true, false] { for scale in [2.0, 3.0, 4.0] { for (text, frame) in cases {
            let px = try render(BraunWidgetView(frame: frame, alpha: false, medium: true), size: size, dark: dark, scale: scale)
            check(find(px, width: Double(size.width), dark: dark), "Б \(name) \(dark ? "тёмная" : "светлая") \(Int(scale))× \(text)", scale: scale)
        } } } }
    }

    /// Формы с маршрутом (А, В): тот же флажок — левый край окошка, а не шеврон 7 × 12 в 3 pt от него (30.10). «long» — «9:12:00», «first» — «12:xx:xx», «last» — «40:00».
    @Test func theRouteFlagIsTheWindowsLeftEdgeToo() throws {
        for (name, size) in Self.sizes { for dark in [true, false] { for scale in [2.0, 3.0, 4.0] { for key in ["long", "first", "last"] {
            let px = try render(BraunWidgetView(frame: WidgetBraunViewTests.scenario(key), alpha: false, medium: true), size: size, dark: dark, scale: scale)
            check(find(px, width: Double(size.width), dark: dark), "маршрут \(name) \(dark ? "тёмная" : "светлая") \(Int(scale))× \(key)", scale: scale)
        } } } }
    }

    /// Снимки Б и А/В для сверки «до / после» по пикселям (`tools`: python по папке) — пишутся, если папка заведена (`$LP_FLAG_DIR`, `/tmp/lp-flag-out/after`).
    @Test func writesThePicturesWhenAsked() throws {
        let dir = ProcessInfo.processInfo.environment["LP_FLAG_DIR"] ?? "/tmp/lp-flag-out/after"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        for (name, size) in Self.sizes { for dark in [true, false] { for scale in [2.0, 3.0] {
            for (kind, frame) in [("bare", Self.bare(15, 18)), ("chev", WidgetBraunViewTests.scenario("long"))] {
                let pal = BraunPalette(dark: dark)
                let view = BraunWidgetView(frame: frame, alpha: false, medium: true).frame(width: size.width, height: size.height).background(pal.bg)
                    .clipShape(RoundedRectangle(cornerRadius: BraunPlate.cornerRadius(plateHeight: size.height), style: .continuous))
                    .environment(\.colorScheme, dark ? .dark : .light).environment(\.widgetFrozenTimer, true).environment(\.widgetFlatGlass, true)
                let r = ImageRenderer(content: view)
                r.scale = scale
                try #require(r.uiImage?.pngData()).write(to: URL(fileURLWithPath: "\(dir)/\(kind)_\(name)_\(dark ? "d" : "l")_\(Int(scale))x.png"))
            }
        } } }
    }
}
#endif
