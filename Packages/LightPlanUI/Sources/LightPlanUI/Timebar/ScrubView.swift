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
    @Environment(\.colorScheme) private var colorScheme

    /// Числа `.scrub` веба: поле касания 36, рельс 4 по центру (16…20),
    /// ползунок 26, гравировка 10 под рельсом (24…34) с полями 13, под всем
    /// ярусом ещё 6 (`.track-wrap { padding-bottom: 6px }`). До 19б здесь
    /// был стенд прототипа: рельс-капсула 34 pt и белый прямоугольник.
    static let field: CGFloat = 36
    static let bottomPad: CGFloat = 6
    private let thumb = 26.0

    var body: some View {
        let pal = Palette(colorScheme)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(pal.rail)
                    .overlay(Capsule().fill(LinearGradient(gradient: PathStops.railGradient(day: state.solarDay),
                                                           startPoint: .leading, endPoint: .trailing)))
                    .frame(width: w, height: 4)
                    .padding(.top, 16)

                RulerView(solarDay: state.solarDay)
                    .frame(width: max(0, w - 26), height: 10)
                    .shotNode("ruler")
                    .padding(.leading, 13).padding(.top, 24)

                heat(on: state.machine.wind.side < 0, pal: pal).padding(.top, 16)
                heat(on: state.machine.wind.side > 0, pal: pal).padding(.leading, max(0, w - 34)).padding(.top, 16)

                knob(pal: pal)
                    .offset(x: thumb / 2 + position() * (w - thumb) - state.machine.wind.thumbWidth / 2,
                            y: Self.field / 2 - state.machine.wind.thumbHeight / 2)
            }
            .frame(width: w, height: Self.field, alignment: .topLeading)
            .shotNode("scrub")
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in state.dragSlider(x: g.location.x, width: w, thumb: thumb) }
                    .onEnded { _ in state.releaseSlider() }
            )
        }
        .frame(height: Self.field)
        .padding(.bottom, Self.bottomPad)
    }

    /// Ручка — стекло с глухим кантом (`::-webkit-slider-thumb`): сквозь неё
    /// видна дорожка света, кант 3 pt держит край на светлом участке, снаружи
    /// волосок `--ink-a22`, сверху блик `--glass-shine`, под ней тень
    /// 0 4 12 чёрным 55 %. Стекло системное (DECISIONS, 21 сентября 2026).
    private func knob(pal: Palette) -> some View {
        let kw = state.machine.wind.thumbWidth, kh = state.machine.wind.thumbHeight
        return Ellipse()
            .fill(pal.knobGlass)
            .glassEffect(.clear, in: Ellipse())
            .overlay(Ellipse().strokeBorder(pal.knobEdge, lineWidth: 3))
            .overlay(
                Ellipse().inset(by: 3).stroke(pal.glassShine, lineWidth: 1)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25)))
            )
            .overlay(Ellipse().inset(by: -1).stroke(pal.inkA22, lineWidth: 1))
            .frame(width: kw, height: kh)
            .shadow(color: .black.opacity(0.55), radius: 6, y: 4)
            .allowsHitTesting(false)
    }

    private func position() -> Double {
        let span = state.solarDay.maxt - state.solarDay.mint
        guard span > 0 else { return 0 }
        return min(max((state.machine.viewMinute - state.solarDay.mint) / span, 0), 1)
    }

    /// Разогрев конца дорожки (`.rail-heat`): латунная полоска 34×4 поверх
    /// рельса у того края, куда давят; яркость — сила взвода.
    private func heat(on active: Bool, pal: Palette) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(pal.brass)
            .frame(width: 34, height: 4)
            .opacity(active ? state.machine.wind.heat : 0)
            .allowsHitTesting(false)
    }
}
