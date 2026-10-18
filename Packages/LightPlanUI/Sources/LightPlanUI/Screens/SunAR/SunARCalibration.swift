import SwiftUI
import LightPlanCore

/// Экран калибровки компаса «восьмёркой» (шаги 29.8в.2, 29.8в.8).
///
/// Шкала — охват движения по гироскопу (`MotionCoverage`), а не время и не точность компаса. Точность компаса
/// показана отдельной строкой так, как её сообщает система: градусы погрешности, какой была при входе и какая сейчас.
/// Экран сам не закрывается: выход — «Готово» (когда движение полное и точность не хуже порога) или «Пропустить»;
/// в `.notImproved` добавляется «Ещё раз».
struct SunARCalibrationView: View {
    let calibration: CompassCalibration
    let lexicon: Lexicon
    let onDone: () -> Void
    let onSkip: () -> Void
    let onRetry: () -> Void

    private var t: Lexicon { lexicon }
    private var phase: CompassCalibration.Phase { calibration.phase }

    var body: some View {
        ZStack {
            // Фон — сплошной тёмный, без просвета: под калибровкой не нужен ни кадр камеры, ни дуга, ни их подписи.
            Color(white: 0.05).ignoresSafeArea()
                .shotNode("ar.cal.screen", text: String(describing: phase))
            VStack(spacing: 0) {
                GeometryReader { g in
                    ScrollView {
                        content
                            .frame(maxWidth: .infinity, minHeight: g.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                buttons
                    .padding(.bottom, 20)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Содержимое

    private var content: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 8)
            Text(t.t("ar.calTitle"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SunARInk.light)
                .multilineTextAlignment(.center)
                .shotNode("ar.cal.title", text: t.t("ar.calTitle"))
            figureEight
                .frame(width: 220, height: 128)
                .accessibilityHidden(true)
            if phase != .noSensor {
                scale
                accuracy
                #if DEBUG
                diagnostics
                #endif
            }
            message
            if let hint = hintText {
                Text(hint)
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SunARInk.sunFill)
                    .padding(.horizontal, 28)
                    .fixedSize(horizontal: false, vertical: true)
                    .shotNode("ar.cal.hint", text: hint)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var message: some View {
        switch phase {
        case .noSensor:
            para(t.t("ar.calNoSensor"), node: "ar.cal.text")
        case .measuring:
            VStack(spacing: 8) {
                para(t.t("ar.calHow"), node: "ar.cal.text")
                para(t.t("ar.calWhy"), dim: true, node: "ar.cal.why")
            }
        case .checking:
            para(t.t("ar.calChecking"), node: "ar.cal.text")
        case .ready:
            para(t.t("ar.calReadyMsg"), node: "ar.cal.text")
        case .notImproved:
            para(calibration.accuracy?.isKnown == true ? t.t("ar.calNotImproved") : t.t("ar.calNoAnswer"),
                 node: "ar.cal.text")
        }
    }

    private func para(_ s: String, dim: Bool = false, node: String) -> some View {
        Text(s)
            .font(.system(size: dim ? 13 : 15))
            .multilineTextAlignment(.center)
            .foregroundStyle(SunARInk.light.opacity(dim ? 0.7 : 1))
            .fixedSize(horizontal: false, vertical: true)
            .shotNode(node, text: s)
    }

    /// Подсказка, пока шкала стоит: чего недостаёт движению.
    private var hintText: String? {
        switch calibration.hint {
        case .tiltMore: return t.t("ar.calHintTilt")
        case .tiltSide: return t.t("ar.calHintSide")
        case .tiltFront: return t.t("ar.calHintFront")
        case .turnMore: return t.t("ar.calHintTurn")
        case .slower: return t.t("ar.calHintSlow")
        case nil: return nil
        }
    }

    // MARK: - Шкала движения

    private var scale: some View {
        let p = min(1, max(0, calibration.progress))
        return VStack(spacing: 6) {
            HStack {
                Text(t.t("ar.calMove"))
                Spacer(minLength: 8)
                Text("\(calibration.percent) %").monospacedDigit()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(SunARInk.light)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                GeometryReader { g in
                    Capsule().fill(SunARInk.light).frame(width: max(p > 0 ? 8 : 0, g.size.width * p))
                }
            }
            .frame(height: 8)
        }
        .frame(width: 260)
        .animation(PlanMotion.pick(.linear(duration: 0.12)), value: p)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t.t("ar.calMove"))
        .accessibilityValue("\(calibration.percent) %")
        .shotNode("ar.cal.scale", text: String(format: "%.2f", p))
    }

    // MARK: - Точность от системы

    /// Погрешность курса, как её отдаёт система: «была ±25°, сейчас ±8°». Число не округляется вверх и не
    /// придумывается: нет ответа — так и сказано.
    private var accuracy: some View {
        let cur = calibration.accuracy
        let line: String
        if let now = cur?.degrees {
            if let was = calibration.entryAccuracy?.degrees, Int(was.rounded()) != Int(now.rounded()) {
                line = t.t("ar.calAccFromTo", ["from": "\(Int(was.rounded()))", "to": "\(Int(now.rounded()))"])
            } else {
                line = t.t("ar.calAcc", ["n": "\(Int(now.rounded()))"])
            }
        } else if let level = cur?.level {
            line = t.t("ar.calAccLevel", ["level": t.t("ar.calLvl\(level.rawValue)")])
        } else {
            line = t.t("ar.calAccNone")
        }
        return VStack(spacing: 2) {
            Text(line)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SunARInk.light)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .shotNode("ar.cal.acc", text: line)
            if cur?.degrees != nil {
                Text(t.t("ar.calNeed", ["n": "\(Int(CompassCalibration.requiredDegrees))"]))
                    .font(.system(size: 12))
                    .foregroundStyle(SunARInk.light.opacity(0.7))
            }
        }
    }

    #if DEBUG
    /// Только в отладочной сборке: накопленное отклонение по ячейкам, градусы — видно, какая не закрывается
    /// (наклон в четыре стороны: нужно 15°; размах поворота: нужно 40°).
    private var diagnostics: some View {
        let m = calibration.coverage
        func d(_ k: MotionCoverage.Cell) -> String { String(format: "%.0f", m.degrees(k)) }
        let line = "F \(d(.tiltForward)) B \(d(.tiltBack)) L \(d(.tiltLeft)) R \(d(.tiltRight)) / \(Int(MotionCoverage.tiltFull))° · turn \(d(.turn)) / \(Int(MotionCoverage.turnFull))°"
        return Text(line)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(SunARInk.light.opacity(0.45))
            .shotNode("ar.cal.diag", text: line)
    }
    #endif

    // MARK: - Кнопки

    private var buttons: some View {
        VStack(spacing: 10) {
            if phase != .noSensor {
                HStack(spacing: 10) {
                    if phase == .notImproved {
                        pill(t.t("ar.calRetry"), node: "ar.cal.retry", action: onRetry)
                    }
                    pill(t.t("ar.calReady"), prominent: true, enabled: calibration.canFinish,
                         node: "ar.cal.done", action: onDone)
                }
            }
            pill(t.t("ar.calSkip"), node: "ar.cal.skip", action: onSkip)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private func pill(_ title: String, prominent: Bool = false, enabled: Bool = true, node: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(prominent && enabled ? Color.black : SunARInk.light)
                .frame(minWidth: 120, minHeight: SunARInk.touch)
                .padding(.horizontal, 12)
                .background(Capsule().fill(prominent && enabled ? SunARInk.light : Color.white.opacity(0.16)))
                .overlay(Capsule().stroke(SunARInk.light.opacity(prominent && enabled ? 0 : 0.6), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        // Недоступная «Готово» остаётся читаемой (белое на тёмном), но тусклой: видно, чего ждём.
        .opacity(enabled ? 1 : 0.45)
        .shotNode(node, text: enabled ? title : "\(title) (off)")
    }

    // MARK: - Восьмёрка с поворотом кисти

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

    /// Телефон идёт по восьмёрке; кисть поворачивает его: крен ±32° и наклон от себя / на себя.
    private func movingFigure(phase: Double) -> some View {
        GeometryReader { g in
            let angle = phase * 2 * .pi
            let at = Lemniscate.point(t: angle, in: g.size)
            ZStack {
                Lemniscate().stroke(SunARInk.light.opacity(0.35), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                PhoneGlyph()
                    .rotationEffect(.degrees(32 * sin(angle)))
                    .rotation3DEffect(.degrees(28 * sin(2 * angle)), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                    .position(at)
            }
        }
    }

    /// Без движения: восьмёрка, две стрелки обхода и телефон, наклонённый в обе стороны (две копии).
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
                PhoneGlyph().rotationEffect(.degrees(-30))
                    .position(Lemniscate.point(t: 0, in: g.size))
                PhoneGlyph().rotationEffect(.degrees(30))
                    .position(Lemniscate.point(t: .pi, in: g.size))
            }
        }
    }
}

/// Телефон на схеме: скруглённый прямоугольник с камерой.
private struct PhoneGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.black)
            .frame(width: 22, height: 40)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(SunARInk.light, lineWidth: 2))
            .overlay(alignment: .top) {
                Circle().fill(SunARInk.sunFill).frame(width: 5, height: 5).padding(.top, 5)
            }
    }
}

/// Лемниската Бернулли — восьмёрка, лежащая на боку.
struct Lemniscate: Shape {
    static func point(t: Double, in size: CGSize) -> CGPoint {
        let a = size.width / 2 - 14
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
