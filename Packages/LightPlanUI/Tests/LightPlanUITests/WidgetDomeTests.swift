import Testing
import SwiftUI
import Foundation
import LightPlanDomain
import LightPlanCore
#if os(iOS)
import UIKit
@testable import LightPlanUI

/// Шаг 30и.7: купол большого виджета (`SunArc` в `LightPlanWidget/Views/LargeView.swift`) — те же пропорции, что у купола «Света»
/// (`DomeGeometry`: 163 × 148), на любой плашке. Числа в расширении скопированы, поэтому здесь они сверяются с приложением, а ширина и
/// высота купола ещё и меряются по пикселям отрисованного неба.
@MainActor
struct WidgetDomeTests {

    private let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    private func tsk(_ h: Int, _ m: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }

    @Test func theCopiedNumbersAreTheAppsOwn() {
        #expect(Double(DomeFit.rx) == DomeGeometry.rx && Double(DomeFit.ry) == DomeGeometry.ry)
        #expect(Double(DomeFit.canvasWidth) == DomeGeometry.viewWidth)
        #expect(Double(DomeFit.horizonUnits) == DomeGeometry.horizonY)
    }

    /// Плашка 338 × 354 (iPhone 14) и 364 × 382 (Pro Max) минус поля 16: купол занимает ширину, форма — 163 : 148 при любой высоте.
    @Test func theShapeIsTheAppsAtEveryPlateSize() {
        for size in [CGSize(width: 306, height: 120), CGSize(width: 306, height: 190), CGSize(width: 332, height: 130), CGSize(width: 332, height: 220), CGSize(width: 332, height: 300)] {
            let fit = DomeFit(in: size)
            let ratio = fit.rx / fit.ry
            #expect(abs(ratio / (163.0 / 148.0) - 1) < 0.001, Comment(rawValue: "\(size): \(ratio)"))
            #expect(fit.centerX == size.width / 2 && fit.horizonY - fit.ry >= 0 && fit.horizonY <= size.height, Comment(rawValue: "\(size) \(fit)"))
            #expect(fit.rx * 2 <= size.width)
        }
        // Широкая плашка с запасом по высоте: купол на ширину холста приложения, как на «Свете» (326 из 390 = 83,6 %).
        let wide = DomeFit(in: CGSize(width: 332, height: 300))
        #expect(abs(wide.rx * 2 / 332 - 326.0 / 390.0) < 0.001)
    }

    /// Меряем небо на картинке: ширина и высота закрашенной области купола.
    @Test func renderedSkyIsOneSixtyThreeByOneFortyEight() throws {
        var report: [String] = []
        for (w, h) in [(332.0, 220.0), (306.0, 200.0), (332.0, 130.0)] {
            let free = WidgetFeed(place: tomsk).frame(at: tsk(12))
            let day = try #require(free.day)
            let v = SunArc(rise: try #require(day.sunrise), set: try #require(day.sunset), now: free.now, clock: "12:00", word: "ЗАКАТ", st: WidgetStyle(dark: true))
                .frame(width: w, height: h).background(Color.black).environment(\.colorScheme, .dark)
            let r = ImageRenderer(content: v)
            r.scale = 3
            let img = try #require(r.uiImage?.cgImage)
            let (bw, bh) = skyBox(img)
            // 163 : 148 — это радиус по горизонтали к радиусу по вертикали: полуширина неба к его высоте.
            let ratio = Double(bw) / 2 / Double(bh)
            report.append("КУПОЛ \(Int(w))×\(Int(h)): небо \(bw)×\(bh) px (×3), полуширина/высота \(String(format: "%.4f", ratio)) при \(String(format: "%.4f", 163.0 / 148.0))")
            #expect(abs(ratio / (163.0 / 148.0) - 1) < 0.01, Comment(rawValue: report.last!))
        }
        print(report.joined(separator: "\n"))
    }

    /// Рамка пикселей «синего неба» (b − r ≥ 24, тёмные): ширина по самому широкому ряду, высота от макушки до горизонта.
    private func skyBox(_ img: CGImage) -> (Int, Int) {
        let w = img.width, h = img.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        func sky(_ x: Int, _ y: Int) -> Bool {
            let i = (y * w + x) * 4
            let r = Int(data[i]), b = Int(data[i + 2])
            return b - r >= 24 && b < 110
        }
        var top = h, bottom = -1, left = w, right = -1
        for y in 0..<h { for x in 0..<w where sky(x, y) {
            top = min(top, y); bottom = max(bottom, y); left = min(left, x); right = max(right, x)
        } }
        return (right - left + 1, bottom - top + 1)
    }

    /// Картинки для глаз: в `$LP_ACTIVITY_SHOTS` или `/tmp/lp-activity-shots`, если папка есть.
    @Test func writesPicturesWhenAsked() throws {
        let dir = ProcessInfo.processInfo.environment["LP_ACTIVITY_SHOTS"] ?? "/tmp/lp-activity-shots"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        for (tag, at, dark) in [("large-day-dark", tsk(12), true), ("large-evening-dark", tsk(16, 30), true), ("large-day-light", tsk(12), false), ("large-night-dark", tsk(22), true)] {
            let f = WidgetFeed(place: tomsk).frame(at: at)
            for (w, h) in [(364.0, 382.0), (338.0, 354.0)] {
                let v = LargeView(frame: f).frame(width: w, height: h)
                    .background(dark ? Color(red: 0.07, green: 0.067, blue: 0.063) : Color(red: 0.98, green: 0.97, blue: 0.95))
                    .environment(\.colorScheme, dark ? .dark : .light)
                let r = ImageRenderer(content: v)
                r.scale = 3
                if let png = r.uiImage?.pngData() { try png.write(to: URL(fileURLWithPath: "\(dir)/\(tag)-\(Int(w)).png")) }
            }
        }
    }
}
#endif
