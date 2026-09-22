import SwiftUI
import LightPlanTimeline

/// Лента под ползунком: контекст соседних суток. Два вида — полоса и
/// барабан (`state.machine.ribbonMode`).
///
/// Порт `Spikes/TimebarSpike/App/RibbonView.swift` (итерация 3) на настоящие
/// даты, знаки погоды (`state.weatherSignName`) и фазы луны
/// (`state.moonFraction`) вместо выдуманных суток спайка.
///
/// Нативного скролла здесь нет вовсе, как и в вебе: жест читает только сдвиг
/// пальца, позицию всегда ставит код (DECISIONS «Лента без нативного
/// скролла»).
struct RibbonView: View {
    let state: TimebarState

    private let height = 54.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Выравнивание по левому краю обязательно: смещения считаются от
            // начала дорожки, как в вебе (DECISIONS «Барабан в нативе»).
            ZStack(alignment: .leading) {
                track(width: w)
                    .offset(x: -state.machine.ribbonOffset(clipWidth: w) + state.ribbonShift)
                    .opacity(state.ribbonOpacity)

                if state.machine.ribbonMode == .drum {
                    // Рамка подаётся вслед за натяжением ползунка ещё до
                    // срыва: видно, что дата уже под нагрузкой.
                    frame.offset(x: w / 2 - (TimelineMachine.drumCell + 6) / 2 + state.machine.wind.strain * 0.6)
                }
            }
            .frame(width: w, height: height, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        state.dragRibbon(translation: g.translation.width, clipWidth: w)
                    }
                    .onEnded { g in
                        let moved = abs(g.translation.width) + abs(g.translation.height)
                        state.releaseRibbon(tapAt: moved < 6 ? g.location.x : nil, clipWidth: w)
                    }
            )
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func track(width: Double) -> some View {
        switch state.machine.ribbonMode {
        case .lane:
            HStack(spacing: 0) {
                ForEach(-1...1, id: \.self) { offset in day(offset: offset, width: width) }
            }
        case .drum:
            HStack(spacing: 0) {
                ForEach(-TimelineMachine.drumSpan...TimelineMachine.drumSpan, id: \.self) { offset in
                    cell(offset: offset)
                }
            }
        }
    }

    // MARK: - Полоса

    private func day(offset: Int, width: Double) -> some View {
        let bounds = state.bounds(offset: offset)
        let pxPerMin = width / 1440
        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(LinearGradient(
                    colors: [Color(red: 0.35, green: 0.26, blue: 0.16),
                             Color(red: 0.88, green: 0.64, blue: 0.30),
                             Color(red: 0.35, green: 0.26, blue: 0.16)],
                    startPoint: .leading, endPoint: .trailing))
                .frame(width: max((bounds.end - bounds.start) * pxPerMin, 0), height: 3)
                .offset(x: bounds.start * pxPerMin, y: height - 14)
                .opacity(0.75)

            ForEach(Array(stride(from: 0, to: 24, by: 1)), id: \.self) { hour in
                let x = Double(hour) * 60 * pxPerMin
                Rectangle()
                    .fill(Color(white: hour % 6 == 0 ? 0.5 : 0.24))
                    .frame(width: 1, height: hour % 6 == 0 ? 12 : 7)
                    .offset(x: x, y: height - 26)
                if hour % 6 == 0 {
                    Text("\(hour)")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .offset(x: x + 3, y: height - 26)
                }
            }

            Text(state.weekdayShort(offset: offset) + " " + String(state.dayNumber(offset: offset)))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(offset == 0 ? .primary : .tertiary)
                .padding(.leading, 8)
                .padding(.top, 6)
        }
        .frame(width: width, height: height)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color(white: 0.3)).frame(width: 1)
        }
    }

    // MARK: - Барабан

    private func cell(offset: Int) -> some View {
        VStack(spacing: 2) {
            Text(state.weekdayShort(offset: offset))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("\(state.dayNumber(offset: offset))")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(offset == 0 ? .primary : .secondary)
            sign(offset: offset)
        }
        .frame(width: TimelineMachine.drumCell, height: height)
    }

    @ViewBuilder
    private func sign(offset: Int) -> some View {
        if state.showMoon {
            MoonGlyph(fraction: state.moonFraction(offset: offset))
                .fill(.secondary)
                .frame(width: 8, height: 8)
                .scaleEffect(x: state.moonMirrored(offset: offset) ? -1 : 1, y: 1)
        } else if let name = state.weatherSignName(offset: offset) {
            Icon(name, size: 13, line: 1.6)
                .foregroundStyle(.secondary)
        } else {
            Color.clear.frame(width: 13, height: 13)
        }
    }

    /// Окно барабана: выбранная ячейка всегда по центру.
    private var frame: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color(white: 0.55), lineWidth: 1.5)
            .frame(width: TimelineMachine.drumCell + 6, height: height - 4)
            .allowsHitTesting(false)
    }
}
