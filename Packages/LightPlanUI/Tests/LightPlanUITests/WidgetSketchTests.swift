import Testing
import SwiftUI
import Foundation
import LightPlanDomain
import LightPlanCore
#if os(iOS)
import UIKit

/// Шаг 30б.2в-1: новые виды виджета (`LightPlanWidget/Views/`: `MediumLiveView`, `SmallLiveView`, `LargeView`,
/// `LockCircularView`, `LockRectangularView`, их разбор дня `DayPlan`) отрисованы по числам, как в `WidgetViewsTests`: содержимое
/// плашки (с её собственными полями — у колец они несут деления) помещается в плашку 158 / 170 (малый), 338 × 158 / 364 × 170 (средний),
/// 338 × 354 / 364 × 382 (большой) в трёх размерах текста; двоеточие отсчёта стоит по середине цифр (мерено по пикселям).
@MainActor
struct WidgetSketchTests {

    private let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    /// Часы Томска (UTC+7) 24.10.2026 плюс `day`.
    private func tsk(_ h: Int, _ m: Int = 0, day d: Int = 24) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }
    private func ms(_ d: Date) -> Int64 { Moment(d).milliseconds }

    /// Сценарий Алексея: свадьба 12:00–00:30, «Пара в студии» до 13:54 (студийный час), дальше «Обед 14:00», «Прогулка 15:00».
    private var wedding: WidgetFeed.Shoot {
        .init(id: "w", start: ms(tsk(12)), end: ms(tsk(0, 30, day: 25)), title: "Свадьба", place: "Томск", wantsSunset: true,
              rents: [.init(from: ms(tsk(12)), to: ms(tsk(14)), deadline: ms(tsk(13, 54)), studio: "Томсон")],
              stops: [.init(at: ms(tsk(12)), name: "Пара в студии", place: "Студия «Томсон»"),
                      .init(at: ms(tsk(14)), name: "Обед", place: "Кафе «Вилка»"),
                      .init(at: ms(tsk(15)), name: "Прогулка", place: "Набережная реки Ушайки"),
                      .init(at: ms(tsk(17)), name: "Церемония", place: "Дворец бракосочетания"),
                      .init(at: ms(tsk(19)), name: "Банкет", place: "Ресторан «Дом»"),
                      .init(at: ms(tsk(22)), name: "Танцы", place: "Ресторан «Дом»")])
    }

    private func frame(at: Date, shoots: [WidgetFeed.Shoot]? = nil) -> WidgetFrame {
        WidgetFeed(place: tomsk, shoots: shoots ?? [wedding]).frame(at: at)
    }

    private var now: WidgetFrame { frame(at: tsk(12, 52)) }
    private let names = "Анна+Игорь"

    // MARK: Разбор дня

    @Test func theDayPlanReadsTheScenario() throws {
        let plan = try #require(DayPlan(now))
        #expect(plan.stops.count == 6)
        #expect(plan.current?.name == "Пара в студии")
        #expect(plan.pointEnd == tsk(13, 54), "точка кончается студийным часом, а не началом «Обеда»")
        #expect(abs(plan.pointLeft! - 62 * 60) < 0.01, "12:52 → 13:54")
        #expect(abs(plan.shootLeft - (11 * 60 + 38) * 60) < 0.01, "12:52 → 00:30")
        #expect(plan.upcomingStops.map(\.name).prefix(2) == ["Обед", "Прогулка"])
        #expect(DayPlan.short(plan.pointLeft!) == "62 мин")
        #expect(DayPlan.hours(plan.shootLeft) == "11 ч", "целые часы вниз")
        #expect(DayPlan.long(plan.shootLeft) == "11 ч 38 мин")
        #expect(plan.title(names: names) == "Свадьба Анна+Игорь" && plan.title(names: nil) == "Свадьба" && plan.title(names: "") == "Свадьба")
        #expect(abs(plan.shootProgress - (52.0 / 750.0)) < 1e-9, "52 минуты из 12 ч 30 мин")
        #expect(abs((plan.pointProgress ?? -1) - 52.0 / 114.0) < 1e-9)
        #expect(plan.shootHourMarks.count == 12, "12 часовых отметок на 12,5 часа")
        #expect(plan.pointQuarterMarks.count == 7, "114 минут: 15, 30 … 105")
        // В 13:00 остаток точки — «54 мин», как в словах Алексея.
        let at13 = try #require(DayPlan(frame(at: tsk(13))))
        #expect(DayPlan.short(at13.pointLeft!) == "54 мин")
        #expect(DayPlan.hours(at13.shootLeft) == "11 ч")
    }

    @Test func theLastPointEndsWithTheShootAndHoursGiveWayToMinutes() throws {
        let late = try #require(DayPlan(frame(at: tsk(23, 50))))
        #expect(late.current?.name == "Танцы")
        #expect(late.pointEnd == tsk(0, 30, day: 25), "последняя точка кончается с съёмкой")
        #expect(late.upcomingStops.isEmpty)
        #expect(DayPlan.hours(late.shootLeft) == "40 мин", "в последний час — минуты")
        let noRent = try #require(DayPlan(frame(at: tsk(15, 20))))
        #expect(noRent.current?.name == "Прогулка" && noRent.pointEnd == tsk(17), "без студии точка идёт до следующей")
    }

    @Test func aShootWithoutStopsHasNoRingForThePointButDoesNotCrash() throws {
        let bare = WidgetFeed.Shoot(id: "b", start: ms(tsk(12)), end: ms(tsk(15)), title: "Портрет", place: "Парк")
        let f = frame(at: tsk(13), shoots: [bare])
        let plan = try #require(DayPlan(f))
        #expect(plan.current == nil && plan.pointLeft == nil && plan.pointProgress == nil && plan.pointQuarterMarks.isEmpty)
        for look in [WidgetLook.plain, .ring] {
            #expect(ideal(MediumLiveView(frame: f, look: look), width: 364, type: .large).height <= 170)
            #expect(ideal(SmallLiveView(frame: f, look: look), width: 170, type: .large).height <= 170)
        }
    }

    // MARK: Деления по периметру

    @Test func theTicksWalkTheOutlineClockwiseFromTheTopCentre() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 60)
        let w = PerimeterWalker(rect: rect, radius: 10)
        let expected: CGFloat = 2 * (100 - 20) + 2 * (60 - 20) + 2 * .pi * 10
        #expect(abs(w.length - expected) < 0.001, "периметр \(w.length) против \(expected)")
        let start = w.sample(0)
        #expect(start.point == CGPoint(x: 50, y: 0) && start.inward == CGVector(dx: 0, dy: 1), "середина верха, внутрь — вниз")
        let right = w.sample(40 + 10 * .pi / 2 + 20)   // середина правой стороны
        #expect(abs(right.point.x - 100) < 0.001 && abs(right.point.y - 30) < 0.001 && right.inward == CGVector(dx: -1, dy: 0))
        let end = w.sample(w.length)
        #expect(abs(end.point.x - 50) < 0.001 && abs(end.point.y) < 0.001, "обход замыкается в начале")
        // Все деления лежат внутри прямоугольника и смотрят в его сторону.
        for i in 0..<200 {
            let s = w.sample(CGFloat(i) / 200 * w.length)
            let tip = CGPoint(x: s.point.x + s.inward.dx * 5, y: s.point.y + s.inward.dy * 5)
            #expect(rect.insetBy(dx: -0.001, dy: -0.001).contains(s.point) && rect.insetBy(dx: -0.001, dy: -0.001).contains(tip))
        }
    }

    // MARK: Влезает ли

    private func ideal<V: View>(_ v: V, width: CGFloat, type: DynamicTypeSize) -> CGSize {
        let host = UIHostingController(rootView: v.environment(\.dynamicTypeSize, type).frame(width: width).fixedSize(horizontal: false, vertical: true))
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private static let types: [(String, DynamicTypeSize)] = [("обычный", .large), ("крупный", .xxLarge), ("огромный", .accessibility3)]

    /// Кадры «живого» дня для среднего и малого: студийный час, точка без студии, последняя точка.
    private func liveFrames() -> [(String, WidgetFrame)] {
        [("студийный час", now), ("точка без студии", frame(at: tsk(15, 20))), ("последняя точка", frame(at: tsk(23, 50)))]
    }

    @Test func mediumLiveFitsInThreeTextSizes() {
        var report: [String] = []
        for (w, h) in [(338.0, 158.0), (364.0, 170.0)] {
            for look in [WidgetLook.plain, .ring] {
                for (name, f) in liveFrames() {
                    for (tn, t) in Self.types {
                        for alpha in [false, true] {
                            let size = ideal(MediumLiveView(frame: f, look: look, names: names, alpha: alpha), width: w, type: t)
                            report.append(String(format: "средний %.0f %@ «%@» %@ α=%d: высота %.1f из %.0f", w, look == .plain ? "простой" : "кольцо", name, tn, alpha ? 1 : 0, size.height, h))
                            #expect(size.height <= h, Comment(rawValue: report.last!))
                        }
                    }
                }
            }
        }
        print(report.joined(separator: "\n"))
    }

    @Test func smallLiveFitsInThreeTextSizes() {
        var report: [String] = []
        for side in [158.0, 170.0] {
            for look in [WidgetLook.plain, .ring] {
                for (name, f) in liveFrames() {
                    for (tn, t) in Self.types {
                        for alpha in [false, true] {
                            let size = ideal(SmallLiveView(frame: f, look: look, names: names, alpha: alpha), width: side, type: t)
                            report.append(String(format: "малый %.0f %@ «%@» %@ α=%d: высота %.1f из %.0f", side, look == .plain ? "простой" : "кольцо", name, tn, alpha ? 1 : 0, size.height, side))
                            #expect(size.height <= side, Comment(rawValue: report.last!))
                        }
                    }
                }
            }
        }
        print(report.joined(separator: "\n"))
    }

    private func largeFrames() -> [(String, WidgetFrame)] {
        let polar = WidgetFeed(place: .init(name: "Tromsø", latitude: 69.6496, longitude: 18.956, zone: "Europe/Oslo"))
            .frame(at: Date(timeIntervalSince1970: 1_782_043_200))
        return liveFrames() + [("до начала", frame(at: tsk(11))), ("без съёмок", frame(at: tsk(12, 52), shoots: [])),
                               ("без съёмок, вечер", frame(at: tsk(20), shoots: [])), ("полярный день", polar)]
    }

    @Test func largeFitsInThreeTextSizes() {
        var report: [String] = []
        for (w, h) in [(338.0, 354.0), (364.0, 382.0)] {
            for (name, f) in largeFrames() {
                for (tn, t) in Self.types {
                    let size = ideal(LargeView(frame: f, names: names, alpha: true), width: w, type: t)
                    report.append(String(format: "большой %.0f «%@» %@: высота %.1f из %.0f", w, name, tn, size.height, h))
                    #expect(size.height <= h, Comment(rawValue: report.last!))
                }
            }
        }
        print(report.joined(separator: "\n"))
    }

    @Test func lockWidgetsFitTheirPlates() {
        // Экран блокировки: круглый 76 × 76, прямоугольный 172 × 76 (iPhone 15 Pro Max; на 14 — 72 и 160).
        for (w, h) in [(160.0, 72.0), (172.0, 76.0)] {
            for (name, f) in liveFrames() + [("без съёмок", frame(at: tsk(12, 52), shoots: []))] {
                for (tn, t) in Self.types {
                    let size = ideal(LockRectangularView(frame: f), width: w, type: t)
                    #expect(size.height <= h, Comment(rawValue: "прямоугольный \(w) «\(name)» \(tn): \(size.height) > \(h)"))
                    let c = ideal(LockCircularView(frame: f), width: h, type: t)
                    #expect(c.height <= h, Comment(rawValue: "круглый \(h) «\(name)» \(tn): \(c.height) > \(h)"))
                }
            }
        }
    }

    @Test func theLockScreenSaysOnlyGenrePointTimeAndPlace() {
        // Текст экрана блокировки сверяется целиком (ревью GPT к 6b15258): имён клиентов нет ни в одной строке, а если вид
        // заведёт новую строку, этот тест покраснеет.
        let rect = LockRectangularView(frame: now).lines
        #expect(rect == ["12:00–13:54", "Свадьба", "Студия «Томсон»"], Comment(rawValue: "\(rect)"))
        #expect(!rect.joined().contains("Анна") && !rect.joined().contains("Игорь"))
        #expect(LockCircularView(frame: now).label == "4:10", Comment(rawValue: "\(String(describing: LockCircularView(frame: now).label))"))
        #expect(LockCircularView(frame: frame(at: tsk(18, 30))).label == nil, "после золотого часа круг без цифр")
        #expect(LockRectangularView(frame: frame(at: tsk(12, 52), shoots: [])).lines == ["—"])
    }

    @Test func captionsFollowTheGenre() {
        let portrait = WidgetFeed.Shoot(id: "p", start: ms(tsk(12)), end: ms(tsk(15)), title: "Портрет", place: "Парк",
                                        stops: [.init(at: ms(tsk(12)), name: "Парк")])
        #expect(WidgetSketchWords.toShoot("Свадьба") == "до конца свадьбы" && WidgetSketchWords.shoot("Свадьба") == "свадьба")
        #expect(WidgetSketchWords.toShoot("Портрет") == "до конца съёмки" && WidgetSketchWords.shoot("Портрет") == "съёмка")
        #expect(WidgetSketchWords.toShoot(DayPlan(frame(at: tsk(13), shoots: [portrait]))!.shoot.title) == "до конца съёмки")
    }

    // MARK: Двоеточие по середине цифр

    /// Рисует `v` чёрным по белому в 4-кратном масштабе и возвращает, на сколько pt середина двоеточия ниже середины цифр (минус — выше).
    /// Столбцы краски делятся на цифры (высота ≥ 0,8 от самой высокой) и двоеточия (остальные: две точки, низкие).
    private func colonDrop<V: View>(_ v: V) -> (drop: CGFloat, digits: Int, colons: Int)? {
        let r = ImageRenderer(content: v.foregroundStyle(.black).padding(6).background(Color.white))
        r.scale = 4
        guard let cg = r.uiImage?.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 255, count: w * h)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        func ink(_ x: Int, _ y: Int) -> Bool { px[y * w + x] < 128 }
        var runs: [(top: CGFloat, bottom: CGFloat)] = []
        var x = 0
        while x < w {
            if (0..<h).contains(where: { ink(x, $0) }) {
                var top = h, bottom = 0
                while x < w, (0..<h).contains(where: { ink(x, $0) }) {
                    for y in 0..<h where ink(x, y) { top = min(top, y); bottom = max(bottom, y) }
                    x += 1
                }
                runs.append((CGFloat(top), CGFloat(bottom)))
            } else { x += 1 }
        }
        let tallest = runs.map { $0.bottom - $0.top }.max() ?? 0
        let digits = runs.filter { $0.bottom - $0.top >= tallest * 0.8 }
        let colons = runs.filter { $0.bottom - $0.top < tallest * 0.8 }
        guard !digits.isEmpty, !colons.isEmpty else { return (0, digits.count, colons.count) }
        let mid = (digits.map(\.top).min()! + digits.map(\.bottom).max()!) / 2
        let colonMid = (colons.map(\.top).min()! + colons.map(\.bottom).max()!) / 2
        return ((colonMid - mid) / 4, digits.count, colons.count)
    }

    @Test func theColonSitsInTheMiddleOfTheDigits() throws {
        var report: [String] = []
        for size in [21.0, 28.0, 34.0] {
            let lifted = try #require(colonDrop(ColonCount(seconds: (4 * 60 + 10) * 60, size: size)))
            #expect(lifted.digits == 3 && lifted.colons == 1, "в «4:10» три цифры и одно двоеточие: \(lifted)")
            // «Было» — как стояло в студийном таймере до 25.10: двоеточие отдельным видом.
            let f = Font.system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
            let flat = try #require(colonDrop(HStack(spacing: 0) { Text("4"); Text(":"); Text("10") }.font(f)))
            report.append(String(format: "кегль %.0f: двоеточие ниже середины цифр — отдельным видом %+.2f pt, одной строкой (`ColonCount`) %+.2f pt",
                                 size, flat.drop, lifted.drop))
            #expect(abs(lifted.drop) <= 0.35, Comment(rawValue: report.last!))
            // Проверка не пустая: отдельным видом двоеточие заметно ниже.
            #expect(flat.drop >= 1.0, "отдельным видом двоеточие ниже середины на \(flat.drop) pt — иначе проверка ничего не доказывает")
        }
        print(report.joined(separator: "\n"))
    }

    /// Не утверждение, а замер для отчёта: где стоит двоеточие в системном `Text(timerInterval:)` (его рисует система, подъём не применить).
    @Test func measuresTheSystemTimerColonForTheRecord() {
        let a = Date(timeIntervalSinceReferenceDate: 800_000_000)
        for size in [21.0, 34.0] {
            let timer = Text(timerInterval: a...a.addingTimeInterval(4 * 3600 + 10 * 60), countsDown: true, showsHours: true)
                .font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
            let m = colonDrop(timer)
            print("системный отсчёт, кегль \(size): \(m.map { String(format: "двоеточие ниже середины цифр на %+.2f pt (цифр %d, двоеточий %d)", $0.drop, $0.digits, $0.colons) } ?? "не отрисован")")
        }
    }

    // MARK: Картинки для Алексея

    private let darkPlate = Color(red: 0.059, green: 0.055, blue: 0.047)
    private let lightPlate = Color(red: 0.98, green: 0.973, blue: 0.953)

    private func plate<V: View>(_ v: V, _ w: CGFloat, _ h: CGFloat, dark: Bool) -> some View {
        v.frame(width: w, height: h)
            .background(dark ? darkPlate : lightPlate)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, dark ? .dark : .light)
    }

    /// Плашка экрана блокировки: на тёмных и светлых обоях, а не на подложке виджета.
    private func lockPlate<V: View>(_ v: V, _ w: CGFloat, _ h: CGFloat, dark: Bool) -> some View {
        v.frame(width: w, height: h)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)))
            .padding(16)
            .background(LinearGradient(colors: dark ? [Color(red: 0.12, green: 0.16, blue: 0.24), Color(red: 0.05, green: 0.06, blue: 0.1)]
                                                    : [Color(red: 0.93, green: 0.86, blue: 0.74), Color(red: 0.85, green: 0.9, blue: 0.95)],
                                       startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, dark ? .dark : .light)
    }

    private func cell(_ caption: String, _ w: CGFloat, _ content: some View) -> some View {
        VStack(spacing: 6) {
            content
            Text(caption).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).multilineTextAlignment(.center).frame(width: w)
        }
    }

    private func sheet(_ rows: [[AnyView]], scale: CGFloat) -> UIImage? {
        let grid = VStack(spacing: 18) {
            ForEach(rows.indices, id: \.self) { r in HStack(alignment: .top, spacing: 18) { ForEach(rows[r].indices, id: \.self) { rows[r][$0] } } }
        }
        .padding(18).background(Color(red: 0.36, green: 0.35, blue: 0.33))
        let r = ImageRenderer(content: grid)
        r.scale = scale
        return r.uiImage
    }

    private func write(_ image: UIImage?, _ dir: String, _ name: String) throws {
        let png = try #require(image?.pngData(), "картинка \(name) не отрисована")
        try png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        #expect(png.count <= 300 * 1024, "\(name).png: \(png.count / 1024) КБ, предел 300")
    }

    /// Картинки для выбора «простой / кольцо»: в `$LP_SKETCH_DIR` или `/tmp/lp-sketch-out`, если папка есть (обычный прогон ничего не пишет).
    @Test func writesTheSketchSheetsWhenAsked() throws {
        let dir = ProcessInfo.processInfo.environment["LP_SKETCH_DIR"] ?? "/tmp/lp-sketch-out"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let f = now, n = names
        func looks(_ look: WidgetLook) -> String { look == .plain ? "простой" : "кольцо" }

        let medium: [[AnyView]] = [WidgetLook.plain, .ring].map { look in
            [true, false].map { dark in
                AnyView(cell("средний · \(looks(look)) · \(dark ? "тёмная" : "светлая")", 364,
                             plate(MediumLiveView(frame: f, look: look, names: n, alpha: true), 364, 170, dark: dark)))
            }
        }
        try write(sheet(medium, scale: 2), dir, "medium")

        let small: [[AnyView]] = [[WidgetLook.plain, .ring].flatMap { look in
            [true, false].map { dark in
                AnyView(cell("малый · \(looks(look)) · \(dark ? "тёмная" : "светлая")", 170,
                             plate(SmallLiveView(frame: f, look: look, names: n, alpha: true), 170, 170, dark: dark)))
            }
        }]
        try write(sheet(small, scale: 2.5), dir, "small")

        let free = frame(at: tsk(12, 52), shoots: [])
        let large: [[AnyView]] = [
            [true, false].map { dark in AnyView(cell("большой · день со съёмкой · \(dark ? "тёмная" : "светлая")", 364, plate(LargeView(frame: f, names: n, alpha: true), 364, 382, dark: dark))) },
            [true, false].map { dark in AnyView(cell("большой · день без съёмок · \(dark ? "тёмная" : "светлая")", 364, plate(LargeView(frame: free, alpha: true), 364, 382, dark: dark))) },
        ]
        try write(sheet(large, scale: 1.8), dir, "large")

        let lock: [[AnyView]] = [
            [true, false].map { dark in AnyView(cell("блокировка · круглый · \(dark ? "тёмные обои" : "светлые обои")", 108, lockPlate(LockCircularView(frame: f), 76, 76, dark: dark))) }
            + [true, false].map { dark in AnyView(cell("блокировка · прямоугольный · \(dark ? "тёмные обои" : "светлые обои")", 204, lockPlate(LockRectangularView(frame: f), 172, 76, dark: dark))) },
        ]
        try write(sheet(lock, scale: 3), dir, "lock")

        // Тот же средний «кольцо» в 13:00: остаток точки — «54 мин», как в словах Алексея.
        let at13 = frame(at: tsk(13))
        let at13Row: [[AnyView]] = [[true, false].map { dark in
            AnyView(cell("средний · кольцо · 13:00 (остаток точки 54 мин) · \(dark ? "тёмная" : "светлая")", 364,
                         plate(MediumLiveView(frame: at13, look: .ring, names: n, alpha: true), 364, 170, dark: dark)))
        }]
        try write(sheet(at13Row, scale: 2), dir, "medium_ring_1300")
    }
}
#endif
