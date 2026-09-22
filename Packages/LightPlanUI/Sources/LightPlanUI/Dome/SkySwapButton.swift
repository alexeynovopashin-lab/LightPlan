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

    private func draw(context: GraphicsContext) {
        let on = Color.primary
        let off = Color.secondary.opacity(0.45)

        var sun = Path()
        sun.addEllipse(in: CGRect(x: 11.5 - 3.9, y: 11 - 3.9, width: 7.8, height: 7.8))
        context.stroke(sun, with: .color(mode == .sun ? on : off), lineWidth: 1.4)
        var rays = Path()
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
        for (a, b) in rayLines { rays.move(to: a); rays.addLine(to: b) }
        context.stroke(rays, with: .color(mode == .sun ? on : off),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

        var slash = Path()
        slash.move(to: CGPoint(x: 23.5, y: 23))
        slash.addLine(to: CGPoint(x: 30, y: 3))
        context.stroke(slash, with: .color(.secondary.opacity(0.3)),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

        // Полумесяц: то же тело, что у знака луны в ячейке барабана
        // (`MoonGlyph`, итерация 17) — не отдельная кривая ради 8 px значка.
        let moonRect = CGRect(x: 32, y: 3.4, width: 12.4, height: 12.4)
        let moon = MoonGlyph(fraction: 0.24).path(in: moonRect)
        context.fill(moon, with: .color(mode == .moon ? Color(red: 0.66, green: 0.74, blue: 0.85) : off))
    }
}
