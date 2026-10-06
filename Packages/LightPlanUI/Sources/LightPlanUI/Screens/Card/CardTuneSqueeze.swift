import SwiftUI

// MARK: - Сжатие блоков при входе в «ползунки» (итерация 27а.2)

/// Числа и кривые сжатия: веб `foldBlocks` / `unfoldBlocks`
/// (`transition: height .26s cubic-bezier(.25,1,.4,1)`, шапка `ord-cap-in .22s ease`).
enum CardTuneSqueeze {
    /// Высота строки перестановки.
    static let rowHeight: CGFloat = 56
    /// Зазор между строками колонки.
    static let gap: CGFloat = 8
    static let duration: Double = 0.26
    static let capDuration: Double = 0.22

    /// Анимация высоты; при «Уменьшении движения» её нет — мгновенная смена.
    static func animation(still: Bool) -> Animation? {
        still ? nil : .timingCurve(0.25, 1, 0.4, 1, duration: duration)
    }

    /// Проявление шапки строки (CSS `ease`); выход без затухания (`display: none`).
    static func capTransition(still: Bool) -> AnyTransition {
        still ? .identity : .asymmetric(
            insertion: AnyTransition.opacity.animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: capDuration)),
            removal: .identity)
    }

    /// Высота обёртки: `t` = 0 — естественная, 1 — строка 56 плюс зазор над ней.
    /// Блок нулевой высоты (выключенный, без начинки) растёт из нуля.
    static func height(natural: CGFloat, t: CGFloat, gap: CGFloat) -> CGFloat {
        let n = max(natural, 0), target = rowHeight + gap
        return n + (target - n) * t
    }
}

/// Раскладка обёртки блока: два потомка — начинка (естественной высоты, прижата
/// кверху) и шапка-строка (56 pt, на `gap · t` ниже кромки). Своя высота идёт за
/// `t`, которое SwiftUI интерполирует по кривой текущей транзакции, поэтому
/// естественную высоту не надо мерить и хранить: её отдаёт сама начинка на каждом кадре.
struct CardSqueezeLayout: Layout {
    var t: CGFloat
    var gap: CGFloat

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let content = subviews[0].sizeThatFits(.init(width: proposal.width, height: nil))
        // На полностью свёрнутом (t = 1) начинку не спрашиваем: её высота не нужна.
        let natural = t >= 1 ? 0 : content.height
        return CGSize(width: proposal.width ?? content.width,
                      height: CardTuneSqueeze.height(natural: natural, t: t, gap: gap))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        subviews[0].place(at: bounds.origin, anchor: .topLeading,
                          proposal: .init(width: bounds.width, height: nil))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + gap * t), anchor: .topLeading,
                          proposal: .init(width: bounds.width, height: CardTuneSqueeze.rowHeight))
    }
}
