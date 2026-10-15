import SwiftUI

/// Стеклянный диск и стеклянная плашка поверх живого кадра (шаги 29.8в.3, 29.8в.4, экран AR).
///
/// Рецепт — тот же, что у ручки таймбара и окна барабана: прозрачное стекло без размытия, середина один к
/// одному, у кромки гнётся (`GlassOptics`, `Glass.metal`), блик сверху, волосок чернил снаружи, тень только
/// снаружи (`OuterShadow`). Рецепт живёт здесь, в `Timebar/`: `Tools/check_glass.sh` нарисованный блик вне
/// этой папки не пускает.
///
/// С 29.8в.4 метка — сплошной диск, а не кольцо, и лежит ПОВЕРХ дуги и подписей (слово Алексея 14.10: «бубликом
/// и за линией, выглядит плохо»). Поэтому рецепт в двух слоях:
/// - `LensRefraction` — гнутый у кромки кадр; лежит ПОД дугой. На телефоне его рисует слой Metal (`SunARLens`),
///   в симуляторе и без камеры — этот вид из копии фона;
/// - `LensGlass` — налёт цвета, блик, волосок и тень; лежит НАД дугой и подписями, дуга видна сквозь стекло.
struct LensGlass: View {
    /// Диаметр диска, pt.
    let diameter: CGFloat
    /// Оттенок стекла: тёплый у солнца, серебристый у луны.
    let tint: Color
    /// Прозрачность налёта: сквозь него просвечивает кадр и дуга.
    var tintOpacity: Double = SunARInk.glassTintOpacity
    var fade: Double = 1
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme)
        let ring = SunARInk.rim(for: diameter)
        ZStack {
            Circle().fill(tint.opacity(tintOpacity))
            // Налёт прозрачного стекла.
            Circle().fill(pal.glassFill)
            // Кромка: сверху свет, снизу тень толщины — как у кольца ручки.
            Circle().inset(by: 0.5)
                .stroke(LinearGradient(stops: [.init(color: pal.glassShine, location: 0),
                                               .init(color: pal.glassShine.opacity(0), location: 0.35),
                                               .init(color: .black.opacity(0), location: 0.65),
                                               .init(color: .black.opacity(0.28), location: 1)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            // Внутренний волосок: где кончается гнущая кромка и начинается чистая середина.
            Circle().inset(by: ring).stroke(tint.opacity(0.55), lineWidth: 0.75)
        }
        .overlay(Circle().inset(by: -1).stroke(pal.inkA22, lineWidth: 1))
        .frame(width: diameter, height: diameter)
        .background(OuterShadow(shape: Circle(), color: .black.opacity(0.45), radius: 5.5, y: 3))
        .opacity(fade)
        .allowsHitTesting(false)
    }
}

/// Кромка диска, гнущая кадр, для случая, когда кадр рисует SwiftUI (небо без камеры): копия фона под диском,
/// сдвиг у кромки — тот же шейдер, что у ручки (`glassRing`); середина один к одному.
struct LensRefraction: View {
    let diameter: CGFloat
    /// Кадр под диском. Его кромка и гнёт.
    let backdrop: AnyView
    /// Левый верхний угол диска в окне экрана — чтобы фон под ним встал на то же место.
    let origin: CGPoint
    /// Размер окна экрана — по нему фон под диском растягивается так же, как сам фон.
    let screen: CGSize
    var fade: Double = 1
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let r = diameter / 2
        backdrop
            .frame(width: screen.width, height: screen.height)
            .offset(x: -origin.x, y: -origin.y)
            .frame(width: diameter, height: diameter, alignment: .topLeading)
            .clipped()
            .layerEffect(GlassOptics.lens(center: CGPoint(x: r, y: r), radius: r, width: SunARInk.rim(for: diameter),
                                          scheme: colorScheme),
                         maxSampleOffset: CGSize(width: GlassOptics.lensShift, height: GlassOptics.lensShift))
            .clipShape(Circle())
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
