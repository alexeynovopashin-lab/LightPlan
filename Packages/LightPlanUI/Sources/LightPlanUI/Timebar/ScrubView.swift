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
            let kw = state.machine.wind.thumbWidth, kh = state.machine.wind.thumbHeight
            let cx = thumb / 2 + position() * (w - thumb)
            ZStack(alignment: .topLeading) {
                // Всё, что лежит под ручкой: сквозь её прозрачное кольцо это
                // видно, и кромка кольца это гнёт (`GlassOptics.ring`).
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
                }
                .frame(width: w, height: Self.field, alignment: .topLeading)
                .layerEffect(GlassOptics.ring(center: CGPoint(x: cx, y: Self.field / 2),
                                              radii: CGSize(width: kw / 2, height: kh / 2),
                                              width: Self.ring, scheme: colorScheme),
                             maxSampleOffset: CGSize(width: GlassOptics.ringShift, height: GlassOptics.ringShift))

                knob(pal: pal)
                    .offset(x: cx - kw / 2, y: Self.field / 2 - kh / 2)
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

    /// Ручка — два стекла (`::-webkit-slider-thumb` веба плюс слово
    /// Алексея). Середина — матовое, системное (DECISIONS, 21 сентября 2026):
    /// сквозь неё видна дорожка света, сверху блик `--glass-shine`. Вокруг —
    /// прозрачное кольцо 3 pt на месте глухого канта `--knob-edge`: «это
    /// пустое пространство вокруг матового стекла также предполагалось
    /// заполнить стеклом, только прозрачным» (DECISIONS «Прозрачное стекло…»,
    /// 23 сентября 2026), в обеих темах. Кольцо само ничего не рисует, кроме
    /// кромок: то, что под ним, гнёт шейдер на слое дорожки. Край ручки
    /// держат волосок `--ink-a22` снаружи и светлая кромка стекла сверху.
    ///
    /// Тень — не `.shadow`: та лежит и под самой ручкой и просвечивает
    /// сквозь стекло, середина ручки в светлой теме гасла 255 → 221 (замер
    /// после 19б, жалоба Алексея «затемняет сам ползунок»). У веба тень
    /// `box-shadow` рисуется только снаружи — так и здесь, `OuterShadow`.
    private func knob(pal: Palette) -> some View {
        let kw = state.machine.wind.thumbWidth, kh = state.machine.wind.thumbHeight
        let r = Self.ring
        return ZStack {
            // Налёт прозрачного стекла — только на кольце: под матовой
            // серединой он высветлял её в тёмной теме 86 → 108 (веб 75;
            // Алексей велел оставить 86).
            Ellipse().strokeBorder(pal.glassFill, lineWidth: r)
            Ellipse()
                .fill(pal.knobGlass)
                .glassEffect(.clear, in: Ellipse())
                .overlay(
                    Ellipse().inset(by: 0.5).stroke(pal.glassShine, lineWidth: 1)
                        .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25)))
                )
                .padding(r)
            // Кромка прозрачного кольца: сверху свет, снизу — тень толщины.
            Ellipse().inset(by: 0.5)
                .stroke(LinearGradient(stops: [.init(color: pal.glassShine, location: 0),
                                               .init(color: pal.glassShine.opacity(0), location: 0.35),
                                               .init(color: .black.opacity(0), location: 0.65),
                                               .init(color: .black.opacity(0.28), location: 1)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
        }
        .overlay(Ellipse().inset(by: -1).stroke(pal.inkA22, lineWidth: 1))
        .frame(width: kw, height: kh)
        .background(OuterShadow(shape: Ellipse(), color: .black.opacity(0.45), radius: 5.5, y: 4))
        .allowsHitTesting(false)
    }

    /// Ширина прозрачного кольца — бывший кант веба `border: 3px`.
    static let ring = 3.0

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

