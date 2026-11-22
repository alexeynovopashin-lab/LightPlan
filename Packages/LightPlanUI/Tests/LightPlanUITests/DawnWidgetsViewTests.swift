import Testing
import Foundation
import SwiftUI
@testable import LightPlanUI
import LightPlanDomain
import LightPlanCore

/// Шаг 31.7 «Рассвет в виджетах и планировщике»: виды. Строки «три дня вперёд» и окошко малого влезают на самом узком айфоне без
/// мельчания и «…» (Алексей: «будь внимателен к текстам»), на пяти языках и в 12-часовых часах; строки планировщика знают оба золотых часа.
@MainActor
struct DawnWidgetsViewTests {

    static let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    static func tsk(_ h: Int, day d: Int = 25) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))!.addingTimeInterval(-7 * 3600)
    }
    static let langs = ["ru", "en", "es", "ja", "zh"]
    /// Самые широкие баллы: «100» у обоих событий.
    static let wide: [WidgetFeed.Rating] = (26...28).map { .init(day: "2026-10-\($0)", score: 100, quality: .excellent, sunrise: 100) }

    static func rows(lang: String, clock12: Bool) -> [BraunIdle.SunsetRow] {
        BraunIdle.sunsetRows(WidgetFeed(place: tomsk, forecast: wide, lang: lang, clock12: clock12).frame(at: tsk(14)))
    }

    // MARK: Средний: «пт 20 ↑ 48 ↓ 72»

    /// Правая колонка среднего: 166 pt на 364, 149 на 338 (`x = 182 − сдвиг`, поле 16). Строка без времени влезает с «100» у обоих событий.
    @Test("средний: день и две оценки влезают на 338 и 364 pt, пять языков")
    func theMediumRowFits() {
        for lang in Self.langs {
            let rows = Self.rows(lang: lang, clock12: lang == "en")
            #expect(rows.count == 3 && rows.allSatisfy { $0.riseScore == 100 && $0.score == 100 })
            let c = BraunSunsetRow.Cols.of(rows)
            for width in [166.0, 149] {
                #expect(BraunSunsetRow.need(c, wide: false) <= width, "\(lang) \(width): строка хочет \(BraunSunsetRow.need(c, wide: false))")
            }
        }
    }

    // MARK: Большой: время, полоска и балл у каждого события

    /// Блок большого — ширина купола (338 − 32 = 306, 364 − 32 = 332) минус поля 14 × 2: строки 278 и 304 pt.
    @Test("большой: со временем и полосками на 24 часах; в 12-часовых на 338 полоски уходят, а не кегль")
    func theBigRowFits() {
        for lang in Self.langs {
            for clock12 in [false, true] {
                let c = BraunSunsetRow.Cols.of(Self.rows(lang: lang, clock12: clock12))
                let bare = BraunSunsetRow.need(c, wide: true) - 2 * (BraunSunsetRow.minBar + BraunSunsetRow.gap)
                for width in [278.0, 304] {
                    #expect(bare <= width, "\(lang) 12ч=\(clock12) \(width): даже без полосок \(bare)")
                    if !clock12 { #expect(BraunSunsetRow.bars(c, width: width), "\(lang) \(width): на 24 часах полоски стоят") }
                }
            }
        }
    }

    /// Строка рисуется в своей ширине: чернил правее края нет (338 pt, «100» и 12-часовые часы — худший случай).
    @Test("большой: строка не выходит за свою ширину")
    func theBigRowDrawsInsideItsWidth() throws {
        let rows = Self.rows(lang: "en", clock12: true)
        let c = BraunSunsetRow.Cols.of(rows)
        for dark in [true, false] {
            let pal = BraunPalette(dark: dark)
            let v = BraunSunsetRow(row: rows[0], pal: pal, width: 278, height: 24, wide: true, cols: c)
                .frame(width: 300, height: 24, alignment: .leading).background(pal.bg)
            let r = ImageRenderer(content: v)
            r.scale = 2
            let cg = try #require(r.cgImage)
            let (w, h) = (cg.width, cg.height)
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = try #require(CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            let bg = data[0..<3].map(Int.init)
            var outside = 0, inside = 0
            for y in 0..<h { for x in 0..<w {
                let o = (y * w + x) * 4
                let d = zip(bg, data[o..<o + 3].map(Int.init)).map { abs($0 - $1) }.reduce(0, +)
                if d > 60 { if x >= 279 * 2 { outside += 1 } else { inside += 1 } }
            } }
            #expect(inside > 200, "строка нарисована (\(inside))")
            #expect(outside == 0, "\(dark ? "чёрный" : "белый"): чернила правее 278 pt (\(outside))")
        }
    }

    // MARK: Малый: окошко «48 · 72»

    /// Окошко 142 pt на три дня — колонки по 47,3; пара 11 pt с точкой влезает с полями ≥ 2 pt, кроме «100 · 100» — та колонка ужимается до 10–10,5 pt.
    @Test("малый: пара «рассвет · закат» влезает в колонку окошка, флажок над своим числом")
    func theSmallPairsFit() {
        typealias P = SmallSkyCanvas.Pairs
        #expect(abs(P.column - SmallSkyCanvas.window.width / 3) < 0.001)
        let cases: [(Int?, Int?)] = [(48, 72), (100, 72), (7, 100), (100, 100), (nil, 64), (nil, nil)]
        for (a, b) in cases {
            let p = P.layout(SmallSky.SunsetCell(day: "пн", score: b, dawn: a))
            if a == 100 && b == 100 {
                // Оркестратор 19.11 (вариант 4): «100 · 100» в 11 pt — 49,2 pt при колонке 47,3; ужимается только эта колонка, не ниже 10 pt,
                // и между соседними колонками остаётся зазор (поле ≥ 0,75 pt с каждой стороны черты — «100100» не слипается).
                #expect(p.size >= P.minSize && p.size < 11, "100 · 100: кегль \(p.size)")
                #expect(p.width <= P.column - 1.5, "100 · 100: \(p.width) в \(P.column)")   // 10 pt: 45,35 из 47,33 — по 0,99 pt до черты, между парами ≈ 2 pt
                continue
            }
            #expect(p.size == 11, "\(String(describing: a)) · \(String(describing: b)): кегль \(p.size)")
            #expect(p.width <= P.column - 4, "\(String(describing: a)) · \(String(describing: b)): \(p.width) в \(P.column)")
            #expect(p.dawnX < 0 && p.sunsetX > 0, "рассвет слева, закат справа")
        }
        #expect(P.layout(SmallSky.SunsetCell(day: "пн", score: 72, dawn: 48)).width > P.layout(SmallSky.SunsetCell(day: "пн", score: 100, dawn: 100)).width - 20)
    }

    /// Золотой знак лучшего события (оркестратор 19.11: «флажок над лучшим днём сделай тем самым золотым знаком… не мельче»): 21 pt, внутри своей
    /// колонки с полем ≥ 1,5 pt до черты, над своим числом, не задевает подпись дня (она уходит к другому числу) и стоит выше цифр, пять языков.
    @Test("малый: золотой знак лучшего события влезает в колонку и не задевает подпись и цифры")
    func theSmallGoldSignFits() {
        typealias P = SmallSkyCanvas.Pairs
        #expect(P.sign >= 21, "знак не мельче, чем был (21 pt)")
        let half = (21.5 - 2.5) / 24 / 2 * Double(P.sign) + 0.75   // половина рисунка + половина линии 1,7·21/24
        let top = Double(P.signY) - (0.5 - 4.0 / 24) * Double(P.sign) - 0.75
        let bottom = Double(P.signY) + (16.5 / 24 - 0.5) * Double(P.sign) + 0.75
        let digitsTop = 148 - 114 - 0.36 * 11 - 0.36 * 11   // верх цифр 11 pt (высота прописной ≈ 0,72 размера)
        #expect(top >= 1 && bottom <= digitsTop - 3, "знак по высоте: \(top)…\(bottom), цифры с \(digitsTop)")
        for lang in Self.langs {
            for fc in [Self.wide, (26...28).map { WidgetFeed.Rating(day: "2026-10-\($0)", score: 72, quality: .good, sunrise: 48) },
                       (26...28).map { WidgetFeed.Rating(day: "2026-10-\($0)", score: 72, quality: .good, sunrise: 100) },
                       (26...28).map { WidgetFeed.Rating(day: "2026-10-\($0)", score: 100, quality: .excellent, sunrise: 7) }] {
                guard case .sunsets(let cells, _) = SmallSky.window(WidgetFeed(place: Self.tomsk, forecast: fc, lang: lang).frame(at: Self.tsk(14))) else {
                    Issue.record("\(lang): ждали дни"); continue
                }
                for c in cells {
                    for e in [SkyEvent.dawn, .sunset] {
                        let m = P.mark(c, best: e), p = P.layout(c)
                        guard let sx = m.signX.map(Double.init) else { Issue.record("нет знака"); continue }
                        let num = Double(e == .dawn ? p.dawnX : p.sunsetX)
                        // Однозначный балл у черты («7 · 100»: число в 15,7 pt от середины) знак накрывает со сдвигом до 2,6 pt — не дальше 3 pt и на своей стороне.
                        #expect(abs(sx - num) <= 3 && sx * num > 0, "\(lang) \(c.dawn ?? -1)·\(c.score ?? -1) \(e): знак \(sx), число \(num)")
                        #expect(abs(sx) + half <= Double(P.column) / 2 - 1.5, "\(lang) \(c.day) \(e): знак у черты (\(abs(sx) + half) из \(P.column / 2))")
                        let lw = BraunText.width(c.day, size: 9, semibold: true) / 2, lx = Double(m.labelX)
                        #expect(abs(lx - sx) >= lw + half + 1, "\(lang) \(c.day) \(e): подпись задевает знак")
                        #expect(abs(lx) + lw <= Double(P.column) / 2 - 1, "\(lang) \(c.day): подпись за чертой")
                    }
                    #expect(P.mark(c, best: nil).signX == nil && P.mark(c, best: nil).labelX == 0, "у других дней подпись посередине, знака нет")
                }
            }
        }
    }

    @Test("малый: окошко рисует пары, не закаты")
    func theSmallWindowDrawsPairs() throws {
        let fc: [WidgetFeed.Rating] = [.init(day: "2026-10-26", score: 72, quality: .good, sunrise: 48),
                                       .init(day: "2026-10-27", score: 35, quality: .plain, sunrise: 81),
                                       .init(day: "2026-10-28", score: 64, quality: .good, sunrise: 20)]
        let f = WidgetFeed(place: Self.tomsk, forecast: fc).frame(at: Self.tsk(14))
        guard case .sunsets(let cells, let best) = SmallSky.window(f) else { Issue.record("ждали дни"); return }
        let p = SmallSkyCanvas.Pairs.layout(cells[1])
        #expect(p.items.map(\.text) == ["81", "·", "35"])
        #expect(best == SmallSky.Best(day: 1, event: .dawn))
    }

    // MARK: Планировщик

    static let place = Place(latitude: 56.49, longitude: 84.95, zone: ZoneID(fixedOffsetHours: 7))
    static let sun = SolarDay(date: CivilDate(year: 2026, month: 11, day: 19), place: place)

    @Test("месяц: длина золотого часа — до полудня утренняя (восход → +6°), после — вечерняя")
    func theMonthGoldenLengthFollowsTheDaySign() throws {
        let rise = try #require(Self.sun.rise), a = try #require(Self.sun.goldenA)
        #expect(PlannerDayPanel.goldenMinutes(Self.sun, .dawn) == a - rise)
        #expect(PlannerDayPanel.goldenMinutes(Self.sun, .sunset) == PlannerDayPanel.goldenMinutes(Self.sun))
    }

    @Test("месяц: время восхода красится рассветным баллом той же шкалой, что закат")
    func theSunriseIsColouredByTheDawnScore() {
        let pal = Palette(.dark)
        #expect(PlannerDayPanel.scoreColor(81, pal, none: pal.ink2) == pal.brass)
        #expect(PlannerDayPanel.scoreColor(60, pal, none: pal.ink2) == pal.green)
        #expect(PlannerDayPanel.scoreColor(30, pal, none: pal.ink2) == pal.ink)
        #expect(PlannerDayPanel.scoreColor(10, pal, none: pal.ink2) == pal.blue)
        #expect(PlannerDayPanel.scoreColor(nil, pal, none: pal.ink2) == pal.ink2, "нет балла — серый, как до 31.7")
    }

    @Test("месяц, свободный день: оба золотых часа, на пяти языках")
    func theFreeMonthDayNamesBothGoldenHours() throws {
        let c = ClockText(language: "ru", preference: .h24)
        let s = PlannerDayList.freeLine(Self.sun, t: Lexicon("ru"), clock: c)
        let ma = c.fmt(Self.sun.blueA), mb = c.fmt(Self.sun.goldenA), ea = c.fmt(Self.sun.goldenB), eb = c.fmt(Self.sun.blueB)
        #expect(s == "золотой час \(ma)–\(mb) · \(ea)–\(eb)")
        for lang in Self.langs {
            let line = PlannerDayList.freeLine(Self.sun, t: Lexicon(lang), clock: ClockText(language: lang, preference: .h12))
            #expect(!line.contains("{") && line.contains(" · "), "\(lang): \(line)")
        }
    }

    @Test("неделя, свободный день: «золотой час 08:40 · 15:57»")
    func theFreeWeekDayNamesBothGoldenStarts() {
        let c = ClockText(language: "ru", preference: .h24)
        #expect(PlannerWeekBody.freeGolden(Self.sun, t: Lexicon("ru"), fmt: c.fmt) == "золотой час \(c.fmt(Self.sun.blueA)) · \(c.fmt(Self.sun.goldenB))")
    }

    // MARK: Картинки

    /// Лист «как стало» (31.7): малый, средний и большой при пустой неделе утром, днём и после заката; русские 24 часа и английские 12 —
    /// на 364 и на самом узком 338 / 158. Пишет, только если есть папка `LP_DAWN_DIR` (или `/tmp/lp-dawn-31-7`).
    @Test func writesTheDawnSheetWhenAsked() throws {
        let dir = ProcessInfo.processInfo.environment["LP_DAWN_DIR"] ?? "/tmp/lp-dawn-31-7"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let fc: [WidgetFeed.Rating] = [.init(day: "2026-10-25", score: 28, quality: .plain, sunrise: 61, clouds: 10),
                                       .init(day: "2026-10-26", score: 72, quality: .good, sunrise: 48, clouds: 40),
                                       .init(day: "2026-10-27", score: 35, quality: .plain, sunrise: 81, clouds: 90),
                                       .init(day: "2026-10-28", score: 64, quality: .good, sunrise: 20, clouds: 30)]
        let l = try #require(Self.tomsk.light(on: CivilDate(year: 2026, month: 10, day: 25)))
        let m = try #require(l.morningGolden), set = try #require(l.sunset)
        let moments: [(String, Date)] = [("утро", m.addingTimeInterval(-1800)), ("день", Self.tsk(13)), ("вечер", set.addingTimeInterval(3600))]
        for (lang, c12) in [("ru", false), ("en", true)] {
            for (shape, sizes) in [(WidgetShape.small, [CGSize(width: 170, height: 170), CGSize(width: 158, height: 158)]),
                                   (.medium, [CGSize(width: 364, height: 170), CGSize(width: 338, height: 158)]),
                                   (.large, [CGSize(width: 364, height: 382), CGSize(width: 338, height: 354)])] {
                let cells: [AnyView] = moments.flatMap { name, at in sizes.flatMap { size in [true, false].map { dark in
                    let f = WidgetFeed(place: Self.tomsk, forecast: fc, lang: lang, clock12: c12).frame(at: at)
                    return AnyView(VStack(spacing: 4) {
                        WidgetRoot(frame: f, shape: shape, alpha: false)
                            .frame(width: size.width, height: size.height)
                            .clipShape(RoundedRectangle(cornerRadius: BraunPlate.cornerRadius(plateHeight: size.height), style: .continuous))
                            .environment(\.colorScheme, dark ? .dark : .light)
                            .environment(\.widgetFrozenTimer, true)
                            .environment(\.widgetFlatGlass, true)
                        Text("\(name) · \(Int(size.width)) · \(dark ? "тёмная" : "светлая")").font(.system(size: 9, weight: .medium)).foregroundStyle(.white)
                    })
                } } }
                let perRow = 4
                let grid = VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<(cells.count + perRow - 1) / perRow, id: \.self) { r in
                        HStack(alignment: .top, spacing: 10) { ForEach(r * perRow..<min(cells.count, (r + 1) * perRow), id: \.self) { cells[$0] } }
                    }
                }
                .padding(10).background(Color(red: 0.36, green: 0.35, blue: 0.33))
                let r = ImageRenderer(content: grid)
                r.scale = 2
                let png = try #require(r.uiImage?.pngData(), "картинка не отрисована")
                try png.write(to: URL(fileURLWithPath: "\(dir)/\(shape)_\(lang).png"))
            }
        }
        // Худший случай малого: «100 · 100» у всех трёх дней, лучший — рассвет первого дня (ничья → ранний).
        let wide = VStack(spacing: 10) {
            ForEach([CGFloat(170), 158], id: \.self) { w in
                HStack(spacing: 10) {
                    ForEach([true, false], id: \.self) { dark in
                        WidgetRoot(frame: WidgetFeed(place: Self.tomsk, forecast: Self.wide).frame(at: Self.tsk(14)), shape: .small, alpha: false)
                            .frame(width: w, height: w)
                            .clipShape(RoundedRectangle(cornerRadius: BraunPlate.cornerRadius(plateHeight: w), style: .continuous))
                            .environment(\.colorScheme, dark ? .dark : .light)
                            .environment(\.widgetFrozenTimer, true)
                    }
                }
            }
        }
        .padding(10).background(Color(red: 0.36, green: 0.35, blue: 0.33))
        let r = ImageRenderer(content: wide)
        r.scale = 3
        try #require(r.uiImage?.pngData(), "картинка не отрисована").write(to: URL(fileURLWithPath: "\(dir)/small_100_ru.png"))
    }
}
