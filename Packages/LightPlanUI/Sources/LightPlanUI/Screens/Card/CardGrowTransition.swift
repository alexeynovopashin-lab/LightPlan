import SwiftUI

// MARK: - Строка вырастает в карточку (30и.5; схема «раскрытие + стопки», вариант А)

/// Откуда растёт карточка: рамка строки списка дня на экране (общие координаты) и её имя с временем. Ставится при нажатии
/// на строку, живёт, пока карточка открыта, и по ней же карточка уходит обратно — «в свою строку».
struct CardGrowSource: Equatable {
    var frame: CGRect
    var time: String
    var name: String
}

/// Ход 0…1: плашка карточки растёт из рамки строки до всего слоя, содержимое карточки проявляется во второй половине пути, а
/// имя и время строки стоят на месте и гаснут (карточка рисует свои — рядом, не вместо). Одна кривая на вход и на выход:
/// при закрытии та же анимация идёт назад.
struct CardGrowReveal: ViewModifier, @preconcurrency Animatable {
    var p: CGFloat
    let source: CardGrowSource
    @Environment(\.colorScheme) private var scheme

    var animatableData: CGFloat {
        get { p }
        set { p = newValue }
    }

    /// Доля пути, с которой проявляется содержимое карточки, и до которой стоят слова строки.
    static let contentFrom: CGFloat = 0.35, contentTo: CGFloat = 0.8
    static func contentOpacity(_ p: CGFloat) -> CGFloat { min(1, max(0, (p - contentFrom) / (contentTo - contentFrom))) }
    static func ghostOpacity(_ p: CGFloat) -> CGFloat { 1 - min(1, max(0, p / 0.45)) }
    static let rowRadius: CGFloat = 12, cardRadius: CGFloat = 26

    func body(content: Content) -> some View {
        let pal = Palette(scheme)
        content
            .opacity(Self.contentOpacity(p))
            .background { GeometryReader { g in plate(g, pal) } }
            .overlay { GeometryReader { g in ghost(g, pal) } }
            .mask { GeometryReader { g in shape(g, grown: true) } }
    }

    private func rect(_ g: GeometryProxy) -> CGRect {
        let full = g.frame(in: .global)
        let f = source.frame
        func l(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        return CGRect(x: l(f.minX, full.minX) - full.minX, y: l(f.minY, full.minY) - full.minY,
                      width: l(f.width, full.width), height: l(f.height, full.height))
    }

    private func shape(_ g: GeometryProxy, grown: Bool) -> some View {
        let r = rect(g)
        return RoundedRectangle(cornerRadius: Self.rowRadius + (Self.cardRadius - Self.rowRadius) * p, style: .continuous)
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }

    /// Плашка под содержимым: цвет строки, переходящий в цвет страницы карточки.
    private func plate(_ g: GeometryProxy, _ pal: Palette) -> some View {
        let r = rect(g)
        return RoundedRectangle(cornerRadius: Self.rowRadius + (Self.cardRadius - Self.rowRadius) * p, style: .continuous)
            .fill(p < 0.5 ? pal.sheet4 : pal.surface)
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }

    /// Время и имя строки на её месте: те же поля 12 и кегль 16, что у строки списка дня.
    private func ghost(_ g: GeometryProxy, _ pal: Palette) -> some View {
        let f = source.frame
        let full = g.frame(in: .global)
        return HStack(spacing: 10) {
            Text(source.time).font(webFont(16)).monospacedDigit().foregroundStyle(pal.brassInk)
            Text(source.name).font(webFont(16, 500)).foregroundStyle(pal.ink).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 12 + 17 + 10)   // знак жанра строки — 17 pt и 10 зазора; сам знак под плашкой не рисуем
        .frame(width: f.width, height: f.height, alignment: .leading)
        .position(x: f.midX - full.minX, y: f.midY - full.minY)
        .opacity(Self.ghostOpacity(p))
        .allowsHitTesting(false)
    }
}

extension AnyTransition {
    /// Карточка вырастает из строки (0 — строка, 1 — слой); уходит тем же движением назад.
    static func cardGrow(_ source: CardGrowSource) -> AnyTransition {
        .modifier(active: CardGrowReveal(p: 0, source: source), identity: CardGrowReveal(p: 1, source: source))
    }
}
