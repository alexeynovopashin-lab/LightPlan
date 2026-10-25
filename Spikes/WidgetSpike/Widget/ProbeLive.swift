import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// 30б.3а: the lock-screen probe activity (wedding timeline / studio countdown + three dummy buttons).
struct ProbeLive: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProbeAttributes.self) { ctx in
            ProbeLockView(state: ctx.state)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(ctx.state.mode == .studio ? "Студия" : "Свадьба").font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) { ProbeCountdown(state: ctx.state).font(.headline) }
                DynamicIslandExpandedRegion(.center) { ProbeNextLabel(state: ctx.state).font(.caption) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProbeRequested(state: ctx.state)
                        ProbeButtons()
                    }
                }
            } compactLeading: {
                Image(systemName: ctx.state.mode == .studio ? "camera.fill" : "heart.fill")
            } compactTrailing: {
                ProbeCountdown(state: ctx.state).frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "clock.fill")
            }
        }
    }
}
