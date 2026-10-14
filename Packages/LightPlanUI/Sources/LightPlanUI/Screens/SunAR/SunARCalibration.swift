import SwiftUI
import LightPlanCore

/// Экран калибровки компаса «восьмёркой» перед первым включением AR (шаг 29.8в.2).
///
/// Шкала — `CompassCalibration.progress`: качество магнитного поля от системы и устойчивость курса, а не таймер.
/// Восьмёрка рисуется лемнискатой; точка бежит по ней, показывая, как водить телефоном. При «Уменьшении движения»
/// точка не бежит: статичная схема со стрелками и тот же текст.
struct SunARCalibrationView: View {
    let progress: Double
    let phase: CompassCalibration.Phase
    /// Точность поля уже годится — осталось подержать курс (подсказка меняется).
    let accuracyEnough: Bool
    let lexicon: Lexicon
    let onSkip: () -> Void

    private var t: Lexicon { lexicon }

    var body: some View {
        ZStack {
            // Фон — сплошной тёмный, без просвета: под калибровкой не нужен ни кадр камеры, ни дуга, ни их подписи.
            Color(white: 0.05).ignoresSafeArea()
                .shotNode("ar.cal.screen", text: String(describing: phase))
            VStack(spacing: 22) {
                Spacer(minLength: 0)
                Text(t.t("ar.calTitle"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(SunARInk.light)
                figureEight
                    .frame(width: 240, height: 120)
                    .accessibilityHidden(true)
                if phase != .noSensor {
                    scale
                }
                Text(message)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SunARInk.light)
                    .padding(.horizontal, 32)
                    .shotNode("ar.cal.text", text: message)
                Spacer(minLength: 0)
                Button(action: onSkip) {
                    Text(t.t("ar.calSkip")).font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SunARInk.light)
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                        .overlay(Capsule().stroke(SunARInk.light.opacity(0.6), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .shotNode("ar.cal.skip", text: t.t("ar.calSkip"))
                .padding(.bottom, 28)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var message: String {
        switch phase {
        case .noSensor: return t.t("ar.calNoSensor")
        case .ready: return t.t("ar.calReady")
        case .measuring: return accuracyEnough ? t.t("ar.calHold") : t.t("ar.calHint")
        }
    }

    // MARK: - Шкала

    private var scale: some View {
        let p = min(1, max(0, progress))
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.22))
            GeometryReader { g in
                Capsule().fill(SunARInk.light).frame(width: max(8, g.size.width * p))
            }
        }
        .frame(width: 240, height: 8)
        .animation(PlanMotion.pick(.linear(duration: 0.12)), value: p)
        .accessibilityElement()
        .accessibilityLabel(t.t("ar.calTitle"))
        .accessibilityValue("\(Int((p * 100).rounded())) %")
        .shotNode("ar.cal.scale", text: String(format: "%.2f", p))
    }

    // MARK: - Восьмёрка

    @ViewBuilder
    private var figureEight: some View {
        if PlanMotion.still {
            staticFigure
        } else {
            TimelineView(.animation) { tl in
                // Один круг по восьмёрке за 4 секунды.
                let phase = (tl.date.timeIntervalSinceReferenceDate / 4).truncatingRemainder(dividingBy: 1)
                movingFigure(phase: phase)
            }
        }
    }

    private func movingFigure(phase: Double) -> some View {
        GeometryReader { g in
            let dot = Lemniscate.point(t: phase * 2 * .pi, in: g.size)
            ZStack {
                Lemniscate().stroke(SunARInk.light.opacity(0.45), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Circle().fill(SunARInk.sunFill).frame(width: 18, height: 18)
                    .overlay(Circle().stroke(SunARInk.light, lineWidth: 2))
                    .position(dot)
            }
        }
    }

    /// Без движения: та же восьмёрка и две стрелки по направлению обхода.
    private var staticFigure: some View {
        GeometryReader { g in
            ZStack {
                Lemniscate().stroke(SunARInk.light.opacity(0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                ForEach([0.18, 0.68], id: \.self) { k in
                    let t = k * 2 * .pi
                    let p = Lemniscate.point(t: t, in: g.size)
                    let q = Lemniscate.point(t: t + 0.05, in: g.size)
                    let angle = atan2(q.y - p.y, q.x - p.x)
                    Triangle()
                        .fill(SunARInk.light)
                        .frame(width: 14, height: 14)
                        .rotationEffect(.radians(angle + .pi / 2))
                        .position(p)
                }
            }
        }
    }
}

/// Лемниската Бернулли — восьмёрка, лежащая на боку.
struct Lemniscate: Shape {
    static func point(t: Double, in size: CGSize) -> CGPoint {
        let a = size.width / 2 - 8
        let d = 1 + sin(t) * sin(t)
        let x = a * cos(t) / d
        let y = a * sin(t) * cos(t) / d * 1.45
        return CGPoint(x: size.width / 2 + x, y: size.height / 2 + y)
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n = 160
        for i in 0...n {
            let q = Lemniscate.point(t: Double(i) / Double(n) * 2 * .pi, in: rect.size)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        return p
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
