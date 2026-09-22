import SwiftUI
import LightPlanCore
import LightPlanTimeline

/// Ползунок таймбара — свой, а не системный `Slider`: системный клампит
/// значение и на упоре перестаёт отдавать движение, а нам нужно то, что
/// происходит **за** упором — намерение «давлю дальше» (передача разряда).
///
/// Порт `Spikes/TimebarSpike/App/ScrubView.swift` (итерация 3): дорожка света
/// здесь настоящая, `LightTrack.gradient(day:)` от `SolarDay`, а не выдумка.
struct ScrubView: View {
    let state: TimebarState

    private let thumb = 26.0
    private let track = 34.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(white: 0.11))
                    .overlay(Capsule().strokeBorder(Color(white: 0.22), lineWidth: 1))
                    .frame(height: track)

                Capsule()
                    .fill(LinearGradient(gradient: LightTrack.gradient(day: state.solarDay),
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: track - 16)
                    .padding(.horizontal, 6)
                    .opacity(0.65)

                RulerView(solarDay: state.solarDay)
                    .frame(height: 10)
                    .padding(.horizontal, 6)
                    .offset(y: -track / 2 - 2)

                heat(at: .trailing, on: state.machine.wind.side > 0)
                heat(at: .leading, on: state.machine.wind.side < 0)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white)
                    .frame(width: state.machine.wind.thumbWidth, height: state.machine.wind.thumbHeight)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                    .offset(x: thumb / 2 + position(width: w) * (w - thumb) - state.machine.wind.thumbWidth / 2)
            }
            .frame(height: track + 18, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in state.dragSlider(x: g.location.x, width: w, thumb: thumb) }
                    .onEnded { _ in state.releaseSlider() }
            )
        }
        .frame(height: track + 18)
    }

    private func position(width w: Double) -> Double {
        let span = state.solarDay.maxt - state.solarDay.mint
        guard span > 0 else { return 0 }
        return min(max((state.machine.viewMinute - state.solarDay.mint) / span, 0), 1)
    }

    /// Конец дорожки разогревается по мере взвода.
    private func heat(at edge: Alignment, on active: Bool) -> some View {
        HStack {
            if edge == .trailing { Spacer(minLength: 0) }
            Capsule()
                .fill(RadialGradient(
                    colors: [Color(red: 1, green: 0.72, blue: 0.36), .clear],
                    center: edge == .trailing ? .trailing : .leading,
                    startRadius: 0, endRadius: 60))
                .frame(width: 84, height: track)
                .opacity(active ? state.machine.wind.heat : 0)
            if edge == .leading { Spacer(minLength: 0) }
        }
        .allowsHitTesting(false)
    }
}
