import ActivityKit
import LightPlanCore
import LightPlanDomain
import SwiftUI
import WidgetKit

@main
struct SpikeBundle: WidgetBundle {
    var body: some Widget {
        DayWidget()
        GoldenLive()
    }
}

struct DayEntry: TimelineEntry {
    let date: Date
    let fromApp: String
    let golden: (start: Date, end: Date)?
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { DayEntry(date: Date(), fromApp: "…", golden: nil) }
    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) { completion(entry(for: Date(), why: "snapshot")) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        // One entry per day for three days: the widget computes light itself, the app only gives the place.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let entries = [entry(for: Date(), why: "timeline")] + (1...2).map {
            entry(for: cal.date(byAdding: .day, value: $0, to: today)!, why: "timeline+\($0)")
        }
        completion(Timeline(entries: entries, policy: .after(cal.date(byAdding: .day, value: 1, to: today)!)))
    }

    func entry(for day: Date, why: String) -> DayEntry {
        var fromApp = "no feed"
        if let url = Spike.container?.appendingPathComponent("feed.json"),
           let data = try? Data(contentsOf: url),
           let feed = try? JSONDecoder().decode(Feed.self, from: data) {
            fromApp = "\(feed.place) \(feed.wrote.formatted(date: .omitted, time: .shortened))"
        }
        let t0 = DispatchTime.now().uptimeNanoseconds
        let g = Spike.golden(on: day)
        let us = (DispatchTime.now().uptimeNanoseconds - t0) / 1000
        Spike.log("\(why) read=\(fromApp) golden=\(g.map { "\($0.start)…\($0.end)" } ?? "nil") solarDay=\(us)µs domain=\(String(describing: Debts.self))")
        return DayEntry(date: day, fromApp: fromApp, golden: g)
    }
}

struct DayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpikeDay", provider: DayProvider()) { e in
            VStack(alignment: .leading, spacing: 4) {
                Text(e.fromApp).font(.caption2)
                if let g = e.golden {
                    Text("☀︎ \(g.start.formatted(date: .omitted, time: .shortened))")
                    if g.start > Date() {
                        Text(timerInterval: Date()...g.start, countsDown: true).monospacedDigit()
                    }
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Spike day")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct GoldenLive: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GoldenAttributes.self) { ctx in
            HStack {
                Text("\(ctx.attributes.place) · \(ctx.isStale ? "идёт, до конца" : "до начала")")
                Spacer()
                Countdown(state: ctx.state, stale: ctx.isStale)
            }
            .padding()
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("☀︎") }
                DynamicIslandExpandedRegion(.trailing) { Countdown(state: ctx.state, stale: ctx.isStale) }
                DynamicIslandExpandedRegion(.bottom) { Text(ctx.state.title) }
            } compactLeading: {
                Text(ctx.isStale ? "☀︎ идёт" : "☀︎")
            } compactTrailing: {
                Countdown(state: ctx.state, stale: ctx.isStale).frame(maxWidth: 44)
            } minimal: {
                Text("☀︎")
            }
        }
    }
}

/// Before golden hour: time to its start; once the system marks the content stale (staleDate = start), time to its end.
struct Countdown: View {
    let state: GoldenAttributes.ContentState
    let stale: Bool
    var body: some View {
        Text(timerInterval: Date()...(stale ? state.end : state.until), countsDown: true).monospacedDigit()
    }
}
