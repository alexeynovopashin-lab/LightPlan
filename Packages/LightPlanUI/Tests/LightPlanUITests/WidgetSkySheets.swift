import Testing
import SwiftUI
import Foundation
import LightPlanDomain
import LightPlanCore
@testable import LightPlanUI
#if os(iOS)
import UIKit

/// Слово неба в среднем виджете без съёмок (DECISIONS 30.10): листы для глаз, пять языков × четыре момента, обе темы, 364 × 170 и 338 × 158.
/// Слова — те, что приложение кладёт в файл виджета (`AppModel.widgetWords` из словаря), поэтому этот же файл собирается и на старом коде:
/// так сняты «до» и «после». Пишет только в заведённую папку `$LP_SKY_SHOTS` (или `/tmp/lp-sky-shots`), обычный прогон ничего не пишет.
@MainActor
struct WidgetSkySheets {
    static let langs = ["ru", "en", "es", "ja", "zh"]
    /// Час по Томску и категория неба: рассвет в тумане, закат в тумане, яркий закат, вечер — завтрашний рассвет серый.
    static let moments: [(h: Int, q: DayQuality, label: String)] = [(5, .fog, "05:00 туман"), (14, .fog, "14:00 туман"), (14, .excellent, "14:00 яркий"), (21, .poor, "21:00 серый")]

    static let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    static func tsk(_ h: Int, day d: Int = 25) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))!.addingTimeInterval(-7 * 3600)
    }

    /// Балл, у которого категория — `q` (у тумана балл есть, слово даёт категория дня).
    static func score(_ q: DayQuality) -> Int {
        switch q { case .excellent: 85; case .good: 62; case .plain: 40; case .poor: 15; case .fog: 45 }
    }

    static func frame(lang: String, hour: Int, quality q: DayQuality, shoots: [WidgetFeed.Shoot] = []) -> WidgetFrame {
        let r = { (day: String) in WidgetFeed.Rating(day: day, score: score(q), quality: q, sunrise: score(q)) }
        let words = AppModel.widgetWords(Lexicon(lang))
        return WidgetFeed(place: tomsk, shoots: shoots, words: words, forecast: [r("2026-10-25"), r("2026-10-26")], lang: lang).frame(at: tsk(hour))
    }

    @Test func writesTheSkySheetsWhenAsked() throws {
        let dir = ProcessInfo.processInfo.environment["LP_SKY_SHOTS"] ?? "/tmp/lp-sky-shots"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        for (tag, size) in [("364", CGSize(width: 364, height: 170)), ("338", CGSize(width: 338, height: 158))] {
            for dark in [true, false] {
                let grid = VStack(alignment: .leading, spacing: 12) {
                    ForEach(Self.langs, id: \.self) { lang in
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Self.moments.indices, id: \.self) { i in
                                let m = Self.moments[i]
                                VStack(spacing: 4) {
                                    BraunIdleView(frame: Self.frame(lang: lang, hour: m.h, quality: m.q))
                                        .frame(width: size.width, height: size.height)
                                        .background(BraunPalette(dark: dark).bg)
                                        .clipShape(RoundedRectangle(cornerRadius: BraunPlate.cornerRadius(plateHeight: size.height), style: .continuous))
                                        .environment(\.colorScheme, dark ? .dark : .light)
                                        .environment(\.widgetFrozenTimer, true)
                                        .environment(\.widgetFlatGlass, true)
                                    Text("\(lang) · \(m.label)").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white)
                                }
                            }
                        }
                    }
                }
                .padding(12).background(Color(red: 0.36, green: 0.35, blue: 0.33))
                let r = ImageRenderer(content: grid)
                r.scale = 2
                let png = try #require(r.uiImage?.pngData())
                try png.write(to: URL(fileURLWithPath: "\(dir)/sky_\(tag)_\(dark ? "dark" : "light").png"))
            }
        }
    }
}
#endif
