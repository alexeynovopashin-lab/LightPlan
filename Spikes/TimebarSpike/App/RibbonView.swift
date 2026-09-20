import SwiftUI

/// Лента под ползунком: контекст соседних суток. Два вида — полоса и барабан.
///
/// Нативного скролла здесь нет вовсе, как и в вебе: жест читает только сдвиг
/// пальца, позицию всегда ставит код. Инерции и резинового отката нет, значит
/// убегать и упираться нечему (DECISIONS, «Лента без нативного скролла»).
struct RibbonView: View {
    let model: TimebarModel

    private let height = 54.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Выравнивание по левому краю обязательно: смещения считаются от
            // начала дорожки, как в вебе. При центрировании SwiftUI добавляет
            // свою поправку, и окно барабана встаёт на соседнюю ячейку.
            ZStack(alignment: .leading) {
                track(width: w)
                    .offset(x: -model.ribbonOffset(clipWidth: w) + model.ribbonShift)
                    .opacity(model.ribbonOpacity)

                if model.ribbonMode == .drum {
                    frame.offset(x: w / 2 - (TimebarModel.drumCell + 6) / 2 + model.frameShift)
                }
            }
            .frame(width: w, height: height, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if g.translation == .zero { model.ribbonGrab() }
                        model.ribbonDrag(translation: g.translation.width, clipWidth: w)
                    }
                    .onEnded { _ in model.ribbonRelease() }
            )
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func track(width: Double) -> some View {
        switch model.ribbonMode {
        case .lane:
            // Трое суток шириной в экран: вчера, сегодня, завтра.
            HStack(spacing: 0) {
                ForEach(-1...1, id: \.self) { offset in
                    day(offset: offset, width: width)
                }
            }
        case .drum:
            HStack(spacing: 0) {
                ForEach(-TimebarModel.drumSpan...TimebarModel.drumSpan, id: \.self) { offset in
                    cell(offset: offset)
                }
            }
        }
    }

    // MARK: - Полоса

    private func day(offset: Int, width: Double) -> some View {
        let date = model.date(offset: offset)
        return ZStack(alignment: .topLeading) {
            // Светлая часть суток видна как тёплая полоса: остальное — ночь.
            GeometryReader { _ in
                let bounds = model.bounds(offset: offset)
                let pxPerMin = width / 1440
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.35, green: 0.26, blue: 0.16),
                                 Color(red: 0.88, green: 0.64, blue: 0.30),
                                 Color(red: 0.35, green: 0.26, blue: 0.16)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: (bounds.end - bounds.start) * pxPerMin, height: 3)
                    .offset(x: bounds.start * pxPerMin, y: height - 14)
                    .opacity(0.75)
            }

            ForEach(Array(stride(from: 0, to: 24, by: 1)), id: \.self) { hour in
                let x = Double(hour) * 60 * (width / 1440)
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

            Text(date.formatted(.dateTime.weekday(.abbreviated).day()))
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
        let date = model.date(offset: offset)
        let calendar = Calendar.current
        return VStack(spacing: 2) {
            Text(date.formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(offset == 0 ? .primary : .secondary)
        }
        .frame(width: TimebarModel.drumCell, height: height)
        .contentShape(Rectangle())
        .onTapGesture { model.drumTap(offset: offset) }
    }

    /// Окно барабана: выбранная ячейка всегда по центру.
    private var frame: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color(white: 0.55), lineWidth: 1.5)
            .frame(width: TimebarModel.drumCell + 6, height: height - 4)
            .allowsHitTesting(false)
    }
}
