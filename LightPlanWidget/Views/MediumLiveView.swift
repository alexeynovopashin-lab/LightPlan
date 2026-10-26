import SwiftUI
import LightPlanDomain

/// Средний виджет, пока съёмка идёт (30б.2в): кольцо. Выбор Алексея 26.10 («средний кольцо») из двух картинок 30б.2в-1; «простой» убран.
/// Слова Алексея 25.10: «знак точки и имена Свадьба Анна+Игорь; кольцо с двумя слоями: вся свадьба и точка; маршрут не съезжает
/// вниз, надо заполнить пустое место сверху; деления по периметру, как у часов Apple».
///
/// Вид получает всю плашку (364 × 170 на Pro Max) и сам ставит поля: деления лежат в полях и места не занимают (в виджете для этого
/// `.contentMarginsDisabled()`). Цифры статичные — их меняет лента (`WidgetFeed.timeline(shape:)`, запись на каждую минуту).
struct MediumLiveView: View {
    let frame: WidgetFrame
    var alpha = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let plan = DayPlan(frame) {
                Inner(plan: plan, alpha: alpha, st: WidgetStyle(dark: scheme == .dark))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)   // виджет не прокручивается: крупнее не влезает вместе с маршрутом
    }

    private struct Inner: View {
        let plan: DayPlan
        let alpha: Bool
        let st: WidgetStyle
        @Environment(\.dynamicTypeSize) private var type

        var body: some View {
            ZStack {
                // Внешний слой — вся съёмка: часовые отметки подлиннее. Внутренний — текущая точка: четверти часа.
                PerimeterTicks(inset: 6, length: 6, progress: plan.shootProgress, majors: plan.shootHourMarks,
                               on: st.ink.opacity(0.9), off: st.ink.opacity(0.2))
                PerimeterTicks(inset: 17, length: 5, corner: 38, progress: plan.pointProgress ?? 0, majors: plan.pointQuarterMarks,
                               on: st.amber, off: st.amber.opacity(0.22))
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        head
                        Text(plan.title).font(.caption).foregroundStyle(st.ink2).lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: 2)
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            stat(plan.hours(plan.shootLeft), plan.shootNoun, st.ink)
                            if let left = plan.pointLeft { stat(plan.short(left), plan.words[.point], st.amber) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    route(rows: type.rows(normal: 3, large: 2, huge: 2)).frame(width: 118, alignment: .topLeading)
                }
                .padding(.horizontal, 30).padding(.vertical, 28)
            }
            .overlay(alignment: .topTrailing) { if alpha { AlphaBadge().padding(.top, 25).padding(.trailing, 30) } }
        }

        private var head: some View {
            HStack(spacing: 6) {
                if let cur = plan.current {
                    WidgetIcon(name: cur.sign, size: 18).foregroundStyle(st.amber)
                    Text(cur.name).font(.subheadline.weight(.semibold)).foregroundStyle(st.ink).lineLimit(1).minimumScaleFactor(0.8)
                } else {
                    Text(plan.shoot.title).font(.subheadline.weight(.semibold)).foregroundStyle(st.ink).lineLimit(1)
                }
            }
        }

        private func stat(_ value: String, _ caption: String, _ color: Color) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
                Text(caption).font(.caption2).foregroundStyle(st.ink2).lineLimit(1)
            }
        }

        /// Маршрут: «Дальше» и следующие точки сверху вниз, строки делят всю высоту поровну — пустоты сверху нет.
        private func route(rows: Int) -> some View {
            let items = Array(plan.upcomingStops.prefix(rows))
            return VStack(alignment: .leading, spacing: 0) {
                Text(plan.words[.next]).font(.caption.weight(.semibold)).foregroundStyle(st.ink2).lineLimit(1)
                ForEach(Array(items.enumerated()), id: \.offset) { _, s in
                    StopLine(plan: plan, stop: s, signSize: 14, st: st).frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
