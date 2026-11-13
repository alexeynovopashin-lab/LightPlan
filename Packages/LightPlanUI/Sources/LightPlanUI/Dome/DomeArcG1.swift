import SwiftUI
import LightPlanCore

/// Дуга дня «Света» на светлой теме — вариант Г1 «тонкая» (28к.5; DECISIONS 13.11 «Дуга светлой темы: Г1, тонкая», слова Алексея «Г1, тонкая»).
///
/// Порт листа `light_plan:Light_Plan/docs/light_arc_2026-11-13/build.py` буквально, 1 единица = 1 pt, геометрия — `DomeGeometry`
/// (эллипс rx 163, ry 148, центр 195;196). Вместо ровной линии в 3 pt — лента, которая у вершины 2,4 pt и ровно, по углу, растёт
/// до 4,0 pt у оснований. Слои от оси наружу: белая жила (0,46 толщины), персиковый переход `#FFD9A8` (0,76), оранжевая кромка
/// `#F09329` (1,0), плотное свечение (2,1×, 5,0 pt у вершины) и мягкое (4,6×, 11,0 pt).
///
/// **Цвет вдоль дуги — по высоте солнца в эту минуту дня:** ниже `goldenBelow` — оранжевая, от `whiteFrom` (или от `whiteShareOfMax`
/// высоты полудня этого дня, что ниже) — белая, между ними плавно (smoothstep). Три числа — стартовые, Алексей не утверждал
/// (он судит по телефону), поэтому они здесь именованные константы и правятся в одном месте.
///
/// Только светлая тема: тёмная идёт прежней линией, ни один её пиксель не меняется.
enum ArcG1 {

    // MARK: Толщины и доли слоёв (лист: `legs(body, foot, k)`)

    /// Толщина ленты у вершины и у оснований, pt.
    static let apexThickness: Double = 2.4
    static let footThickness: Double = 4.0
    /// Доли толщины по слоям от оси наружу.
    static let coreShare: Double = 0.46
    static let peachShare: Double = 0.76
    static let edgeShare: Double = 1.0
    static let denseShare: Double = 2.1
    static let softShare: Double = 4.6
    /// Непрозрачность свечений и размытие в долях толщины у вершины (стандартное отклонение, pt).
    static let softOpacity: Double = 0.40
    static let denseOpacity: Double = 0.85
    static let softBlurShare: Double = 1.5
    static let denseBlurShare: Double = 0.48
    static let peachBlurShare: Double = 0.1
    /// Насколько белеют свечения, когда солнце высоко: мягкое и плотное.
    static let softWhiteStrength: Double = 0.55
    static let denseWhiteStrength: Double = 0.7

    // MARK: Цвет по высоте солнца (стартовые числа, не утверждены)

    /// Ниже этой высоты солнца дуга оранжевая целиком.
    static let goldenBelow: Degrees = 6
    /// Выше этой высоты дуга белая целиком…
    static let whiteFrom: Degrees = 30
    /// …или выше этой доли высоты полудня того же дня, если она ниже: зимой, когда солнце за день не поднимается до 30°.
    static let whiteShareOfMax: Double = 0.8

    // MARK: Краски листа

    static let orange = RGB(0xF0, 0x93, 0x29)
    static let peach = RGB(0xFF, 0xD9, 0xA8)
    static let cream = RGB(0xFF, 0xF4, 0xE4)
    static let white = RGB(0xFF, 0xFF, 0xFF)

    /// Число отсчётов градиента вдоль дуги (лист: 41 стоп, по сорок промежутков).
    static let samples = 40

    struct RGB: Equatable {
        let r: Double, g: Double, b: Double
        init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
        /// Цвет `a → b` на доле `t` (лист: `mix`, с округлением до целого уровня).
        static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
            func m(_ x: Double, _ y: Double) -> Double { (x * (1 - t) + y * t).rounded() }
            return RGB(m(a.r, b.r), m(a.g, b.g), m(a.b, b.b))
        }
        var color: Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
    }

    // MARK: Геометрия

    /// Толщина ленты (множитель `k` = 1) на угле `degrees` от основания: 0 у основания, 90 у вершины, 180 у другого основания.
    static func thickness(atAngle degrees: Double) -> Double {
        let toFoot = min(degrees, 180 - degrees)
        return apexThickness + (footThickness - apexThickness) * (1 - toFoot / 90)
    }

    /// Точка на расстоянии `off` по нормали от эллипса купола (наружу — плюс), параметр `t` в радианах.
    static func point(_ t: Double, offset off: Double) -> CGPoint {
        let g = DomeGeometry.self
        let x = g.cx + g.rx * cos(t), y = g.cy - g.ry * sin(t)
        let nx = cos(t) / g.rx, ny = sin(t) / g.ry
        let n = hypot(nx, ny)
        return CGPoint(x: CGFloat(x + nx / n * off), y: CGFloat(y - ny / n * off))
    }

    /// Контур ленты, умноженной на `k` по толщине (лист: `legs`), шаг 2° — 91 точка на сторону.
    static func outline(scale k: Double) -> Path {
        var outer: [CGPoint] = [], inner: [CGPoint] = []
        var i = 0
        while i <= 180 {
            let t = Double(180 - i) * .pi / 180
            let w = thickness(atAngle: Double(i)) * k
            outer.append(point(t, offset: w / 2))
            inner.append(point(t, offset: -w / 2))
            i += 2
        }
        var path = Path()
        path.move(to: outer[0])
        for p in outer.dropFirst() { path.addLine(to: p) }
        for p in inner.reversed() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }

    // MARK: Белизна по высоте солнца

    /// Белизна 0…1 дуги в минуту, когда солнце на высоте `elevation` (лист: `white`), при высоте полудня дня `dayMax`.
    static func whiteness(elevation: Degrees, dayMax: Degrees) -> Double {
        // Охрана листа, где её нет: в день, чей полдень ниже золотой границы, верх не бывает ниже границы + 1°.
        let top = max(goldenBelow + 1, min(whiteFrom, whiteShareOfMax * dayMax))
        let x = max(0, min(1, (elevation - goldenBelow) / (top - goldenBelow)))
        return x * x * (3 - 2 * x)
    }

    /// Белизна в `samples + 1` точках дня от начала дуги до конца (по времени — так же, как идёт светило по `posOn`).
    static func whiteRamp(for sun: SolarDay) -> [Double] {
        let a = sun.arcA, b = sun.arcB
        let elevations = (0...samples).map { sun.elevation(at: a + (b - a) * Double($0) / Double(samples)) }
        let dayMax = max(elevations.max() ?? 0, sun.elevation(at: sun.solarNoon))
        return elevations.map { whiteness(elevation: $0, dayMax: dayMax) }
    }

    /// Градиент вдоль дуги `from → to` с белизной ramp × strength. Место стопа — по X дуги: час идёт по углу, X = cx − rx·cos(π f).
    static func gradient(_ ramp: [Double], from: RGB, to: RGB, strength: Double = 1) -> Gradient {
        Gradient(stops: ramp.enumerated().map { i, w in
            .init(color: RGB.mix(from, to, w * strength).color, location: (1 - cos(.pi * Double(i) / Double(samples))) / 2)
        })
    }

    // MARK: Рисование

    /// Рисует дугу: свечения, кромку, переход и жилу. Обрезает по горизонту, как лист (`clipPath #above`).
    static func paint(_ context: inout GraphicsContext, sun: SolarDay) {
        let g = DomeGeometry.self
        let ramp = whiteRamp(for: sun)
        let start = CGPoint(x: CGFloat(g.cx - g.rx), y: 0), end = CGPoint(x: CGFloat(g.cx + g.rx), y: 0)
        let body = apexThickness

        context.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: 0, y: 0, width: CGFloat(g.viewWidth), height: CGFloat(g.horizonY))))

            func blurred(_ share: Double, opacity: Double, scale: Double, _ gradient: Gradient) {
                layer.drawLayer { shell in
                    shell.opacity = opacity
                    shell.drawLayer { blur in
                        blur.addFilter(.blur(radius: CGFloat(body * share)))
                        blur.fill(outline(scale: scale), with: .linearGradient(gradient, startPoint: start, endPoint: end))
                    }
                }
            }
            blurred(softBlurShare, opacity: softOpacity, scale: softShare,
                    gradient(ramp, from: orange, to: white, strength: softWhiteStrength))
            blurred(denseBlurShare, opacity: denseOpacity, scale: denseShare,
                    gradient(ramp, from: orange, to: white, strength: denseWhiteStrength))
            layer.fill(outline(scale: edgeShare), with: .linearGradient(gradient(ramp, from: orange, to: cream),
                                                                        startPoint: start, endPoint: end))
            blurred(peachBlurShare, opacity: 1, scale: peachShare, gradient(ramp, from: peach, to: white))
            layer.fill(outline(scale: coreShare), with: .color(white.color))
        }
    }

    // MARK: Диск солнца (лист: `sun(uid, flat=False)`)

    /// Размытое свечение вокруг диска: радиус, непрозрачность, размытие (лист: r 14, .45, σ 6).
    static let discHaloRadius: Double = 14
    static let discHaloOpacity: Double = 0.45
    static let discHaloBlur: Double = 6
    /// Внешнее кольцо, как у тёмной темы (`DomeGeometry.ringRadius`, 16 pt): заливка и кромка цвета состояния света (`ringColor`, как у тёмной: красное у горизонта). Без него светлое солнце читалось
    /// вдвое мельче тёмного (слово Алексея 14.11): видимый поперечник 15 pt против 32 pt.
    static let discRingFill: Double = 0.18
    static let discRingStroke: Double = 0.34
    /// Диск: кромка шире ядра на 1,2 pt, персиковое кольцо уже на 0,4, белая середина уже на 2 (`DomeGeometry.coreRadius` = 6,5).
    /// Во сколько раз светлый диск крупнее листа (слово Алексея 14.11: «увеличить диаметр солнца, саму серединку»): кромка 7,7 → 10,0 pt, белая середина 4,5 → 5,9 pt. 1 = как на листе.
    static let discScale: Double = 1.3
    static let discRimExtra: Double = 1.2
    static let discPeachInset: Double = 0.4
    static let discWhiteInset: Double = 2

    /// Диск солнца светлой темы: оранжевая кромка, персиковое кольцо, белая середина, под ним мягкое оранжевое свечение.
    /// `ringColor` — цвет состояния света в эту минуту. `halo`, `ring` и `core` — доли силы 0…1 (над линией горизонта обе равны доле светила; под линией — размытая копия, см. `paintBody`).
    static func paintDisc(_ context: inout GraphicsContext, at pos: CGPoint, halo: Double, ring: Double, ringColor: Color, core: Double) {
        let r = DomeGeometry.coreRadius
        func disc(_ radius: Double) -> Path {
            Path(ellipseIn: CGRect(x: pos.x - CGFloat(radius), y: pos.y - CGFloat(radius), width: CGFloat(radius * 2), height: CGFloat(radius * 2)))
        }
        if halo > 0.002 {
            context.drawLayer { shell in
                shell.opacity = discHaloOpacity * halo
                shell.drawLayer { blur in
                    blur.addFilter(.blur(radius: CGFloat(discHaloBlur)))
                    blur.fill(disc(discHaloRadius), with: .color(orange.color))
                }
            }
        }
        if ring > 0.002 {
            let ringPath = disc(DomeGeometry.ringRadius)
            context.fill(ringPath, with: .color(ringColor.opacity(discRingFill * ring)))
            context.stroke(ringPath, with: .color(ringColor.opacity(discRingStroke * ring)), lineWidth: 1)
        }
        guard core > 0.002 else { return }
        context.drawLayer { layer in
            layer.opacity = core
            layer.fill(disc((r + discRimExtra) * discScale), with: .color(orange.color))
            layer.fill(disc((r - discPeachInset) * discScale), with: .color(peach.color))
            layer.fill(disc((r - discWhiteInset) * discScale), with: .color(white.color))
        }
    }
}
