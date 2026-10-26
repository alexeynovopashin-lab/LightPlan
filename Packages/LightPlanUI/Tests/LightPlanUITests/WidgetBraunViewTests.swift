import Testing
import SwiftUI
import Foundation
import LightPlanDomain
import LightPlanCore
#if os(iOS)
import UIKit

/// Шаг 30б.2в-4: средний и малый виджет по демке Алексея 26.10 (`light_plan:Light_Plan/docs/widget_design_2026-10-26/`). Числа сверяются с формулами
/// демки (`renderVals()`, `ticks()`, `fit()`), прогнанными в Chrome на восьми сценариях и четырёх плашках (таблица `expected` ниже — вывод
/// этого прогона, не округление на глаз); цвета берутся с пикселей отрисованных видов и сверяются с палитрой Braun из демки.
@MainActor
struct WidgetBraunViewTests {

    // MARK: Сценарии демки (`scen()`)

    private static let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    /// Часы Томска (UTC+7), 24.10.2026 плюс `day`.
    static func tsk(_ h: Int, _ m: Int = 0, day d: Int = 24) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }
    private static func ms(_ d: Date) -> Int64 { Moment(d).milliseconds }
    private static func stop(_ h: Int, _ m: Int, _ name: String, _ sign: String) -> WidgetFeed.Stop {
        .init(at: ms(tsk(h, m)), name: name, place: "", sign: sign)
    }
    private static func rent(_ from: (Int, Int), _ to: (Int, Int)) -> WidgetFeed.Rent {
        .init(from: ms(tsk(from.0, from.1)), to: ms(tsk(to.0, to.1)), deadline: ms(tsk(to.0, to.1)), studio: "Студия")
    }

    private static let sbory = stop(12, 0, "Сборы", "makeup"), obed = stop(13, 0, "Обед", "feast"), progulka = stop(15, 0, "Прогулка", "park")
    private static let fotozona = stop(16, 0, "Фотозона", "camera"), banket = stop(16, 40, "Банкет", "feast"), tancy = stop(19, 0, "Танцы", "dance")

    static func wedding(names: String = "Анна и Игорь", stops: [WidgetFeed.Stop], rents: [WidgetFeed.Rent] = [rent((13, 0), (14, 0))]) -> WidgetFeed.Shoot {
        .init(id: "w", start: ms(tsk(12)), end: ms(tsk(0, 30, day: 25)), title: "Свадьба", place: "Томск", rents: rents, stops: stops,
              genre: "wedding", names: names)
    }
    static func studio() -> WidgetFeed.Shoot {
        .init(id: "s", start: ms(tsk(12)), end: ms(tsk(16)), title: "Портретная съёмка", place: "Томск",
              rents: [rent((13, 0), (13, 54)), rent((14, 0), (14, 54))],
              stops: [stop(12, 0, "Грим", "makeup"), stop(13, 0, "Зал «Лофт»", "studio"), stop(14, 0, "Зал «Белый»", "studio"), stop(15, 0, "Отбор кадров", "camera")],
              genre: "portrait", names: "Ольга Ветрова")
    }

    /// Кадр сценария демки: (съёмка, «сейчас»).
    static func scenario(_ key: String) -> WidgetFrame {
        let base = [sbory, obed, progulka, fotozona, banket, tancy]
        let shoot: WidgetFeed.Shoot, at: Date
        switch key {
        case "longNames": (shoot, at) = (wedding(names: "Анна-Мария и Константин", stops: base), tsk(13, 48))
        case "longPoint":
            let park = stop(15, 0, "Фотосессия в парке", "park")
            (shoot, at) = (wedding(stops: [sbory, obed, park, fotozona, banket, tancy]), tsk(15, 41))
        case "long":
            (shoot, at) = (wedding(stops: [sbory, obed, stop(14, 30, "Прогулка", "park"), stop(17, 0, "Банкет", "feast"), tancy]), tsk(15, 18))
        case "first": (shoot, at) = (wedding(stops: base), tsk(12, 20))
        case "last": (shoot, at) = (wedding(stops: base), tsk(23, 50))
        case "studio": (shoot, at) = (studio(), tsk(13, 48))
        case "studioAfter": (shoot, at) = (studio(), tsk(13, 57))
        default: (shoot, at) = (wedding(stops: base), tsk(13, 48))
        }
        return WidgetFeed(place: tomsk, shoots: [shoot]).frame(at: at)
    }

    enum Plate {
        case pro, regular, small, smallRegular
        var size: CGSize {
            switch self {
            case .pro: return CGSize(width: 364, height: 170)
            case .regular: return CGSize(width: 338, height: 158)
            case .small: return CGSize(width: 170, height: 170)
            case .smallRegular: return CGSize(width: 158, height: 158)
            }
        }
        var medium: Bool { self == .pro || self == .regular }
    }

    // MARK: Числа демки

    struct Expect {
        var scenario: String, plate: Plate
        var d: Double, cx: Double, cy: Double
        var head: Double, headH: Double
        var lit: Int, text: String, num: Double
        /// (высота, y, кегль названия) по пяти строкам барабана; `nil` — пустая строка.
        var rows: [(Double, Double, Double)?]
        /// (x, y, ширина) колонки барабана; `nil` в малом.
        var drum: (Double, Double, Double)?
        var hours: Int, past: Int
        /// (номер риски, x, y) её начала на периметре.
        var ticks: [(Int, Double, Double)]
        init(_ scenario: String, _ plate: Plate, d: Double, cx: Double, cy: Double, head: Double, headH: Double, lit: Int, text: String, num: Double,
             rows: [(Double, Double, Double)?], drum: (Double, Double, Double)?, hours: Int, past: Int, ticks: [(Int, Double, Double)]) {
            self.scenario = scenario; self.plate = plate; self.d = d; self.cx = cx; self.cy = cy; self.head = head; self.headH = headH
            self.lit = lit; self.text = text; self.num = num; self.rows = rows; self.drum = drum; self.hours = hours; self.past = past; self.ticks = ticks
        }
    }

    static let expected: [Expect] = [
        .init("lunch", .pro, d: 116, cx: 74, cy: 96, head: 15, headH: 18, lit: 12, text: "12 мин", num: 22, rows: [nil, (22, 22, 13), (28, 44, 16), (22, 72, 13), (17, 94, 11)], drum: (146, 38, 202), hours: 13, past: 22, ticks: [(0, 182, 3), (37, 361, 81.63), (75, 182, 167), (112, 3, 88.37)]),
        .init("lunch", .regular, d: 104, cx: 68, cy: 90, head: 15, headH: 18, lit: 12, text: "12 мин", num: 20, rows: [nil, (21, 17, 13), (28, 38, 16), (21, 66, 13), (16, 87, 11)], drum: (134, 38, 188), hours: 13, past: 22, ticks: [(0, 169, 3), (37, 335, 75.87), (75, 169, 155), (112, 3, 82.13)]),
        .init("lunch", .small, d: 116, cx: 85, cy: 96, head: 15, headH: 18, lit: 12, text: "12 мин", num: 22, rows: [], drum: nil, hours: 13, past: 22, ticks: [(0, 85, 3), (37, 167, 82.92), (75, 85, 167), (112, 3, 87.08)]),
        .init("lunch", .smallRegular, d: 104, cx: 79, cy: 90, head: 15, headH: 18, lit: 12, text: "12 мин", num: 20, rows: [], drum: nil, hours: 13, past: 22, ticks: [(0, 79, 3), (37, 155, 77.07), (75, 79, 155), (112, 3, 80.93)]),
        .init("longNames", .pro, d: 116, cx: 74, cy: 96, head: 15, headH: 18, lit: 12, text: "12 мин", num: 22, rows: [nil, (22, 22, 13), (28, 44, 16), (22, 72, 13), (17, 94, 11)], drum: (146, 38, 202), hours: 13, past: 22, ticks: [(0, 182, 3), (37, 361, 81.63), (75, 182, 167), (112, 3, 88.37)]),
        .init("longNames", .regular, d: 104, cx: 68, cy: 90, head: 15, headH: 18, lit: 12, text: "12 мин", num: 20, rows: [nil, (21, 17, 13), (28, 38, 16), (21, 66, 13), (16, 87, 11)], drum: (134, 38, 188), hours: 13, past: 22, ticks: [(0, 169, 3), (37, 335, 75.87), (75, 169, 155), (112, 3, 82.13)]),
        .init("longNames", .small, d: 102, cx: 85, cy: 103, head: 13, headH: 32, lit: 12, text: "12 мин", num: 20, rows: [], drum: nil, hours: 13, past: 22, ticks: [(0, 85, 3), (37, 167, 82.92), (75, 85, 167), (112, 3, 87.08)]),
        .init("longNames", .smallRegular, d: 90, cx: 79, cy: 97, head: 13, headH: 32, lit: 12, text: "12 мин", num: 20, rows: [], drum: nil, hours: 13, past: 22, ticks: [(0, 79, 3), (37, 155, 77.07), (75, 79, 155), (112, 3, 80.93)]),
        .init("longPoint", .pro, d: 116, cx: 74, cy: 96, head: 15, headH: 18, lit: 19, text: "19 мин", num: 22, rows: [(17, -2, 11), (22, 15, 13), (42, 37, 13), (22, 79, 13), (17, 101, 11)], drum: (146, 38, 202), hours: 13, past: 45, ticks: [(0, 182, 3), (37, 361, 81.63), (75, 182, 167), (112, 3, 88.37)]),
        .init("longPoint", .regular, d: 104, cx: 68, cy: 90, head: 15, headH: 18, lit: 19, text: "19 мин", num: 20, rows: [(16, -6, 11), (21, 10, 13), (42, 31, 13), (21, 73, 13), (16, 94, 11)], drum: (134, 38, 188), hours: 13, past: 45, ticks: [(0, 169, 3), (37, 335, 75.87), (75, 169, 155), (112, 3, 82.13)]),
        .init("longPoint", .small, d: 116, cx: 85, cy: 96, head: 15, headH: 18, lit: 19, text: "19 мин", num: 22, rows: [], drum: nil, hours: 13, past: 45, ticks: [(0, 85, 3), (37, 167, 82.92), (75, 85, 167), (112, 3, 87.08)]),
        .init("longPoint", .smallRegular, d: 104, cx: 79, cy: 90, head: 15, headH: 18, lit: 19, text: "19 мин", num: 20, rows: [], drum: nil, hours: 13, past: 45, ticks: [(0, 79, 3), (37, 155, 77.07), (75, 79, 155), (112, 3, 80.93)]),
        .init("long", .pro, d: 116, cx: 74, cy: 96, head: 15, headH: 18, lit: 60, text: "1 ч 42 мин", num: 22, rows: [(17, 5, 11), (22, 22, 13), (28, 44, 16), (22, 72, 13), (17, 94, 11)], drum: (146, 38, 202), hours: 13, past: 40, ticks: [(0, 182, 3), (37, 361, 81.63), (75, 182, 167), (112, 3, 88.37)]),
        .init("long", .regular, d: 104, cx: 68, cy: 90, head: 15, headH: 18, lit: 60, text: "1 ч 42 мин", num: 20, rows: [(16, 1, 11), (21, 17, 13), (28, 38, 16), (21, 66, 13), (16, 87, 11)], drum: (134, 38, 188), hours: 13, past: 40, ticks: [(0, 169, 3), (37, 335, 75.87), (75, 169, 155), (112, 3, 82.13)]),
        .init("long", .small, d: 116, cx: 85, cy: 96, head: 15, headH: 18, lit: 60, text: "1 ч 42 мин", num: 22, rows: [], drum: nil, hours: 13, past: 40, ticks: [(0, 85, 3), (37, 167, 82.92), (75, 85, 167), (112, 3, 87.08)]),
        .init("long", .smallRegular, d: 104, cx: 79, cy: 90, head: 15, headH: 18, lit: 60, text: "1 ч 42 мин", num: 20, rows: [], drum: nil, hours: 13, past: 40, ticks: [(0, 79, 3), (37, 155, 77.07), (75, 79, 155), (112, 3, 80.93)]),
        .init("first", .pro, d: 116, cx: 74, cy: 96, head: 15, headH: 18, lit: 40, text: "40 мин", num: 22, rows: [nil, nil, (28, 44, 16), (22, 72, 13), (17, 94, 11)], drum: (146, 38, 202), hours: 13, past: 4, ticks: [(0, 182, 3), (37, 361, 81.63), (75, 182, 167), (112, 3, 88.37)]),
        .init("first", .regular, d: 104, cx: 68, cy: 90, head: 15, headH: 18, lit: 40, text: "40 мин", num: 20, rows: [nil, nil, (28, 38, 16), (21, 66, 13), (16, 87, 11)], drum: (134, 38, 188), hours: 13, past: 4, ticks: [(0, 169, 3), (37, 335, 75.87), (75, 169, 155), (112, 3, 82.13)]),
        .init("first", .small, d: 116, cx: 85, cy: 96, head: 15, headH: 18, lit: 40, text: "40 мин", num: 22, rows: [], drum: nil, hours: 13, past: 4, ticks: [(0, 85, 3), (37, 167, 82.92), (75, 85, 167), (112, 3, 87.08)]),
        .init("first", .smallRegular, d: 104, cx: 79, cy: 90, head: 15, headH: 18, lit: 40, text: "40 мин", num: 20, rows: [], drum: nil, hours: 13, past: 4, ticks: [(0, 79, 3), (37, 155, 77.07), (75, 79, 155), (112, 3, 80.93)]),
        .init("last", .pro, d: 116, cx: 74, cy: 96, head: 15, headH: 18, lit: 40, text: "40 мин", num: 22, rows: [(17, 5, 11), (22, 22, 13), (28, 44, 16), nil, nil], drum: (146, 38, 202), hours: 13, past: 142, ticks: [(0, 182, 3), (37, 361, 81.63), (75, 182, 167), (112, 3, 88.37)]),
        .init("last", .regular, d: 104, cx: 68, cy: 90, head: 15, headH: 18, lit: 40, text: "40 мин", num: 20, rows: [(16, 1, 11), (21, 17, 13), (28, 38, 16), nil, nil], drum: (134, 38, 188), hours: 13, past: 142, ticks: [(0, 169, 3), (37, 335, 75.87), (75, 169, 155), (112, 3, 82.13)]),
        .init("last", .small, d: 116, cx: 85, cy: 96, head: 15, headH: 18, lit: 40, text: "40 мин", num: 22, rows: [], drum: nil, hours: 13, past: 142, ticks: [(0, 85, 3), (37, 167, 82.92), (75, 85, 167), (112, 3, 87.08)]),
        .init("last", .smallRegular, d: 104, cx: 79, cy: 90, head: 15, headH: 18, lit: 40, text: "40 мин", num: 20, rows: [], drum: nil, hours: 13, past: 142, ticks: [(0, 79, 3), (37, 155, 77.07), (75, 79, 155), (112, 3, 80.93)]),
        .init("studio", .pro, d: 116, cx: 74, cy: 96, head: 15, headH: 18, lit: 6, text: "6 мин", num: 22, rows: [nil, (22, 22, 13), (28, 44, 16), (22, 72, 13), (17, 94, 11)], drum: (146, 38, 202), hours: 4, past: 68, ticks: [(0, 182, 3), (37, 361, 81.63), (75, 182, 167), (112, 3, 88.37)]),
        .init("studio", .regular, d: 104, cx: 68, cy: 90, head: 15, headH: 18, lit: 6, text: "6 мин", num: 20, rows: [nil, (21, 17, 13), (28, 38, 16), (21, 66, 13), (16, 87, 11)], drum: (134, 38, 188), hours: 4, past: 68, ticks: [(0, 169, 3), (37, 335, 75.87), (75, 169, 155), (112, 3, 82.13)]),
        .init("studio", .small, d: 116, cx: 85, cy: 96, head: 15, headH: 18, lit: 6, text: "6 мин", num: 22, rows: [], drum: nil, hours: 4, past: 68, ticks: [(0, 85, 3), (37, 167, 82.92), (75, 85, 167), (112, 3, 87.08)]),
        .init("studio", .smallRegular, d: 104, cx: 79, cy: 90, head: 13, headH: 18, lit: 6, text: "6 мин", num: 20, rows: [], drum: nil, hours: 4, past: 68, ticks: [(0, 79, 3), (37, 155, 77.07), (75, 79, 155), (112, 3, 80.93)]),
        .init("studioAfter", .pro, d: 116, cx: 74, cy: 96, head: 15, headH: 18, lit: 0, text: "0 мин", num: 22, rows: [nil, (22, 22, 13), (28, 44, 16), (22, 72, 13), (17, 94, 11)], drum: (146, 38, 202), hours: 4, past: 74, ticks: [(0, 182, 3), (37, 361, 81.63), (75, 182, 167), (112, 3, 88.37)]),
        .init("studioAfter", .regular, d: 104, cx: 68, cy: 90, head: 15, headH: 18, lit: 0, text: "0 мин", num: 20, rows: [nil, (21, 17, 13), (28, 38, 16), (21, 66, 13), (16, 87, 11)], drum: (134, 38, 188), hours: 4, past: 74, ticks: [(0, 169, 3), (37, 335, 75.87), (75, 169, 155), (112, 3, 82.13)]),
        .init("studioAfter", .small, d: 116, cx: 85, cy: 96, head: 15, headH: 18, lit: 0, text: "0 мин", num: 22, rows: [], drum: nil, hours: 4, past: 74, ticks: [(0, 85, 3), (37, 167, 82.92), (75, 85, 167), (112, 3, 87.08)]),
        .init("studioAfter", .smallRegular, d: 104, cx: 79, cy: 90, head: 13, headH: 18, lit: 0, text: "0 мин", num: 20, rows: [], drum: nil, hours: 4, past: 74, ticks: [(0, 79, 3), (37, 155, 77.07), (75, 79, 155), (112, 3, 80.93)]),
    ]

    // MARK: Отрисовка

    /// Виджет в плашке заданного размера, как его кладёт система: подложка, скругление, заморожённый таймер окошка (кадр стоит на своём моменте).
    private func plate(_ frame: WidgetFrame, _ p: Plate, dark: Bool, alpha: Bool = false) -> some View {
        let pal = BraunPalette(dark: dark)
        return BraunWidgetView(frame: frame, alpha: alpha, medium: p.medium)
            .frame(width: p.size.width, height: p.size.height)
            .background(pal.bg)
            .clipShape(RoundedRectangle(cornerRadius: BraunPlate.cornerRadius(plateHeight: p.size.height), style: .continuous))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.widgetFrozenTimer, true)
    }

    /// Пиксели картинки (sRGB, RGBA), `scale` пикселей на pt.
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

    private func hex(_ v: UInt32) -> (Double, Double, Double) { (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF)) }
    private func near(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ tol: Double) -> Bool {
        abs(a.0 - b.0) <= tol && abs(a.1 - b.1) <= tol && abs(a.2 - b.2) <= tol
    }
    private func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double { abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) }

    // MARK: Числа против демки

    @Test func layoutMatchesTheDemoFormulasForEveryScenarioAndPlate() throws {
        var report: [String] = []
        for e in Self.expected {
            let f = Self.scenario(e.scenario)
            let plan = try #require(DayPlan(f))
            let L = BraunLayout(plan: plan, size: e.plate.size, medium: e.plate.medium)
            let tag = "\(e.scenario) \(Int(e.plate.size.width))×\(Int(e.plate.size.height))"
            report.append("\(tag): D \(L.diameter), шапка \(L.header.size)/\(L.header.lines), горит \(BraunDial.lit(minutesLeft: Int(((plan.pointLeft ?? 0) / 60).rounded(.up))))")
            #expect(L.diameter == e.d, "\(tag): диаметр \(L.diameter) против демки \(e.d)")
            #expect(abs(L.cx - e.cx) < 0.01 && abs(L.cy - e.cy) < 0.01, "\(tag): центр часов (\(L.cx), \(L.cy)) против (\(e.cx), \(e.cy))")
            #expect(L.header.size == e.head && L.headerHeight == e.headH, "\(tag): шапка \(L.header.size)/\(L.headerHeight) против \(e.head)/\(e.headH)")
            let minutes = Int(((plan.pointLeft ?? 0) / 60).rounded(.up))
            #expect(BraunDial.lit(minutesLeft: minutes) == e.lit, "\(tag): горит \(BraunDial.lit(minutesLeft: minutes)) против \(e.lit)")
            let words = plan.words
            let text = BraunDial.countdown(minutes: minutes).map { "\($0.value) \(words[$0.unit == .hour ? .hourShort : .minShort])" }.joined(separator: " ")
            #expect(text == e.text, "\(tag): отсчёт «\(text)» против «\(e.text)»")
            #expect(BraunDial.numberSize(diameter: L.diameter) == e.num, "\(tag): кегль числа")
            // Барабан.
            if let (dx, dy, dw) = e.drum {
                #expect(abs(L.drum.minX - dx) < 0.01 && abs(L.drum.minY - dy) < 0.01 && abs(L.drum.width - dw) < 0.01 && L.drum.height == e.d,
                        "\(tag): колонка \(L.drum) против (\(dx), \(dy), \(dw))")
                #expect(L.rows.count == 5)
                for (i, row) in L.rows.enumerated() {
                    if let (h, y, fs) = e.rows[i] {
                        #expect(row.stop != nil && row.slot.height == h && abs(row.slot.y - y) < 0.01 && row.step.size == fs,
                                "\(tag), строка \(i - 2): (\(row.slot.height), \(row.slot.y), \(row.step.size)) против (\(h), \(y), \(fs))")
                    } else {
                        #expect(row.stop == nil, "\(tag), строка \(i - 2): в демке пусто, а тут «\(row.stop?.name ?? "")»")
                    }
                }
            } else {
                #expect(L.rows.isEmpty && L.windowWidth == 0, "\(tag): в малом нет ни барабана, ни окошка")
            }
            // Риски: число часовых и пройденных, начало шести рисок на периметре.
            let shoot = plan.shoot
            let dur = shoot.endDate.timeIntervalSince(shoot.startDate), el = f.now.timeIntervalSince(shoot.startDate)
            let local = shoot.startDate.timeIntervalSince1970 + Double(plan.zone.secondsFromGMT(for: shoot.startDate))
            #expect(BraunTicks.hourIndexes(start: local, duration: dur).count == e.hours, "\(tag): часовых рисок")
            #expect((0..<BraunTicks.count).filter { BraunTicks.isPast(index: $0, duration: dur, elapsed: el) }.count == e.past, "\(tag): пройденных рисок")
            let w = PerimeterWalker(rect: CGRect(origin: .zero, size: e.plate.size).insetBy(dx: 3, dy: 3), radius: CGFloat(L.radius - 3))
            for (i, x, y) in e.ticks {
                let p = w.sample(CGFloat(i) / 150 * w.length).point
                #expect(abs(Double(p.x) - x) < 0.02 && abs(Double(p.y) - y) < 0.02, "\(tag): риска \(i) в (\(p.x), \(p.y)) против (\(x), \(y))")
            }
        }
        print(report.joined(separator: "\n"))
    }

    // MARK: Круг по пикселям

    /// Правило А по картинке: центр каждой из 60 точек зарисован горящим цветом ровно у тех, у кого его должно быть, — в обеих темах.
    @Test func theDotsOnThePictureFollowTheRule() throws {
        for (key, plateKind) in [("lunch", Plate.pro), ("studioAfter", .pro), ("long", .regular), ("first", .small), ("last", .smallRegular)] {
            for dark in [true, false] {
                let f = Self.scenario(key)
                let plan = try #require(DayPlan(f))
                let L = BraunLayout(plan: plan, size: plateKind.size, medium: plateKind.medium)
                let minutes = Int(((plan.pointLeft ?? 0) / 60).rounded(.up))
                let pal = BraunPalette(dark: dark)
                let px = try render(plate(f, plateKind, dark: dark), scale: 4)
                let litRGB = dark ? hex(0xECECEA) : hex(0x111111), offRGB = dark ? hex(0x2E2E2E) : hex(0xDCDCDA)
                _ = pal
                var seen: [Int] = []
                for k in 0..<60 {
                    let c = BraunDial.dotCenter(k, diameter: L.diameter)
                    let got = px.rgb(L.cx + c.x, L.cy + c.y)
                    let isLit = dist(got, litRGB) < dist(got, offRGB)
                    if isLit { seen.append(k) }
                    #expect(isLit == BraunDial.isLit(dot: k, minutesLeft: minutes), "\(key) \(dark ? "тёмная" : "светлая") \(Int(plateKind.size.width)): точка \(k) \(isLit ? "горит" : "погасла")")
                }
                #expect(seen.count == BraunDial.lit(minutesLeft: minutes), "\(key): горит \(seen.count), должно \(BraunDial.lit(minutesLeft: minutes))")
            }
        }
    }

    // MARK: Цвета по пикселям

    @Test func theColoursAreTheBraunPaletteOfTheDemo() throws {
        struct Pal { var dial, dotOn, dotOff, tickOff, tickMinor, tickHour, pill, window, flag, amber, muted: (Double, Double, Double) }
        func rgb(_ v: UInt32) -> (Double, Double, Double) { hex(v) }
        let light = Pal(dial: rgb(0xFAFAFA), dotOn: rgb(0x111111), dotOff: rgb(0xDCDCDA), tickOff: rgb(0xCBCBC9), tickMinor: rgb(0x6E6E6E), tickHour: rgb(0x111111),
                        pill: rgb(0xF4B400), window: rgb(0xD3D3D1), flag: rgb(0xAD0A15), amber: rgb(0x111111), muted: rgb(0x5B5B5B))
        // Подложка центра в тёмной — белый 7 % поверх #161616.
        let pillDark = (22 * 0.93 + 255 * 0.07, 22 * 0.93 + 255 * 0.07, 22 * 0.93 + 255 * 0.07)
        let dark = Pal(dial: rgb(0x0D0D0D), dotOn: rgb(0xECECEA), dotOff: rgb(0x2E2E2E), tickOff: rgb(0x303030), tickMinor: rgb(0x8C8C8C), tickHour: rgb(0xECECEA),
                       pill: pillDark, window: rgb(0x0A0A0A), flag: rgb(0xC8102E), amber: rgb(0xF4B400), muted: rgb(0x9B9B9B))
        let f = Self.scenario("lunch")
        let plan = try #require(DayPlan(f))
        let size = Plate.pro.size
        let L = BraunLayout(plan: plan, size: size, medium: true)
        let walker = PerimeterWalker(rect: CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3), radius: CGFloat(L.radius - 3))
        func onTick(_ i: Int, _ along: Double) -> (Double, Double) {
            let s = walker.sample(CGFloat(i) / 150 * walker.length)
            return (Double(s.point.x) + Double(s.inward.dx) * along, Double(s.point.y) + Double(s.inward.dy) * along)
        }
        for (isDark, p) in [(true, dark), (false, light)] {
            let px = try render(plate(f, .pro, dark: isDark), scale: 4)
            let tag = isDark ? "Braun чёрный" : "Braun белый"
            let bg = isDark ? hex(0x161616) : hex(0xE4E4E2)
            #expect(near(px.rgb(139, 85), bg, 1), "\(tag): фон \(px.rgb(139, 85))")
            #expect(near(px.rgb(L.cx, L.cy + 38), p.dial, 2), "\(tag): диск часов \(px.rgb(L.cx, L.cy + 38))")
            let on = BraunDial.dotCenter(55, diameter: L.diameter), off = BraunDial.dotCenter(30, diameter: L.diameter)
            #expect(near(px.rgb(L.cx + on.x, L.cy + on.y), p.dotOn, 3), "\(tag): горящая точка \(px.rgb(L.cx + on.x, L.cy + on.y))")
            #expect(near(px.rgb(L.cx + off.x, L.cy + off.y), p.dotOff, 3), "\(tag): погасшая точка \(px.rgb(L.cx + off.x, L.cy + off.y))")
            #expect(near(px.rgb(150, L.cy), p.pill, 3), "\(tag): подложка центра \(px.rgb(150, L.cy))")
            let t0 = onTick(0, 3.5), t149 = onTick(149, 2), t24 = onTick(24, 3.75)
            #expect(near(px.rgb(t0.0, t0.1), p.tickOff, 4), "\(tag): пройденная часовая риска \(px.rgb(t0.0, t0.1))")
            #expect(near(px.rgb(t149.0, t149.1), p.tickMinor, 8), "\(tag): обычная риска \(px.rgb(t149.0, t149.1))")
            #expect(near(px.rgb(t24.0, t24.1), p.tickHour, 5), "\(tag): часовая риска впереди \(px.rgb(t24.0, t24.1))")
            let wx = 364 - 16 - L.windowWidth
            #expect(near(px.rgb(wx + 3, 25), p.window, 12), "\(tag): окошко \(px.rgb(wx + 3, 25))")
            #expect(near(px.rgb(wx + L.windowWidth / 2 - 2, 13), p.flag, 8), "\(tag): флажок \(px.rgb(wx + L.windowWidth / 2 - 2, 13))")
            // Текст центра барабана и соседа: самый далёкий от фона строки пиксель — цвет текста (стебли букв шире пикселя на 4-кратном масштабе).
            func ink(_ x0: Double, _ y0: Double, _ w: Double, _ h: Double, ground: (Double, Double, Double)) -> (Double, Double, Double) {
                var best = ground, far = 0.0
                var y = y0
                while y < y0 + h { var x = x0; while x < x0 + w { let c = px.rgb(x, y); if dist(c, ground) > far { far = dist(c, ground); best = c }; x += 0.25 }; y += 0.25 }
                return best
            }
            let centre = ink(146 + 10, 38 + 44, 190, 28, ground: p.pill)
            #expect(near(centre, p.amber, 14), "\(tag): текст центра \(centre)")
            let neighbour = ink(146 + 10, 38 + 22, 190, 22, ground: bg)
            #expect(near(neighbour, p.muted, 22), "\(tag): текст соседа \(neighbour)")
        }
        // Подложка плашки «Домой» — тот же цвет, что палитра.
        for (style, v) in [(UIUserInterfaceStyle.light, 0xE4E4E2 as UInt32), (.dark, 0x161616)] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(BraunPalette.container).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
            #expect(near((Double(r) * 255, Double(g) * 255, Double(b) * 255), hex(v), 1), "подложка в теме \(style.rawValue)")
        }
    }

    // MARK: Барабан: пустые строки и имена целиком

    /// На первой точке две верхние строки барабана пусты: в них нет ни одного пикселя чернил, подложка центра стоит на своём месте.
    @Test func emptyDrumRowsStayEmptyAndTheOthersDoNotMove() throws {
        let f = Self.scenario("first")
        let plan = try #require(DayPlan(f))
        let L = BraunLayout(plan: plan, size: Plate.pro.size, medium: true)
        #expect(L.rows.map { $0.stop?.name } == [nil, nil, "Сборы", "Обед", "Прогулка"])
        let mid = try #require(DayPlan(Self.scenario("lunch")))
        let M = BraunLayout(plan: mid, size: Plate.pro.size, medium: true)
        #expect(zip(L.rows, M.rows).allSatisfy { $0.slot == $1.slot }, "строки стоят на тех же местах, сосед есть или нет")
        for dark in [true, false] {
            let bg = BraunPalette(dark: dark)
            let px = try render(plate(f, .pro, dark: dark), scale: 2)
            let ground = dark ? hex(0x161616) : hex(0xE4E4E2)
            _ = bg
            for row in L.rows.prefix(2) {
                var worst = 0.0
                var y = L.drum.minY + row.slot.y + 0.5
                while y < L.drum.minY + row.slot.y + row.slot.height - 0.5 {
                    var x = L.drum.minX + 1
                    while x < L.drum.maxX - 1 { worst = max(worst, dist(px.rgb(x, y), ground)); x += 1 }
                    y += 1
                }
                #expect(worst <= 3, "пустая строка \(row.slot.offset) (\(dark ? "тёмная" : "светлая")): есть чернила, отличие \(worst)")
            }
        }
    }

    /// Названия барабана не режутся: в каждой строке шрифт, в который имя влезло, или две строки (у центра); длинное имя уходит в две строки.
    @Test func drumNamesAreNeverCut() throws {
        for e in Self.expected where e.plate.medium {
            let plan = try #require(DayPlan(Self.scenario(e.scenario)))
            let L = BraunLayout(plan: plan, size: e.plate.size, medium: true)
            let avail = BraunDrum.nameWidth(column: Double(L.drum.width))
            for row in L.rows {
                guard let stop = row.stop else { continue }
                let w = BraunText.width(stop.name, size: row.step.size, semibold: row.slot.offset == 0)
                #expect(row.step.lines > 1 || w <= avail, "\(e.scenario) \(Int(e.plate.size.width)): «\(stop.name)» \(w) pt при кегле \(row.step.size) не влезает в \(avail)")
            }
        }
        // «Фотосессия в парке» на 338 pt не влезает ни в 16, ни в 14 — две строки по 13, строка 42.
        let plan = try #require(DayPlan(Self.scenario("longPoint")))
        let narrow = BraunLayout(plan: plan, size: Plate.regular.size, medium: true)
        let centre = narrow.rows[2]
        #expect(centre.stop?.name == "Фотосессия в парке" && centre.slot.height == (centre.step.lines > 1 ? 42 : 28))
        var long = Self.wedding(stops: [Self.sbory, Self.stop(13, 0, "Очень длинное название точки маршрута, которое нигде не помещается", "feast"), Self.progulka])
        long.rents = []
        let f = WidgetFeed(place: Self.tomsk, shoots: [long]).frame(at: Self.tsk(13, 30))
        let l = BraunLayout(plan: try #require(DayPlan(f)), size: Plate.regular.size, medium: true)
        #expect(l.rows[2].step.lines == 2 && l.rows[2].step.size == 13 && l.rows[2].slot.height == 42, "длинное имя: две строки по 13, строка 42")
        #expect(l.rows[1].slot.y + l.rows[1].slot.height == l.rows[2].slot.y && l.rows[3].slot.y == l.rows[2].slot.y + 42, "соседи встык с центром в две строки")
    }

    // MARK: Окошко, малый, шапка

    @Test func theWindowIsAsWideForTenHoursAsForFortyMinutesAndTicksFromAnHour() throws {
        let long = try #require(DayPlan(Self.scenario("lunch"))), short = try #require(DayPlan(Self.scenario("last")))
        let a = BraunLayout(plan: long, size: Plate.pro.size, medium: true), b = BraunLayout(plan: short, size: Plate.pro.size, medium: true)
        #expect(a.windowWidth == b.windowWidth && a.windowWidth > 40, "рамка не прыгает: \(a.windowWidth) и \(b.windowWidth)")
        #expect(abs(a.windowWidth - (BraunText.width("00:00:00", size: 13, semibold: true, mono: true) + 14)) < 0.001)
        #expect(BraunWindow.text(remaining: 10 * 3600 + 42 * 60) == "10:42:00" && BraunWindow.text(remaining: 42 * 60) == "42:00")
    }

    @Test func theSmallWidgetHasNoWindowAndGrowsTheHeaderToTwoLines() throws {
        let plan = try #require(DayPlan(Self.scenario("longNames")))
        let s = BraunLayout(plan: plan, size: Plate.small.size, medium: false)
        #expect(s.windowWidth == 0 && s.rows.isEmpty && s.headerWidth == 138)
        #expect(s.header.size == 13 && s.header.lines == 2 && s.headerHeight == 32 && s.diameter == 102, "малый, длинные имена: 13 в две строки, шапка 32, круг 102")
        #expect(s.cx == 85, "круг по центру малого")
        let m = BraunLayout(plan: plan, size: Plate.pro.size, medium: true)
        #expect(m.header.size == 15 && m.header.lines == 1 && m.headerHeight == 18 && m.diameter == 116 && m.cx == 74, "средний держит имена в одной строке")
        let pxSmall = try render(plate(Self.scenario("lunch"), .small, dark: false), scale: 2)
        // Правый верхний угол малого — подложка, в нём нет окошка.
        #expect(near(pxSmall.rgb(150, 25), hex(0xE4E4E2), 2), "малый: справа сверху \(pxSmall.rgb(150, 25))")
    }

    /// Настоящий таймер окошка (`Text(timerInterval:)`, без заморозки) стоит в рамке: чернила внутри окна, левее и правее окна — подложка.
    /// Что он показывает, зависит от часов телефона, поэтому проверяется только место.
    @Test func theLiveTimerStaysInsideItsWindow() throws {
        for (kind, p) in [("lunch", Plate.pro), ("last", .regular)] {
            let f = Self.scenario(kind)
            let L = BraunLayout(plan: try #require(DayPlan(f)), size: p.size, medium: true)
            let pal = BraunPalette(dark: true)
            let view = BraunWidgetView(frame: f, alpha: false, medium: true).frame(width: p.size.width, height: p.size.height)
                .background(pal.bg).environment(\.colorScheme, .dark)
            let px = try render(view, scale: 4)
            let left = Double(p.size.width) - 16 - L.windowWidth
            var inside = 0.0, outside = 0.0
            var y = 20.0
            while y < 30 {
                var x = left + 2
                while x < left + L.windowWidth - 2 { inside = max(inside, dist(px.rgb(x, y), hex(0x0A0A0A))); x += 0.5 }
                x = left - 8
                while x < left - 2 { outside = max(outside, dist(px.rgb(x, y), hex(0x161616))); x += 0.5 }
                y += 0.5
            }
            #expect(inside > 200, "\(kind): в окошке нет цифр таймера")
            #expect(outside <= 3, "\(kind): цифры таймера вылезли за левый край окна (\(outside))")
        }
    }

    @Test func theHeaderCarriesTheGenreSignOfTheLibrary() throws {
        func ink(_ f: WidgetFrame) throws -> [UInt8] {
            let px = try render(plate(f, .pro, dark: false), scale: 4)
            var out: [UInt8] = []
            var y = 17.0
            while y < 33 { var x = 16.0; while x < 32 { out.append(UInt8(min(255, px.rgb(x, y).0))); x += 0.25 }; y += 0.25 }
            return out
        }
        let wed = try ink(Self.scenario("lunch")), por = try ink(Self.scenario("studio"))
        #expect(wed != por, "знак свадьбы и знак портрета разные")
        #expect(wed.contains { $0 < 90 }, "знак нарисован чернилами")
        #expect(WidgetIconTable.genres["wedding"] != nil && WidgetIconTable.genres["portrait"] != nil)
        #expect(WidgetIconArt.parts(genre: "нет такого").count == WidgetIconArt.parts("camera").count, "неизвестный жанр — камера")
    }

    // MARK: Снимки

    private func cell(_ caption: String, _ w: CGFloat, _ content: some View) -> some View {
        VStack(spacing: 6) {
            content
            Text(caption).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white).multilineTextAlignment(.center).frame(width: w)
        }
    }

    private func sheet(_ rows: [[AnyView]], scale: CGFloat) -> UIImage? {
        let grid = VStack(spacing: 14) {
            ForEach(rows.indices, id: \.self) { r in HStack(alignment: .top, spacing: 14) { ForEach(rows[r].indices, id: \.self) { rows[r][$0] } } }
        }
        .padding(14).background(Color(red: 0.36, green: 0.35, blue: 0.33))
        let r = ImageRenderer(content: grid)
        r.scale = scale
        return r.uiImage
    }

    private static let captions: [(String, String)] = [
        ("lunch", "обед 13:48"), ("longNames", "длинные имена 13:48"), ("longPoint", "длинное имя точки 15:41"), ("long", "точка 2 ч 30 мин, 15:18"),
        ("first", "первая точка 12:20"), ("last", "последняя точка 23:50"), ("studio", "студия 13:48"), ("studioAfter", "студия 13:57"),
    ]

    /// Картинки сценариев демки: в `$LP_BUILT_DIR` или `/tmp/lp-built-out`, если папка заведена (обычный прогон ничего не пишет).
    /// Лежат в `docs/30b2v_sketches/built/`: `medium_pro_a|b.png` (364 × 170), `medium_regular_a|b.png` (338 × 158), `small_pro.png` (170), `small_regular.png` (158);
    /// каждый сценарий в тёмной («Braun чёрный») и светлой («Braun белый») теме, бирка «α» как на слотах.
    @Test func writesTheBraunSheetsWhenAsked() throws {
        let dir = ProcessInfo.processInfo.environment["LP_BUILT_DIR"] ?? "/tmp/lp-built-out"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        func pair(_ key: String, _ caption: String, _ p: Plate) -> [AnyView] {
            [true, false].map { dark in
                AnyView(cell("\(caption) · \(dark ? "чёрный" : "белый")", p.size.width, plate(Self.scenario(key), p, dark: dark, alpha: true)))
            }
        }
        func write(_ image: UIImage?, _ name: String) throws {
            let png = try #require(image?.pngData(), "картинка \(name) не отрисована")
            try png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            #expect(png.count <= 300 * 1024, "\(name).png: \(png.count / 1024) КБ, предел 300")
        }
        for (tag, p) in [("pro", Plate.pro), ("regular", .regular)] {
            for (part, range) in [("a", 0..<4), ("b", 4..<8)] {
                try write(sheet(Self.captions[range].map { pair($0.0, $0.1, p) }, scale: 1.35), "medium_\(tag)_\(part)")
            }
        }
        for (tag, p) in [("pro", Plate.small), ("regular", .smallRegular)] {
            let cells = Self.captions.map { pair($0.0, $0.1, p) }
            try write(sheet(stride(from: 0, to: 8, by: 2).map { cells[$0] + cells[$0 + 1] }, scale: 1.45), "small_\(tag)")
        }
    }
}
#endif
