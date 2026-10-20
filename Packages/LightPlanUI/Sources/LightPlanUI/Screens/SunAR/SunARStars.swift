import SwiftUI
import LightPlanCore

/// Слои «Звёзды» и «Созвездия» на экране AR (шаг 29.8в.13). Расчёт — ядра (`StarSkyAR`), здесь рисование и раскладка
/// подписей. Слой лежит между полосой Млечного Пути и дугой и рисуется всегда, днём тоже (29.8в.18): это инструмент
/// планирования съёмки, а не копия глаза. Видимость глазом — справка в списке «Слоёв» (`SkyEyeNote`).

// MARK: - Холст

/// Точки и линии фигур одним холстом. `origin` — левый верхний угол холста в окне экрана: копия под линзой (своё
/// стекло) рисует тот же кадр в маленьком холсте; `holes` — диски меток, под которыми слой не рисуется.
struct SunARStarCanvas: View {
    let scene: StarSkyARScene
    var origin: CGPoint = .zero
    var holes: [SunARHole] = []

    var body: some View {
        Canvas { ctxIn, size in
            var ctx = ctxIn
            ctx.translateBy(x: -origin.x, y: -origin.y)
            let view = CGRect(origin: origin, size: size)
            if !holes.isEmpty {
                ctx.clip(to: SunARHole.clipArea(view, holes: holes), style: FillStyle(eoFill: true))
            }
            let near = view.insetBy(dx: -40, dy: -40)
            if !scene.segments.isEmpty {
                var lines = Path()
                for s in scene.segments {
                    let a = CGPoint(x: s.from.x, y: s.from.y), b = CGPoint(x: s.to.x, y: s.to.y)
                    // Линия, у которой оба конца далеко по одну сторону холста, на него не попадает.
                    guard near.contains(a) || near.contains(b) || near.intersects(CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                                                                       width: abs(a.x - b.x), height: abs(a.y - b.y))) else { continue }
                    lines.move(to: a); lines.addLine(to: b)
                }
                ctx.stroke(lines, with: .color(.white.opacity(SunARInk.figureLineOpacity)),
                           style: StrokeStyle(lineWidth: SunARInk.figureLineWidth, lineCap: .round))
            }
            for d in scene.dots {
                let c = CGPoint(x: d.point.x, y: d.point.y)
                guard near.contains(c) else { continue }
                let t = StarLook.tint(spectralClass: d.spectralClass)
                let color = Color(red: t.red, green: t.green, blue: t.blue)
                let r = CGFloat(d.radius), a = d.brightness
                if d.magnitude < 1.5 {
                    // Яркие звёзды — с мягким ореолом: глаз читает блеск по размеру пятна, а не только по точке.
                    let h = r * 3.2
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - h, y: c.y - h, width: 2 * h, height: 2 * h)),
                             with: .radialGradient(Gradient(colors: [color.opacity(0.32 * a), color.opacity(0)]),
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

/// Раскладка подписей слоя: названия созвездий у центра фигуры, имена ярких звёзд рядом с точкой. Чистая геометрия, как `SunARLabelLayout`: экран рисует то, что она вернула, тест меряет зазоры.
///
/// Правило 29.8в.6 и 29.8в.10: подписи слоя не ложатся на подписи солнца и луны, часов дуги и сторон света, на диски
/// меток и на стрелки за краем. Занятое приходит списком `taken`; подпись, которой не нашлось свободного места
/// (в окне, без наложений), не рисуется — а не лежит поверх чужой.
enum SunARStarLabels {
    enum Kind: Equatable { case figure, star }

    struct Candidate: Equatable {
        let id: String
        let kind: Kind
        let text: String
        /// Центр фигуры или центр точки звезды.
        let anchor: CGPoint
        /// Радиус точки звезды (у фигуры 0): подпись стоит за её краем.
        let radius: CGFloat
    }

    struct Placed: Identifiable, Equatable {
        let id: String
        let kind: Kind
        let text: String
        let center: CGPoint
        let rect: CGRect
    }

    /// Просвет до занятого, pt.
    static let gap: CGFloat = 4
    /// Поля вокруг текста в рамке подписи (только для раскладки, плашки нет), pt.
    static let padX: CGFloat = 3
    static let padY: CGFloat = 2

    static func font(_ kind: Kind) -> (size: CGFloat, weight: Font.Weight) {
        kind == .figure ? (11, .medium) : (10.5, .medium)
    }

    static func textRect(_ text: String, kind: Kind, center: CGPoint) -> CGRect {
        let f = font(kind)
        let s = SunARLabelLayout.textSize(text, size: f.size, weight: f.weight)
        return CGRect(x: center.x - s.width / 2 - padX, y: center.y - s.height / 2 - padY,
                      width: s.width + 2 * padX, height: s.height + 2 * padY)
    }

    /// Кандидаты из сцены: фигуры, чей центр в окне, и названные звёзды, чья точка в окне. Звёзды — от ярких к слабым.
    static func candidates(scene: StarSkyARScene, window: CGRect, name: (String) -> String) -> [Candidate] {
        var out: [Candidate] = []
        for f in scene.figures {
            let p = CGPoint(x: f.point.x, y: f.point.y)
            guard window.contains(p) else { continue }
            out.append(Candidate(id: "con." + f.code, kind: .figure, text: name("con." + f.code), anchor: p, radius: 0))
        }
        for d in scene.dots.sorted(by: { $0.magnitude < $1.magnitude }) {
            guard let key = d.nameKey else { continue }
            let p = CGPoint(x: d.point.x, y: d.point.y)
            guard window.contains(p) else { continue }
            out.append(Candidate(id: key, kind: .star, text: name(key), anchor: p, radius: CGFloat(d.radius)))
        }
        return out
    }

    /// Центры, которые пробуются по порядку: фигура — на месте, ниже, выше; звезда — справа от точки, слева, над, под.
    private static func options(_ c: Candidate) -> [CGPoint] {
        let f = font(c.kind)
        let s = SunARLabelLayout.textSize(c.text, size: f.size, weight: f.weight)
        let a = c.anchor
        switch c.kind {
        case .figure:
            let step = s.height + 2 * padY + gap
            return [a, CGPoint(x: a.x, y: a.y + step), CGPoint(x: a.x, y: a.y - step)]
        case .star:
            let dx = c.radius + 5 + s.width / 2, dy = c.radius + 4 + s.height / 2
            return [CGPoint(x: a.x + dx, y: a.y), CGPoint(x: a.x - dx, y: a.y),
                    CGPoint(x: a.x, y: a.y - dy), CGPoint(x: a.x, y: a.y + dy)]
        }
    }

    static func free(_ r: CGRect, taken: [CGRect]) -> Bool {
        let grown = r.insetBy(dx: -gap, dy: -gap)
        return !taken.contains { grown.intersects($0) }
    }

    /// Ставит подписи по порядку списка; каждая — на первое свободное место из её вариантов, целиком в окне.
    static func place(_ candidates: [Candidate], taken: [CGRect], window: CGRect) -> [Placed] {
        var busy = taken
        var out: [Placed] = []
        for c in candidates {
            for center in options(c) {
                let r = textRect(c.text, kind: c.kind, center: center)
                guard window.contains(r), free(r, taken: busy) else { continue }
                out.append(Placed(id: c.id, kind: c.kind, text: c.text, center: center, rect: r))
                busy.append(r)
                break
            }
        }
        return out
    }
}

// MARK: - Слой

/// Холст и подписи слоя. Подписи тихие: название созвездия тише названия звезды.
struct SunARStarLayer: View {
    let scene: StarSkyARScene
    let labels: [SunARStarLabels.Placed]
    var holes: [SunARHole] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            SunARStarCanvas(scene: scene, holes: holes)
            ForEach(labels) { l in
                let f = SunARStarLabels.font(l.kind)
                Text(l.text)
                    .font(.system(size: f.size, weight: f.weight))
                    .foregroundStyle(SunARInk.light)
                    .opacity(l.kind == .figure ? SunARInk.figureNameOpacity : SunARInk.starNameOpacity)
                    .shadow(color: .black.opacity(0.7), radius: 1.5, x: 0, y: 0.5)
                    .fixedSize()
                    .shotNode("ar.starLabel." + l.id, text: l.text)
                    .position(x: l.center.x, y: l.center.y)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Значки переключателей

/// Значок «Звёзды»: тот же знак `stars`, что у погоды в приложении («ясная ночь»).
struct StarsToggleIcon: View {
    var body: some View {
        Icon("stars", size: 24, line: 1.6)
            .foregroundStyle(SunARInk.starTone)
            .frame(width: 26, height: 22)
    }
}

