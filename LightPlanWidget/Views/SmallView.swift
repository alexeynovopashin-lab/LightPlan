import SwiftUI
import LightPlanDomain

/// Малый виджет без идущей съёмки (30б.2). Слова Алексея 24.10: нет съёмок — рассвет, затем закат; есть — ближайшая съёмка и свет,
/// если он ей нужен. Идущую съёмку показывает кольцо (`SmallLiveView`, 30б.2в); поля вид получает сам (`WidgetRoot`).
struct SmallView: View {
    let frame: WidgetFrame
    let alpha: Bool
    @Environment(\.colorScheme) private var scheme

    private var st: WidgetStyle { WidgetStyle(dark: scheme == .dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            Spacer(minLength: 0)
            switch frame.kind {
            case .blank: blank
            case .light: light
            case .upcoming, .live: upcoming   // идущую съёмку в виджет несёт `WidgetRoot`, не этот вид
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // виджет не прокручивается: крупнее не влезает
    }

    // MARK: Шапка: подпись слева, «α» справа

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(captionColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if alpha { AlphaBadge() }
        }
    }

    private var caption: String {
        switch frame.kind {
        case .blank: return "Light Plan"
        case .light:
            switch frame.light?.kind {
            case .sunrise?: return frame.words[.sunrise]
            case .sunset?: return frame.words[.sunset]
            case .polarDay?: return frame.words[.polarDay]
            case .polarNight?: return frame.words[.polarNight]
            case nil: return ""
            }
        case .upcoming:
            guard let p = frame.primary else { return "" }
            return "\(frame.dayWord(p)) · \(p.shoot.title)"
        case .live:
            return frame.primary?.shoot.title ?? ""
        }
    }

    private var captionColor: Color { st.ink2 }

    // MARK: Состояния

    private var blank: some View {
        Text("—").font(.system(size: 34, weight: .semibold, design: .rounded)).foregroundStyle(st.ink)
    }

    @ViewBuilder private var light: some View {
        if let e = frame.light, let at = e.at {
            big(frame.clock(at, in: frame.zone))
            Text(lightFoot(e))
                .font(.footnote).foregroundStyle(st.ink2).lineLimit(1).minimumScaleFactor(0.8)
            nextShootLine
        } else {
            big("—")
            Text(frame.place.name).font(.footnote).foregroundStyle(st.ink2).lineLimit(1)
            nextShootLine
        }
    }

    /// Подпись под временем: место «Света»; завтрашний рассвет — со словом «Завтра».
    private func lightFoot(_ e: WidgetFrame.LightEvent) -> String {
        let name = frame.place.name
        guard e.dayOffset >= 1 else { return name }
        return name.isEmpty ? frame.words[.tomorrow] : "\(frame.words[.tomorrow]) · \(name)"
    }

    /// Свободный день: «Дальше: сб 15:00» — ближайшая съёмка дальше завтра.
    @ViewBuilder private var nextShootLine: some View {
        if let s = frame.shoots.first {
            Text("\(frame.words[.next]): \(frame.dayWord(s)) \(frame.clock(s.shoot.startDate, in: s.zone))")
                .font(.caption2).foregroundStyle(st.amber).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder private var upcoming: some View {
        if let p = frame.primary {
            big(frame.clock(p.shoot.startDate, in: p.zone))
            if !p.shoot.place.isEmpty {
                Text(p.shoot.place).font(.footnote).foregroundStyle(st.ink2).lineLimit(p.golden == nil ? 2 : 1).minimumScaleFactor(0.85)
            }
            if let g = p.golden {
                Text("\(frame.words[.golden]) \(frame.clock(g, in: p.zone))")
                    .font(.caption2.weight(.semibold)).foregroundStyle(st.amber).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    private func big(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 34, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(st.ink)
            .lineLimit(1).minimumScaleFactor(0.6)
    }
}
