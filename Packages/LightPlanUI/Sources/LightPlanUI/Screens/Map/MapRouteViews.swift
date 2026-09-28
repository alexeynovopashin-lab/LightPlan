import SwiftUI
import LightPlanCore
import LightPlanDomain

// Режим маршрута «Карты» (итерация 24а): визир, кнопки «Маршрут» и «Моё
// место», кольцо касания и полоса черновика. Числа — справка веба
// `docs/native_24a_route_web_spec.md`.

/// Визир (`sightMorph`, `SIGHT_A/B`): головка не подменяется вторым знаком, а
/// перетекает в белую булавку. Обе фигуры — четыре кубические дуги одной
/// формы на холсте знака `pin` (24): круг r 7 с центром (12, 10) и капля с
/// остриём (12, 21); доля `t` смешивает их линейно, как `sightDraw`.
/// Натив мерит головку и булавку одними 20 pt (20г), поэтому масштаба веба
/// (13 → 10,5) нет: меняется только форма и сдвиг — у круга под центром
/// кадра центр головки, у булавки — остриё, ровно там, где встанет точка.
struct SightShape: Shape {
    var t: Double
    var animatableData: Double { get { t } set { t = newValue } }

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        let y0 = m(17, 21)
        var path = Path()
        path.move(to: p(12, y0))
        path.addCurve(to: p(19, 10), control1: p(m(15.866, 12), m(17, 21)), control2: p(19, m(13.866, 14.7)))
        path.addCurve(to: p(12, 3), control1: p(19, 6.134), control2: p(15.866, 3))
        path.addCurve(to: p(5, 10), control1: p(8.134, 3), control2: p(5, 6.134))
        path.addCurve(to: p(12, y0), control1: p(5, m(13.866, 14.7)), control2: p(m(8.134, 12), m(17, 21)))
        path.closeSubpath()
        return path
    }
}

/// Головка ротора с визиром. Рамка — холст знака 24 × 24 в масштабе булавки
/// (20 / 14); её середина ставится в центр окна. Доля анимируется снаружи
/// (`withAnimation`), `Animatable` пересобирает стекло на каждом кадре: у
/// встроенного стекла своей интерполяции формы нет.
struct SightHead: View, @preconcurrency Animatable {
    var t: Double
    let pal: Palette
    var animatableData: Double { get { t } set { t = newValue } }

    static let side: CGFloat = 24 * MapSpots.glyphScale

    var body: some View {
        let k = MapSpots.glyphScale
        ZStack(alignment: .topLeading) {
            KnobGlass(shape: SightShape(t: t), pal: pal)
            // Зрачок `r = 2,6·t` — точка сохранённой булавки (`PinGlyph`).
            Circle().fill(pal.brass)
                .frame(width: 2 * 2.6 * k * t, height: 2 * 2.6 * k * t)
                .offset(x: (12 - 2.6 * t) * k, y: (10 - 2.6 * t) * k)
        }
        .frame(width: Self.side, height: Self.side)
        // Под центром окна: у круга — центр головки (12, 10), у булавки —
        // остриё (12, 21). Середина рамки — (12, 12).
        .offset(y: (2 - 11 * t) * k)
    }
}

/// Знак `.map-here` «Моё место» (`#mapHere`): кольцо r 4 и четыре риски.
struct MapHereGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        var p = Path()
        p.addEllipse(in: CGRect(x: 8, y: 8, width: 8, height: 8))
        for (a, b) in [((12.0, 2.0), (12.0, 5.0)), ((12, 19), (12, 22)), ((2, 12), (5, 12)), ((19, 12), (22, 12))] {
            p.move(to: CGPoint(x: a.0, y: a.1))
            p.addLine(to: CGPoint(x: b.0, y: b.1))
        }
        return p.applying(CGAffineTransform(scaleX: k, y: k)).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Кружок карты 34 на стекле со знаком 18 / 1,8 (`.map-here`): «Моё место»
/// и «Маршрут». Нажатый и включённый — латунью.
struct MapRoundButton<Glyph: View>: View {
    let pal: Palette
    let darkCanvas: Bool
    let on: Bool
    let label: String
    let node: String
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        let ink = MapGlassCircle.ink(pal, darkCanvas: darkCanvas)
        Button(action: action) { EmptyView() }
            .buttonStyle(MapRoundPress(on: on, ink: ink, glyph: glyph))
            .modifier(MapGlassCircle(pal: pal, darkCanvas: darkCanvas))
            .accessibilityLabel(label)
            .shotNode(node)
    }
}

/// Знак кружка; нажатый — латунью (`.map-here:active { color: var(--brass) }`).
private struct MapRoundPress<Glyph: View>: ButtonStyle {
    let on: Bool
    let ink: Palette
    let glyph: () -> Glyph
    func makeBody(configuration: Configuration) -> some View {
        glyph()
            .foregroundStyle(on || configuration.isPressed ? ink.brass : ink.ink3)
            .frame(width: 18, height: 18)
            .frame(width: 34, height: 34)
            .contentShape(Circle())
    }
}

/// Кольцо касания (`.map-tap`): 54, кант 1,4 латунью, `scale .3 → 1`,
/// `opacity .6 → 0` за 0,44 с. Говорит «нажатие засчитано» там, где палец:
/// точка родится в центре кадра, а палец жмёт мимо. Живёт вне ротора.
struct MapTapRing: View {
    let pal: Palette
    @State private var go = false

    var body: some View {
        Circle().strokeBorder(pal.brass, lineWidth: 1.4)
            .frame(width: 54, height: 54)
            .scaleEffect(go ? 1 : 0.3)
            .opacity(go ? 0 : 0.6)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 0.44)) { go = true } }
    }
}

/// Номер места в черновике (`.sm-no`): кружок 15 латунью, цифра 9,5 / 700
/// цветом `--surface`. У веба он слева-сверху от знака 18 px и заходит на
/// головку на 1,4; у натива головка 20 pt — то же направление и тот же нахлёст.
struct RouteNumber: View {
    let n: Int
    let pal: Palette

    /// Центр кружка от острия булавки.
    static let center = CGPoint(x: -14.9, y: -21.7)

    var body: some View {
        Text(String(n))
            .font(.system(size: 9.5, weight: .bold).monospacedDigit())
            .foregroundStyle(pal.surface)
            .frame(width: 15, height: 15)
            .background(Circle().fill(pal.brass))
    }
}

/// Полоса черновика (`#mapRouteBar`), шаг 1 итерации: верхняя строка — знак
/// `route` 17 / 1,7 латунью и текст. Список, «＋», «✕» и «Сделать съёмкой» —
/// шаг 2. Плашка: `--bar` на стекле, рамка 1 `--ink-10`, радиус 16, внутри
/// 8 / 8 / 9.
struct RouteBar: View {
    let count: Int
    let hasSpots: Bool
    let lexicon: Lexicon
    let pal: Palette

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 9) {
                Icon("route", size: 17, line: 1.7).foregroundStyle(pal.brass)
                VStack(alignment: .leading, spacing: 1) {
                    if count > 0 {
                        Text(lexicon.count("unit.point", count))
                            .font(.system(size: 11)).foregroundStyle(pal.ink4)
                            .shotNode("route.sum", text: lexicon.count("unit.point", count))
                    } else {
                        Text(lexicon.t(hasSpots ? "map.routeHint" : "map.routeNoSpots"))
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(pal.ink)
                        Text(lexicon.t(hasSpots ? "map.routeFromSaved" : "map.routeNoSpotsSub"))
                            .font(.system(size: 11)).foregroundStyle(pal.ink4)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 5)
            .frame(minHeight: 28)
        }
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 9, trailing: 8))
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.bar)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(pal.ink10, lineWidth: 1))
        .shotNode("map.routeBar")
    }
}
