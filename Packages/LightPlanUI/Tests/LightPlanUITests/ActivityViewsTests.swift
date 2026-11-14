import Testing
import SwiftUI
import Foundation
import LightPlanDomain
import LightPlanCore
#if os(iOS)
import UIKit

/// Шаг 30б.3: виды экрана активности (`LightPlanWidget/Views/ActivityViews.swift`, в этом наборе — по ссылке `WidgetViews`) отрисованы
/// по числам: высота плашки на экране блокировки в системной ширине. Потолок — около 160 pt по документации Apple (не мерено);
/// спайк 30б.3а: свадьба 128 pt, студия без ленты 79 pt. Настоящий потолок меряет прогон на симуляторе (`Tools/shots/activity.js`).
@MainActor
struct ActivityViewsTests {

    private let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    private func tsk(_ h: Int, _ m: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }
    private func ms(_ d: Date) -> Int64 { Moment(d).milliseconds }
    private func stop(_ h: Int, _ m: Int, _ name: String, _ sign: String) -> WidgetFeed.Stop {
        .init(at: ms(tsk(h, m)), name: name, place: "", sign: sign)
    }

    private func frame(_ stops: [WidgetFeed.Stop], sunset: Bool = false, rents: [WidgetFeed.Rent] = [], mode: ActivityFrame.Mode = .route,
                       at now: Date, genre: String = "wedding") -> ActivityFrame {
        let s = WidgetFeed.Shoot(id: "w", start: ms(tsk(12)), end: ms(tsk(22)), title: "Свадьба", place: "Томск", wantsSunset: sunset,
                                 rents: rents, stops: stops, genre: genre)
        return ActivityFrame.make(feed: WidgetFeed(place: tomsk, shoots: [s]), shoot: s, now: now, mode: mode,
                                  reach: .init(admin: true, playlist: true))
    }
    private var wedding: [WidgetFeed.Stop] {
        [stop(12, 0, "Сборы жениха", "makeup"), stop(14, 30, "Церемония", "rings"), stop(16, 0, "Прогулка", "park"), stop(19, 0, "Банкет", "feast")]
    }
    private var rent: [WidgetFeed.Rent] {
        [.init(from: ms(tsk(14)), to: ms(tsk(16)), deadline: ms(tsk(15, 55)), studio: "Томсон")]
    }
    private var many: [WidgetFeed.Stop] {
        (0..<16).map { stop(12 + $0 / 2, ($0 % 2) * 30, "Достопримечательность \($0 + 1)", "camera") }
    }

    /// Ширины плашки: узкий iPhone, 14/15, как в спайке (361), Pro Max.
    private static let widths: [CGFloat] = [330, 358, 361, 408]
    /// Потолок высоты плашки (документация, не мерено; меряет прогон симулятора).
    static let ceiling: CGFloat = 160

    private func height(_ f: ActivityFrame, width: CGFloat) -> CGFloat {
        let host = UIHostingController(rootView: ActivityLockView(frame: f).frame(width: width).fixedSize(horizontal: false, vertical: true))
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    private func cases() -> [(String, ActivityFrame)] {
        [
            ("свадьба, 4 точки", frame(wedding, at: tsk(15))),
            ("свадьба с золотым часом", frame(wedding, sunset: true, at: tsk(15))),
            ("16 точек", frame(many, at: tsk(15))),
            ("лента + выход из зала", frame(wedding, rents: rent, at: tsk(15))),
            ("студия", frame(wedding, rents: rent, mode: .studio, at: tsk(15))),
            ("студия с золотым часом", frame(wedding, sunset: true, rents: rent, mode: .studio, at: tsk(15))),
            ("без точек", frame([], at: tsk(15))),
        ]
    }

    @Test func printsTheHeightOfEveryState() {
        var report: [String] = []
        for (name, f) in cases() {
            let row = Self.widths.map { String(format: "%.0f→%.1f", $0, height(f, width: $0)) }.joined(separator: "  ")
            report.append("ВЫСОТА «\(name)»: \(row)")
        }
        print(report.joined(separator: "\n"))
    }

    /// Лента, лента с арендой и студия (слово Алексея 28.10: кнопки с подписями, лента без слов) под потолком.
    @Test func everyStateFitsUnderTheCeiling() {
        for (name, f) in cases() {
            for w in Self.widths {
                let h = height(f, width: w)
                #expect(h <= Self.ceiling, Comment(rawValue: "«\(name)» \(w): \(h) > \(Self.ceiling)"))
            }
        }
    }

    @Test func studioKeepsLabelledButtonsAndDropsTheSecondLine() {
        let f = frame(wedding, rents: rent, mode: .studio, at: tsk(15))
        #expect(f.call == "Позвонить админу" && f.playlist == "Плейлист" && f.mode == .studio)
        // Без номера администратора и плейлиста кнопок нет и места под них нет: плашка ниже.
        let bare = ActivityFrame.make(feed: WidgetFeed(place: tomsk, shoots: []), shoot: .init(id: "w", start: ms(tsk(12)), end: ms(tsk(22)), title: "Свадьба",
                                      rents: rent, stops: wedding), now: tsk(15), mode: .studio)
        #expect(bare.call == nil && bare.playlist == nil)
        #expect(height(bare, width: 361) < height(f, width: 361))
    }

    @Test func theSignsAreThereForEveryPointTheSystemCanName() {
        // Каждое имя знака, что может назвать приложение для ленты, есть в таблице расширения (иначе точка — кружок).
        for (name, f) in cases() {
            for p in f.points where !p.gold { #expect(p.sign.map { WidgetIconTable.common[$0] != nil } ?? true, Comment(rawValue: "\(name): \(p.word)")) }
        }
    }

    @Test func laneCentresRunFromEdgeToEdge() {
        #expect(ActivityLane.xs(count: 0, width: 300) == [])
        #expect(ActivityLane.xs(count: 1, width: 300) == [150])
        #expect(ActivityLane.xs(count: 2, width: 300) == [14, 286])
        let five = ActivityLane.xs(count: 5, width: 300)
        #expect(five.first == 14 && five.last == 286 && abs(five[2] - 150) < 0.001)
    }

    // MARK: Окошко отсчёта (30и.9)

    /// Плашка в картинку (3×, подложка #2E2A26 без прозрачности — как её красит расширение) и полосы строк, где есть что-то кроме подложки.
    private struct Picture {
        let w: Int, h: Int, scale: Double
        let ink: [[Bool]]   // [y][x]
        /// Полосы подряд идущих «чернильных» строк (щель в 1 px склеивается), сверху вниз.
        var bands: [ClosedRange<Int>] {
            var out: [ClosedRange<Int>] = [], start: Int?, gap = 0
            for y in 6..<h {   // блик плашки — верхний 1 pt (3 px), до полей ещё 30 px
                if ink[y].contains(true) { if start == nil { start = y }; gap = 0 }
                else if let s = start { gap += 1; if gap > 1 { out.append(s...(y - gap)); start = nil } }
            }
            if let s = start { out.append(s...(h - 1)) }
            return out
        }
        func right(_ b: ClosedRange<Int>) -> Int { b.compactMap { y in ink[y].lastIndex(of: true) }.max() ?? -1 }
        func left(_ b: ClosedRange<Int>, from x0: Int) -> Int { b.compactMap { y in ink[y][x0...].firstIndex(of: true) }.min() ?? -1 }
    }

    private func picture(_ f: ActivityFrame, width: CGFloat = 361) -> Picture? {
        let v = ActivityLockView(frame: f).frame(width: width).background(Color(red: 0x2E / 255, green: 0x2A / 255, blue: 0x26 / 255))
            .environment(\.colorScheme, .dark).environment(\.activityStill, f.asOfDate)
        let r = ImageRenderer(content: v)
        r.scale = 3
        guard let cg = r.uiImage?.cgImage, let data = cg.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return nil }
        let bpp = cg.bitsPerPixel / 8
        var ink = [[Bool]](repeating: [Bool](repeating: false, count: cg.width), count: cg.height)
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let o = y * cg.bytesPerRow + x * bpp
                // RGBA или BGRA — подложка #2E2A26 даёт по каналам 0x2E/0x2A/0x26 в любом порядке, берём разницу с ближайшей из трёх.
                let px = [Int(p[o]), Int(p[o + 1]), Int(p[o + 2])]
                let bg = [0x2E, 0x2A, 0x26]
                let bgRev = [0x26, 0x2A, 0x2E]
                let d = zip(px, bg).map { abs($0 - $1) }.max()!, dr = zip(px, bgRev).map { abs($0 - $1) }.max()!
                ink[y][x] = min(d, dr) > 14
            }
        }
        return Picture(w: cg.width, h: cg.height, scale: 3, ink: ink)
    }

    /// Правый край окошка отсчёта — правый край «Далее: …» строкой ниже (на телефоне 14.11 цифры стояли на 38 pt левее: 110 px из 1290),
    /// окошко не шире и не выше своих цифр больше чем на поля.
    @Test func theCountdownWindowEndsWhereTheLineBelowEnds() throws {
        for (name, f) in [("свадьба, 4 точки", frame(wedding, at: tsk(15))), ("свадьба, часы с часами", frame(wedding, at: tsk(12, 5)))] {
            let pic = try #require(picture(f), Comment(rawValue: name))
            let bands = pic.bands
            #expect(bands.count >= 3, "полос \(bands.count): статус, диапазон, лента — \(name)")
            guard bands.count >= 2 else { continue }
            let windowRight = Double(pic.right(bands[0])) + 1, lineRight = Double(pic.right(bands[1])) + 1
            let edge = Double(pic.w) - 16 * pic.scale   // правый край поля плашки
            let windowLeft = Double(pic.left(bands[0], from: pic.w / 2))
            let wPt = (windowRight - windowLeft) / pic.scale, hPt = Double(bands[0].count) / pic.scale
            print("ОКОШКО «\(name)»: правый край окошка \(String(format: "%.2f", windowRight / pic.scale)) pt, «Далее» \(String(format: "%.2f", lineRight / pic.scale)) pt, поле \(String(format: "%.2f", edge / pic.scale)) pt; разница \(String(format: "%.2f", abs(windowRight - lineRight) / pic.scale)) pt; окошко \(String(format: "%.1f", wPt)) × \(String(format: "%.1f", hPt)) pt")
            #expect(abs(windowRight - edge) <= 1, "окошко не на краю поля плашки: \(windowRight / pic.scale) pt против \(edge / pic.scale) — \(name)")
            #expect(abs(windowRight - lineRight) <= 1.5 * pic.scale, "правые края разошлись на \(abs(windowRight - lineRight) / pic.scale) pt — \(name)")
            #expect(abs(hPt - Double(ActivityCountdownWindow.height)) <= 1, "высота окошка \(hPt) pt — \(name)")
        }
    }

    /// Окошко — тело виджета, без красного флажка: тот же цвет `BraunPalette(dark: true).win` и ни одного красного пикселя.
    @Test func theWindowIsTheWidgetsBodyWithoutTheRedFlag() throws {
        let f = frame(wedding, at: tsk(15))
        let v = ActivityCountdownWindow(to: f.next!.date).environment(\.activityStill, f.asOfDate).background(Color(red: 0x2E / 255, green: 0x2A / 255, blue: 0x26 / 255))
        let r = ImageRenderer(content: v)
        r.scale = 1
        let img = try #require(r.uiImage?.cgImage)
        let data = try #require(img.dataProvider?.data), p = try #require(CFDataGetBytePtr(data))
        var red = 0, centre: [Int] = []
        for y in 0..<img.height { for x in 0..<img.width {
            let o = y * img.bytesPerRow + x * (img.bitsPerPixel / 8)
            let a = [Int(p[o]), Int(p[o + 1]), Int(p[o + 2])]
            if max(a[0], a[2]) > 120 && min(a[0], a[2]) < 60 && abs(a[0] - a[2]) > 80 { red += 1 }
            if y == img.height / 2 && x == 2 { centre = a }
        } }
        #expect(red == 0, "красных пикселей: \(red)")
        // Тело окошка на левом краю, у середины высоты: #0A0A0A (тёмная `win`), не подложка #2E2A26.
        #expect(centre.allSatisfy { $0 < 0x1A }, "цвет тела окошка \(centre)")
    }

    /// Картинки для глаз: в `$LP_ACTIVITY_SHOTS` или `/tmp/lp-activity-shots`, если папка есть.
    @Test func writesPicturesWhenAsked() throws {
        let dir = ProcessInfo.processInfo.environment["LP_ACTIVITY_SHOTS"] ?? "/tmp/lp-activity-shots"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        func write(_ f: ActivityFrame, _ tag: String) throws {
            let v = ActivityLockView(frame: f).frame(width: 361).background(Color(red: 0.059, green: 0.055, blue: 0.047))
                .environment(\.colorScheme, .dark).environment(\.activityStill, f.asOfDate)
            let r = ImageRenderer(content: v)
            r.scale = 3
            if let png = r.uiImage?.pngData() { try png.write(to: URL(fileURLWithPath: "\(dir)/\(tag).png")) }
        }
        for (i, (name, f)) in cases().enumerated() {
            try write(f, "\(i)-" + name.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ",", with: ""))
        }
        // Подпись часов с названием точки без склонения (предложение оркестратора 28.10, не включено): две формы, читающиеся с любым именем.
        let s = WidgetFeed.Shoot(id: "w", start: ms(tsk(12)), end: ms(tsk(22)), title: "Свадьба", place: "Томск", stops: wedding, genre: "wedding")
        for (tag, template) in [("words-a", "до точки «{name}»"), ("words-b", "Далее: {name}"), ("words-now", "до {name}")] {
            var w = ActivityWords()
            w.untilName = template
            try write(ActivityFrame.make(feed: WidgetFeed(place: tomsk, shoots: [s]), shoot: s, now: tsk(15), words: w), tag)
        }
    }
}
#endif
