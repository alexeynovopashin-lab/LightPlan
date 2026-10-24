import ActivityKit
import Foundation
import LightPlanCore

/// What both processes share: the App Group, a log, the feed and the Live Activity shape.
enum Spike {
    /// App id for both processes: the widget's own id ends in `.Widget`.
    static var appID: String {
        let id = Bundle.main.bundleIdentifier ?? "?"
        return id.hasSuffix(".Widget") ? String(id.dropLast(".Widget".count)) : id
    }
    static var group: String { "group." + appID }
    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }
    static var who: String { (Bundle.main.bundleIdentifier ?? "").hasSuffix(".Widget") ? "widget" : "app" }

    /// One line per event into `<group>/spike.log` (probe.sh reads it) and stdout.
    static func log(_ text: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(who) \(text)\n"
        print(line, terminator: "")
        guard let url = container?.appendingPathComponent("spike.log") else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// Tomsk, the place the probe computes for.
    static let lat = 56.4977, lon = 84.9744, zoneHours = 7.0

    /// Golden hour of `day` by our own Core package; clock dates in the place's zone.
    static func golden(on day: Date) -> (start: Date, end: Date)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: Int(zoneHours * 3600))!
        let c = cal.dateComponents([.year, .month, .day], from: day)
        let sun = SolarDay(date: CivilDate(year: c.year!, month: c.month!, day: c.day!),
                           latitude: lat, longitude: lon, utcOffsetHours: zoneHours)
        guard let a = sun.goldenB, let b = sun.blueB else { return nil }
        let midnight = cal.startOfDay(for: day)
        return (midnight.addingTimeInterval(a * 60), midnight.addingTimeInterval(b * 60))
    }
}

/// What the app writes for the widget. The real one would carry the next shoots.
struct Feed: Codable {
    var wrote: Date
    var place: String
    var goldenStart: Date?
}

struct GoldenAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var until: Date
        /// End of golden hour; after `until` (staleDate) the views count down to it without an update.
        var end: Date
    }
    var place: String
}
