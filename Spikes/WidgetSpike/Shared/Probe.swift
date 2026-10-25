import ActivityKit
import AppIntents
import Foundation

// 30б.3а: lock-screen probe. One Live Activity with a wedding timeline and a studio mode;
// the buttons are dummies — the question is what each one does from a locked phone.

struct ProbePoint: Codable, Hashable {
    var name: String
    var at: Date
}

struct ProbeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Mode: String, Codable, Hashable { case wedding, studio }
        var mode: Mode
        var points: [ProbePoint]
        /// Index of the next point as of the last update; the views cannot recompute it by themselves.
        var next: Int
        var rentEnd: Date
        /// «+1 час» presses and the time of the last one: the visible proof the view changed without the app.
        var requests: Int
        var requestedAt: Date?
    }
    var title: String
}

enum ProbeURL {
    /// A dummy number: the system asks before dialling a `tel:` link; nobody is called on purpose.
    static let admin = URL(string: "tel:+70000000000")!
    static let music = URL(string: "https://music.yandex.ru")!
}

/// «+1 час»: a background action. `LiveActivityIntent` runs in the app's process without opening it.
struct PlusHourIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "+1 час"
    static var isDiscoverable: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    func perform() async throws -> some IntentResult {
        await ProbeActivity.plusHour()
        return .result()
    }
}

enum ProbeActivity {
    /// Wedding timeline from `now`: Сборы now, Церемония +3, Прогулка +6, Банкет +10 minutes (the real one: 12:00, 14:30, 16:00, 19:00).
    static func plan(now: Date = Date()) -> ProbeAttributes.ContentState {
        let names = ["Сборы", "Церемония", "Прогулка", "Банкет"]
        let minutes: [Double] = [0, 3, 6, 10]
        let points = zip(names, minutes).map { ProbePoint(name: $0, at: now.addingTimeInterval($1 * 60)) }
        return ProbeAttributes.ContentState(mode: .wedding, points: points, next: nextIndex(points, now: now),
                                            rentEnd: now.addingTimeInterval(15 * 60), requests: 0, requestedAt: nil)
    }

    /// First point still ahead of `now`; `points.count` when the day is over.
    static func nextIndex(_ points: [ProbePoint], now: Date) -> Int {
        points.firstIndex { $0.at > now } ?? points.count
    }

    static func start() async {
        await endAll()
        let state = plan()
        do {
            let a = try Activity.request(attributes: ProbeAttributes(title: "Свадьба"),
                                         content: .init(state: state, staleDate: nil), pushType: nil)
            Spike.log("probe start ok id=\(a.id) next=\(state.next) rentEnd=\(state.rentEnd)")
        } catch {
            Spike.log("probe start FAILED \(error)")
        }
    }

    static func endAll() async {
        for a in Activity<ProbeAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        Spike.log("probe end, left=\(Activity<ProbeAttributes>.activities.count)")
    }

    static func mutate(_ why: String, _ change: (inout ProbeAttributes.ContentState) -> Void) async {
        let all = Activity<ProbeAttributes>.activities
        for a in all {
            var s = a.content.state
            change(&s)
            await a.update(.init(state: s, staleDate: nil))
            Spike.log("probe \(why): mode=\(s.mode.rawValue) next=\(s.next) requests=\(s.requests)")
        }
        if all.isEmpty { Spike.log("probe \(why): no activity") }
    }

    static func plusHour() async {
        await mutate("plusHour") { $0.requests += 1; $0.requestedAt = Date() }
    }

    /// The tap on the «Студийный час» notification.
    static func switchToStudio(source: String) async {
        await mutate("studio via \(source)") { $0.mode = .studio }
    }

    /// App opened: move the highlight to the current point (the decision of 25.10: it may lag until the app is opened).
    static func refresh() async {
        await mutate("refresh") { $0.next = nextIndex($0.points, now: Date()) }
    }
}
