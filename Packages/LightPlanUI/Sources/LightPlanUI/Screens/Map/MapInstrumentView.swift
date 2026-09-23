import SwiftUI

/// Рисует сцену прибора одним `Canvas` в окне `optic` (точки экрана):
/// `viewBox` 358 × 340 вписан по меньшей стороне и стоит посередине — как
/// `preserveAspectRatio="xMidYMid meet"` у `#mapLight`. Кегли и толщины
/// масштабируются вместе с ним, как у SVG.
///
/// Пальцу прибор не мешает — карта под ним тащится; ловят касание только
/// светила, прицелом 16 (диск 4,5–5,5 пальцем не попасть).
struct MapInstrumentView: View {
    let scene: MapInstrument.Scene
    let optic: CGRect
    let onTapSun: (Double, Double) -> Void
    let onTapMoon: (Double, Double) -> Void

    var body: some View {
        let s = min(optic.width / MapInstrument.size.width, optic.height / MapInstrument.size.height)
        let ox = optic.minX + (optic.width - MapInstrument.size.width * s) / 2
        let oy = optic.minY + (optic.height - MapInstrument.size.height * s) / 2
        let toScreen = { (p: CGPoint) in CGPoint(x: ox + p.x * s, y: oy + p.y * s) }
        let rect = { (r: CGRect) in CGRect(x: ox + r.minX * s, y: oy + r.minY * s, width: r.width * s, height: r.height * s) }

        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                ctx.translateBy(x: ox, y: oy)
                ctx.scaleBy(x: s, y: s)
                for el in scene.elements { Self.draw(el, in: &ctx) }
            }
            .allowsHitTesting(false)

            marks(toScreen: toScreen, rect: rect, scale: s)

            if let p = scene.sunAt, let h = scene.sunHorizontal {
                target(toScreen(p), r: 16 * s) { onTapSun(h.az, h.alt) }
            }
            if let p = scene.moonAt, let h = scene.moonHorizontal {
                target(toScreen(p), r: 16 * s) { onTapMoon(h.az, h.alt) }
            }
        }
    }

    private func target(_ p: CGPoint, r: CGFloat, action: @escaping () -> Void) -> some View {
        Circle().fill(Color.white.opacity(0.001))
            .frame(width: 2 * r, height: 2 * r)
            .position(p)
            .onTapGesture(perform: action)
    }

    // MARK: - Узлы пары

    /// Невидимые рамки под именами `tools/shot.js` (`map.*`): у фигур —
    /// геометрия без обводки, как `getBoundingClientRect` у SVG; у подписей —
    /// строка той же гарнитуры.
    @ViewBuilder
    private func marks(toScreen: @escaping (CGPoint) -> CGPoint, rect: (CGRect) -> CGRect, scale s: CGFloat) -> some View {
        let m = scene.marks
        let c = CGPoint(x: MapInstrument.cx, y: MapInstrument.cy)
        node("map.optic", optic,
             text: m.dust.isEmpty ? nil : m.dust.map(String.init).joined(separator: " "))
        node("map.horizon", rect(MapInstrument.box(c, MapInstrument.horizonR)))
        node("map.rim", rect(MapInstrument.box(c, MapInstrument.tickOut)), text: String(m.hourDots))
        if let r = m.sun { node("map.sun", rect(r)) }
        if let r = m.sunGhost { node("map.sunGhost", rect(r)) }
        if let r = m.moon { node("map.moon", rect(r)) }
        if let r = m.core { node("map.core", rect(r)) }
        ForEach(Array(scene.elements.enumerated()), id: \.offset) { _, el in
            if case .text(let str, let center, let size, let weight, let mono, _, let anchor, let tracking) = el,
               let name = textNode(center: center, m) {
                Text(str)
                    .font(.system(size: size * s, weight: weight, design: mono ? .monospaced : .default))
                    .tracking(tracking * s)
                    .fixedSize()
                    .opacity(0)
                    .shotNode(name, text: str)
                    .alignmentGuide(.leading) { d in
                        let p = toScreen(center)
                        switch anchor {
                        case .start: return -p.x
                        case .middle: return -(p.x - d.width / 2)
                        case .end: return -(p.x - d.width)
                        }
                    }
                    .alignmentGuide(.top) { d in -(toScreen(center).y - d.height / 2) }
            }
        }
    }

    private func textNode(center: CGPoint, _ m: MapInstrument.Marks) -> String? {
        if center == m.north { return "map.north" }
        if let r = m.rise, center == r.0 { return "map.rise" }
        if let r = m.set, center == r.0 { return "map.set" }
        return nil
    }

    private func node(_ name: String, _ r: CGRect, text: String? = nil) -> some View {
        Color.clear
            .frame(width: r.width, height: r.height)
            .shotNode(name, text: text)
            .position(x: r.midX, y: r.midY)
            .allowsHitTesting(false)
    }

    // MARK: - Рисование

    static func draw(_ el: MapInstrument.Element, in ctx: inout GraphicsContext) {
        switch el {
        case .circle(let c, let r, let fill, let stroke, let width, let dash):
            let path = Path(ellipseIn: MapInstrument.box(c, r))
            if let fill { ctx.fill(path, with: .color(fill.color)) }
            if let stroke { ctx.stroke(path, with: .color(stroke.color), style: StrokeStyle(lineWidth: width, dash: dash)) }
        case .scrim(let c, let r):
            // `#limbScrim`: кольцо затемнения цветом тёмного холста у обода.
            let ink = RGBA.hex(0x14110E)
            let g = Gradient(stops: [
                .init(color: RGBA(ink.r, ink.g, ink.b, 0).color, location: 0.86),
                .init(color: RGBA(ink.r, ink.g, ink.b, 0.35).color, location: 0.91),
                .init(color: RGBA(ink.r, ink.g, ink.b, 0).color, location: 1),
            ])
            ctx.fill(Path(ellipseIn: MapInstrument.box(c, r)),
                     with: .radialGradient(g, center: c, startRadius: 0, endRadius: r))
        case .line(let a, let b, let stroke, let width, let dash, let round):
            var p = Path(); p.move(to: a); p.addLine(to: b)
            ctx.stroke(p, with: .color(stroke.color),
                       style: StrokeStyle(lineWidth: width, lineCap: round ? .round : .butt, dash: dash))
        case .path(let runs, let stroke, let width, let dash):
            var p = Path()
            for run in runs {
                guard let first = run.first else { continue }
                p.move(to: first)
                for q in run.dropFirst() { p.addLine(to: q) }
            }
            ctx.stroke(p, with: .color(stroke.color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
        case .dots(let pts, let color, let width):
            // Нулевой отрезок с круглым концом у веба — диск диаметром в толщину.
            var p = Path()
            let r = width / 2
            for q in pts { p.addEllipse(in: CGRect(x: q.x - r, y: q.y - r, width: width, height: width)) }
            ctx.fill(p, with: .color(color.color))
        case .text(let str, let center, let size, let weight, let mono, let color, let anchor, let tracking):
            let t = Text(str)
                .font(.system(size: size, weight: weight, design: mono ? .monospaced : .default))
                .tracking(tracking)
                .foregroundStyle(color.color)
            let a: UnitPoint = anchor == .start ? .leading : anchor == .end ? .trailing : .center
            ctx.draw(t, at: center, anchor: a)
        case .chip(let str, let center, let size, let color, let background, let tick):
            if let tick {
                var p = Path(); p.move(to: tick.0); p.addLine(to: tick.1)
                ctx.stroke(p, with: .color(tick.3.color), lineWidth: tick.2)
            }
            let text = ctx.resolve(Text(str).font(.system(size: size, weight: .semibold, design: .monospaced))
                .foregroundStyle(color.color))
            let bw = text.measure(in: CGSize(width: 400, height: 100)).width
            let h = size + 2 + 7
            let box = CGRect(x: center.x - bw / 2 - 6, y: center.y - h / 2, width: bw + 12, height: h)
            let shape = Path(roundedRect: box, cornerRadius: h / 2)
            ctx.fill(shape, with: .color(background.color))
            ctx.stroke(shape, with: .color(RGBA(color.r, color.g, color.b, 0.5).color), lineWidth: 1)
            ctx.draw(text, at: center, anchor: .center)
        }
    }
}
