import SwiftUI

/// Тумблер солнце/луна: одна кнопка ИЛИ/ИЛИ, горит выбранное — порт
/// `#skySwap` (веб), `viewBox 0 0 52 26`.
struct SkySwapButton: View {
    @Binding var mode: DomeSkyMode

    var body: some View {
        Button {
            mode = mode == .sun ? .moon : .sun
        } label: {
            Canvas { context, size in
                let scale = size.width / 52
                context.scaleBy(x: scale, y: scale)
                draw(context: context)
            }
            .frame(width: 52, height: 26)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Солнце или луна"))
    }

    @Environment(\.colorScheme) private var colorScheme

    /// Цвета `.sky-swap` веба: выбранное светило — латунь или лунный, прочее
    /// — `--ink-7`, косая черта — `--rail-5`; линия 1,5 и у луны тоже (у веба
    /// это контур знака `moon` в масштабе 0,62, не заливка).
    private func draw(context: GraphicsContext) {
        let pal = Palette(colorScheme)
        let sunInk = mode == .sun ? pal.brass : pal.ink7
        let line = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)

        var sun = Path()
        sun.addEllipse(in: CGRect(x: 11.5 - 3.9, y: 11 - 3.9, width: 7.8, height: 7.8))
        let rayLines: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 11.5, y: 3.7), CGPoint(x: 11.5, y: 5.7)),
            (CGPoint(x: 11.5, y: 16.3), CGPoint(x: 11.5, y: 18.3)),
            (CGPoint(x: 4.2, y: 11), CGPoint(x: 6.2, y: 11)),
            (CGPoint(x: 16.8, y: 11), CGPoint(x: 18.8, y: 11)),
            (CGPoint(x: 6.3, y: 5.8), CGPoint(x: 7.7, y: 7.2)),
            (CGPoint(x: 15.3, y: 14.8), CGPoint(x: 16.7, y: 16.2)),
            (CGPoint(x: 6.3, y: 16.2), CGPoint(x: 7.7, y: 14.8)),
            (CGPoint(x: 15.3, y: 7.2), CGPoint(x: 16.7, y: 5.8)),
        ]
        for (a, b) in rayLines { sun.move(to: a); sun.addLine(to: b) }
        context.stroke(sun, with: .color(sunInk), style: line)

        var slash = Path()
        slash.move(to: CGPoint(x: 23.5, y: 23))
        slash.addLine(to: CGPoint(x: 30, y: 3))
        context.stroke(slash, with: .color(pal.rail5), style: line)

        // Знак `moon` библиотеки (итерация 15) в том же масштабе, что у веба:
        // `translate(32 3.4) scale(0.62)`, своя толщина 2,42 → 1,5 на экране.
        if let moon = IconArt.art(namespace: "common", name: "moon", in: IconLibrary.common)?.parts.first?.path {
            let placed = moon.applying(CGAffineTransform(scaleX: 0.62, y: 0.62).concatenating(
                CGAffineTransform(translationX: 32, y: 3.4)))
            context.stroke(placed, with: .color(mode == .moon ? pal.moon : pal.ink7), style: line)
        }
    }
}
