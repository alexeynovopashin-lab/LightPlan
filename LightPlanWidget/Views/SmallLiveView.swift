import SwiftUI
import LightPlanDomain

/// Малый виджет, пока съёмка идёт (30б.2в): кольцо, как у среднего (выбор Алексея 26.10). Плашка 170 × 170 на Pro Max, 158 × 158 на iPhone 14.
struct SmallLiveView: View {
    let frame: WidgetFrame
    var alpha = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let plan = DayPlan(frame) {
                Inner(plan: plan, alpha: alpha, st: WidgetStyle(dark: scheme == .dark))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)   // малая плашка: крупнее не влезает вместе с остатком съёмки
    }

    private struct Inner: View {
        let plan: DayPlan
        let alpha: Bool
        let st: WidgetStyle

        var body: some View {
            ZStack {
                PerimeterTicks(inset: 6, length: 6, progress: plan.shootProgress, majors: plan.shootHourMarks,
                               on: st.ink.opacity(0.9), off: st.ink.opacity(0.2), spacing: 7)
                PerimeterTicks(inset: 17, length: 5, corner: 38, progress: plan.pointProgress ?? 0, majors: plan.pointQuarterMarks,
                               on: st.amber, off: st.amber.opacity(0.22), spacing: 7)
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        head(size: 15)
                        Spacer(minLength: 0)
                        if alpha { AlphaBadge() }
                    }
                    Text(plan.title).font(.caption2).foregroundStyle(st.ink2).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    if let left = plan.pointLeft {
                        Text(plan.short(left)).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(st.amber).lineLimit(1).minimumScaleFactor(0.6)
                        Text(plan.words[.untilPoint]).font(.caption2).foregroundStyle(st.ink2).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                    Text("\(plan.shootNoun) · \(plan.hours(plan.shootLeft))")
                        .font(.caption.weight(.semibold)).foregroundStyle(st.ink).lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 28).padding(.vertical, 28)
            }
        }

        @ViewBuilder private func head(size: CGFloat) -> some View {
            HStack(spacing: 4) {
                if let cur = plan.current {
                    WidgetIcon(name: cur.sign, size: size).foregroundStyle(st.amber)
                    Text(cur.name).font(.footnote.weight(.semibold)).foregroundStyle(st.ink).lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Text(plan.shoot.title).font(.footnote.weight(.semibold)).foregroundStyle(st.ink).lineLimit(1)
                }
            }
        }
    }
}
