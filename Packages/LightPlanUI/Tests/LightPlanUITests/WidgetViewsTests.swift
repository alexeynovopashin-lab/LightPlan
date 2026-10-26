import Testing
import SwiftUI
import Foundation
import LightPlanDomain
import LightPlanCore
#if os(iOS)
import UIKit

/// Шаги 30б.2 и 30б.2в: виды виджета (`LightPlanWidget/Views/`, подключены к этому набору ссылкой `WidgetViews`) отрисованы по числам:
/// плашка «Домой» целиком, как её собирает расширение (`WidgetRoot`), помещается в 158 × 158 (самый тесный iPhone 14) и 170 × 170
/// (17 Pro Max), средняя 338 × 158 / 364 × 170, в трёх размерах шрифта (обычный, крупный, огромный). Состояния — все: свет, съёмка
/// впереди, идёт (кольцо) — поля у видов без кольца ставит корень, у кольца они несут деления.
@MainActor
struct WidgetViewsTests {

    private let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    private func tsk(_ h: Int, _ m: Int = 0, day d: Int = 24) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }
    private func ms(_ d: Date) -> Int64 { Moment(d).milliseconds }

    private func shoot(_ id: String, _ from: Date, _ to: Date, title: String = "Свадьба", place: String = "Набережная, Томск",
                       sunset: Bool = false, rents: [WidgetFeed.Rent] = [], stops: [WidgetFeed.Stop] = []) -> WidgetFeed.Shoot {
        .init(id: id, start: ms(from), end: ms(to), title: title, place: place, wantsSunset: sunset, rents: rents, stops: stops)
    }

    private func feed(_ shoots: [WidgetFeed.Shoot], words: WidgetFeed.Words = .init()) -> WidgetFeed {
        WidgetFeed(place: tomsk, shoots: shoots, words: words)
    }

    private var studio: WidgetFeed.Shoot {
        shoot("live", tsk(14), tsk(19), title: "Портретная съёмка", place: "Томсон, зал Эдисон", sunset: true,
              rents: [.init(from: ms(tsk(14)), to: ms(tsk(16)), deadline: ms(tsk(15, 55)), studio: "Томсон")],
              stops: [.init(at: ms(tsk(14)), name: "Студия", place: "Томсон, зал Эдисон"),
                      .init(at: ms(tsk(16, 30)), name: "Прогулка по набережной", place: "Набережная реки Ушайки"),
                      .init(at: ms(tsk(18)), name: "Банкет"), .init(at: ms(tsk(19)), name: "Возвращение домой")])
    }

    /// Все состояния плашки: (подпись, кадр).
    private func cases() -> [(String, WidgetFrame)] {
        let free = feed([])
        let near = feed([shoot("a", tsk(15), tsk(18), sunset: true), shoot("b", tsk(10, day: 25), tsk(12, day: 25), title: "Семейная съёмка")])
        let far = feed([shoot("c", tsk(15, day: 27), tsk(17, day: 27), title: "Love story")])
        let tromso = WidgetFeed(place: .init(name: "Tromsø", latitude: 69.6496, longitude: 18.956, zone: "Europe/Oslo"))
        var polar = tromso.frame(at: tsk(12).addingTimeInterval(60 * 86400 * 0))
        polar = WidgetFeed(place: tromso.place).frame(at: Date(timeIntervalSince1970: 1_782_043_200))   // 21.06.2026
        return [
            ("свет: рассвет", free.frame(at: tsk(4))),
            ("свет: закат", free.frame(at: tsk(12))),
            ("свет: завтрашний рассвет", free.frame(at: tsk(20))),
            ("свет: полярный день", polar),
            ("свет + съёмка дальше", far.frame(at: tsk(12))),
            ("съёмка с золотым часом", near.frame(at: tsk(9))),
            ("съёмка завтра", near.frame(at: tsk(20))),
            ("идёт, студийный час", feed([studio]).frame(at: tsk(14, 30))),
            ("идёт, конец съёмки", feed([studio]).frame(at: tsk(17))),
            ("пусто", WidgetFeed(place: .init(name: "", latitude: 0, longitude: 0, zone: "none")).frame(at: tsk(12))),
        ]
    }

    private func ideal<V: View>(_ v: V, width: CGFloat, type: DynamicTypeSize) -> CGSize {
        let host = UIHostingController(rootView: v.environment(\.dynamicTypeSize, type).frame(width: width).fixedSize(horizontal: false, vertical: true))
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private static let types: [(String, DynamicTypeSize)] = [("обычный", .large), ("крупный", .xxLarge), ("огромный", .accessibility3)]

    @Test func smallFitsEveryStateInThreeTextSizes() {
        var report: [String] = []
        for (w, h) in [(158.0, 158.0), (170.0, 170.0)] {
            for (name, frame) in cases() where frame.kind != .live {   // идущую съёмку рисуют виды на заданных pt (`WidgetBraunViewTests`)
                for (tn, t) in Self.types {
                    for alpha in [false, true] {
                        let size = ideal(WidgetRoot(frame: frame, shape: .small, alpha: alpha), width: w, type: t)
                        report.append(String(format: "малый %.0f «%@» %@ α=%d: высота %.1f из %.0f", w, name, tn, alpha ? 1 : 0, size.height, h))
                        let why = "малый \(w) «\(name)» \(tn): \(size.height) > \(h)"
                        #expect(size.height <= h, Comment(rawValue: why))
                    }
                }
            }
        }
        print(report.joined(separator: "\n"))
    }

    @Test func mediumFitsEveryStateInThreeTextSizes() {
        var report: [String] = []
        for (w, h) in [(338.0, 158.0), (364.0, 170.0)] {
            for (name, frame) in cases() where frame.kind != .live {
                for (tn, t) in Self.types {
                    let size = ideal(WidgetRoot(frame: frame, shape: .medium, alpha: true), width: w, type: t)
                    report.append(String(format: "средний %.0f «%@» %@: высота %.1f из %.0f", w, name, tn, size.height, h))
                    let why = "средний \(w) «\(name)» \(tn): \(size.height) > \(h)"
                    #expect(size.height <= h, Comment(rawValue: why))
                }
            }
        }
        print(report.joined(separator: "\n"))
    }

    @Test func theAlphaBadgeIsABrassCircle() {
        let size = ideal(AlphaBadge(), width: 100, type: .large)
        #expect(size.width == 100 || size.height == 16, "бирка 16 pt: \(size)")
    }

    @Test func lockLineTellsLightAndShootInShortWords() {
        let line = { (f: WidgetFrame, alpha: Bool) in LockInlineView(frame: f, alpha: alpha).line }
        let near = feed([shoot("a", tsk(15), tsk(18), sunset: true)]).frame(at: tsk(9))
        #expect(line(near, false).hasPrefix("☀︎ ") && line(near, false).hasSuffix("· съёмка 15:00"), Comment(rawValue: line(near, false)))
        #expect(line(near, false).contains("·") && !line(near, false).contains("Свадьба"))
        #expect(line(near, true).hasSuffix(" α") && !line(near, false).hasSuffix("α"))
        let free = feed([]).frame(at: tsk(12))
        #expect(line(free, false).hasPrefix("☀︎ Закат 17:5"), Comment(rawValue: line(free, false)))
        #expect(line(near, false).count <= 24, "помещается под часами: \(line(near, false).count) знаков")
    }

    /// Картинки для глаз: в `$LP_WIDGET_SHOTS` или `/tmp/lp-widget-shots`, если папка есть (файлы — не доказательство, доказательство — числа выше).
    @Test func writesPicturesWhenAsked() throws {
        let dir = ProcessInfo.processInfo.environment["LP_WIDGET_SHOTS"] ?? "/tmp/lp-widget-shots"
        // Только если папка заведена заранее: обычный прогон ничего не пишет.
        guard FileManager.default.fileExists(atPath: dir) else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (i, (name, frame)) in cases().enumerated() {
            for scheme in [ColorScheme.dark, .light] {
                let bg = scheme == .dark ? Color(red: 0.059, green: 0.055, blue: 0.047) : Color(red: 0.98, green: 0.973, blue: 0.953)
                let small = WidgetRoot(frame: frame, shape: .small, alpha: i % 2 == 1).frame(width: 170, height: 170).background(bg).environment(\.colorScheme, scheme)
                let medium = WidgetRoot(frame: frame, shape: .medium, alpha: i % 2 == 1).frame(width: 364, height: 170).background(bg).environment(\.colorScheme, scheme)
                for (tag, v) in [("s", AnyView(small)), ("m", AnyView(medium))] {
                    let r = ImageRenderer(content: v)
                    r.scale = 2
                    if let png = r.uiImage?.pngData() { try png.write(to: URL(fileURLWithPath: "\(dir)/\(i)\(tag)-\(scheme == .dark ? "d" : "l")-\(name.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ":", with: "")).png")) }
                }
            }
        }
    }
}
#endif
