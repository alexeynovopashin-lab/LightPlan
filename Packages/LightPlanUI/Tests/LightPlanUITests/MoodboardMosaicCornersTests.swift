import CoreGraphics
import Foundation
import SwiftUI
import Testing
import LightPlanDomain
@testable import LightPlanUI

/// Углы мозаики плитки «Все» (30и.2, слово Алексея: «углы миниатюр плиток надкушены»). Плитку рисуем в 2× и 3×, в обеих
/// темах, и читаем пиксели у четырёх внешних углов: тонкая рамка (hairline) должна идти по внешнему контуру без разрыва,
/// а не обрываться там, где контур загибается. Отчёт в файл — `TEST_RUNNER_CORNER_REPORT=/путь xcodebuild test …`.
@MainActor
struct MoodboardMosaicCornersTests {

    private static let side: CGFloat = 113  // ширина плитки на 393 pt: (393 − 2·16 − 2·10) / 3

    private static func cells(_ n: Int) -> [MbFolder] {
        (0..<n).map { MbFolder(kind: .shoot, boardId: "mb\($0 * 7 + 3)", boardIds: ["mb\($0 * 7 + 3)"], genre: nil) }
    }

    private struct Pixels {
        let w: Int, h: Int, bytes: [UInt8]
        func rgba(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
            guard x >= 0, y >= 0, x < w, y < h else { return (0, 0, 0, 0) }
            let i = (y * w + x) * 4
            let a = Double(bytes[i + 3]) / 255
            let u = a > 0 ? 1 / a : 0  // из предумноженного обратно
            return (Double(bytes[i]) * u, Double(bytes[i + 1]) * u, Double(bytes[i + 2]) * u, a)
        }
    }

    private func render(_ n: Int, _ scheme: ColorScheme, scale: CGFloat) throws -> Pixels {
        try render(MbMosaic(cells: Self.cells(n), side: Self.side), scheme, scale: scale)
    }

    private func render<V: View>(_ content: V, _ scheme: ColorScheme, scale: CGFloat) throws -> Pixels {
        let view = content.environment(\.colorScheme, scheme)
        let r = ImageRenderer(content: view)
        r.scale = scale
        let img = try #require(r.cgImage)
        var data = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let ctx = try #require(CGContext(data: &data, width: img.width, height: img.height, bitsPerComponent: 8,
                                         bytesPerRow: img.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return Pixels(w: img.width, h: img.height, bytes: data)
    }

    struct CornerReading { var straight = 0.0, arcCover = 0.0, diag = 0.0 }

    /// Угол читается как левый верхний (остальные отражаются). Кольцо — глубина 0,25…0,75 pt под контуром (середина рамки в 1 pt),
    /// заливка — глубина 2,5…4 pt. Контраст — наибольшая разница каналов кольца и средней заливки, из 255.
    private func read(_ p: Pixels, scale: CGFloat, flipX: Bool, flipY: Bool) -> CornerReading {
        func at(_ ux: Int, _ uy: Int) -> (r: Double, g: Double, b: Double, a: Double) {
            p.rgba(flipX ? p.w - 1 - ux : ux, flipY ? p.h - 1 - uy : uy)
        }
        let reach = Int((4.5 * scale).rounded(.up)) + 1, win = Int((40 * scale).rounded()), band = Int((12 * scale).rounded())
        // Расстояние до ближайшего прозрачного пикселя (вне картинки — прозрачно), в pt.
        func depth(_ ux: Int, _ uy: Int) -> Double {
            var best = Double.greatestFiniteMagnitude
            for dy in -reach...reach {
                for dx in -reach...reach {
                    if at(ux + dx, uy + dy).a < 0.5 { best = min(best, (Double(dx * dx + dy * dy)).squareRoot()) }
                }
            }
            return max(0, best - 0.5) / Double(scale)
        }
        var fill: [(Double, Double, Double)] = [], ring: [(ux: Int, uy: Int, c: (Double, Double, Double))] = []
        for uy in 0..<win {
            for ux in 0..<win where (ux < band || uy < band) && at(ux, uy).a >= 0.5 {
                let d = depth(ux, uy), px = at(ux, uy)
                if d >= 2.5 && d <= 4 { fill.append((px.r, px.g, px.b)) }
                if d >= 0.25 && d <= 0.75 { ring.append((ux, uy, (px.r, px.g, px.b))) }
            }
        }
        let n = Double(max(fill.count, 1))
        let m = (fill.map { $0.0 }.reduce(0, +) / n, fill.map { $0.1 }.reduce(0, +) / n, fill.map { $0.2 }.reduce(0, +) / n)
        func contrast(_ c: (Double, Double, Double)) -> Double { max(abs(c.0 - m.0), abs(c.1 - m.1), abs(c.2 - m.2)) }
        // Прямой участок: 16…40 pt от угла вдоль верхней и левой стороны.
        let lo = Int(16 * scale), hi = Int(40 * scale), edge = Int(2.5 * scale)
        let straight = ring.filter { ($0.uy < edge && $0.ux >= lo && $0.ux <= hi) || ($0.ux < edge && $0.uy >= lo && $0.uy <= hi) }
        let s = straight.map { contrast($0.c) }.reduce(0, +) / Double(max(straight.count, 1))
        // Дуга: квадрат 12 × 12 pt в углу.
        let box = Int(12 * scale)
        let arc = ring.filter { $0.ux < box && $0.uy < box }
        let good = arc.filter { contrast($0.c) >= 0.5 * s }.count
        // По диагонали от угла до первого непрозрачного пикселя, pt.
        var k = 0
        while k < win && at(k, k).a < 0.5 { k += 1 }
        return CornerReading(straight: s, arcCover: Double(good) / Double(max(arc.count, 1)), diag: Double(k) * 2.0.squareRoot() / Double(scale))
    }

    @Test func outerCornersKeepTheirRim() throws {
        var lines: [String] = []
        var worst = 1.0
        var diags: [Double] = []
        for scheme in [ColorScheme.dark, .light] {
            for scale in [CGFloat(2), 3] {
                for n in 1...4 {
                    let px = try render(n, scheme, scale: scale)
                    for (name, fx, fy) in [("tl", false, false), ("tr", true, false), ("bl", false, true), ("br", true, true)] {
                        let r = read(px, scale: scale, flipX: fx, flipY: fy)
                        lines.append(String(format: "%@ %dx cells=%d %@ rim=%.0f/255 arcCover=%.2f diag=%.2fpt",
                                            scheme == .dark ? "dark " : "light", Int(scale), n, name, r.straight, r.arcCover, r.diag))
                        worst = min(worst, r.arcCover)
                        diags.append(r.diag)
                        #expect(r.straight > 20, "\(scheme) \(scale)x \(n) \(name): рамки на прямом участке не видно — измерение пустое")
                    }
                }
            }
        }
        if let path = ProcessInfo.processInfo.environment["CORNER_REPORT"] {
            try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
        #expect(worst >= 0.9, "рамка на дуге внешнего угла рвётся: худший охват \(worst)")
        let spread = (diags.max() ?? 0) - (diags.min() ?? 0)
        #expect(spread <= 0.6, "силуэт углов не одинаков: разброс \(spread) pt")
    }

    /// Те же замеры у одиночной обложки (`MbArt`, полоска `MoodboardStrip`, полёт `MbFly`): там обрезки поверх нет, рамка идёт по
    /// той же фигуре, что и заливка, — угол цел и до правки (ошибка только в мозаике).
    @Test func singleCoversKeepTheirRim() throws {
        var lines: [String] = []
        for scheme in [ColorScheme.dark, .light] {
            for radius in [CGFloat(12), 13] {
                let cover = MbCover(boardId: "mb3", genre: nil, radius: radius, mark: 0.56, stroke: 1.9).frame(width: Self.side, height: Self.side)
                let px = try render(cover, scheme, scale: 3)
                for (name, fx, fy) in [("tl", false, false), ("tr", true, false), ("bl", false, true), ("br", true, true)] {
                    let r = read(px, scale: 3, flipX: fx, flipY: fy)
                    lines.append(String(format: "%@ 3x cover r=%.0f %@ rim=%.0f/255 arcCover=%.2f", scheme == .dark ? "dark " : "light", radius, name, r.straight, r.arcCover))
                    #expect(r.arcCover >= 0.9, "\(scheme) r=\(radius) \(name): рамка рвётся (\(r.arcCover))")
                }
            }
        }
        if let path = ProcessInfo.processInfo.environment["CORNER_REPORT"] {
            try? (lines.joined(separator: "\n") + "\n").write(toFile: path + ".single", atomically: true, encoding: .utf8)
        }
    }
}
