import Testing
import SwiftUI
import Foundation
import LightPlanDomain
import LightPlanCore
#if os(iOS)
import UIKit

/// Шаг 30б.2в-5: средний виджет Braun без маршрута — Б, Г, Д, Е «Семьи виджетов» (Алексей 27.10). Числа доски (`WidgetBoardNumbers.swift`) сняты с
/// настоящей доски в Chrome; здесь они сверяются с пикселями отрисованных видов: где стоит каждый текст, какого он цвета и размера (по ширине
/// чернил), где подложки, окошко, флажок, круг. Времена света у доски заданы (08:10, 17:01, 17:56), у вида — настоящие для Томска 25.10: строки
/// сверяются по месту и цвету, не по цифрам.
@MainActor
struct WidgetBraunIdleViewTests {

    enum Scenario: CaseIterable { case b, g, d, e, z }

    static let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    static func tsk(_ h: Int, _ m: Int = 0, day d: Int = 25) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }
    private static func ms(_ d: Date) -> Int64 { Moment(d).milliseconds }
    private static func shoot(_ id: String, _ from: Date, _ to: Date, _ names: String, _ genre: String, _ title: String) -> WidgetFeed.Shoot {
        .init(id: id, start: ms(from), end: ms(to), title: title, genre: genre, names: names)
    }
    private static let ivanov = shoot("iv", tsk(11, day: 28), tsk(13, day: 28), "Семья Ивановых", "family", "Семья")
    private static let masha = shoot("md", tsk(13, day: 30), tsk(15, day: 30), "Мария и Дмитрий", "wedding", "Свадьба")
    private static let wedding = shoot("w", tsk(12), tsk(24, 30), "Анна и Игорь", "wedding", "Свадьба")
    private static let rating = [WidgetFeed.Rating(day: "2026-10-25", score: 62, quality: .good)]

    /// `clock12` — 12-часовые часы («5:56 PM», язык en): так в приложении при настройке «Часы» 12.
    static func frame(_ s: Scenario, clock12: Bool = false) -> WidgetFrame {
        func feed(_ shoots: [WidgetFeed.Shoot], _ forecast: [WidgetFeed.Rating] = rating) -> WidgetFeed {
            WidgetFeed(place: tomsk, shoots: shoots, forecast: forecast, lang: clock12 ? "en" : "ru", clock12: clock12)
        }
        switch s {
        case .b: return feed([wedding]).frame(at: tsk(15, 18))
        case .g: return feed([wedding, ivanov, masha]).frame(at: tsk(9, 30))
        case .d: return feed([ivanov, masha]).frame(at: tsk(14))
        case .e: return feed([ivanov, masha], []).frame(at: tsk(21))
        case .z: return feed([]).frame(at: tsk(14))
        }
    }

    @ViewBuilder static func widget(_ s: Scenario, alpha: Bool, clock12: Bool) -> some View {
        let f = frame(s, clock12: clock12)
        if s == .b { BraunWidgetView(frame: f, alpha: alpha, medium: true) } else { BraunIdleView(frame: f, alpha: alpha) }
    }

    struct Plate { var size: CGSize; static let pro = Plate(size: CGSize(width: 364, height: 170)), regular = Plate(size: CGSize(width: 338, height: 158)) }

    private func plate(_ s: Scenario, _ p: Plate, dark: Bool, alpha: Bool = false, clock12: Bool = false) -> some View {
        Self.widget(s, alpha: alpha, clock12: clock12)
            .frame(width: p.size.width, height: p.size.height)
            .background(BraunPalette(dark: dark).bg)
            .clipShape(RoundedRectangle(cornerRadius: BraunPlate.cornerRadius(plateHeight: p.size.height), style: .continuous))
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
    private func over(_ c: UInt32, _ a: Double, _ bg: UInt32) -> (Double, Double, Double) {
        let f = hex(c), b = hex(bg)
        return (f.0 * a + b.0 * (1 - a), f.1 * a + b.1 * (1 - a), f.2 * a + b.2 * (1 - a))
    }

    /// Рамка чернил цвета `c` (не дальше `tol` по сумме каналов) в прямоугольнике доски, раздутом на `pad`.
    private func ink(_ px: Pixels, _ t: BoardText, pad: Double = 1.5, tol: Double = 60) -> (x0: Double, x1: Double, y0: Double, y1: Double)? {
        var x0 = Double.infinity, x1 = -Double.infinity, y0 = Double.infinity, y1 = -Double.infinity
        let step = 0.25
        var y = t.y - pad
        while y < t.y + t.h + pad {
            var x = t.x - pad
            while x < t.x + t.w + pad {
                if dist(px.rgb(x, y), hex(t.c)) <= tol { x0 = min(x0, x); x1 = max(x1, x + step); y0 = min(y0, y); y1 = max(y1, y + step) }
                x += step
            }
            y += step
        }
        return x0.isFinite ? (x0, x1, y0, y1) : nil
    }

    // MARK: Сверка с доской

    private func board(_ s: Scenario, dark: Bool) -> (texts: [BoardText], fills: [BoardFill]) {
        switch (s, dark) {
        case (.b, true): (WidgetBoard.b1DarkText, WidgetBoard.b1DarkFill)
        case (.b, false): (WidgetBoard.b1LightText, WidgetBoard.b1LightFill)
        case (.g, true): (WidgetBoard.gDarkText, WidgetBoard.gDarkFill)
        case (.g, false): (WidgetBoard.gLightText, WidgetBoard.gLightFill)
        case (.d, true): (WidgetBoard.dDarkText, WidgetBoard.dDarkFill)
        case (.d, false): (WidgetBoard.dLightText, WidgetBoard.dLightFill)
        case (.e, true): (WidgetBoard.eDarkText, WidgetBoard.eDarkFill)
        case (.e, false): (WidgetBoard.eLightText, WidgetBoard.eLightFill)
        case (.z, true): (WidgetBoard.zDarkText, WidgetBoard.zDarkFill)
        case (.z, false): (WidgetBoard.zLightText, WidgetBoard.zLightFill)
        }
    }

    /// Каждый текст доски стоит там же и тем же цветом: чернила внутри прямоугольника доски (допуск 2 pt), по высоте центр рамки чернил не дальше
    /// 2 pt от центра прямоугольника, у «плотных» текстов (ширина = ширина строки) ширина чернил не отличается больше чем на 6 % и 2 pt.
    @Test func everyTextOfTheBoardIsWhereTheBoardPutsItAtTheProMaxSize() throws {
        var report: [String] = []
        for dark in [true, false] {
            for s in Scenario.allCases {
                let px = try render(plate(s, .pro, dark: dark), scale: 4)
                let (texts, _) = board(s, dark: dark)
                for t in texts {
                    // Число балла над трубкой доски (28.10 ушло в линзу внутри трубки, `WidgetGaugeTests`) — места на доске больше нет.
                    if s != .b, t.t == "62" { continue }
                    // Окошко свадьбы рисует живой таймер, в снимке он заморожен: строки из окошка — те же цифры, но место проверяем по рамке.
                    guard let b = ink(px, t) else {
                        // Цвет совпал нигде: свет у вида настоящий, у доски — заданный; роли цветов те же, а вот пустого места быть не должно.
                        Issue.record("\(s) \(dark ? "чёрный" : "белый"): «\(t.t)» не найден в (\(t.x), \(t.y), \(t.w), \(t.h)) цветом \(String(t.c, radix: 16))")
                        continue
                    }
                    let cy = (b.y0 + b.y1) / 2, ry = t.y + t.h / 2
                    let tag = "\(s) \(dark ? "чёрный" : "белый") «\(t.t)»"
                    report.append("\(tag): чернила x \(b.x0)…\(b.x1) y \(b.y0)…\(b.y1) против \(t.x)…\(t.x + t.w) × \(t.y)…\(t.y + t.h)")
                    #expect(abs(cy - ry) <= 2.0, "\(tag): центр по высоте \(cy) против \(ry)")
                    #expect(b.x0 >= t.x - 2 && b.x1 <= t.x + t.w + 2, "\(tag): вышел за прямоугольник доски по x")
                    if t.tight {
                        let wInk = b.x1 - b.x0
                        // Цифры: «1» в моноширинном начертании стоит в поле с широкими пустотами — чернила уже строки на 4–5 pt.
                        let digits = t.t.allSatisfy(\.isNumber)
                        #expect(abs(wInk - t.w) <= max(2, 0.06 * t.w) + (digits ? 5 : 1.2), "\(tag): ширина чернил \(wInk) против \(t.w) (кегль/начертание)")
                    }
                }
            }
        }
        try? report.joined(separator: "\n").write(toFile: "/tmp/cc-idle-ink.log", atomically: true, encoding: .utf8)
    }

    /// Подложки и цветные детали: ближайшая строка на подложке (белый 7 % / жёлтый), центр барабана света, круг, красный флажок и вырез.
    @Test func fillsSitWhereTheBoardPutsThem() throws {
        for dark in [true, false] {
            let bg: UInt32 = dark ? 0x161616 : 0xE4E4E2
            for s in Scenario.allCases {
                let px = try render(plate(s, .pro, dark: dark), scale: 4)
                for f in board(s, dark: dark).fills {
                    let tag = "\(s) \(dark ? "чёрный" : "белый") \(f.n)"
                    switch f.n {
                    case "pill", "drumPill":
                        // Две точки внутри подложки, не на тексте: у левого и у правого края; цвет = заливка поверх фона.
                        let want = over(f.c, f.a, bg)
                        for x in [f.x + 3, f.x + f.w - 3] { #expect(dist(px.rgb(x, f.y + 3), want) <= 6, "\(tag): (\(x), \(f.y + 3)) \(px.rgb(x, f.y + 3)) против \(want)") }
                        #expect(dist(px.rgb(f.x + 3, f.y + f.h + 1), hex(bg)) <= 6, "\(tag): под подложкой фон")
                    case "dial":
                        #expect(dist(px.rgb(f.x + f.w / 2 - 20, f.y + f.h / 2 + 30), hex(f.c)) <= 14, "\(tag): диск")
                    case "window":
                        // Правый верх окошка: скругление 4, точка (w−5, 5) внутри. Левее — полоса флажка, её цвет проверяет «flag».
                        #expect(dist(px.rgb(f.x + f.w - 5, f.y + 5), hex(f.c)) <= 90, "\(tag): окошко \(px.rgb(f.x + f.w - 5, f.y + 5)) против \(String(f.c, radix: 16))")
                        #expect(f.x + f.w == 348, "правый край окошка на поле 16")
                    case "flag":
                        // Окошко вида шире доски (ширину задаёт «00:00:00», чтобы рамка не прыгала), поэтому флажок стоит левее: от рамки вида, не доски.
                        let plan = try #require(DayPlan(Self.frame(s)))
                        let left = 348 - BraunLayout(plan: plan, size: Plate.pro.size, medium: true, bare: true).windowWidth
                        #expect(dist(px.rgb(left + 3, f.y + 2), hex(f.c)) <= 12, "\(tag): красная полоса у верха \(px.rgb(left + 3, f.y + 2))")
                        #expect(dist(px.rgb(left + 0.4, f.y + 2), hex(bg)) <= 10, "\(tag): левее полосы вырез — фон плашки \(px.rgb(left + 0.4, f.y + 2))")
                        #expect(dist(px.rgb(left + 10.5, f.y + 9), hex(bg == 0x161616 ? 0x0A0A0A : 0xD3D3D1)) <= 40, "\(tag): за остриём флажка (9 от края) — окно")
                    case "track":
                        #expect(dist(px.rgb(f.x + f.w / 2, f.y + 6), over(f.c, f.a, bg)) <= 6, "\(tag): дорожка столбика пуста сверху")
                    case "level":
                        // Полоски уровня больше нет (28.10): уровень показывает линза с числом, её место и цвет проверяет `WidgetGaugeTests`.
                        break
                        // Мерено: полоска вида на 5 % темнее доски (233, 230, 223 против 246, 243, 236) — допуск 20 на канал, расхождение в отчёте.
                        #expect(dist(px.rgb(f.x + f.w / 2, f.y + f.h / 2), hex(f.c)) <= 45, "\(tag): полоска уровня \(px.rgb(f.x + f.w / 2, f.y + f.h / 2))")
                    default: break
                    }
                }
            }
        }
    }

    // MARK: Б и Г — рёбра круга и рисков

    /// Б: на круге горят 44 точки (15:18 из 12:00–00:30), в центре «9 ч 12 мин» и знак жанра; справа центр барабана света — подложка 28 pt.
    @Test func theBareFormCountsTheWholeShootAndShowsLightOnTheRight() throws {
        let f = Self.frame(.b)
        let plan = try #require(DayPlan(f))
        let L = BraunLayout(plan: plan, size: Plate.pro.size, medium: true, bare: true)
        #expect(L.bare && L.diameter == 116 && L.cx == 74 && L.cy == 96)
        #expect(L.drum == CGRect(x: 146, y: 38, width: 202, height: 116))
        #expect(L.rows.map { $0.light?.kind } == [nil, .sunrise, .golden, .sunset, nil], "рассвет, золотой час в центре, закат")
        #expect(L.rows.map(\.slot.y) == [0, 22, 44, 72, 94] && L.rows.map(\.slot.height) == [22, 22, 28, 22, 22])
        #expect(L.rows[3].extra == "хороший" && L.rows[1].extra == nil && L.rows[2].extra == nil, "оценка только у заката")
        #expect(L.windowWidth > 0 && L.header.size == 15)
        #expect(BraunIdle.wholeShootLit(left: plan.shootLeft, total: plan.shoot.endDate.timeIntervalSince(plan.shoot.startDate)) == 44)
        // Без прогноза строки оценки нет.
        let noRating = WidgetFeed(place: Self.tomsk, shoots: [Self.wedding]).frame(at: Self.tsk(15, 18))
        let L2 = BraunLayout(plan: try #require(DayPlan(noRating)), size: Plate.pro.size, medium: true, bare: true)
        #expect(L2.rows.allSatisfy { $0.extra == nil }, "прогноза нет — оценки в строке заката нет")
        // Точки на картинке: считаем горящие по цвету.
        let px = try render(plate(.b, .pro, dark: true), scale: 4)
        var lit = 0
        for k in 0..<60 {
            let p = BraunDial.dotCenter(k, diameter: 116)
            if dist(px.rgb(74 + p.x, 96 + p.y), hex(0xECECEA)) <= 40 { lit += 1 }
        }
        #expect(lit == 44, "на картинке горит \(lit) точек")
    }

    /// Г: 21 риска из 150 пройдено (9:30 от 8:10…17:56), часовых — по числу ровных часов светового дня.
    @Test func theShootAheadFormDrawsTheDayRingAndTheOthersDoNot() throws {
        func inkAtTop(_ s: Scenario) throws -> Bool {
            let px = try render(plate(s, .pro, dark: true), scale: 4)
            // Риска на старте — по центру верха, внешний конец в 3 от края: чернила светлее фона в (182, 4…8).
            return (4...8).contains { dist(px.rgb(182, Double($0)), hex(0x161616)) > 60 }
        }
        #expect(try inkAtTop(.g), "Г: риски есть")
        #expect(try !inkAtTop(.d), "Д: периметр чист")
        #expect(try !inkAtTop(.e), "Е: периметр чист")
        #expect(try !inkAtTop(.z), "пустая неделя: периметр чист")
        let f = Self.frame(.g)
        let d = try #require(f.day), a = try #require(d.sunrise), b = try #require(d.sunset)
        let elapsed = f.now.timeIntervalSince(a), total = b.timeIntervalSince(a)
        let past = (0..<BraunTicks.count).filter { BraunTicks.isPast(index: $0, duration: total, elapsed: elapsed) }.count
        #expect((19...23).contains(past), "прошло \(past) рисок (доска: 21)")
    }

    // MARK: 338 × 158

    /// На 338 × 158 всё остаётся между полями: чернила Д и Е (без рисков) не заходят за поле 16 справа и снизу, три строки Г влезают.
    @Test func theRegularPlateKeepsEverythingInsideTheMargins() throws {
        for dark in [true, false] {
            let bg: UInt32 = dark ? 0x161616 : 0xE4E4E2
            for s in [Scenario.d, .e, .z] {
                let p = Plate.regular
                let px = try render(plate(s, p, dark: dark), scale: 4)
                var worst = 0.0
                var y = 4.0
                while y < Double(p.size.height) - 4 {
                    var x = 4.0
                    while x < Double(p.size.width) - 4 {
                        // Углы плашки скруглены и прозрачны — их не меряем: правая и нижняя полосы поля между углами.
                        let rightStrip = x > Double(p.size.width) - 16 + 0.5 && y > 22 && y < Double(p.size.height) - 22
                        let bottomStrip = y > Double(p.size.height) - 16 + 0.5 && x > 22 && x < Double(p.size.width) - 22
                        let outside = rightStrip || bottomStrip
                        if outside { worst = max(worst, dist(px.rgb(x, y), hex(bg))) }
                        x += 0.5
                    }
                    y += 0.5
                }
                #expect(worst <= 8, "\(s) \(dark ? "чёрный" : "белый"): чернила в поле 16 (\(worst))")
            }
        }
        let g = Self.frame(.g)
        let h = BraunIdle.weekRowHeights(plateHeight: 158)
        #expect(BraunIdle.weekRows(g).count == 3 && 16 + h.near + 2 * h.other + 2 * BraunIdle.weekRowGap <= 158 - 16)
    }

    /// Имена и вторые строки сначала мельчают и только потом режутся «…»: строки доски влезают целиком на обоих размерах плашки, а
    /// «Анна-Мария и Константин Ковалёвы-Ивановы» уходит до 11 и режется.
    @Test func longNamesStepDownThenTruncate() {
        let long = BraunIdle.WeekRow(id: "x", genre: "wedding", names: "Анна-Мария и Константин Ковалёвы-Ивановы", day: "сб 31", time: "13:00", relative: "через 3 дня", near: true)
        let masha = BraunIdle.WeekRow(id: "y", genre: "wedding", names: "Мария и Дмитрий", day: "пт 30", time: "13:00", relative: nil, near: false)
        let iv = BraunIdle.WeekRow(id: "z", genre: "family", names: "Семья Ивановых", day: "ср 28", time: "11:00", relative: "через 3 дня", near: true)
        let widths: [Double] = [166, 149]
        for width in widths {
            for r in [masha, iv] {
                let f = BraunWeekRow.fit(r, width: width)
                #expect(f.nameFits && f.lineFits, "ширина \(width): «\(r.names)» / «\(r.line2)» — кегли \(f.name)/\(f.line), влезло \(f.nameFits)/\(f.lineFits)")
            }
        }
        let f = BraunWeekRow.fit(long, width: 166)
        #expect(f.name == 11 && !f.nameFits, "длинные имена: 11 и «…»")
        #expect(BraunWeekRow.fit(masha, width: 166).name == 13 && BraunWeekRow.fit(iv, width: 166).line == 11, "на Pro Max кегли доски: 13 и 11")
    }

    /// Строка заката в Б с оценкой: на 364 она влезает в 13 целиком, на 338 «Закат» мельчает, а если и так тесно — из хвоста уходит знак, слово оценки остаётся целым.
    @Test func theSunsetRowKeepsItsRatingWholeOnBothPlates() throws {
        let plan = try #require(DayPlan(Self.frame(.b)))
        let pro = BraunLayout(plan: plan, size: Plate.pro.size, medium: true, bare: true)
        let reg = BraunLayout(plan: plan, size: Plate.regular.size, medium: true, bare: true)
        #expect(pro.rows[3].step.size == 13, "Pro Max: «Закат» 13, как на доске")
        #expect(reg.rows[3].step.size <= 13)
        #expect(pro.rows[3].extraIcon, "Pro Max: знак оценки на месте")
        for L in [pro, reg] {
            let avail = L.drumNameWidth - BraunLayout.lightSignWidth(offset: 1) - BraunLayout.ratingWidth("хороший", icon: L.rows[3].extraIcon)
            #expect(BraunText.width("Закат", size: L.rows[3].step.size, semibold: false) <= avail, "строка заката влезла целиком, кегль \(L.rows[3].step.size)")
        }
    }

    /// Волосок между светом и неделей: 0,5 pt, 28 % чернил, на x 168 (на 338 — на 162) от поля 16 высотой плашка − 32.
    @Test func theHairlineBetweenLightAndWeekStays() throws {
        for dark in [true, false] {
            let bg: UInt32 = dark ? 0x161616 : 0xE4E4E2
            let ink: UInt32 = dark ? 0xECECEA : 0x111111
            for s in [Scenario.g, .d, .e, .z] {
                let px = try render(plate(s, .pro, dark: dark), scale: 4)
                let want = over(ink, 0.28, bg)
                #expect(dist(px.rgb(168.25, 60), want) <= 8, "\(s) \(dark ? "чёрный" : "белый"): волосок \(px.rgb(168.25, 60)) против \(want)")
                #expect(dist(px.rgb(168.25, 12), hex(bg)) <= 8 || s == .g, "волосок начинается с y 16")
                #expect(dist(px.rgb(167.5, 60), hex(bg)) <= 8, "и не шире 0,5")
            }
        }
    }

    /// Знаки света на строках доски — свои, не запасные: рассвет, золотой час (солнце с циферблатом), закат и оценка заката (закат с отражением)
    /// стоят в таблице расширения и различаются между собой.
    @Test func theLightRowsHaveTheirOwnSignsInTheWidgetTable() {
        let names = [BraunSign.light(.sunrise), BraunSign.light(.golden), BraunSign.light(.sunset), BraunSign.rating]
        #expect(names == ["sunrise", "golden", "sunset", "sunset_glow"], "оценка заката — свой знак, не запасной «закат»")
        for n in names { #expect(WidgetIconTable.common[n] != nil, "знака «\(n)» нет в таблице расширения") }
        #expect(Set(names.compactMap { WidgetIconTable.common[$0] }).count == 4, "четыре знака света разные")
    }

    /// «ср 28 · 11:00 · через 3 дня» у ближайшей строки доходит до конца целиком (доска: 148 pt текста в рамке 146, x 192…340) — без «…».
    @Test func theNearRowSecondLineIsNotCut() throws {
        let px = try render(plate(.d, .pro, dark: true), scale: 4)
        let t: BoardText = ("ср 28 · 11:00 · через 3 дня", 192, 40.5, 160, 14, 11, 500, 0x9B9B9B, false)
        let b = try #require(ink(px, t, pad: 0))
        #expect(b.x1 >= 336, "вторая строка ближайшей кончается на \(b.x1), на доске около 340: обрезана")
        #expect(b.x1 <= 348, "и не выходит за поле 16")
    }

    // MARK: 12-часовые часы (ревью GPT к bd4357e)

    /// «12:56 PM» не режется: время делится на «ч:мм» и AM / PM, двоеточие стоит в своём поле, суффикс — в поле, которое раскладка отдаёт самым
    /// широким на барабане; название сдвигается на ту же ширину.
    @Test func twelveHourTimesKeepTheirSuffixAndTheColonColumn() throws {
        let a = try #require(ColonTime.split("12:56 PM"))
        #expect(a.prefix == "" && a.h == "12" && a.m == "56" && a.suffix == "PM")
        let b = try #require(ColonTime.split("5:56\u{202F}PM"))
        #expect(b.h == "5" && b.suffix == "PM", "узкий неразрывный пробел новых ICU — тоже разделитель")
        let c = try #require(ColonTime.split("午後5:56"))
        #expect(c.prefix == "午後" && c.h == "5" && c.suffix == "")
        let d = try #require(ColonTime.split("13:48"))
        #expect(d.prefix == "" && d.suffix == "" && d.h == "13" && d.m == "48")
        #expect(ColonTime.split("нет времени") == nil)
        let r = ColonTime.reserves(["4:58 AM", "12:01 PM"])
        #expect(r.before == 0 && r.after > 10 && r.after < 26, "поле суффикса \(r.after)")
        #expect(ColonTime.reserves(["16:58", "08:12"]) == (0, 0), "24 часа — поля нет")
        #expect(ColonTime.reserves(["午後5:56"]).before > 10)

        let f12 = Self.frame(.b, clock12: true), f24 = Self.frame(.b)
        let L12 = BraunLayout(plan: try #require(DayPlan(f12)), size: Plate.pro.size, medium: true, bare: true)
        let L24 = BraunLayout(plan: try #require(DayPlan(f24)), size: Plate.pro.size, medium: true, bare: true)
        #expect(L12.timeAfter > 10 && L12.timeBefore == 0 && L24.timeAfter == 0)
        // Название влезает и при суффиксе: место под него отдано.
        for p in [Plate.pro, .regular] {
            let L = BraunLayout(plan: try #require(DayPlan(f12)), size: p.size, medium: true, bare: true)
            let avail = L.drumNameWidth - BraunLayout.lightSignWidth(offset: 0)
            let step = L.rows[2].step
            #expect(step.lines > 1 || BraunText.width(f12.words[.golden], size: step.size, semibold: true) <= avail + 0.01, "\(Int(p.size.width)): «Золотой час» влезает при суффиксе или переносится, шаг \(step)")
        }
        // На картинке суффикс нарисован: чернила в поле суффикса центральной строки (x 202…), а при 24 часах там пусто (подложка).
        func suffixInk(_ clock12: Bool) throws -> Bool {
            let px = try render(plate(.b, .pro, dark: true, clock12: clock12), scale: 4)
            let pill = over(0xFFFFFF, 0.07, 0x161616)
            var y = 88.0
            while y < 104 { var x = 203.0; while x < 209.5 { if dist(px.rgb(x, y), pill) > 60 { return true }; x += 0.25 }; y += 0.25 }
            return false
        }
        #expect(try suffixInk(true), "12 часов: «PM» рядом с временем")
        #expect(try !suffixInk(false), "24 часа: на том месте пусто")
    }

    // MARK: Снимки

    private func cell(_ caption: String, _ w: CGFloat, _ content: some View) -> some View {
        VStack(spacing: 6) {
            content
            Text(caption).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white).multilineTextAlignment(.center).frame(width: w)
        }
    }

    private static let captions: [(Scenario, String)] = [
        (.b, "Б · идёт без маршрута 15:18"), (.g, "Г · съёмка сегодня 09:30"), (.d, "Д · день без съёмок 14:00"),
        (.e, "Е · вечер 21:00"), (.z, "+ · на неделе съёмок нет 14:00"),
    ]

    /// Картинки в `$LP_BUILT_DIR` или `/tmp/lp-built-out`, если папка заведена: `medium_idle_pro.png` (364 × 170) и `medium_idle_regular.png` (338 × 158);
    /// каждое состояние в чёрной и белой теме, бирка «α» как на слотах. Лежат в `docs/30b2v_sketches/built/`.
    @Test func writesTheIdleSheetsWhenAsked() throws {
        let dir = ProcessInfo.processInfo.environment["LP_BUILT_DIR"] ?? "/tmp/lp-built-out"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        for (tag, p) in [("pro", Plate.pro), ("regular", .regular)] {
            let rows: [[AnyView]] = Self.captions.map { sc, caption in
                [true, false].map { dark in
                    AnyView(cell("\(caption) · \(dark ? "чёрный" : "белый")", p.size.width, plate(sc, p, dark: dark, alpha: true)))
                }
            }
            let grid = VStack(spacing: 14) {
                ForEach(rows.indices, id: \.self) { r in HStack(alignment: .top, spacing: 14) { ForEach(rows[r].indices, id: \.self) { rows[r][$0] } } }
            }
            .padding(14).background(Color(red: 0.36, green: 0.35, blue: 0.33))
            let r = ImageRenderer(content: grid)
            r.scale = 1.35
            let png = try #require(r.uiImage?.pngData(), "картинка \(tag) не отрисована")
            try png.write(to: URL(fileURLWithPath: "\(dir)/medium_idle_\(tag).png"))
            #expect(png.count <= 300 * 1024, "medium_idle_\(tag).png: \(png.count / 1024) КБ, предел 300")
        }
    }

    /// `medium_clock12.png`: те же состояния при 12-часовых часах — Pro Max чёрная и 338 pt белая.
    @Test func writesThe12HourSheetWhenAsked() throws {
        let dir = ProcessInfo.processInfo.environment["LP_BUILT_DIR"] ?? "/tmp/lp-built-out"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let rows: [[AnyView]] = [(Plate.pro, true), (Plate.regular, false)].map { p, dark in
            [Scenario.b, .g, .d].map { sc in
                AnyView(cell("\(sc) · 12 ч · \(Int(p.size.width)) · \(dark ? "чёрный" : "белый")", p.size.width, plate(sc, p, dark: dark, alpha: true, clock12: true)))
            }
        }
        let grid = VStack(spacing: 14) {
            ForEach(rows.indices, id: \.self) { r in HStack(alignment: .top, spacing: 14) { ForEach(rows[r].indices, id: \.self) { rows[r][$0] } } }
        }
        .padding(14).background(Color(red: 0.36, green: 0.35, blue: 0.33))
        let r = ImageRenderer(content: grid)
        r.scale = 1.0
        let png = try #require(r.uiImage?.pngData())
        try png.write(to: URL(fileURLWithPath: "\(dir)/medium_clock12.png"))
        #expect(png.count <= 300 * 1024, "medium_clock12.png: \(png.count / 1024) КБ")
    }
}
#endif
