import SwiftUI

/// Глубина светлой темы (28к.3, вариант «Б», Алексей 12.11): белая плашка лежит на сером фоне с мягкой тенью под собой и
/// светлым кантом по краю, выбранное выпуклое, под плашками «Съёмок» и карточки — стекло. Принцип «Светлая тема — не
/// инверсия»: блик белый, тень тёмная в обеих темах. **В тёмной теме все приёмы ничего не добавляют** (пиксели прежние):
/// там плашку отделяет тон, как и раньше.
///
/// Числа живут здесь, а не в экранах: экран зовёт `.plateStyle(pal, radius:)` / `.raisedStyle(pal, radius:)`.
public enum PlateTokens {
    /// 30з.2 (слово Алексея 13.11: «убираем тени от блоков на светлой теме»): тени плашек светлой темы выключены — плашку от страницы
    /// отделяют тон фона и светлый кант. Числа теней ниже целы: `true` вернёт их.
    public static let lightShadowsOn = false

    /// Чернила тени и чёрных элементов («+ Съёмка», выбранный день).
    public static let shadowInk = Color.black
    public static let blackFill = Color(hex: 0x141416)

    /// Светлый кант плашки: белый, 1,5 pt (тот же у подложки месяца вместо тёмного волоска).
    public static let rimColor = Color.white.opacity(0.95)
    public static let rimWidth: CGFloat = 1.5

    /// Мягкая тень плашки: широкая 0,10 / радиус 16 / вниз 8 и контактная 0,05 / 1 / 1.
    public static let plate = Shadow(opacity: 0.10, radius: 16, y: 8, contactOpacity: 0.05)
    /// Тень выбранного и поднятого (сегмент, день, «Запланировать съёмку»): короче и плотнее.
    public static let raised = Shadow(opacity: 0.16, radius: 5, y: 2, contactOpacity: 0.10)

    /// Белая вуаль плашек «Съёмок» и карточки: под ней стекло `.glassEffect(.regular)`.
    public static let glassVeil = 0.72

    public struct Shadow: Sendable, Equatable {
        public let opacity: Double
        public let radius: CGFloat
        public let y: CGFloat
        /// Контактная тень: радиус 1, вниз 1.
        public let contactOpacity: Double
    }
}

public extension View {
    /// Плашка светлой темы: тень снаружи контура (внутри плашка не темнеет), светлый кант, при `glass` — системное стекло
    /// под полупрозрачной заливкой. В тёмной теме — сам экран без изменений.
    @ViewBuilder
    func plateStyle(_ pal: Palette, radius: CGFloat, glass: Bool = false) -> some View {
        if pal.dark { self } else { modifier(PlateModifier(radius: radius, glass: glass, token: PlateTokens.plate, rim: true)) }
    }

    /// Выбранное и поднятое в светлой теме: короткая тень под белым (выпуклое). В тёмной теме и при `on == false` — ничего.
    @ViewBuilder
    func raisedStyle(_ pal: Palette, radius: CGFloat, on: Bool = true) -> some View {
        if on, !pal.dark, PlateTokens.lightShadowsOn { modifier(PlateModifier(radius: radius, glass: false, token: PlateTokens.raised, rim: false)) } else { self }
    }
}

/// Тень только снаружи контура (как у подложки месяца): полупрозрачная заливка над ней не темнеет.
private struct PlateModifier: ViewModifier {
    let radius: CGFloat
    let glass: Bool
    let token: PlateTokens.Shadow
    let rim: Bool

    func body(content: Content) -> some View {
        let r = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                // Тень у встроенного стекла своя и падает наружу: в светлой теме её срезаем по контуру (слово Алексея 16.11 «вернулись тени»).
                if glass { Color.clear.glassEffect(.regular, in: r).clipShape(r) }
            }
            .overlay {
                if rim { r.strokeBorder(PlateTokens.rimColor, lineWidth: PlateTokens.rimWidth).allowsHitTesting(false) }
            }
            .background {
                if PlateTokens.lightShadowsOn {
                ZStack {
                    r.fill(PlateTokens.shadowInk).shadow(color: PlateTokens.shadowInk.opacity(token.opacity), radius: token.radius, y: token.y)
                    r.fill(PlateTokens.shadowInk).shadow(color: PlateTokens.shadowInk.opacity(token.contactOpacity), radius: 1, y: 1)
                }
                .mask {
                    ZStack {
                        Rectangle().padding(-60)
                        r.blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
                .allowsHitTesting(false)
                }
            }
    }
}

public extension View {
    /// Тень блока (плашка, подложка месяца, обложка мудборда, панель «Отменить»): только в тёмной теме; в светлой выключена (30з.2).
    func blockShadow(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        modifier(BlockShadowModifier(color: color, radius: radius, x: x, y: y))
    }
}

private struct BlockShadowModifier: ViewModifier {
    let color: Color, radius: CGFloat, x: CGFloat, y: CGFloat
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        if scheme == .dark || PlateTokens.lightShadowsOn { content.shadow(color: color, radius: radius, x: x, y: y) } else { content }
    }
}

public extension View {
    /// 30з.2а (слово Алексея 13.11: «плашка календаря мне нравится больше, на экране свет плашки слишком светлые»): плашка «Света» —
    /// того же вида, что подложка месяца на «Съёмках» (`PlannerMonthView`): заливка `pal.sheetGlass` над системным стеклом
    /// `.glassEffect(.regular)`, скругление 22, край — волосок `pal.hairline` в тёмной и белый кант `PlateTokens.rimColor` в светлой.
    /// Тени снаружи нет в обеих темах (в светлой — слово Алексея 13.11; в тёмной у месяца тень есть, здесь её не взяли: плашки стоят
    /// впритык друг к другу и к кромке экрана). Нарисованного блика нет (`Tools/check_glass.sh`).
    ///
    /// `hush` (0…1): под стеклом тон страницы с такой плотностью — плашка, под которой прокручивается чужое содержимое («время» на «Свете»,
    /// 30з.2), не показывает его резко сквозь стекло.
    func glassPlate(_ pal: Palette, radius: CGFloat = GlassPlateTokens.radius, hush: Double = 0) -> some View {
        let r = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return modifier(GlassPlateModifier(pal: pal, shape: r, hush: hush))
    }
}

public enum GlassPlateTokens {
    /// Скругление — то же, что у подложки месяца (`MonthMetrics.plateRadius`).
    public static let radius: CGFloat = 22
}

private struct GlassPlateModifier: ViewModifier {
    let pal: Palette
    let shape: RoundedRectangle
    let hush: Double

    func body(content: Content) -> some View {
        content
            .background { shape.fill(pal.sheetGlass) }
            // Тень у встроенного стекла своя и падает наружу: срез по контуру её убирает (и в светлой, и в тёмной).
            .background { Color.clear.glassEffect(.regular, in: shape).clipShape(shape) }
            .background { if hush > 0 { shape.fill(pal.surface.opacity(hush)) } }
            .overlay { shape.strokeBorder(pal.dark ? pal.hairline : PlateTokens.rimColor, lineWidth: pal.dark ? 1 : PlateTokens.rimWidth).allowsHitTesting(false) }
    }
}

public extension View {
    /// Светлая тема (30з.2): у встроенного стекла есть своя мягкая тень вокруг контура; срез по форме оставляет кант и убирает тень.
    /// Тёмная — стекло как есть.
    func flatGlass<S: Shape>(_ shape: S, light: Bool) -> some View {
        modifier(FlatGlassModifier(shape: shape, light: light))
    }
}

private struct FlatGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let light: Bool
    func body(content: Content) -> some View {
        if light { content.clipShape(shape) } else { content }
    }
}
