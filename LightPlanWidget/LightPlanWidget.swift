import WidgetKit
import SwiftUI
import LightPlanCore
import LightPlanDomain

// Виджет дня (30б.2, `docs/30b_widget_cut.md`). Свет расширение считает само (`SolarDay`, `.iau`), поэтому лента идёт и при
// закрытом приложении; съёмки, место и слова берёт из `widget.json` общей папки (пишет приложение, `WidgetShare`).
// Что показать в данный момент — решает `WidgetFeed.frame(at:)` (Domain, под тестами), какой вид на какой форме — `WidgetRoot`;
// здесь только лента и сборка. Лента зависит от формы (`WidgetFeed.timeline(shape:)`): кольцу нужна запись на каждую минуту.

struct DayEntry: TimelineEntry {
    let date: Date
    let frame: WidgetFrame
    /// Слот или ветка носит латунную «α», основной «Light Plan» — чистый (`WidgetFeed.isMainApp`).
    let alpha: Bool
    static func shape(_ family: WidgetFamily) -> WidgetShape {
        switch family {
        case .systemMedium: return .medium
        case .systemLarge: return .large
        case .accessoryCircular: return .circular
        case .accessoryRectangular: return .rectangular
        case .accessoryInline: return .inline
        default: return .small
        }
    }
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

    /// Сейчас и каждый момент, когда плашка меняется сама (`WidgetFeed.timeline`) — на 36 часов вперёд, а кольцу и кругу блокировки ещё
    /// и каждую минуту; новая лента — через 36 часов или на последнем моменте, если лента обрезана (`WidgetFeed.entryLimit` записей).
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let now = Date()
        let feed = Self.feed()
        let line = feed?.timeline(from: now, shape: DayEntry.shape(context.family))
            ?? .init(dates: [now], reload: now.addingTimeInterval(36 * 3600))
        completion(Timeline(entries: line.dates.map { Self.entry(feed, at: $0) }, policy: .after(line.reload)))
    }
}

private extension FileManager {
    func containerURLForGroup(_ id: String) -> URL? { containerURL(forSecurityApplicationGroupIdentifier: id) }
}

struct DayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    var body: some View {
        let shape = DayEntry.shape(family)
        WidgetRoot(frame: entry.frame, shape: shape, alpha: entry.alpha)
            .widgetURL(entry.frame.url)
            // Подложка нужна «Домой»; на экране блокировки система красит содержимое сама, своей плашки там не бывает.
            // Малый и средний, пока съёмка идёт, — палитра Braun (30б.2в-4); прочие виды и состояния — прежняя.
            .containerBackground(for: .widget) {
                switch shape {
                case .circular, .rectangular, .inline: Color.clear
                case .small, .medium where entry.frame.kind == .live: BraunPalette.container
                default: Color("WidgetBackground")
                }
            }
    }
}

struct LightPlanWidget: Widget {
    /// Имя в галерее — имя приложения на главном экране: «Light Plan» у основного, «LP <ветка>» у слота.
    private static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Light Plan"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LightPlanWidget", provider: DayProvider()) { entry in
            DayWidgetView(entry: entry)
        }
        .configurationDisplayName(Self.name)
        .description("Рассвет и закат, ближайшая съёмка, студийный час")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()   // кольцу деления лежат в полях плашки; прочим видам поля ставит `WidgetRoot`
    }
}
