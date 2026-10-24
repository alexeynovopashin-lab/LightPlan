import WidgetKit
import SwiftUI
import LightPlanCore
import LightPlanDomain

// Заглушка 30б.1 (`docs/30b_widget_cut.md`): «☀︎ <начало золотого часа сегодня>» на месте «Света». Место — из
// `widget.json` общей папки (пишет приложение, `WidgetShare`), свет расширение считает само (`SolarDay`, `.iau`),
// поэтому лента дней идёт и при закрытом приложении. Что виджет покажет на деле — 30б.2.

struct GoldenEntry: TimelineEntry {
    let date: Date
    /// `nil` — приложение ещё не оставило место (не открывали после установки).
    let name: String?
    /// `nil` — места нет или в этот день солнце не опускается через 6° (полярные день и ночь).
    let start: Date?
    let zone: TimeZone?
}

struct GoldenProvider: TimelineProvider {
    private static func feed() -> WidgetFeed? {
        let group = WidgetFeed.groupID(bundleID: Bundle.main.bundleIdentifier ?? "")
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let data = try? Data(contentsOf: dir.appendingPathComponent(WidgetFeed.fileName))
        else { return nil }
        return WidgetFeed.decode(data)
    }

    private static func entry(at date: Date, spot: WidgetFeed.Spot?) -> GoldenEntry {
        let day = spot?.today(at: date)
        return GoldenEntry(date: date, name: spot?.name, start: day.flatMap { spot?.goldenStart(on: $0) }, zone: spot?.timeZone)
    }

    func placeholder(in context: Context) -> GoldenEntry {
        GoldenEntry(date: Date(), name: nil, start: nil, zone: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (GoldenEntry) -> Void) {
        completion(Self.entry(at: Date(), spot: Self.feed()?.place))
    }

    /// Сейчас и две следующие полуночи по часам места: три дня без приложения, дальше — новая лента.
    func getTimeline(in context: Context, completion: @escaping (Timeline<GoldenEntry>) -> Void) {
        let now = Date()
        let spot = Self.feed()?.place
        var dates = [now]
        if let tz = spot?.timeZone {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            var midnight = cal.startOfDay(for: now)
            for _ in 0..<2 {
                midnight = cal.date(byAdding: .day, value: 1, to: midnight)!
                dates.append(midnight)
            }
        }
        completion(Timeline(entries: dates.map { Self.entry(at: $0, spot: spot) }, policy: .atEnd))
    }
}

struct GoldenView: View {
    let entry: GoldenEntry

    private var time: String {
        guard let start = entry.start else { return "—" }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = entry.zone ?? .current
        return start.formatted(style)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("☀︎ \(time)")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let name = entry.name {
                Text(name)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct LightPlanWidget: Widget {
    /// Имя в галерее — имя приложения на главном экране: «Light Plan» у основного, «LP <ветка>» у слота.
    private static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Light Plan"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LightPlanWidget", provider: GoldenProvider()) { entry in
            GoldenView(entry: entry)
        }
        .configurationDisplayName(Self.name)
        // Подпись заглушки; переводы — вместе с настоящим виджетом (30б.2).
        .description("Начало золотого часа сегодня")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    LightPlanWidget()
} timeline: {
    GoldenEntry(date: .now, name: "Томск", start: .now, zone: TimeZone(identifier: "Asia/Tomsk"))
    GoldenEntry(date: .now, name: nil, start: nil, zone: nil)
}
