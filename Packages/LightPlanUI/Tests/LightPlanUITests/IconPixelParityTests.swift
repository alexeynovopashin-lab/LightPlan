import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
@testable import LightPlanUI

/// Знаки Swift против знаков Chromium: одна и та же библиотека, нарисованная
/// двумя движками, клетка с клеткой.
///
/// Эталон — `icons_ref.png`, лист, который Chromium рисует из живой `beta/icons.js`
/// (`Tools/icons_ref.js`): клетка 96 px, чёрное на белом, линия 1,5, круглые концы.
/// Swift рисует тот же лист `Icon`-ом. Сглаживание у движков разное, поэтому
/// совпадение не побитовое, а по доле пересечения тёмных пикселей (IoU) и по
/// количеству чернил в клетке.
@MainActor
struct IconPixelParityTests {

    struct Ref: Decodable { let cell: Int; let cols: Int; let rows: Int; let line: Double; let order: [String] }

    private static var dir: URL {
        var u = URL(fileURLWithPath: #filePath)
        u.deleteLastPathComponent()
        return u
    }

    /// Порядок листа: общий словарь, жанры, пожелания — имена по алфавиту.
    static func order() -> [String] {
        IconLibrary.common.keys.sorted().map { "common:" + $0 }
            + IconLibrary.genres.keys.sorted().map { "genres:" + $0 }
            + IconLibrary.wishes.keys.sorted().map { "wishes:" + $0 }
    }

    static func icon(_ key: String, size: CGFloat, line: CGFloat) -> Icon {
        let parts = key.split(separator: ":", maxSplits: 1)
        let name = String(parts[1])
        switch parts[0] {
        case "genres": return Icon(genre: name, size: size, line: line)
        case "wishes": return Icon(wish: name, size: size, line: line)
        default: return Icon(name, size: size, line: line)
        }
    }

    /// Серый 8 бит, белое = 255.
    static func gray(_ image: CGImage) -> (px: [UInt8], w: Int, h: Int) {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 255, count: w * h)
        px.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (px, w, h)
    }

    static func renderSheet(_ ref: Ref) -> CGImage? {
        let keys = order()
        let rows = (0..<ref.rows).map { r in
            HStack(spacing: 0) {
                ForEach(0..<ref.cols, id: \.self) { c in
                    let i = r * ref.cols + c
                    if i < keys.count {
                        icon(keys[i], size: CGFloat(ref.cell), line: CGFloat(ref.line))
                    } else {
                        Color.clear.frame(width: CGFloat(ref.cell), height: CGFloat(ref.cell))
                    }
                }
            }
        }
        let sheet = VStack(spacing: 0) { ForEach(0..<rows.count, id: \.self) { rows[$0] } }
            // Явные 0 и 1: системные `.black` и `.white` в SwiftUI — не крайние точки шкалы
            // (замер: линия выходила серым 39, и чернил казалось на 16 % меньше).
            .foregroundStyle(Color(.sRGB, white: 0, opacity: 1))
            .background(Color(.sRGB, white: 1, opacity: 1))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.cgImage
    }

    struct Cell { let key: String; let iou: Double; let inkRatio: Double; let farMiss: Double }

    static func measure() throws -> [Cell] {
        let ref = try JSONDecoder().decode(Ref.self, from: Data(contentsOf: dir.appendingPathComponent("icons_ref.json")))
        let src = CGImageSourceCreateWithURL(dir.appendingPathComponent("icons_ref.png") as CFURL, nil)!
        let refImg = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        let a = gray(refImg)
        let swiftImg = try #require(renderSheet(ref))
        let b = gray(swiftImg)
        #expect(a.w == b.w && a.h == b.h, "размер листа: эталон \(a.w)×\(a.h), Swift \(b.w)×\(b.h)")
        var cells: [Cell] = []
        let keys = order()
        for (i, key) in keys.enumerated() {
            let x0 = (i % ref.cols) * ref.cell, y0 = (i / ref.cols) * ref.cell
            var inter = 0, union = 0
            var inkA = 0.0, inkB = 0.0
            for y in y0..<(y0 + ref.cell) {
                for x in x0..<(x0 + ref.cell) {
                    let pa = a.px[y * a.w + x], pb = b.px[y * b.w + x]
                    inkA += Double(255 - pa) / 255
                    inkB += Double(255 - pb) / 255
                    let da = pa < 128, db = pb < 128
                    if da && db { inter += 1 }
                    if da || db { union += 1 }
                }
            }
            // Тёмные пиксели одного движка, рядом с которыми (в 2 px) у другого нет тёмных:
            // так отличается сглаживание от сдвинутой или потерянной геометрии.
            func far(_ p: [UInt8], _ q: [UInt8], _ w: Int) -> Int {
                var miss = 0
                for y in y0..<(y0 + ref.cell) {
                    for x in x0..<(x0 + ref.cell) where p[y * w + x] < 128 {
                        var near = false
                        search: for dy in -2...2 {
                            for dx in -2...2 {
                                let yy = y + dy, xx = x + dx
                                if yy >= y0, yy < y0 + ref.cell, xx >= x0, xx < x0 + ref.cell, q[yy * w + xx] < 128 {
                                    near = true; break search
                                }
                            }
                        }
                        if !near { miss += 1 }
                    }
                }
                return miss
            }
            let dark = max(1, union)
            cells.append(Cell(key: key, iou: union == 0 ? 1 : Double(inter) / Double(union),
                              inkRatio: inkA == 0 ? 1 : inkB / inkA,
                              farMiss: Double(far(a.px, b.px, a.w) + far(b.px, a.px, a.w)) / Double(dark)))
        }
        return cells
    }

    @Test func orderMatchesReference() throws {
        let ref = try JSONDecoder().decode(Ref.self, from: Data(contentsOf: Self.dir.appendingPathComponent("icons_ref.json")))
        #expect(Self.order() == ref.order, "порядок знаков в Swift и в эталоне разошёлся — пересобрать: node Tools/icons_ref.js")
    }

    /// Пороги выбраны по замеру 21 сентября 2026 (IoU min 0,925, среднее 0,971;
    /// чернил 0,97–1,03 от эталона) с запасом на разницу версий CoreGraphics.
    /// Ловят потерянную или сдвинутую геометрию и дрейф толщины; сглаживание — нет.
    @Test func matchesChromium() throws {
        let cells = try Self.measure()
        let worst = cells.sorted { $0.iou < $1.iou }.prefix(5)
        print("ЗНАКИ: клеток \(cells.count); IoU min \(cells.map(\.iou).min()!), среднее \(cells.map(\.iou).reduce(0, +) / Double(cells.count)); "
            + "чернил \(cells.map(\.inkRatio).min()!)…\(cells.map(\.inkRatio).max()!); дальше 2 px до пары max \(cells.map(\.farMiss).max()!)")
        for c in worst { print("  худшие: IoU \(String(format: "%.4f", c.iou)) чернил \(String(format: "%.4f", c.inkRatio)) далёких \(String(format: "%.4f", c.farMiss)) \(c.key)") }
        #expect(cells.count == 216)
        let bad = cells.filter { $0.iou < 0.90 || abs($0.inkRatio - 1) > 0.05 || $0.farMiss > 0.01 }
        #expect(bad.isEmpty, "не сошлись с Chromium: \(bad.map { "\($0.key) IoU \(String(format: "%.3f", $0.iou)) чернил \(String(format: "%.3f", $0.inkRatio)) далёких \(String(format: "%.4f", $0.farMiss))" })")
    }
}
