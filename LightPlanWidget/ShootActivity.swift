import ActivityKit
import SwiftUI
import WidgetKit
import LightPlanDomain

/// Экран активности на заблокированном телефоне и в Dynamic Island (30б.3). Что рисовать — решает `ActivityFrame` (Domain), вид —
/// `ActivityViews.swift`; здесь только оболочка WidgetKit.
struct ShootActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShootActivityAttributes.self) { context in
            ActivityLockView(frame: context.state)
                .activityBackgroundTint(Color(red: 0x0F / 255, green: 0x0E / 255, blue: 0x0C / 255).opacity(0.92))
                .activitySystemActionForegroundColor(WidgetStyle(dark: true).ink)
                .widgetURL(WidgetFeed.shootURL(context.state.shootId))
        } dynamicIsland: { context in
            let frame = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityGlyph(frame: frame, size: 20).foregroundStyle(WidgetStyle.brass)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityIslandTimer(frame: frame)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(frame.status).font(.system(size: 14)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityIslandBottom(frame: frame)
                }
            } compactLeading: {
                ActivityGlyph(frame: frame).foregroundStyle(WidgetStyle.brass)
            } compactTrailing: {
                ActivityIslandTimer(frame: frame)
            } minimal: {
                ActivityGlyph(frame: frame, size: 14).foregroundStyle(WidgetStyle.brass)
            }
            .widgetURL(WidgetFeed.shootURL(frame.shootId))
        }
    }
}
