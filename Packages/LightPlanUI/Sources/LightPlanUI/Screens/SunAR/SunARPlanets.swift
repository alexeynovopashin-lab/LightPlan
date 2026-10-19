import SwiftUI
import LightPlanCore

/// Слой «Планеты» на экране AR (шаг 29.8в.15). Расчёт — ядра (`PlanetSkyAR`), здесь рисование и раскладка подписей.
/// Слой лежит над звёздами и под дугой. Днём (солнце выше −6°) планет нет и ничего не рисуется — об этом написано в
/// списке «Слоёв» (отдельной плашки на экране нет: у звёзд она уже есть, две подряд закрыли бы небо).

// MARK: - Холст

/// Точки планет одним холстом. `origin` и `holes` — как у `SunARStarCanvas`: копия под линзой рисует тот же кадр в
/// маленьком холсте, а под дисками меток (своё стекло) слой вырезан.
struct SunARPlanetCanvas: View {
    let scene: PlanetSkyARScene
    var origin: CGPoint = .zero
    var holes: [SunARHole] = []

    var body: some View {
        let k = scene.visibility
        Canvas { ctxIn, size in
            guard k > 0 else { return }
            var ctx = ctxIn
            ctx.translateBy(x: -origin.x, y: -origin.y)
            let view = CGRect(origin: origin, size: size)
            if !holes.isEmpty {
                ctx.clip(to: SunARHole.clipArea(view, holes: holes), style: FillStyle(eoFill: true))
            }
            let near = view.insetBy(dx: -40, dy: -40)
            for d in scene.dots {
                let c = CGPoint(x: d.point.x, y: d.point.y)
                guard near.contains(c) else { continue }
                let t = PlanetLook.tint(d.planet)
                let color = Color(red: t.red, green: t.green, blue: t.blue)
                let r = CGFloat(d.radius), a = d.brightness * k
                if d.magnitude < PlanetLook.haloMagnitude {
                    let h = r * 3.2
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - h, y: c.y - h, width: 2 * h, height: 2 * h)),
                             with: .radialGradient(Gradient(colors: [color.opacity(0.34 * a), color.opacity(0)]),
                                                   center: c, startRadius: 0, endRadius: h))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(color.opacity(a)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Подписи

/// Раскладка подписей планет: название рядом с точкой — справа, слева, над, под — на первом свободном месте. Подписи не
/// ложатся на занятое (`taken`: подписи солнца, луны, часов, сторон света, стрелки, диски меток, ядро Млечного Пути) и
/// друг на друга; подпись без места не рисуется. Подписи звёзд и созвездий ставятся после и обходят подписи и точки
/// планет (`SunARSkyStack`).
enum SunARPlanetLabels {
    struct Candidate: Equatable {
        let planet: Planet
        let text: String
        let anchor: CGPoint
        let radius: CGFloat
    }

    struct Placed: Identifiable, Equatable {
        let planet: Planet
        let text: String
        let center: CGPoint
        let rect: CGRect
        var id: String { planet.nameKey }
    }

    static let fontSize: CGFloat = 11.5
    static let weight: Font.Weight = .semibold

    static func textRect(_ text: String, center: CGPoint) -> CGRect {
        let s = SunARLabelLayout.textSize(text, size: fontSize, weight: weight)
        return CGRect(x: center.x - s.width / 2 - SunARStarLabels.padX, y: center.y - s.height / 2 - SunARStarLabels.padY,
                      width: s.width + 2 * SunARStarLabels.padX, height: s.height + 2 * SunARStarLabels.padY)
    }

    /// Кандидаты: планеты, чья точка в окне, от ярких к слабым.
    static func candidates(scene: PlanetSkyARScene, window: CGRect, name: (String) -> String) -> [Candidate] {
        guard scene.visibility > 0 else { return [] }
        return scene.dots.sorted { $0.magnitude < $1.magnitude }.compactMap { d in
            let p = CGPoint(x: d.point.x, y: d.point.y)
            guard window.contains(p) else { return nil }
            return Candidate(planet: d.planet, text: name(d.planet.nameKey), anchor: p, radius: CGFloat(d.radius))
        }
    }

    private static func options(_ c: Candidate) -> [CGPoint] {
        let s = SunARLabelLayout.textSize(c.text, size: fontSize, weight: weight)
        let a = c.anchor
        let dx = c.radius + 6 + s.width / 2, dy = c.radius + 5 + s.height / 2
        return [CGPoint(x: a.x + dx, y: a.y), CGPoint(x: a.x - dx, y: a.y),
                CGPoint(x: a.x, y: a.y - dy), CGPoint(x: a.x, y: a.y + dy)]
    }

    /// Пятно точки планеты для раскладки: радиус точки и запас 3 pt. Подпись одной планеты не ложится на точку другой.
    static func dotRect(_ c: Candidate) -> CGRect {
        let h = c.radius + 3
        return CGRect(x: c.anchor.x - h, y: c.anchor.y - h, width: 2 * h, height: 2 * h)
    }

    static func place(_ candidates: [Candidate], taken: [CGRect], window: CGRect) -> [Placed] {
        var busy = taken
        var out: [Placed] = []
        for c in candidates {
            // Точки других планет заняты сразу, ещё до того, как их подписи поставлены; своя точка не мешает — подпись и так за её краем.
            let dots = candidates.filter { $0.planet != c.planet }.map(dotRect)
            for center in options(c) {
                let r = textRect(c.text, center: center)
                guard window.contains(r), SunARStarLabels.free(r, taken: busy + dots) else { continue }
                out.append(Placed(planet: c.planet, text: c.text, center: center, rect: r))
                busy.append(r)
                break
            }
        }
        return out
    }

    /// Занятое планетами для подписей звёзд: рамки подписей и пятна точек с ореолом.
    static func occupied(scene: PlanetSkyARScene, labels: [Placed]) -> [CGRect] {
        guard scene.visibility > 0 else { return [] }
        return labels.map(\.rect) + scene.dots.map {
            let h = CGFloat($0.radius) * ($0.magnitude < PlanetLook.haloMagnitude ? 1.6 : 1) + 2
            return CGRect(x: $0.point.x - h, y: $0.point.y - h, width: 2 * h, height: 2 * h)
        }
    }
}

// MARK: - Слой

struct SunARPlanetLayer: View {
    let scene: PlanetSkyARScene
    let labels: [SunARPlanetLabels.Placed]
    var holes: [SunARHole] = []

    var body: some View {
        let k = scene.visibility
        ZStack(alignment: .topLeading) {
            SunARPlanetCanvas(scene: scene, holes: holes)
            if k > 0 {
                ForEach(labels) { l in
                    Text(l.text)
                        .font(.system(size: SunARPlanetLabels.fontSize, weight: SunARPlanetLabels.weight))
                        .foregroundStyle(SunARInk.light)
                        .opacity(SunARInk.planetNameOpacity * k)
                        .shadow(color: .black.opacity(0.7), radius: 1.5, x: 0, y: 0.5)
                        .fixedSize()
                        .shotNode("ar.planetLabel." + l.planet.rawValue, text: l.text)
                        .position(x: l.center.x, y: l.center.y)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Значок переключателя

/// Значок «Планеты»: шар с кольцом, как рисуют Сатурн. Цвет — тон слоя.
struct PlanetsToggleIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let tone = SunARInk.planetTone
            let ring = Path(ellipseIn: CGRect(x: c.x - 12.5, y: c.y - 3.6, width: 25, height: 7.2))
                .applying(CGAffineTransform(translationX: -c.x, y: -c.y).rotated(by: -0.38).translatedBy(x: c.x, y: c.y))
            // Задняя половина кольца — под шаром, передняя — над ним.
            ctx.stroke(ring, with: .color(tone.opacity(0.55)), style: StrokeStyle(lineWidth: 1.2))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(tone))
            var front = ctx
            front.clip(to: Path(CGRect(x: 0, y: c.y + 0.5, width: size.width, height: size.height)))
            front.stroke(ring, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.2))
        }
        .frame(width: 26, height: 22)
    }
}
