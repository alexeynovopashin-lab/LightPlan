import SwiftUI

/// Ползунок свой, а не системный `Slider`. Причина не в виде: системный
/// клампит значение и на упоре перестаёт отдавать движение, а нам нужно
/// именно то, что происходит **за** упором — намерение «давлю дальше».
struct ScrubView: View {
    let model: TimebarModel

    /// Ход ползунка в покое; при взводе он сплющивается.
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

                // Дорожка света: где светило выше, там теплее. В песочнице
                // это просто градиент — солнечная модель придёт позже.
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.12, green: 0.14, blue: 0.2),
                                 Color(red: 0.88, green: 0.64, blue: 0.30),
                                 Color(red: 0.12, green: 0.14, blue: 0.2)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(height: track - 16)
                    .padding(.horizontal, 6)
                    .opacity(0.65)

                heat(at: .trailing, on: model.wind.side > 0)
                heat(at: .leading, on: model.wind.side < 0)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white)
                    .frame(width: model.wind.thumbWidth, height: model.wind.thumbHeight)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                    .offset(x: thumb / 2 + model.position * (w - thumb) - model.wind.thumbWidth / 2)
            }
            .frame(height: track + 18, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in model.drag(x: g.location.x, width: w, thumb: thumb) }
                    .onEnded { _ in model.release() }
            )
        }
        .frame(height: track + 18)
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
                .opacity(active ? model.wind.heat : 0)
            if edge == .leading { Spacer(minLength: 0) }
        }
        .allowsHitTesting(false)
    }
}
