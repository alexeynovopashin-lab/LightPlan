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

    private func height(_ f: ActivityFrame, width: CGFloat, _ style: ActivityStudioStyle = .icons) -> CGFloat {
        let host = UIHostingController(rootView: ActivityLockView(frame: f, studio: style).frame(width: width).fixedSize(horizontal: false, vertical: true))
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
            for style in f.mode == .studio ? [ActivityStudioStyle.full, .icons, .compact] : [.icons] {
                let row = Self.widths.map { String(format: "%.0f→%.1f", $0, height(f, width: $0, style)) }.joined(separator: "  ")
                report.append("ВЫСОТА «\(name)» \(f.mode == .studio ? style.rawValue : "-"): \(row)")
            }
        }
        print(report.joined(separator: "\n"))
    }

    /// Лента и студия в выбранных стилях (`icons`, `compact`) под потолком; `full` — выше, ради него эскизы Алексею.
    @Test func everyShippedStateFitsUnderTheCeiling() {
        for (name, f) in cases() {
            for style in f.mode == .studio ? [ActivityStudioStyle.icons, .compact] : [.icons] {
                for w in Self.widths {
                    let h = height(f, width: w, style)
                    #expect(h <= Self.ceiling, Comment(rawValue: "«\(name)» \(style.rawValue) \(w): \(h) > \(Self.ceiling)"))
                }
            }
        }
    }

    @Test func fullStudioDoesNotFitAndThatIsWhySketchesExist() {
        let f = frame(wedding, rents: rent, mode: .studio, at: tsk(15))
        #expect(height(f, width: 361, .full) > Self.ceiling)
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
        for (i, (name, f)) in cases().enumerated() {
            for style in f.mode == .studio ? [ActivityStudioStyle.full, .icons, .compact] : [.icons] {
                let v = ActivityLockView(frame: f, studio: style).frame(width: 361).background(Color(red: 0.059, green: 0.055, blue: 0.047))
                    .environment(\.colorScheme, .dark).environment(\.activityStill, f.asOfDate)
                let r = ImageRenderer(content: v)
                r.scale = 3
                if let png = r.uiImage?.pngData() {
                    let tag = name.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ",", with: "")
                    try png.write(to: URL(fileURLWithPath: "\(dir)/\(i)-\(tag)-\(style.rawValue).png"))
                }
            }
        }
    }
}
#endif
