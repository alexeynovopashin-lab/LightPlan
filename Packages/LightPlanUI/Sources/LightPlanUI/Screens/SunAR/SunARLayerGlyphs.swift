import SwiftUI

/// Знаки слоёв «Созвездия», «Планеты» и «Млечный Путь» в списке «Слоёв» (шаг 29.8в.16). Слова Алексея 19.10:
/// «созвездие — медведица, планеты — солнечная система, млечный путь — галактика».
///
/// В библиотеке знаков веба (`icons.js`, 217 знаков, лист `tools/icons.html`) таких нет — есть только `stars`
/// и `moon`, они уже стоят у «Звёзд» и «Луны»; веб заморожен, поэтому знаки нарисованы здесь, как `LayersGlyph`
/// на «Карте»: холст 24 × 24, содержимое в рамке 3…21 (так стоят знаки библиотеки: `stars` занимает 3,6…20,4),
/// линия 1,6, концы и стыки круглые, цвет — тон слоя. Линии и точки — отдельные фигуры: линию красит `stroke`,
/// точку — `fill`.
enum SunARLayerGlyph {
    /// Толщина линии в единицах холста 24 × 24 — как у `Icon(…, line: 1.6)` у «Звёзд».
    static let line: CGFloat = 1.6

    // MARK: Большая Медведица

    /// Семь звёзд ковша, слева направо: рукоятка (Алкаид, Мицар, Алиот), затем чаша (Мегрец, Фекда, Мерак, Дубхе).
    /// Рукоятка загибается так же, как на небе; чаша — четырёхугольник, замкнутый.
    static let dipper: [CGPoint] = [
        CGPoint(x: 4.2, y: 11.4), CGPoint(x: 7.6, y: 7.6), CGPoint(x: 11.6, y: 8.4),
        CGPoint(x: 13.0, y: 12.2), CGPoint(x: 13.8, y: 17.6), CGPoint(x: 19.4, y: 18.2), CGPoint(x: 19.8, y: 12.8),
    ]

    /// Радиус точки-звезды, единиц холста.
    static let starRadius: CGFloat = 1.45

    // MARK: Солнечная система

    static let systemCenter = CGPoint(x: 12, y: 12)
    static let sunRadius: CGFloat = 2.3
    /// Радиусы двух орбит.
    static let orbits: [CGFloat] = [5.6, 9]
    /// Планеты: орбита (индекс в `orbits`), угол от оси вправо по часовой в градусах, радиус точки.
    static let bodies: [(orbit: Int, degrees: Double, radius: CGFloat)] = [(0, -50, 1.5), (1, 148, 1.8)]

    static func bodyCenter(_ b: (orbit: Int, degrees: Double, radius: CGFloat)) -> CGPoint {
        let a = b.degrees * .pi / 180, r = orbits[b.orbit]
        return CGPoint(x: systemCenter.x + r * CGFloat(cos(a)), y: systemCenter.y + r * CGFloat(sin(a)))
    }

    // MARK: Галактика

    static let galaxyCenter = CGPoint(x: 12, y: 12)
    static let coreRadius: CGFloat = 2.0
    /// Две ветви спирали, наклонённой к зрителю: каждая огибает ядро чуть меньше оборота — S-образный росчерк; на целом
    /// обороте (проба 29.8в.16) при линии 1,6 ветви на 24 pt слипаются в пятно.
    static let armTurns: Double = 0.78
    static let armInner: CGFloat = 3.2
    static let armOuter: CGFloat = 10.6
    /// Наклон диска: сплющивание по короткой оси и поворот. Без наклона спираль читается как «ураган».
    static let tiltSquash: CGFloat = 0.72
    static let tiltAngle: Double = -.pi / 7

    /// Точка ветви `arm` (0 или 1) на доле пути `t` от ядра к краю.
    static func armPoint(arm: Int, t: Double) -> CGPoint {
        let theta = Double(arm) * .pi + armTurns * 2 * .pi * t
        let r = armInner + (armOuter - armInner) * CGFloat(t)
        let x = r * CGFloat(cos(theta)), y = r * CGFloat(sin(theta)) * tiltSquash
        let c = CGFloat(cos(tiltAngle)), s = CGFloat(sin(tiltAngle))
        return CGPoint(x: galaxyCenter.x + x * c - y * s, y: galaxyCenter.y + x * s + y * c)
    }
}

private func scaled(_ p: Path, in rect: CGRect) -> Path {
    let k = min(rect.width, rect.height) / 24
    return p.applying(CGAffineTransform(scaleX: k, y: k)).offsetBy(dx: rect.minX, dy: rect.minY)
}

private func dot(_ p: inout Path, _ c: CGPoint, _ r: CGFloat) {
    p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
}

// MARK: - Созвездие: ковш Большой Медведицы

/// Линии ковша: рукоятка и чаша.
struct DipperLines: Shape {
    func path(in rect: CGRect) -> Path {
        let s = SunARLayerGlyph.dipper
        var p = Path()
        p.move(to: s[0])
        for q in s.dropFirst() { p.addLine(to: q) }
        p.addLine(to: s[3])       // чаша замыкается: Дубхе → Мегрец
        return scaled(p, in: rect)
    }
}

/// Семь звёзд ковша точками.
struct DipperStars: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for s in SunARLayerGlyph.dipper { dot(&p, s, SunARLayerGlyph.starRadius) }
        return scaled(p, in: rect)
    }
}

struct DipperGlyph: View {
    var body: some View {
        ZStack {
            DipperLines().stroke(SunARInk.constellationTone, style: StrokeStyle(lineWidth: SunARLayerGlyph.line, lineCap: .round, lineJoin: .round))
            DipperStars().fill(Color.white)
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Планеты: солнечная система

struct OrbitLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for r in SunARLayerGlyph.orbits { dot(&p, SunARLayerGlyph.systemCenter, r) }
        return scaled(p, in: rect)
    }
}

struct SolarBodies: Shape {
    let sun: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if sun {
            dot(&p, SunARLayerGlyph.systemCenter, SunARLayerGlyph.sunRadius)
        } else {
            for b in SunARLayerGlyph.bodies { dot(&p, SunARLayerGlyph.bodyCenter(b), b.radius) }
        }
        return scaled(p, in: rect)
    }
}

struct SolarSystemGlyph: View {
    var body: some View {
        ZStack {
            OrbitLines().stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: SunARLayerGlyph.line * 0.8, lineCap: .round))
            SolarBodies(sun: true).fill(SunARInk.planetTone)
            SolarBodies(sun: false).fill(Color.white)
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Млечный Путь: галактика

struct GalaxyArms: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n = 28
        for arm in 0..<2 {
            for i in 0...n {
                let q = SunARLayerGlyph.armPoint(arm: arm, t: Double(i) / Double(n))
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
        }
        return scaled(p, in: rect)
    }
}

struct GalaxyCore: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        dot(&p, SunARLayerGlyph.galaxyCenter, SunARLayerGlyph.coreRadius)
        return scaled(p, in: rect)
    }
}

struct GalaxyGlyph: View {
    var body: some View {
        ZStack {
            GalaxyArms().stroke(SunARInk.milkyWayTone, style: StrokeStyle(lineWidth: SunARLayerGlyph.line, lineCap: .round, lineJoin: .round))
            GalaxyCore().fill(SunARInk.coreTone)
        }
        .frame(width: 24, height: 24)
    }
}
