import SwiftUI
import LightPlanDomain

/// Средний виджет, пока съёмка идёт (30б.2в-1, два варианта на выбор Алексею по картинкам).
/// Слова Алексея 25.10: «знак точки и имена Свадьба Анна+Игорь; два таймера, простой или кольцо; кольцо с двумя слоями: вся
/// свадьба и точка; маршрут не съезжает вниз, надо заполнить пустое место сверху; деления по периметру, как у часов Apple».
///
/// Вид получает всю плашку (364 × 170 на Pro Max) и сам ставит поля: у кольца деления лежат в полях и места не занимают.
struct MediumLiveView: View {
    let frame: WidgetFrame
    var look: WidgetLook = .plain
    var names: String?
    var alpha = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let plan = DayPlan(frame) {
                Inner(plan: plan, look: look, names: names, alpha: alpha, st: WidgetStyle(dark: scheme == .dark))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)   // виджет не прокручивается: крупнее не влезает вместе с маршрутом
    }

    private struct Inner: View {
        let plan: DayPlan
        let look: WidgetLook
        let names: String?
        let alpha: Bool
        let st: WidgetStyle
        @Environment(\.dynamicTypeSize) private var type

        var body: some View {
            switch look {
            case .plain: plain
            case .ring: ring
            }
        }

        // MARK: Простой: отсчёты текстом

        private var plain: some View {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    head
                    Text(plan.title(names: names)).font(.caption).foregroundStyle(st.ink2).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    if let left = plan.pointLeft {
                        Text(DayPlan.long(left))
                            .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(st.amber).lineLimit(1).minimumScaleFactor(0.6)
                        Text(WidgetSketchWords.toPoint).font(.caption2).foregroundStyle(st.ink2).lineLimit(1)
                    }
                    Text("\(WidgetSketchWords.toShoot) \(DayPlan.long(plan.shootLeft))")
                        .font(.caption2).monospacedDigit().foregroundStyle(st.ink2).lineLimit(1).minimumScaleFactor(0.75).padding(.top, 3)
                }
                .frame(width: 148, alignment: .topLeading)
                Rectangle().fill(st.ink.opacity(0.12)).frame(width: 1)
                route(rows: type.rows(normal: 4, large: 3, huge: 2), header: true)
            }
            .padding(16)
            .overlay(alignment: .topTrailing) { if alpha { AlphaBadge().padding(8) } }
        }

        // MARK: Кольцо: два слоя делений, внутри текст

        private var ring: some View {
            ZStack {
                // Внешний слой — вся съёмка: часовые отметки подлиннее. Внутренний — текущая точка: четверти часа.
                PerimeterTicks(inset: 6, length: 6, progress: plan.shootProgress, majors: plan.shootHourMarks,
                               on: st.ink.opacity(0.9), off: st.ink.opacity(0.2))
                PerimeterTicks(inset: 17, length: 5, corner: 38, progress: plan.pointProgress ?? 0, majors: plan.pointQuarterMarks,
                               on: st.amber, off: st.amber.opacity(0.22))
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        head
                        Text(plan.title(names: names)).font(.caption).foregroundStyle(st.ink2).lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: 2)
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            stat(DayPlan.hours(plan.shootLeft), WidgetSketchWords.shoot, st.ink)
                            if let left = plan.pointLeft { stat(DayPlan.short(left), WidgetSketchWords.point, st.amber) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    route(rows: type.rows(normal: 3, large: 2, huge: 2), header: true).frame(width: 118, alignment: .topLeading)
                }
                .padding(.horizontal, 30).padding(.vertical, 28)
            }
            .overlay(alignment: .topTrailing) { if alpha { AlphaBadge().padding(.top, 25).padding(.trailing, 30) } }
        }

        // MARK: Кирпичи

        private var head: some View {
            HStack(spacing: 6) {
                if let cur = plan.current {
                    WidgetSign(title: cur.name, place: cur.place, studio: plan.frame.primary?.countdown?.kind == .studio, size: 18)
                        .foregroundStyle(st.amber)
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
        private func route(rows: Int, header: Bool) -> some View {
            let items = Array(plan.upcomingStops.prefix(rows))
            return VStack(alignment: .leading, spacing: 0) {
                if header {
                    Text(WidgetSketchWords.route).font(.caption.weight(.semibold)).foregroundStyle(st.ink2).lineLimit(1)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { _, s in
                    StopLine(plan: plan, stop: s, signSize: 14, st: st).frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
