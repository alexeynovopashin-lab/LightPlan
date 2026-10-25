import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

/// Launch arguments drive the probe (probe.sh): `-LA start|bgstart|bgupdate|end`.
@main
struct SpikeApp: App {
    @UIApplicationDelegateAdaptor(ProbeDelegate.self) private var delegate
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        // Run once the scene is up: beginBackgroundTask from App.init was silently dropped (bgstart, 24.10).
        WindowGroup { ProbeView().task { Probe.run() } }
            .onChange(of: phase) { _, now in
                // Opening the app moves the highlighted point to the current one (decision 25.10).
                if now == .active { Task { await ProbeActivity.refresh() } }
            }
    }
}

@MainActor
enum Probe {
    static func run() {
        Spike.log("launch container=\(Spike.container?.path ?? "nil") group=\(Spike.group)")
        let g = Spike.golden(on: Date())
        let feed = Feed(wrote: Date(), place: "Томск", goldenStart: g?.start)
        if let url = Spike.container?.appendingPathComponent("feed.json"),
           let data = try? JSONEncoder().encode(feed) {
            do { try data.write(to: url); Spike.log("wrote feed.json \(data.count) B goldenStart=\(g.map { "\($0.start)" } ?? "nil")") }
            catch { Spike.log("feed write failed \(error)") }
        }
        WidgetCenter.shared.reloadAllTimelines()
        Spike.log("liveActivities enabled=\(ActivityAuthorizationInfo().areActivitiesEnabled)")

        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LA"), i + 1 < args.count else { return }
        switch args[i + 1] {
        case "start": start(minutes: 3)
        case "phase": start(minutes: 20.0 / 60, endMinutes: 80.0 / 60, tag: "phase")
        case "update": Task { await update(title: "updated") }
        case "end": Task { await endAll(); await ProbeActivity.endAll() }
        case "probe": Task { await ProbeControl.start(notifyMinutes: 1) }
        case "probe-notice": Task { await ProbeControl.start(notifyMinutes: 1); await ProbeControl.scheduleNotice(seconds: 12) }
        case "plus": Task { await ProbeActivity.plusHour() }
        case "studio": Task { await ProbeActivity.switchToStudio(source: "launch arg") }
        case "bgstart":
            // Ask for a Live Activity 8 s after launch; probe.sh sends the app home at 3 s.
            hold(seconds: 25)
            Spike.log("bgstart armed")
            Task { try? await Task.sleep(for: .seconds(8)); start(minutes: 3, tag: "bg") }
        case "bgupdate":
            // Start in the foreground, then update every 5 s while the app is in the background.
            start(minutes: 3)
            hold(seconds: 30)
            Task {
                for n in 1...6 {
                    try? await Task.sleep(for: .seconds(5))
                    await update(title: "bg \(n) state=\(UIApplication.shared.applicationState.rawValue)")
                }
            }
        default: break
        }
    }

    static func start(minutes: Double, endMinutes: Double? = nil, tag: String = "fg") {
        let until = Date().addingTimeInterval(minutes * 60)
        let end = Date().addingTimeInterval((endMinutes ?? minutes + 60) * 60)
        let state = GoldenAttributes.ContentState(title: "Золотой час", until: until, end: end)
        do {
            let a = try Activity.request(attributes: GoldenAttributes(place: "Томск"),
                                         content: .init(state: state, staleDate: until),
                                         pushType: nil)
            Spike.log("LA \(tag) request ok id=\(a.id) appState=\(UIApplication.shared.applicationState.rawValue)")
        } catch {
            Spike.log("LA \(tag) request FAILED \(error) appState=\(UIApplication.shared.applicationState.rawValue)")
        }
    }

    static func update(title: String) async {
        let all = Activity<GoldenAttributes>.activities
        for a in all {
            var s = a.content.state
            s.title = title
            await a.update(.init(state: s, staleDate: s.until))
        }
        Spike.log("LA update '\(title)' activities=\(all.count) states=\(all.map { "\($0.activityState)" })")
    }

    static func endAll() async {
        for a in Activity<GoldenAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        Spike.log("LA end, left=\(Activity<GoldenAttributes>.activities.count)")
    }

    /// Keeps the process running in the background for a while, as a real app would.
    static func hold(seconds: Double) {
        var id = UIBackgroundTaskIdentifier.invalid
        id = UIApplication.shared.beginBackgroundTask(withName: "spike") {
            Spike.log("bg task expired")
            UIApplication.shared.endBackgroundTask(id)
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            Spike.log("bg hold done, remaining=\(Int(UIApplication.shared.backgroundTimeRemaining))")
            UIApplication.shared.endBackgroundTask(id)
        }
    }
}
