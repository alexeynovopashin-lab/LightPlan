import ActivityKit
import SwiftUI
import UserNotifications

/// 30б.3а: the probe screen — start / end the lock-screen activity, schedule «Студийный час», show the log.
struct ProbeView: View {
    @State private var notifyMinutes = 2
    @State private var shown = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LP 30б.3а — замер кнопок").font(.title2.bold())
            Stepper("«Студийный час» через \(notifyMinutes) мин", value: $notifyMinutes, in: 1...30)
            HStack {
                Button("Запустить активность") { Task { await ProbeControl.start(notifyMinutes: notifyMinutes) } }
                    .buttonStyle(.borderedProminent)
                Button("Завершить") { Task { await ProbeActivity.endAll(); await ProbeControl.cancelNotice() } }
                    .buttonStyle(.bordered)
            }
            Text("После «Запустить» заблокируй телефон (боковая кнопка) и нажимай кнопки на экране блокировки. Памятка — в документе.")
                .font(.footnote).foregroundStyle(.secondary)
            Divider()
            Text("Журнал (последние строки)").font(.footnote.weight(.semibold))
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                Text(Self.tail()).font(.system(size: 10, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
            }
            if ProcessInfo.processInfo.arguments.contains("-ProbePreview") { ProbePreview() }
            Spacer()
        }
        .padding()
    }

    static func tail() -> String {
        guard let url = Spike.container?.appendingPathComponent("spike.log"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "—" }
        return text.split(separator: "\n").filter { $0.contains("probe") || $0.contains("notice") }
            .suffix(12).map { String($0.dropFirst(11).prefix(90)) }.joined(separator: "\n")
    }
}

enum ProbeControl {
    static let noticeID = "lp.studiohour"

    static func start(notifyMinutes: Int) async {
        // The activity first: the permission question waits for a tap and must not hold the start back.
        await ProbeActivity.start()
        let ok = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        Spike.log("notice permission granted=\(ok.map(String.init) ?? "error")")
        await scheduleNotice(seconds: Double(notifyMinutes) * 60)
    }

    static func scheduleNotice(seconds: Double) async {
        let c = UNMutableNotificationContent()
        c.title = "Студийный час"
        c.body = "Нажми — включится режим студии на экране активности"
        c.sound = .default
        let req = UNNotificationRequest(identifier: noticeID, content: c,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false))
        do {
            try await UNUserNotificationCenter.current().add(req)
            Spike.log("notice scheduled in \(Int(seconds)) s")
        } catch {
            Spike.log("notice schedule FAILED \(error)")
        }
    }

    static func cancelNotice() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [noticeID])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [noticeID])
    }
}

/// Tap on the notification → the activity switches to studio mode. Also shows it as a banner while the app is open.
final class ProbeDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Spike.log("notice arrived while the app is open")
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == ProbeControl.noticeID else { return }
        Spike.log("notice tapped")
        await ProbeActivity.switchToStudio(source: "notification tap")
    }
}

/// Layout check in the simulator: the lock-screen view at the system's width, with its measured height in the log.
struct ProbePreview: View {
    static func state() -> ProbeAttributes.ContentState {
        let args = ProcessInfo.processInfo.arguments
        var s = ProbeActivity.plan(now: Date().addingTimeInterval(-4 * 60))
        s.next = ProbeActivity.nextIndex(s.points, now: Date())
        if args.contains("-ProbeStudio") { s.mode = .studio }
        if args.contains("-ProbePlus") { s.requests = 1; s.requestedAt = Date() }
        return s
    }

    var body: some View {
        ProbeLockView(state: Self.state())
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 24))
            .environment(\.colorScheme, .dark)
            .frame(width: 361)
            .background(GeometryReader { g in Color.clear.onAppear { Spike.log("preview height=\(Int(g.size.height)) width=\(Int(g.size.width))") } })
    }
}
