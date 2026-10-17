import SwiftUI

/// Стеклянный диск и стеклянная плашка поверх живого кадра (шаги 29.8в.3, 29.8в.4, 29.8в.5, экран AR).
///
/// Рецепт — тот же, что у ручки таймбара и окна барабана: прозрачное стекло без размытия, середина один к
/// одному, у кромки гнётся (`GlassOptics`, `Glass.metal`), свет сверху, тёмный контур снаружи, тень только
/// снаружи (`OuterShadow`). Рецепт живёт здесь, в `Timebar/`: `Tools/check_glass.sh` нарисованный блик вне
/// этой папки не пускает.
///
/// Диск лежит ПОВЕРХ дуги и подписей (слово Алексея 14.10: «бубликом и за линией, выглядит плохо»), и гнёт
/// всё, что под ним, — в том числе дугу (слово 15.10: «стекло без кромки, нет искажений»). Поэтому рецепт в
/// двух слоях, и порядок слоёв — часть рецепта:
/// - `LensRefraction` — копия того, что под диском (кадр без камеры, дуга, подписи часов), с гнутой кромкой.
///   Лежит ВЫШЕ дуги: оригинал дуги внутри диска вырезан (`SunARHole`), на его месте — гнутая копия. На телефоне
///   кадр камеры гнёт ещё и слой Metal (`SunARLens`) под дугой — те же ширина кромки и сдвиг;
/// - `LensGlass` — налёт оттенка, свет по кромке, контур и тень. Лежит над линзой.
///
/// Цвет диска (шаг 29.8в.6): налёт с обычным смешиванием на светлом фоне разбеливается, поэтому у солнца под налётом
/// лежит ещё слой «умножение» (`multiply`): окрашенное стекло — цвет света на любом сером фоне тот же, только
/// темнее. Слой «умножение» лежит снаружи группы затухания призрака: внутри группы с прозрачностью он не видел
/// бы фона.
struct LensGlass: View {
    /// Диаметр диска, pt.
    let diameter: CGFloat
    /// Оттенок стекла: у солнца — по состоянию света, у луны — серебристый.
    let tint: Color
    /// Прозрачность налёта: сквозь него просвечивает кадр и дуга.
    var tintOpacity: Double = SunARInk.glassTintOpacity
    /// Непрозрачность слоя «умножение» тем же оттенком: 0 — слоя нет (луна), у солнца `SunARInk.sunMultiply`.
    var multiply: Double = 0
    /// Цвет слоя «умножение»; `nil` — цвет стекла (`tint`). У призрака солнца — чистый тон, чтобы множитель 0,4 не
    /// терял насыщенность.
    var multiplyTint: Color?
    /// Белый налёт стекла (`SunARInk.moonVeil` / `sunVeil`).
    var veil: Double = SunARInk.moonVeil
    /// Призрак: светило под горизонтом — налёт и тень тише (`SunARInk.ghostFill`).
    var fade: Double = 1
    /// Контур пунктиром (солнце ниже горизонта): держится заметнее налёта (`SunARInk.ghostContour`).
    var dashedContour = false

    var body: some View {
        let ring = SunARInk.rim(for: diameter)
        ZStack {
            if multiply > 0 {
                Circle().fill(multiplyTint ?? tint).opacity(multiply).blendMode(.multiply)
            }
            ZStack {
                Circle().fill(tint.opacity(tintOpacity))
                // Налёт прозрачного стекла.
                if veil > 0 { Circle().fill(Color.white.opacity(veil)) }
                // Свет по кромке: сверху плотный, к середине высоты гаснет — как у кольца ручки и у `KnobGlass`.
                Circle().inset(by: 0.75)
                    .stroke(LinearGradient(stops: [.init(color: .white.opacity(0.92), location: 0),
                                                   .init(color: .white.opacity(0.35), location: 0.22),
                                                   .init(color: .white.opacity(0), location: 0.5)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1.5)
                // Низ кромки темнеет: стекло имеет толщину.
                Circle().inset(by: 0.75)
                    .stroke(LinearGradient(stops: [.init(color: .black.opacity(0), location: 0.55),
                                                   .init(color: .black.opacity(0.32), location: 1)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1.5)
                // Внутренний волосок: где кончается гнущая кромка и начинается чистая середина.
                Circle().inset(by: ring).stroke(tint.opacity(0.5), lineWidth: 0.75)
            }
            .opacity(fade)
        }
        .overlay { contour }
        .frame(width: diameter, height: diameter)
        .background(OuterShadow(shape: Circle(), color: .black.opacity(0.45 * fade), radius: 5.5, y: 3))
        .allowsHitTesting(false)
    }

    /// Тонкий тёмный контур снаружи кромки (1 pt, чёрный 0,55): на белом небе стекло без него теряло край.
    /// Пунктирный — тёмная подложка и светлый штрих поверх: читается и на тёмном, и на светлом.
    @ViewBuilder private var contour: some View {
        if dashedContour {
            let dash = StrokeStyle(lineWidth: 1.25, lineCap: .butt, dash: SunARInk.ghostDash)
            Circle().inset(by: -0.75).stroke(Color.black.opacity(0.55 * SunARInk.ghostContour), lineWidth: 2.75)
            Circle().inset(by: -0.75).stroke(Color.white.opacity(SunARInk.ghostContour), style: dash)
        } else {
            Circle().inset(by: -0.5).stroke(Color.black.opacity(0.55 * fade), lineWidth: 1)
        }
    }
}

/// Линза диска: копия того, что лежит под ним, с гнутой кромкой — середина один к одному, у края сдвиг до
/// `SunARInk.lensShift`, насыщенность и яркость `--glass-optic` веба (тёмная: `saturate(1.5) brightness(1.06)`;
/// камера под экраном AR всегда тёмная подложка, поэтому схема не зависит от темы приложения).
///
/// Содержимое строит вызывающий: оно получает левый верхний угол окна линзы в окне экрана и рисует «то, что
/// под диском» от этой точки. Окно шире диска на сдвиг со всех сторон — шейдер берёт точки за кромкой, и там
/// должно быть что брать.
struct LensRefraction<Content: View>: View {
    let diameter: CGFloat
    /// Левый верхний угол диска в окне экрана.
    let origin: CGPoint
    @ViewBuilder let content: (_ windowOrigin: CGPoint, _ windowSize: CGSize) -> Content

    /// Поле вокруг диска: на максимальный сдвиг.
    static var pad: CGFloat { SunARInk.lensShift }

    var body: some View {
        let pad = Self.pad
        let r = diameter / 2
        let side = diameter + 2 * pad
        let windowOrigin = CGPoint(x: origin.x - pad, y: origin.y - pad)
        content(windowOrigin, CGSize(width: side, height: side))
            .frame(width: side, height: side, alignment: .topLeading)
            .clipped()
            .layerEffect(GlassOptics.lens(center: CGPoint(x: r + pad, y: r + pad), radius: r,
                                          width: SunARInk.rim(for: diameter), scheme: .dark),
                         maxSampleOffset: CGSize(width: GlassOptics.lensShift, height: GlassOptics.lensShift))
            .clipShape(Circle().inset(by: pad))
            .frame(width: side, height: side)
            .position(x: origin.x + r, y: origin.y + r)
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
