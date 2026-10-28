import Testing
import SwiftUI
import UIKit
@testable import LightPlanUI

/// Строка света дня без подложки-капсулы (28.10, слово Алексея): знаки стоят чернилами на оси цифр, показания —
/// серединой на оси экрана, черта вырезана под свёрнутый шеврон, шеврон нажимается квадратом не меньше 44 pt.
/// Пиксели считаются на 4× (четверть pt): `ImageRenderer` рисует ту же разметку, что строка.
@MainActor
struct LightLineTests {

    private static let scale: CGFloat = 4

    private func gray<V: View>(_ view: V, scheme: ColorScheme, width: CGFloat, height: CGFloat) throws -> (px: [UInt8], w: Int, h: Int) {
        let pal = Palette(scheme)
        let r = ImageRenderer(content: view.frame(width: width, height: height, alignment: .leading)
            .background(pal.surface).environment(\.colorScheme, scheme))
        r.scale = Self.scale
        return IconPixelParityTests.gray(try #require(r.cgImage))
    }

    /// Верх и низ чернил в колонках `cols` (pt) → середина по y в pt; чернила — от фона не меньше чем на полнаибольшего.
    private func inkMid(_ g: (px: [UInt8], w: Int, h: Int), cols: ClosedRange<CGFloat>) -> CGFloat? {
        let bg = Int(g.px[0])
        let x0 = Int(cols.lowerBound * Self.scale), x1 = min(g.w, Int(cols.upperBound * Self.scale))
        var best = 0
        for y in 0..<g.h { for x in x0..<x1 { best = max(best, abs(Int(g.px[y * g.w + x]) - bg)) } }
        guard best > 40 else { return nil }
        var top: Int?, bottom = 0
        for y in 0..<g.h {
            let on = (x0..<x1).contains { abs(Int(g.px[y * g.w + $0]) - bg) * 2 >= best }
            if on { if top == nil { top = y }; bottom = y + 1 }
        }
        guard let top else { return nil }
        return CGFloat(top + bottom) / 2 / Self.scale
    }

    private func row(_ scheme: ColorScheme, weather: String) -> LightLineRow {
        LightLineRow(rise: "08:19", set: "17:47", setColor: Palette(scheme).brass, golden: "57 мин",
                     weather: .init(icon: weather, temp: "17°"), note: "", pal: Palette(scheme))
    }

    /// Знак на оси цифр: середина его чернил от середины чернил цифр ближе чем на 0,3 pt — у каждого из знаков строки
    /// и у каждого знака погоды, в обеих темах. До правки золотой час стоял на 1 pt ниже оси.
    @Test(arguments: [ColorScheme.dark, .light])
    func iconsStandOnTheDigitAxis(_ scheme: ColorScheme) throws {
        for (icon, text) in [("sunrise", "08:19"), ("sunset", "17:47"), ("golden", "57")] {
            let v = row(scheme, weather: "cloud").item(icon, text, Palette(scheme).ink2, node: "t")
            let g = try gray(v, scheme: scheme, width: 80, height: 20)
            let i = try #require(inkMid(g, cols: 0...17)), d = try #require(inkMid(g, cols: 21...80))
            #expect(abs(i - d) < 0.3, "\(icon) \(scheme): значок \(i), цифры \(d), смещение \(i - d) pt")
        }
        for icon in ["clear", "cloud", "rain", "fog"] {
            let v = row(scheme, weather: icon).weatherGroup(.init(icon: icon, temp: "17°")).frame(height: 20)
            let g = try gray(v, scheme: scheme, width: 60, height: 20)
            let i = try #require(inkMid(g, cols: 0...17)), d = try #require(inkMid(g, cols: 29...60))
            #expect(abs(i - d) < 0.3, "погода \(icon) \(scheme): значок \(i), градусы \(d), смещение \(i - d) pt")
        }
    }

    /// Положение показаний: середина на оси экрана; не помещаются — слева с полем 12; вплотную к шеврону не заходят.
    @Test func rowSitsOnTheScreenAxis() {
        // Панель 400, ось в рамке показаний 196 (200 − 4), рамка 352 шириной.
        #expect(LightLine.originX(content: 265, width: 352, axis: 196) == 196 - 132.5)
        #expect(LightLine.originX(content: 300, width: 352, axis: 196) == 46)
        #expect(LightLine.originX(content: 400, width: 352, axis: 196) == 12)      // шире рамки — слева с полем, лишнее срежется
        #expect(LightLine.originX(content: 330, width: 352, axis: 196) == 22)      // середина ушла бы вправо — упирается в край
        #expect(LightLine.originX(content: 265, width: 352, axis: nil) == 12)      // панель не измерена — как было
    }

    /// Черта: раскрыта — сплошная, свёрнута — выемка вокруг шеврона шириной 28 pt, а в 20 pt от него черта цела.
    @Test func ruleLeavesAGapOnlyWhenShut() throws {
        let width: CGFloat = 440
        func g(_ t: Double) throws -> (px: [UInt8], w: Int, h: Int) {
            try gray(LightLineRule(color: .white, t: t).frame(width: width, height: 1), scheme: .dark, width: width, height: 1)
        }
        let c = Int((width - LightLineRule.chevronFromRight) * Self.scale)
        let open = try g(0), shut = try g(1)
        #expect(open.px[c] > 200 && shut.px[c] < 60, "в центре шеврона: раскрыта \(open.px[c]), свёрнута \(shut.px[c])")
        let off = Int(20 * Self.scale)
        #expect(shut.px[c - off] > 200 && shut.px[c + off] > 200, "в 20 pt от шеврона черта цела")
        #expect(shut.px[c + Int(13 * Self.scale)] < 60 && shut.px[c - Int(13 * Self.scale)] < 60, "выемка до 14 pt в каждую сторону")
    }

    @Test func chevronTapSquareIsAtLeast44() {
        #expect(LightLine.tapSide >= 44)
    }

    // MARK: ширина на узких экранах

    private func idealWidth(_ v: LightLineRow) -> CGFloat {
        UIHostingController(rootView: v.fixedSize()).sizeThatFits(in: CGSize(width: 2000, height: 100)).width
    }

    private func wide(_ scheme: ColorScheme, golden: String, rise: String, set: String) -> LightLineRow {
        LightLineRow(rise: rise, set: set, setColor: Palette(scheme).brass, golden: golden,
                     weather: .init(icon: "rain", temp: "17°"), note: "", pal: Palette(scheme))
    }

    /// Рамка показаний на 393 pt: панель 353, минус 2 × 4 и ручка 40 — 305; слева поле 12. Строка с «1 ч 12 м» в 24-часовых часах
    /// помещается; ширины 12-часовых часов с длинной подписью и узкого 320 печатаются, а не требуются (до правки так же резались).
    @Test func rowFitsInTheFrameAt393() {
        let frame = (393 - 40) - 2 * FoldGeometry.inset - FoldGeometry.chevronWidth - LightLine.leadingMin
        let w24 = idealWidth(wide(.dark, golden: "1 ч 12 м", rise: "08:19", set: "17:47"))
        let w12 = idealWidth(wide(.dark, golden: "1 ч 12 м", rise: "8:19 AM", set: "5:47 PM"))
        print("LIGHTLINE width24=\(w24) width12=\(w12) frame393=\(frame) frame440=\(frame + 47) frame320=\(frame - 73)")
        #expect(w24 <= frame, "24 ч, «1 ч 12 м»: \(w24) > \(frame)")
    }

    /// Листы строки в трёх ширинах — по просьбе: `LIGHT_LINE_OUT=<папка>` (папка должна быть).
    @Test func writesTheRowSheetsWhenAsked() throws {
        guard let dir = ProcessInfo.processInfo.environment["LIGHT_LINE_OUT"] else { return }
        for scheme in [ColorScheme.dark, .light] {
            let pal = Palette(scheme)
            for (w, gold, rise, set) in [(320.0, "57 мин", "08:19", "17:47"), (393, "57 мин", "08:19", "17:47"), (393, "1 ч 12 м", "08:19", "17:47"),
                                         (393, "1 ч 12 м", "8:19 AM", "5:47 PM"), (440, "1 ч 12 м", "8:19 AM", "5:47 PM")] {
                let panel = w - 40
                let main = panel - 2 * FoldGeometry.inset - FoldGeometry.chevronWidth
                let v = ZStack(alignment: .topLeading) {
                    LightLineCentre(axis: panel / 2 - FoldGeometry.inset) {
                        LightLineRow(rise: rise, set: set, setColor: pal.brass, golden: gold,
                                     weather: .init(icon: "rain", temp: "17°"), note: "", pal: pal)
                    }
                    .frame(width: main, height: FoldGeometry.barHeight).clipped().offset(x: FoldGeometry.inset)
                    Icon("chevron", size: 16, line: 1.6).rotationEffect(.degrees(-90)).foregroundStyle(pal.ink4)
                        .frame(width: FoldGeometry.chevronWidth, height: FoldGeometry.barHeight).offset(x: panel - FoldGeometry.inset - FoldGeometry.chevronWidth)
                }
                let r = ImageRenderer(content: v.frame(width: panel, height: FoldGeometry.barHeight, alignment: .topLeading).background(pal.surface)
                    .environment(\.colorScheme, scheme))
                r.scale = 3
                if let cg = r.cgImage, let data = UIImage(cgImage: cg).pngData() {
                    let name = "row_\(scheme == .dark ? "dark" : "light")_\(Int(w))_\(gold.count > 6 ? "long" : "short")_\(rise.contains("AM") ? "12h" : "24h").png"
                    try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
                }
            }
        }
    }
}
