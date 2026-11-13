import SwiftUI
import LightPlanCore

/// 30з.2 (макет 4 Алексея 12.11): «расширил зону синего неба из-под купола, затемнил чёрным радиальным градиентом по периметру
/// (в углах)». Подложка «шапка + купол»: тот же градиент неба, что рисовал купол (`DomeSky`: зенит → горизонт), но на всю ширину
/// и вверх до края экрана; под горизонтом небо за полсотни точек стекает в цвет страницы — там лежит стекло первой плашки.
///
/// Купол свой основной градиент больше не рисует (`DomeView.skyFill`): небо одно, виньетка лежит и снаружи, и внутри — без шва.
/// Координаты — рамки «шапка + купол» (`zoneSize`), ось y вниз от её верха; выше верха подложка продолжается на `above`, чтобы
/// закрыть безопасную зону и оттяжку прокрутки.
///
/// Тёмная тема: виньетка чёрная, 0,62 в углах. Светлая (решение исполнителя, Алексей сказал «на ваше усмотрение»): небо ночью — цвет
/// страницы, поэтому подложка проявляется вместе с небом (`presence`, астрономическая ночь −18° … −12°); виньетка серая и тихая — 0,14
/// в углах: чёрная 0,6 на бледном дневном небе была бы грязью.
struct LightSkyBackdrop: View {
    let sky: DomeSky
    let pal: Palette
    /// Рамка «шапка + купол» в содержимом прокрутки и положение зенита и горизонта дуги в ней.
    let zoneSize: CGSize
    let zenithY: CGFloat
    let horizonY: CGFloat
    /// Сколько точек безопасной зоны сверху (виньетка считается по видимому экрану).
    let safeTop: CGFloat
    /// 0…1: в светлой теме небо проявляется из цвета страницы по мере того, как солнце выходит из астрономической ночи.
    let presence: Double

    static let above: CGFloat = 400
    /// Небо стекает в цвет страницы на столько точек ниже горизонта (там стекло первой плашки).
    static let fade: CGFloat = 64

    /// Сила виньетки в углах (низ). Верхние углы темнее вдвое: вторая такая же виньетка над верхней половиной (слово Алексея 13.11:
    /// «затемняющий градиент в верхних углах надо усилить»): 0,62 → ≈ 0,86 в тёмной, 0,14 → ≈ 0,26 в светлой; радиус и середина те же.
    static func vignetteStrength(dark: Bool) -> Double { dark ? 0.62 : 0.14 }

    var body: some View {
        let top = -Self.above
        let end = horizonY + Self.fade
        let total = end - top
        let loc = { (y: CGFloat) -> CGFloat in min(1, max(0, (y - top) / total)) }
        let vTop = -safeTop
        let vHeight = horizonY + Self.fade - vTop
        ZStack(alignment: .top) {
            LinearGradient(stops: [
                .init(color: Color(sky.zenith), location: 0),
                .init(color: Color(sky.zenith), location: loc(zenithY)),
                .init(color: Color(sky.horizon), location: loc(horizonY)),
                .init(color: pal.surface, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .opacity(pal.dark ? 1 : presence)
            // Виньетка: эллипс по видимому экрану (от края экрана до низа подложки), центр чуть выше середины; к низу сходит на нет
            // вместе с небом.
            EllipticalGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.42),
                .init(color: Color.black.opacity(Self.vignetteStrength(dark: pal.dark) * (pal.dark ? 1 : presence)), location: 1),
            ], center: UnitPoint(x: 0.5, y: 0.46), startRadiusFraction: 0, endRadiusFraction: 0.78)
            .frame(width: zoneSize.width, height: vHeight)
            .mask {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: (horizonY - vTop) / vHeight),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .offset(y: Self.above + vTop)
            // Добавка только в верхних углах: тот же эллипс ещё раз, под маской «сверху до 60 % высоты зоны».
            EllipticalGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.42),
                .init(color: Color.black.opacity(Self.vignetteStrength(dark: pal.dark) * (pal.dark ? 1 : presence)), location: 1),
            ], center: UnitPoint(x: 0.5, y: 0.46), startRadiusFraction: 0, endRadiusFraction: 0.78)
            .frame(width: zoneSize.width, height: vHeight)
            .mask {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.22),
                    .init(color: .clear, location: 0.6),
                ], startPoint: .top, endPoint: .bottom)
            }
            .offset(y: Self.above + vTop)
        }
        .frame(width: zoneSize.width, height: total, alignment: .top)
        .offset(y: top)
        .allowsHitTesting(false)
    }
}
