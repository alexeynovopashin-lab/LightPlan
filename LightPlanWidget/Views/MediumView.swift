import SwiftUI
import LightPlanDomain

/// Средний виджет без идущей съёмки (30б.2, вариант оркестратора 24.10): слева сегодняшний свет, справа две ближайшие съёмки.
/// Идущую съёмку показывает кольцо (`MediumLiveView`, 30б.2в). Кольцу без съёмки нечего считать, поэтому свет и ближайшие съёмки
/// остались как были; вид получает поля сам (`WidgetRoot`).
struct MediumView: View {
    let frame: WidgetFrame
    let alpha: Bool
    @Environment(\.colorScheme) private var scheme

    private var st: WidgetStyle { WidgetStyle(dark: scheme == .dark) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            left.frame(width: 118).frame(maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(st.ink.opacity(0.12)).frame(width: 1)
            right.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .topTrailing) { if alpha { AlphaBadge() } }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // виджет не прокручивается: крупнее не влезает
    }

    // MARK: Слева: свет сегодня

    private var left: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(frame.place.name.isEmpty ? "Light Plan" : frame.place.name)
                .font(.caption.weight(.semibold)).foregroundStyle(st.ink2).lineLimit(1)
            Spacer(minLength: 0)
            if let d = frame.day { dayRows(d) } else { Text("—").font(.title2).foregroundStyle(st.ink) }
        }
    }

    @ViewBuilder private func dayRows(_ d: WidgetFeed.DayLight) -> some View {
        if d.sunrise == nil && d.sunset == nil {
            Text(d.polar == .night ? frame.words[.polarNight] : frame.words[.polarDay])
                .font(.title3.weight(.semibold)).foregroundStyle(st.ink).lineLimit(2).minimumScaleFactor(0.7)
        } else {
            row(frame.words[.sunrise], d.sunrise, accent: false)
            row(frame.words[.golden], d.golden, accent: true)
            row(frame.words[.sunset], d.sunset, accent: false)
        }
    }

    private func row(_ name: String, _ at: Date?, accent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(name).font(.caption).foregroundStyle(accent ? st.amber : st.ink2).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text(at.map { frame.clock($0, in: frame.zone) } ?? "—")
                .font(.system(.subheadline, design: .rounded).weight(.semibold)).monospacedDigit()
                .foregroundStyle(st.ink).lineLimit(1)
        }
    }

    // MARK: Справа: ближайшие съёмки

    private var right: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(frame.words[.shoot].capitalizedFirst).font(.caption.weight(.semibold)).foregroundStyle(st.ink2).lineLimit(1)
            Spacer(minLength: 0)
            if frame.shoots.isEmpty {
                Text("—").font(.title3).foregroundStyle(st.ink2)
            }
            ForEach(frame.shoots) { shootRow($0) }
        }
    }

    private func shootRow(_ s: WidgetFrame.ShootFrame) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(frame.clock(s.shoot.startDate, in: s.zone))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold)).monospacedDigit()
                    .foregroundStyle(st.ink)
                Text(s.shoot.title).font(.footnote).foregroundStyle(st.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            Text(s.shoot.place.isEmpty ? frame.dayWord(s) : "\(frame.dayWord(s)) · \(s.shoot.place)")
                .font(.caption2).foregroundStyle(st.ink2).lineLimit(1)
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
