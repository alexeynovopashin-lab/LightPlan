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
        #expect(ActivityLane.xs(count: 2, width: 300) == [13, 287])
        let five = ActivityLane.xs(count: 5, width: 300)
        #expect(five.first == 13 && five.last == 287 && abs(five[2] - 150) < 0.001)
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
