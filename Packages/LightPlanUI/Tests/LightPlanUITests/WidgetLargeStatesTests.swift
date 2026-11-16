import Testing
import SwiftUI
import Foundation
import LightPlanDomain
import LightPlanCore
@testable import LightPlanUI
#if os(iOS)
import UIKit

/// 30и.14: большой виджет в трёх видах (`LargeView` → `LargeIdleView`, `LargePhotoView`, `LargeRouteView`; эскиз 30и.13 § 9, выбор Алексея
/// «большой виджет с рисками-таймером»). Что держат тесты: какой вид стоит в каком кадре; **риски есть только у вида с маршрутом** и стоят в полосе
/// 3…10,5 от края, а текст в неё не заходит (Алексей 16.11: «будь внимателен к текстам, чтобы не наползали на них»); блок «съёмок нет» заполнен
/// закатами; сломанная свадьба (съёмка 00:00–00:35, точки с 08:00) рисуется, а не пустеет.
@MainActor
struct WidgetLargeStatesTests {

    private static let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    /// Часы Томска (UTC+7) 24.10.2026 плюс `day`.
    private static func tsk(_ h: Int, _ m: Int = 0, day d: Int = 24) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }
    private static func ms(_ d: Date) -> Int64 { Moment(d).milliseconds }
    private static func stop(_ at: Date, _ name: String, _ place: String = "", studio: Bool = false) -> WidgetFeed.Stop {
        .init(at: ms(at), name: name, place: place, sign: PointSign.name(for: name, place: place, studio: studio))
    }

    /// Свадьба 12:00–00:30 с шестью точками (сценарий Алексея).
    static var wedding: WidgetFeed.Shoot {
        .init(id: "w", start: ms(tsk(12)), end: ms(tsk(0, 30, day: 25)), title: "Свадьба", place: "Томск", wantsSunset: true,
              rents: [.init(from: ms(tsk(12)), to: ms(tsk(14)), deadline: ms(tsk(13, 54)), studio: "Томсон")],
              stops: [stop(tsk(12), "Пара в студии", "Студия «Томсон»", studio: true), stop(tsk(14), "Обед", "Кафе «Вилка»"),
                      stop(tsk(15), "Прогулка", "Набережная"), stop(tsk(17), "Церемония", "Дворец бракосочетания"),
                      stop(tsk(19), "Банкет", "Ресторан «Дом»"), stop(tsk(22), "Танцы", "Ресторан «Дом»")],
              genre: "wedding", names: "Анна+Игорь")
    }
    /// Фотосессия 16:00–18:00 без маршрута.
    static var photo: WidgetFeed.Shoot {
        .init(id: "p", start: ms(tsk(16)), end: ms(tsk(18)), title: "Портрет", place: "Томск", genre: "portrait", names: "Мария")
    }
    private static var family: WidgetFeed.Shoot { .init(id: "f", start: ms(tsk(11, day: 26)), end: ms(tsk(13, day: 26)), title: "Семья", genre: "family", names: "Орловы") }
    private static var maria: WidgetFeed.Shoot { .init(id: "m", start: ms(tsk(10, day: 28)), end: ms(tsk(12, day: 28)), title: "Свадьба", genre: "wedding", names: "Ольга+Паша") }
    /// Съёмка 00:00–00:35, точки с 08:00: маршрут целиком за окном съёмки (так сломал свадьбу Алексей 16.11).
    static var broken: WidgetFeed.Shoot {
        .init(id: "b", start: ms(tsk(0)), end: ms(tsk(0, 35)), title: "Свадьба",
              stops: [stop(tsk(8), "Сборы"), stop(tsk(10), "Выезд"), stop(tsk(12), "ЗАГС")], genre: "wedding", names: "Анна+Игорь")
    }
    /// Оценки закатов четырёх дней: сегодня, завтра, дальше (у третьего часа заката нет — слово неба).
    static let forecast: [WidgetFeed.Rating] = [
        .init(day: "2026-10-24", score: 62, quality: .good, sunrise: 34), .init(day: "2026-10-25", score: 82, quality: .excellent),
        .init(day: "2026-10-26", score: nil, quality: .fog), .init(day: "2026-10-27", score: 41, quality: .plain),
    ]

    static func frame(at now: Date, shoots: [WidgetFeed.Shoot], forecast: [WidgetFeed.Rating] = forecast) -> WidgetFrame {
        WidgetFeed(place: tomsk, shoots: shoots, forecast: forecast).frame(at: now)
    }

    enum Case: CaseIterable { case weekWithShoots, emptyWeek, photo, route, broken }
    static func frame(_ c: Case) -> WidgetFrame {
        switch c {
        case .weekWithShoots: frame(at: tsk(20), shoots: [family, maria])
        case .emptyWeek: frame(at: tsk(20), shoots: [])
        case .photo: frame(at: tsk(16, 48), shoots: [photo, family])
        case .route: frame(at: tsk(14, 38), shoots: [wedding])
        case .broken: frame(at: tsk(0, 10, day: 24), shoots: [broken])
        }
    }

    static let sizes: [CGSize] = [CGSize(width: 364, height: 382), CGSize(width: 338, height: 354)]

    private func plate(_ f: WidgetFrame, _ size: CGSize, dark: Bool, alpha: Bool = false) -> some View {
        WidgetRoot(frame: f, shape: .large, alpha: alpha)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: BraunPlate.cornerRadius(plateHeight: size.height), style: .continuous))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.widgetFrozenTimer, true)
            .environment(\.widgetFlatGlass, true)
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
    private func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double { abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) }

    /// Сколько точек полосы рядом с краем отличаются от подложки: полоса между `from` и `to` pt от края, по четырём сторонам, без скруглённых углов.
    private func inkInBand(_ px: Pixels, size: CGSize, from: Double, to: Double, bg: UInt32) -> Int {
        let W = Double(size.width), H = Double(size.height), corner = 26.0
        var n = 0
        var t = from
        while t < to {
            var u = corner
            while u < max(W, H) - corner {
                if u < W - corner, dist(px.rgb(u, t), hex(bg)) > 40 || dist(px.rgb(u, H - t), hex(bg)) > 40 { n += 1 }
                if u < H - corner, dist(px.rgb(t, u), hex(bg)) > 40 || dist(px.rgb(W - t, u), hex(bg)) > 40 { n += 1 }
                u += 0.5
            }
            t += 0.5
        }
        return n
    }

    // MARK: Какой вид стоит

    @Test func eachCaseGetsItsView() {
        let states = Case.allCases.map { BigWidget.state(Self.frame($0)) }
        #expect(states == [.idle, .idle, .photo, .route, .route], "неделя со съёмками, пустая неделя, фотосессия, свадьба, сломанная свадьба")
    }

    // MARK: Риски — только у маршрута

    /// Риски стоят у вида с маршрутом (150 штук: в полосе 3…10,5 от края видны чернила) и больше нигде; текст в эту полосу не заходит —
    /// в полосе 11…15,5 чисто, на обоих размерах и в обеих темах.
    @Test func ticksAreOnlyAroundTheRouteAndTextStaysOffThem() throws {
        for size in Self.sizes {
            for dark in [true, false] {
                let bg: UInt32 = dark ? 0x161616 : 0xE4E4E2
                for c in Case.allCases {
                    let px = try render(plate(Self.frame(c), size, dark: dark), scale: 4)
                    let ticks = inkInBand(px, size: size, from: 3.5, to: 10, bg: bg)
                    let text = inkInBand(px, size: size, from: 11.5, to: 15.5, bg: bg)
                    let route = BigWidget.state(Self.frame(c)) == .route
                    let name = "\(Int(size.width)) \(dark ? "чёрный" : "белый") \(c)"
                    if route { #expect(ticks > 600, "\(name): рисков нет (\(ticks))") } else { #expect(ticks == 0, "\(name): риски без маршрута (\(ticks))") }
                    #expect(text == 0, "\(name): чернила в полосе между рисками и текстом (\(text))")
                }
            }
        }
    }

    /// Пройдено 2 ч 38 мин из 12 ч 30 мин → 31 или 32 риски из 150 погасли (одна риска — 5 минут), остальные горят. Считаем по цвету рисок вдоль верха
    /// и по правому краю: гаснут они по часовой от середины верха.
    @Test func theTickTimerCountsTheWholeShoot() {
        let f = Self.frame(.route)
        let plan = DayPlan(f)!
        let total = plan.shoot.endDate.timeIntervalSince(plan.shoot.startDate)
        let elapsed = f.now.timeIntervalSince(plan.shoot.startDate)
        let past = (0..<BraunTicks.count).filter { BraunTicks.isPast(index: $0, duration: total, elapsed: elapsed) }.count
        #expect((31...32).contains(past), "прошло \(past) рисок")
        let hours = BraunTicks.hourIndexes(start: plan.shoot.startDate.timeIntervalSince1970 + 7 * 3600, duration: total)
        #expect(hours.count == 13, "ровные часы 12:00…00:00 — 13 длинных рисок: \(hours.count)")
    }

    // MARK: Ножки: оценки не наползают друг на друга

    /// Строки оценки левой и правой ножек не заходят под среднюю («золотой час») даже на 338 pt: у вида со «Светом» колонки с отступом по дуге,
    /// у вида с маршрутом — на всю ширину; строка при нужде мельчает до 0,7, но должна влезать.
    @Test func theFeetScoreLinesFitBesideTheGoldenHour() {
        for size in Self.sizes {
            let iw = size.width - 32
            let withDome = 18 * iw / DomeFit.canvasWidth
            for c in Case.allCases {
                let f = Self.frame(c)
                #expect(LargeFeet.fits(frame: f, iw: iw, inset: BigWidget.state(f) == .route ? 0 : withDome), "\(Int(size.width)) \(c): оценки ножек не влезают рядом с золотым часом")
            }
        }
    }

    // MARK: Нет съёмок: блок заполнен

    /// «Съёмок нет» (Алексей 16.11: «чтобы пространство не пустовало»): нижний блок большого заполнен закатами — чернила есть в его нижней половине;
    /// у кадра без прогноза в тех же строках остаётся время заката, пустых строк нет.
    @Test func theEmptyWeekBlockIsFilledWithSunsets() throws {
        for size in Self.sizes {
            let px = try render(plate(Self.frame(.emptyWeek), size, dark: true), scale: 4)
            let bg = hex(0x0D0D0D)
            var ink = 0
            let y0 = Double(size.height) * 0.78
            var y = y0
            while y < Double(size.height) - 20 {
                var x = 30.0
                while x < Double(size.width) - 30 {
                    if dist(px.rgb(x, y), bg) > 120 { ink += 1 }
                    x += 1
                }
                y += 1
            }
            #expect(ink > 400, "\(Int(size.width)): в нижней части блока почти нет чернил (\(ink))")
        }
        let noForecast = Self.frame(at: Self.tsk(20), shoots: [], forecast: [])
        let rows = BraunIdle.sunsetRows(noForecast)
        #expect(rows.count == 3 && rows.allSatisfy { $0.time.contains(":") && $0.score == nil && $0.word == nil }, "без прогноза — три строки только со временем")
    }

    // MARK: Сломанная свадьба

    /// Съёмка 00:00–00:35, точки с 08:00: вид с маршрутом не пустеет — в часах знак жанра и минуты до конца съёмки (25), в таймлайне точки без текущей.
    @Test func aBrokenWeddingStillDrawsItsRoute() throws {
        let f = Self.frame(.broken)
        let plan = try #require(DayPlan(f))
        #expect(plan.current == nil && plan.waitingStop == nil && abs(plan.dialLeft - 25 * 60) < 0.01 && plan.dialSignIsGenre)
        #expect(BigWidget.routeWindow(count: plan.stops.count, current: plan.currentIndex, rows: 6) == 0..<3, "точки с начала списка")
        for size in Self.sizes {
            let px = try render(plate(f, size, dark: true), scale: 4)
            // Часы стоят слева в блоке: в их круге есть светлые точки (горят 25 из 60) — считаем светлые пиксели в квадрате часов.
            var lit = 0
            var y = Double(size.height) * 0.30
            while y < Double(size.height) * 0.62 {
                var x = 20.0
                while x < 110 { if dist(px.rgb(x, y), hex(0x0D0D0D)) > 300 { lit += 1 }; x += 0.5 }
                y += 0.5
            }
            #expect(lit > 40, "\(Int(size.width)): часы пустые (\(lit))")
        }
    }

    // MARK: Картинки для проверки глазом

    /// Листы видов в `$LP_BUILT_DIR` или `/tmp/lp-built-out`, если папка заведена: `large_states_pro.png` (364 × 382) и `large_states_regular.png` (338 × 354);
    /// строки — неделя со съёмками, пустая неделя, фотосессия, свадьба, сломанная свадьба; столбцы — чёрная и белая. Лежат в `docs/30b2v_sketches/built/`.
    @Test func writesTheStateSheetsWhenAsked() throws {
        let dir = ProcessInfo.processInfo.environment["LP_BUILT_DIR"] ?? "/tmp/lp-built-out"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let captions: [Case: String] = [.weekWithShoots: "съёмок сегодня нет, на неделе есть · 20:00", .emptyWeek: "съёмок на неделе нет · 20:00",
                                        .photo: "идёт фотосессия · 16:48", .route: "идёт свадьба с маршрутом · 14:38", .broken: "сломанная свадьба 00:00–00:35 · 00:10"]
        for (tag, size) in [("pro", Self.sizes[0]), ("regular", Self.sizes[1])] {
            let rows: [[AnyView]] = Case.allCases.map { c in
                [true, false].map { dark in
                    AnyView(VStack(spacing: 6) {
                        plate(Self.frame(c), size, dark: dark, alpha: true)
                        Text("\(captions[c] ?? "") · \(dark ? "тёмная" : "светлая")").font(.system(size: 11, weight: .medium)).foregroundStyle(.white).frame(width: size.width)
                    })
                }
            }
            let grid = VStack(spacing: 14) {
                ForEach(rows.indices, id: \.self) { r in HStack(alignment: .top, spacing: 14) { ForEach(rows[r].indices, id: \.self) { rows[r][$0] } } }
            }
            .padding(14).background(Color(red: 0.36, green: 0.35, blue: 0.33))
            let r = ImageRenderer(content: grid)
            r.scale = 1.3
            let png = try #require(r.uiImage?.pngData(), "картинка \(tag) не отрисована")
            try png.write(to: URL(fileURLWithPath: "\(dir)/large_states_\(tag).png"))
        }
    }
}
#endif
