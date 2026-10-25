import WidgetKit
import SwiftUI
import LightPlanCore
import LightPlanDomain

// Виджет дня (30б.2, `docs/30b_widget_cut.md`). Свет расширение считает само (`SolarDay`, `.iau`), поэтому лента идёт и при
// закрытом приложении; съёмки, место и слова берёт из `widget.json` общей папки (пишет приложение, `WidgetShare`).
// Что показать в данный момент — решает `WidgetFeed.frame(at:)` (Domain, под тестами); здесь только лента и вид.

struct DayEntry: TimelineEntry {
    let date: Date
    let frame: WidgetFrame
    /// Слот или ветка носит латунную «α», основной «Light Plan» — чистый (`WidgetFeed.isMainApp`).
    let alpha: Bool
}

struct DayProvider: TimelineProvider {
    private static var bundleID: String { Bundle.main.bundleIdentifier ?? "" }

    private static func feed() -> WidgetFeed? {
        let group = WidgetFeed.groupID(bundleID: bundleID)
        guard let dir = FileManager.default.containerURLForGroup(group),
              let data = try? Data(contentsOf: dir.appendingPathComponent(WidgetFeed.fileName))
        else { return nil }
        return WidgetFeed.decode(data)
    }

    private static func entry(_ feed: WidgetFeed?, at date: Date) -> DayEntry {
        let alpha = !WidgetFeed.isMainApp(bundleID: bundleID)
        guard let feed else {
            // Приложение ещё не оставило файл: пустая плашка, а не падение.
            let empty = WidgetFeed(place: .init(name: "", latitude: 0, longitude: 0, zone: "none")).frame(at: date)
            return DayEntry(date: date, frame: empty, alpha: alpha)
        }
        return DayEntry(date: date, frame: feed.frame(at: date), alpha: alpha)
    }

    func placeholder(in context: Context) -> DayEntry { Self.entry(nil, at: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(Self.entry(Self.feed(), at: Date()))
    }

    /// Сейчас и каждый момент, когда плашка меняется сама (`WidgetFeed.changes`) — на 36 часов вперёд; дальше новая лента.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let now = Date()
        let feed = Self.feed()
        let dates = feed?.changes(from: now) ?? [now]
        let policy: TimelineReloadPolicy = .after(now.addingTimeInterval(36 * 3600))
        completion(Timeline(entries: dates.map { Self.entry(feed, at: $0) }, policy: policy))
    }
}

private extension FileManager {
    func containerURLForGroup(_ id: String) -> URL? { containerURL(forSecurityApplicationGroupIdentifier: id) }
}

struct DayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumView(frame: entry.frame, alpha: entry.alpha).widgetURL(entry.frame.url)
        case .accessoryInline:
            LockInlineView(frame: entry.frame, alpha: entry.alpha).widgetURL(entry.frame.url)
        default:
            SmallView(frame: entry.frame, alpha: entry.alpha).widgetURL(entry.frame.url)
        }
    }
}

struct LightPlanWidget: Widget {
    /// Имя в галерее — имя приложения на главном экране: «Light Plan» у основного, «LP <ветка>» у слота.
    private static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Light Plan"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LightPlanWidget", provider: DayProvider()) { entry in
            DayWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName(Self.name)
        .description("Рассвет и закат, ближайшая съёмка, студийный час")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline])
    }
}
