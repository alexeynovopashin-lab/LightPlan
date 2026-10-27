import Testing
import SwiftUI
import Foundation
import LightPlanDomain
import LightPlanCore
#if os(iOS)
import UIKit

/// Шаг 30б.2в-6: средний вид оценивает рассвет до конца утреннего золотого часа, потом закат, после заката — завтрашний рассвет. Здесь: столбик
/// и строка оценки на четырёх моментах (05:00, 09:00, 14:00, 21:00), оценка в строке барабана света (Б), картинки.
@MainActor
struct WidgetRatedViewTests {

    enum Kind: CaseIterable { case bare, ahead, free, empty }
    static let moments: [(h: Int, label: String)] = [(5, "05:00"), (9, "09:00"), (14, "14:00"), (21, "21:00")]

    private static let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    private static func tsk(_ h: Int, _ m: Int = 0, day d: Int = 25) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }
    private static func ms(_ d: Date) -> Int64 { Moment(d).milliseconds }
    private static func shoot(_ id: String, _ a: Date, _ b: Date, _ names: String, _ genre: String, _ title: String) -> WidgetFeed.Shoot {
        .init(id: id, start: ms(a), end: ms(b), title: title, genre: genre, names: names)
    }
    static let ratings = [WidgetFeed.Rating(day: "2026-10-25", score: 62, quality: .good, sunrise: 81),
                          WidgetFeed.Rating(day: "2026-10-26", score: 30, quality: .plain, sunrise: 44)]

    static func frame(_ k: Kind, hour: Int) -> WidgetFrame {
        let iv = shoot("iv", tsk(11, day: 28), tsk(13, day: 28), "Семья Ивановых", "family", "Семья")
        let md = shoot("md", tsk(13, day: 30), tsk(15, day: 30), "Мария и Дмитрий", "wedding", "Свадьба")
        let shoots: [WidgetFeed.Shoot]
        switch k {
        case .bare: shoots = [shoot("w", tsk(4), tsk(23, 30), "Анна и Игорь", "wedding", "Свадьба")]
        case .ahead: shoots = [shoot("w", tsk(22), tsk(23, 30), "Анна и Игорь", "wedding", "Свадьба"), iv, md]
        case .free: shoots = [iv, md]
        case .empty: shoots = []
        }
        return WidgetFeed(place: tomsk, shoots: shoots, forecast: ratings).frame(at: tsk(hour))
    }

    @ViewBuilder static func widget(_ k: Kind, hour: Int, alpha: Bool) -> some View {
        let f = frame(k, hour: hour)
        if k == .bare { BraunWidgetView(frame: f, alpha: alpha, medium: true) } else { BraunIdleView(frame: f, alpha: alpha) }
    }

    struct Plate { var size: CGSize; static let pro = Plate(size: CGSize(width: 364, height: 170)), regular = Plate(size: CGSize(width: 338, height: 158)) }

    private func plate(_ k: Kind, _ hour: Int, _ p: Plate, dark: Bool, alpha: Bool = false) -> some View {
        Self.widget(k, hour: hour, alpha: alpha)
            .frame(width: p.size.width, height: p.size.height)
            .background(BraunPalette(dark: dark).bg)
            .clipShape(RoundedRectangle(cornerRadius: BraunPlate.cornerRadius(plateHeight: p.size.height), style: .continuous))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.widgetFrozenTimer, true)
    }

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

    private func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double { abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) }

    // MARK: Что оценивается на четырёх моментах

    @Test func theFourMomentsRateSunriseSunsetSunriseAsTheRuleSays() throws {
        let want: [(Int, BraunIdle.LightKind, Bool, Int)] = [(5, .sunrise, false, 81), (9, .sunrise, false, 81), (14, .sunset, false, 62), (21, .sunrise, true, 44)]
        for (h, kind, tomorrow, score) in want {
            for k in Kind.allCases {
                let f = Self.frame(k, hour: h)
                let e = try #require(BraunIdle.ratedEvent(f), "\(k) \(h):00")
                #expect(e.kind == kind && e.tomorrow == tomorrow && e.score == score, "\(k) \(h):00: \(e.kind) завтра=\(e.tomorrow) балл=\(String(describing: e.score))")
            }
        }
    }

    /// Уровень на столбике (светлая полоска) стоит на баллах события: 81 утром, 62 днём, 44 вечером (завтрашний рассвет).
    @Test func theGaugeLevelFollowsTheRatedEvent() throws {
        for (h, score) in [(5, 81), (9, 81), (14, 62), (21, 44)] {
            let px = try render(plate(.free, h, .pro, dark: true), scale: 4)
            let fill = 116 * Double(score) / 100
            let y = 38 + 116 - fill
            #expect(dist(px.rgb(145, y), (246, 243, 236)) <= 45, "\(h):00: полоска уровня должна стоять на \(score) (y \(y)), там \(px.rgb(145, y))")
            // И не на соседнем балле другого события.
            let other = 38 + 116 - 116 * Double(score == 62 ? 81 : 62) / 100
            #expect(dist(px.rgb(145, other), (246, 243, 236)) > 45, "\(h):00: полоски на чужом баллу быть не должно")
        }
    }

    /// Б: оценка стоит в строке того события, которое оценивается: рассвет утром, закат днём, завтрашний рассвет вечером.
    @Test func theLightDrumCarriesTheRatingOnTheRatedRow() throws {
        let want: [(Int, BraunIdle.LightKind, Bool)] = [(5, .sunrise, false), (9, .sunrise, false), (14, .sunset, false), (21, .sunrise, true)]
        for (h, kind, tomorrow) in want {
            let f = Self.frame(.bare, hour: h)
            let L = BraunLayout(plan: try #require(DayPlan(f)), size: Plate.pro.size, medium: true, bare: true)
            let withExtra = L.rows.filter { $0.extra != nil }
            #expect(withExtra.count == 1 && withExtra.first?.light?.kind == kind && withExtra.first?.light?.tomorrow == tomorrow, "\(h):00: оценка не в той строке")
        }
    }

    /// Название центра барабана света с оценкой не рвётся на две строки: оценка рядом с ним, а не влезла — второй строкой под ним (подложка 42).
    @Test func theCentreNameNeverWrapsWhenItCarriesTheRating() throws {
        for p in [Plate.pro, .regular] {
            for h in [5, 9, 14, 21] {
                let L = BraunLayout(plan: try #require(DayPlan(Self.frame(.bare, hour: h))), size: p.size, medium: true, bare: true)
                let c = L.rows[2]
                let tag = "\(Int(p.size.width)) \(h):00 центр «\(String(describing: c.light?.kind))»"
                #expect(c.step.lines == 1, "\(tag): название в одну строку, шаг \(c.step)")
                #expect(c.slot.height == (c.extraStacked ? 42 : 28), "\(tag): подложка \(c.slot.height), оценка внизу: \(c.extraStacked)")
                let avail = BraunDrum.nameWidth(column: Double(L.drum.width)) - BraunLayout.lightSignWidth(offset: 0)
                    - (c.extra != nil && !c.extraStacked ? BraunLayout.ratingWidth(c.extra ?? "", icon: c.extraIcon) : 0)
                #expect(BraunText.width(plan(c).name, size: c.step.size, semibold: true) <= avail, "\(tag): название влезло, шаг \(c.step.size)")
                for r in L.rows where r.light != nil && r.extra != nil && r.slot.offset != 0 {
                    let a = BraunDrum.nameWidth(column: Double(L.drum.width)) - BraunLayout.lightSignWidth(offset: r.slot.offset) - BraunLayout.ratingWidth(r.extra ?? "", icon: r.extraIcon, size: r.extraSize)
                    #expect(BraunText.width(plan(r).name, size: r.step.size, semibold: false) <= a, "\(tag): соседняя строка с оценкой влезла целиком (знак \(r.extraIcon), слово \(r.extraSize), название \(r.step.size), место \(a))")
                }
                for r in L.rows where r.light != nil { #expect(r.slot.y >= 0 && r.slot.y + r.slot.height <= L.diameter + 0.01, "\(tag): строка внутри колонки") }
            }
        }
    }

    private func plan(_ r: BraunLayout.Row) -> (name: String, pad: Void) {
        let words = WidgetFeed.Words()
        let k = r.light?.kind ?? .sunrise
        return (words[k == .sunrise ? .sunrise : (k == .golden ? .golden : .sunset)], ())
    }

    /// Строка оценки слева («Рассвет · отличный») влезает в 99 pt хотя бы в 9 pt на всех моментах и всех словах.
    @Test func theRatingLineFitsTheLeftColumnInTheSmallestStep() {
        let words = WidgetFeed.Words()
        for e in [BraunIdle.LightKind.sunrise, .sunset] {
            for q in DayQuality.allCases {
                let text = "\(words[e == .sunrise ? .sunrise : .sunset]) · \(words.rating(q))"
                #expect(BraunText.width(text, size: 9, semibold: false) <= 99, "«\(text)» не влезает даже в 9")
            }
        }
    }

    // MARK: Снимки

    private func cell(_ caption: String, _ w: CGFloat, _ content: some View) -> some View {
        VStack(spacing: 6) {
            content
            Text(caption).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white).multilineTextAlignment(.center).frame(width: w)
        }
    }

    private static let names: [(Kind, String)] = [(.bare, "Б идёт без маршрута"), (.ahead, "Г съёмка сегодня"), (.free, "Д / Е без съёмок"), (.empty, "+ съёмок нет")]

    /// `medium_rated_pro_dark|light.png` и `medium_rated_regular_dark|light.png`: строки — 05:00, 09:00, 14:00, 21:00, столбцы — Б, Г, Д / Е, «съёмок нет».
    @Test func writesTheRatedSheetsWhenAsked() throws {
        let dir = ProcessInfo.processInfo.environment["LP_BUILT_DIR"] ?? "/tmp/lp-built-out"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        for (tag, p) in [("pro", Plate.pro), ("regular", .regular)] {
            for dark in [true, false] {
                let rows: [[AnyView]] = Self.moments.map { m in
                    Self.names.map { k, name in AnyView(cell("\(name) · \(m.label)", p.size.width, plate(k, m.h, p, dark: dark, alpha: true))) }
                }
                let grid = VStack(spacing: 14) {
                    ForEach(rows.indices, id: \.self) { r in HStack(alignment: .top, spacing: 14) { ForEach(rows[r].indices, id: \.self) { rows[r][$0] } } }
                }
                .padding(14).background(Color(red: 0.36, green: 0.35, blue: 0.33))
                let r = ImageRenderer(content: grid)
                r.scale = 1.0
                let png = try #require(r.uiImage?.pngData())
                let name = "medium_rated_\(tag)_\(dark ? "dark" : "light")"
                try png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
                #expect(png.count <= 300 * 1024, "\(name).png: \(png.count / 1024) КБ")
            }
        }
    }
}
#endif
