import Testing
import SwiftUI
import Foundation
import LightPlanDomain
import LightPlanCore
@testable import LightPlanUI
#if os(iOS)
import UIKit

/// 30и.15: малый «окно неба» (`SmallSkyView`, Н2) по пикселям: какой вид стоит, небо по времени, Солнце и Луна там, где их ставит правило,
/// красный указатель у окошка, и ничего не выходит за плашку на 170 и 158 pt в обеих темах.
@MainActor
struct WidgetSmallSkyViewTests {
    private static let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    private static func tsk(_ h: Int, _ m: Int = 0, day d: Int = 24) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }
    private static func ms(_ d: Date) -> Int64 { Moment(d).milliseconds }
    private static var wedding: WidgetFeed.Shoot {
        .init(id: "w", start: ms(tsk(12, day: 25)), end: ms(tsk(20, day: 25)), title: "Свадьба", genre: "wedding", names: "Анна+Игорь")
    }
    private static let forecast: [WidgetFeed.Rating] = [
        .init(day: "2026-10-24", score: 62, quality: .good, sunrise: 34), .init(day: "2026-10-25", score: 82, quality: .excellent, sunrise: 51),
        .init(day: "2026-10-26", score: nil, quality: .fog), .init(day: "2026-10-27", score: 41, quality: .plain),
    ]
    static func frame(at now: Date, shoots: [WidgetFeed.Shoot]) -> WidgetFrame {
        WidgetFeed(place: tomsk, shoots: shoots, forecast: forecast).frame(at: now)
    }

    enum Case: CaseIterable { case day, dusk, night, emptyWeek }
    static func frame(_ c: Case) -> WidgetFrame {
        switch c {
        case .day: frame(at: tsk(13), shoots: [wedding])
        case .dusk: frame(at: tsk(17, 25), shoots: [wedding])
        case .night: frame(at: tsk(21), shoots: [wedding])
        case .emptyWeek: frame(at: tsk(21), shoots: [])
        }
    }
    static let sizes: [CGFloat] = [170, 158]

    private func plate(_ f: WidgetFrame, _ w: CGFloat, dark: Bool, alpha: Bool = false) -> some View {
        WidgetRoot(frame: f, shape: .small, alpha: alpha)
            .frame(width: w, height: w)
            .clipShape(RoundedRectangle(cornerRadius: w > 165 ? 22 : 20.5, style: .continuous))
            .environment(\.colorScheme, dark ? .dark : .light)
    }

    // MARK: Пиксели

    struct Pixels {
        let w: Int, h: Int, scale: Double
        let data: [UInt8]
        func rgb(_ x: Double, _ y: Double) -> (Double, Double, Double) {
            let ix = min(w - 1, max(0, Int((x * scale).rounded(.down)))), iy = min(h - 1, max(0, Int((y * scale).rounded(.down))))
            let o = (iy * w + ix) * 4
            return (Double(data[o]), Double(data[o + 1]), Double(data[o + 2]))
        }
    }
    private func render<V: View>(_ v: V, scale: Double = 3) throws -> Pixels {
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
    private func hex(_ v: UInt32) -> (Double, Double, Double) { (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF)) }
    private func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double { abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) }

    /// Центр светила под холмом с центром `cx` на горизонте 90 (радиус 42,5): там его не видно, проверять нечего.
    private func behindHill(_ p: CGPoint, _ cx: Double) -> Bool {
        let dx = Double(p.x) - cx, dy = Double(p.y) - 90
        return dx * dx + dy * dy < 42.5 * 42.5
    }

    // MARK: Какой вид

    @Test func onlyAQuietSmallPlateIsTheSkyWindow() {
        for c in Case.allCases { #expect(SmallSky.shows(Self.frame(c)), "\(c)") }
        let live = Self.frame(at: Self.tsk(14, day: 25), shoots: [Self.wedding])
        #expect(live.kind == .live && !SmallSky.shows(live), "идущая съёмка — кольцо")
    }

    // MARK: Небо и светила

    /// Цвет верха неба (точка 85, 4 — над Солнцем в полдень её нет, звезда ближе 5 pt тоже нет): день голубой, закат и ночь тёмно-синие.
    /// Солнце (золото F4B400) стоит на точке правила днём и в сумерки; ночью — Луна (золото FBDD77…E0A21A) на своей точке.
    @Test func theSkyAndItsBodiesStandWhereTheRuleSays() throws {
        for w in Self.sizes {
            let k = Double(w) / 170
            for c in [Case.day, .dusk, .night] {
                let f = Self.frame(c)
                let px = try render(plate(f, w, dark: true))
                let look = SmallSky.look(f)
                let top = px.rgb(20 * k, 4 * k)
                switch look.sky {
                case .day: #expect(dist(top, hex(0x4F8FD8)) < 40, "\(Int(w)) \(c): верх неба не дневной \(top)")
                case .twilight: #expect(dist(top, hex(0x2B3664)) < 40, "\(Int(w)) \(c): верх неба не закатный \(top)")
                case .night: #expect(dist(top, hex(0x0F1C50)) < 40, "\(Int(w)) \(c): верх неба не ночной \(top)")
                }
                if let p = look.sun {
                    let s = SmallSkyCanvas.sunPoint(p)
                    if !behindHill(s, 127.5) { #expect(dist(px.rgb(s.x * k, s.y * k), hex(0xF4B400)) < 60, "\(Int(w)) \(c): Солнца нет на \(s)") }
                } else {
                    let m = SmallSkyCanvas.moonPoint(look.moonCycle)
                    if !behindHill(m, 42.5) && !behindHill(m, 127.5) {
                        let (r, g, b) = px.rgb(m.x * k, m.y * k)
                        #expect(r > 200 && g > 140 && b < 140, "\(Int(w)) \(c): Луны нет на \(m): \((r, g, b))")
                    }
                }
            }
        }
    }

    /// Путь Солнца геометрией: на восходе (0) центр диска ровно на кромке левого холма, на закате (1) — правого, в середине дня — над серединой;
    /// за закатом (1,3) он под правым холмом, Луна в новолуние — под левым, в полнолуние — над серединой. Числа холста, не пиксели.
    @Test func theSunRisesAndSetsOnTheHillCrests() {
        func gap(_ p: CGPoint, _ cx: Double) -> Double { hypot(Double(p.x) - cx, Double(p.y) - 90) - 42.5 }
        #expect(abs(gap(SmallSkyCanvas.sunPoint(0), 42.5)) < 1e-9, "восход — на кромке левого холма")
        #expect(abs(gap(SmallSkyCanvas.sunPoint(1), 127.5)) < 1e-9, "закат — на кромке правого")
        let noon = SmallSkyCanvas.sunPoint(0.5)
        #expect(abs(noon.x - 85) < 1e-9 && abs(noon.y - 22) < 1e-9, "середина дня — над серединой: \(noon)")
        let late = SmallSkyCanvas.sunPoint(0.95)
        #expect(late.x > 127.5 && late.y > 40, "за полчаса до заката Солнце низко у правого холма (по формуле ≈ 135, 44): \(late)")
        #expect(gap(SmallSkyCanvas.sunPoint(1 + SmallSky.sunReach), 127.5) < -9, "за пределом диск целиком под холмом")
        #expect(gap(SmallSkyCanvas.moonPoint(0), 42.5) < -24, "новолуние — Луна целиком за левым холмом")
        #expect(abs(SmallSkyCanvas.moonPoint(0.5).x - 85) < 1e-9, "полнолуние — над серединой")
    }

    // MARK: Указатель

    /// Красный флажок Braun — у даты съёмки на левом краю окошка. У дней без съёмок его место занял золотой знак лучшего события (31.7,
    /// оркестратор 19.11): над лучшим числом, внутри окошка; красного над окошком больше нет. Здесь лучший — закат вс 25 (82).
    @Test func theRedPointerMarksTheDateAndTheGoldSignTheBestEvent() throws {
        let gold = hex(0xF4B400)
        for w in Self.sizes {
            let k = Double(w) / 170
            for dark in [true, false] {
                let flag = hex(dark ? 0xC8102E : 0xAD0A15)
                let shoot = try render(plate(Self.frame(.night), w, dark: dark))
                #expect(dist(shoot.rgb(16 * k, 135 * k), flag) < 50, "\(Int(w)) \(dark): нет флажка у даты")
                let sunsets = try render(plate(Self.frame(.emptyWeek), w, dark: dark))
                guard case .sunsets(let cells, let best?) = SmallSky.window(Self.frame(.emptyWeek)) else { Issue.record("ждали дни с баллом"); return }
                typealias P = SmallSkyCanvas.Pairs
                func golds(_ cx: Double) -> Int {   // золотые пиксели в рамке знака 21 × 21 вокруг (cx, 114 + signY)
                    var n = 0
                    let s = Double(P.sign), cy = 114 + Double(P.signY)
                    for iy in stride(from: cy - s / 2, to: cy + s / 2, by: 0.33) {
                        for ix in stride(from: cx - s / 2, to: cx + s / 2, by: 0.33) where dist(sunsets.rgb(ix * k, iy * k), gold) < 90 { n += 1 }
                    }
                    return n
                }
                let p = P.layout(cells[best.day])
                let x = 14 + Double(P.centre(best.day) + (best.event == .dawn ? p.dawnX : p.sunsetX))
                #expect(golds(x) > 40, "\(Int(w)) \(dark): нет золотого знака над лучшим (x \(x), \(golds(x)) px)")
                let other = (0..<3).first { $0 != best.day }!
                #expect(golds(14 + Double(P.centre(other))) == 0, "\(Int(w)) \(dark): знак не только над лучшим")
                var red = 0
                for ix in stride(from: 14.0, to: 156, by: 0.5) where dist(sunsets.rgb(ix * k, 112 * k), flag) < 50 { red += 1 }
                #expect(red == 0, "\(Int(w)) \(dark): красный флажок над окошком остался")
            }
        }
    }

    // MARK: Ничего не режется

    /// Полоса 0…3 pt по краю плашки ниже неба — чистая подложка (текст не выходит к краю), и окошко не пустое: чернила в нём есть.
    @Test func textStaysInsideThePlateAndTheWindowIsFilled() throws {
        for w in Self.sizes {
            let k = Double(w) / 170
            for dark in [true, false] {
                let bg = hex(dark ? 0x161616 : 0xE4E4E2)
                for c in Case.allCases {
                    let px = try render(plate(Self.frame(c), w, dark: dark, alpha: true))
                    var edge = 0
                    var y = 95.0 * k
                    while y < (170 - 24) * k {
                        for x in [1.0, 2.5, Double(w) - 1, Double(w) - 2.5] where dist(px.rgb(x, y), bg) > 30 { edge += 1 }
                        y += 0.5
                    }
                    #expect(edge == 0, "\(Int(w)) \(dark) \(c): у края плашки чернила (\(edge))")
                    let dial = hex(dark ? 0x0D0D0D : 0xFAFAFA)
                    var ink = 0
                    var yy = 120.0 * k
                    while yy < 152 * k {
                        var x = 20.0 * k
                        while x < 150 * k { if dist(px.rgb(x, yy), dial) > 150 { ink += 1 }; x += 0.5 }
                        yy += 0.5
                    }
                    #expect(ink > 150, "\(Int(w)) \(dark) \(c): окошко почти пустое (\(ink))")
                }
            }
        }
    }

    // MARK: Картинки для глаз

    /// `small_sky.png` в `$LP_BUILT_DIR` или `/tmp/lp-built-out`, если папка заведена: строки — день 13:00, перед закатом 17:25, ночь 21:00,
    /// ночь без съёмок на неделе; столбцы — 170 и 158 pt, чёрная и белая. Лежат в `docs/30b2v_sketches/built/`.
    @Test func writesTheSheetWhenAsked() throws {
        let dir = ProcessInfo.processInfo.environment["LP_BUILT_DIR"] ?? "/tmp/lp-built-out"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let captions: [Case: String] = [.day: "день 13:00, свадьба вс 25", .dusk: "перед закатом 17:25", .night: "ночь 21:00", .emptyWeek: "ночь, съёмок на неделе нет"]
        let rows: [[AnyView]] = Case.allCases.map { c in
            Self.sizes.flatMap { w in [true, false].map { dark in
                AnyView(VStack(spacing: 5) {
                    plate(Self.frame(c), w, dark: dark, alpha: true)
                    Text("\(captions[c] ?? "") · \(Int(w)) · \(dark ? "тёмная" : "светлая")").font(.system(size: 9, weight: .medium)).foregroundStyle(.white).frame(width: 170)
                })
            } }
        }
        let grid = VStack(alignment: .leading, spacing: 12) {
            ForEach(rows.indices, id: \.self) { r in HStack(alignment: .top, spacing: 12) { ForEach(rows[r].indices, id: \.self) { rows[r][$0] } } }
        }
        .padding(12).background(Color(red: 0.36, green: 0.35, blue: 0.33))
        let r = ImageRenderer(content: grid)
        r.scale = 2
        let png = try #require(r.uiImage?.pngData(), "картинка не отрисована")
        try png.write(to: URL(fileURLWithPath: "\(dir)/small_sky.png"))
    }
}
#endif
