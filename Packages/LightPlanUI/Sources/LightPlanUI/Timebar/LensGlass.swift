import SwiftUI

/// Стеклянная линза и стеклянная плашка поверх живого кадра (шаг 29.8в.3, экран AR).
///
/// Рецепт — тот же, что у ручки таймбара и окна барабана: прозрачное стекло без размытия, середина один к
/// одному, у кромки гнётся (`GlassOptics`, `Glass.metal`), блик сверху, волосок чернил снаружи, тень только
/// снаружи (`OuterShadow`). Рецепт живёт здесь, в `Timebar/`: `Tools/check_glass.sh` нарисованный блик вне
/// этой папки не пускает.
///
/// Линза не закрывает то, на что наведена: середина пустая, настоящее светило видно в ней как есть.
struct LensGlass: View {
    /// Диаметр линзы, pt.
    let diameter: CGFloat
    /// Цвет состояния света этого момента: кольцо окрашено им.
    let tint: Color
    /// Ширина кольца с кромкой, pt.
    var ring: CGFloat = 7
    /// Прозрачность кольца: сквозь него просвечивает кадр.
    var tintOpacity: Double = 0.5
    /// Кадр под линзой, когда его можно подать в шейдер (SwiftUI-фон без камеры): кромка гнёт именно его.
    /// У живого превью камеры (UIKit) шейдер ничего не читает — там `nil`, кромка без изгиба.
    var backdrop: AnyView?
    /// Левый верхний угол линзы в окне экрана — чтобы фон под ней встал на то же место.
    var origin: CGPoint = .zero
    /// Размер окна экрана — по нему фон под линзой растягивается так же, как сам фон.
    var screen: CGSize = .zero
    var fade: Double = 1
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme)
        let r = diameter / 2
        ZStack {
            if let backdrop {
                // Копия фона под линзой, изогнутая у кромки; середина не рисуется (маска-кольцо), поэтому
                // всё, что лежит над кадром — дуга, подписи, — видно сквозь неё без искажений.
                backdrop
                    .frame(width: screen.width, height: screen.height)
                    .offset(x: -origin.x, y: -origin.y)
                    .frame(width: diameter, height: diameter, alignment: .topLeading)
                    .clipped()
                    .layerEffect(GlassOptics.lens(center: CGPoint(x: r, y: r), radius: r, width: ring, scheme: colorScheme),
                                 maxSampleOffset: CGSize(width: GlassOptics.lensShift, height: GlassOptics.lensShift))
                    .mask(Circle().strokeBorder(.white, lineWidth: ring))
            }
            // Налёт цвета света на кольце.
            Circle().strokeBorder(tint.opacity(tintOpacity), lineWidth: ring)
            // Налёт прозрачного стекла.
            Circle().strokeBorder(pal.glassFill, lineWidth: ring)
            // Кромка: сверху свет, снизу тень толщины — как у кольца ручки.
            Circle().inset(by: 0.5)
                .stroke(LinearGradient(stops: [.init(color: pal.glassShine, location: 0),
                                               .init(color: pal.glassShine.opacity(0), location: 0.35),
                                               .init(color: .black.opacity(0), location: 0.65),
                                               .init(color: .black.opacity(0.28), location: 1)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            // Внутренний волосок: где кончается кольцо и начинается чистая середина.
            Circle().inset(by: ring).stroke(tint.opacity(0.7), lineWidth: 0.75)
        }
        .overlay(Circle().inset(by: -1).stroke(pal.inkA22, lineWidth: 1))
        .frame(width: diameter, height: diameter)
        .background(OuterShadow(shape: Circle(), color: .black.opacity(0.45), radius: 5.5, y: 3))
        .opacity(fade)
        .allowsHitTesting(false)
    }
}

/// Стеклянная плашка подписи: тёмная подложка (на ней считан контраст текста), кромка света сверху и волосок
/// чернил — стекло без размытия, как ручка таймбара.
struct GlassPlate<S: Shape>: View {
    let shape: S
    /// Непрозрачность тёмной подложки под текстом (`SunARInk.plateOpacity`).
    let opacity: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme)
        shape.fill(Color.black.opacity(opacity))
            .overlay(shape.stroke(LinearGradient(
                stops: [.init(color: pal.glassShine, location: 0),
                        .init(color: pal.glassShine.opacity(0), location: 0.45)],
                startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(shape.stroke(pal.inkA22, lineWidth: 0.5))
            .background(OuterShadow(shape: shape, color: .black.opacity(0.35), radius: 3, y: 2))
    }
}
