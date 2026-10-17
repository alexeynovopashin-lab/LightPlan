import SwiftUI
import LightPlanCore

/// Метки светил на экране AR (шаги 29.8в.4, 29.8в.5): солнце и луна — стеклянные линзы, различимые и ночью.
///
/// - **Солнце:** диск стекла; оттенок — по состоянию света в этот момент (`SunARInk.sunGlassTint`: день светло-жёлтый,
///   золотой час янтарный, закат красно-оранжевый, синий час розово-синий, ночью тёмно-синий). Под горизонтом
///   контур пунктиром. 48 pt «сейчас», 34 pt выбранный. Лучиков нет.
/// - **Луна:** диск стекла холодного серебристого оттенка; внутри — фаза из ядра (`MoonPhase`): освещённая часть
///   и терминатор, светлая кромка смотрит на солнце. Новолуние — тонкий контур диска. 40 / 30 pt.
///
/// Слово Алексея 14.10: «солнце и луна бубликом и за линией, выглядит плохо. Заменить на стеклянный кружок…
/// должны различаться, даже в ночном режиме. Луна должна показывать свою фазу». Слово 15.10: «стекло без кромки,
/// нет искажений». Линза гнёт всё, что под ней: кадр камеры (слой Metal) и дугу с подписями (`LensRefraction`
/// над `SunAROverlay`), потому что дуга не «просвечивает» сквозь прозрачный налёт, а гнётся вместе с кадром.

struct SunARMark: Equatable, Identifiable {
    enum Kind: Equatable {
        case sun
        case moon(illuminated: Double, waxing: Bool, limb: Double?)
    }

    let id: String
    let kind: Kind
    let center: CGPoint
    let diameter: CGFloat
    /// 1 — над горизонтом; призрак — 0,4 (светило не исчезает, оно идёт ниже линии горизонта).
    let fade: Double
    /// Солнце: геометрическая высота в этот момент — по ней диск берёт цвет света. У луны не используется.
    var altitude: Double = 45
    /// Видимая высота ниже линии горизонта: контур диска солнца — пунктиром, как дуга под горизонтом.
    var belowHorizon = false

    var radius: CGFloat { diameter / 2 }
    var origin: CGPoint { CGPoint(x: center.x - radius, y: center.y - radius) }
    var isSun: Bool { if case .sun = kind { return true } else { return false } }

    /// Оттенок стекла: у солнца — по состоянию света на его высоте, у луны — серебристый.
    var tint: Color { isSun ? SunARInk.sunGlassTint(altitude: altitude) : SunARInk.moonTint }

    /// Контур пунктиром: солнце ниже линии горизонта. У луны контур сплошной — её отличает фаза.
    var dashedContour: Bool { isSun && belowHorizon }
}

enum SunARMarks {
    static let ghostFade = 0.4

    /// Метки в порядке рисования снизу вверх: луна «сейчас», луна выбранная, солнце выбранное, солнце «сейчас».
    /// Метки, ушедшие за кадр дальше чем на 60 pt, не берутся. Слились (выбранный момент = сейчас) — одна метка
    /// большего диаметра.
    static func make(sun: SunARScene, night: NightSkyARScene?, screen: CGSize) -> [SunARMark] {
        let bounds = CGRect(origin: .zero, size: screen).insetBy(dx: -60, dy: -60)
        func visible(_ p: ScreenPoint?) -> CGPoint? {
            guard let p else { return nil }
            let c = CGPoint(x: p.x, y: p.y)
            return bounds.contains(c) ? c : nil
        }
        var out: [SunARMark] = []

        if let night, let picked = night.picked {
            func moon(_ m: NightSkyARScene.MoonMark, id: String, d: CGFloat) -> SunARMark? {
                guard let c = visible(m.point) else { return nil }
                return SunARMark(id: id, kind: .moon(illuminated: m.illuminated, waxing: m.waxing, limb: m.limbAngle),
                                 center: c, diameter: d, fade: m.ghost ? ghostFade : 1)
            }
            if let now = night.now, let mark = moon(now, id: "moon.now", d: SunARInk.moonNowDiameter) { out.append(mark) }
            // Нет «сейчас» — метки слились: выбранная и есть «сейчас».
            let merged = night.now == nil
            if let mark = moon(picked, id: merged ? "moon.now" : "moon.picked",
                               d: merged ? SunARInk.moonNowDiameter : SunARInk.moonPickedDiameter) { out.append(mark) }
        }

        let pickedFade = sun.markerGhost ? ghostFade : 1.0
        if !sun.markerIsNow, let c = visible(sun.marker) {
            out.append(SunARMark(id: "sun.picked", kind: .sun, center: c, diameter: SunARInk.pickedLensDiameter, fade: pickedFade,
                                 altitude: sun.markerAltitude, belowHorizon: sun.markerBelowHorizon))
        }
        if sun.markerIsNow {
            if let c = visible(sun.marker) {
                out.append(SunARMark(id: "sun.now", kind: .sun, center: c, diameter: SunARInk.nowLensDiameter, fade: pickedFade,
                                     altitude: sun.markerAltitude, belowHorizon: sun.markerBelowHorizon))
            }
        } else if let c = visible(sun.nowMarker), let alt = sun.nowAltitude {
            out.append(SunARMark(id: "sun.now", kind: .sun, center: c, diameter: SunARInk.nowLensDiameter,
                                 fade: sun.nowGhost ? ghostFade : 1, altitude: alt, belowHorizon: sun.nowBelowHorizon))
        }
        return out
    }
}

#if os(iOS)
extension SunARMark {
    /// Диск для слоя Metal: тот же центр и радиус, кромка — по рецепту стекла. Линза гнёт всегда в полную силу:
    /// призрак (`fade`) приглушает налёт и контур диска, а не искажение (дуга под ним идёт без разрыва).
    var lensSpec: ARLensSpec {
        ARLensSpec(center: center, radius: radius, rim: SunARInk.rim(for: diameter), fade: 1)
    }
}
#endif

// MARK: - Рисунок меток

/// Налёт, кромка и контур метки: оттенок, свет сверху, тёмный контур снаружи (`LensGlass`), у луны — фаза.
/// Лежит над линзой (`LensRefraction`): сама она ничего не гнёт, гнёт слой под ней.
struct SunARMarkPaint: View {
    let mark: SunARMark
    /// Строка узла для снимков: что за метка и где (Debug).
    var shotText: String?

    var body: some View {
        let d = mark.diameter
        ZStack {
            switch mark.kind {
            case .sun:
                LensGlass(diameter: d, tint: mark.tint, multiply: SunARInk.sunMultiply, veil: SunARInk.sunVeil,
                          fade: mark.fade, dashedContour: mark.dashedContour)
            case .moon(let illuminated, let waxing, let limb):
                LensGlass(diameter: d, tint: mark.tint, fade: mark.fade)
                MoonPhaseGlyph(illuminated: illuminated, waxing: waxing, limb: limb)
                    .frame(width: d - 2 * SunARInk.moonInset, height: d - 2 * SunARInk.moonInset)
                    .opacity(mark.fade)
            }
        }
        .frame(width: d, height: d)
        // Узел для снимков — рамка самого диска.
        .shotNode("ar.mark." + mark.id, text: shotText)
        .position(x: mark.center.x, y: mark.center.y)
        .allowsHitTesting(false)
    }
}

/// Фаза луны внутри диска: тёмная часть, освещённая часть и тонкий контур. Светлая кромка смотрит туда, куда
/// указывает `limb` (радианы в оси экрана, 0 — вправо, π/2 — вверх); без него — вправо у растущей, влево у
/// убывающей (значок включателя). Новолуние — только контур.
struct MoonPhaseGlyph: View {
    let illuminated: Double
    let waxing: Bool
    let limb: Double?

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            ctx.fill(disc, with: .color(.black.opacity(0.38)))
            let outline = MoonDisc.litOutline(fraction: illuminated)
            if !outline.isEmpty {
                let theta = limb ?? (waxing ? 0 : Double.pi)
                let ct = cos(theta), st = sin(theta)
                var p = Path()
                for (i, q) in outline.enumerated() {
                    // Единичный контур: +x к солнцу, y вниз. Поворот на `theta` против часовой в оси экрана.
                    let pt = CGPoint(x: c.x + r * (q.x * ct + q.y * st), y: c.y + r * (-q.x * st + q.y * ct))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath()
                ctx.fill(p, with: .color(.white.opacity(0.92)))
            }
            ctx.stroke(disc, with: .color(.white.opacity(0.8)), lineWidth: 0.8)
        }
    }
}

// MARK: - Подписи «сейчас» и выбранного момента

/// Подпись выбранного момента на плашке — только если он не «сейчас» (слово Алексея 15.10: время «сейчас»
/// не пишется на метке вовсе, оно в панели внизу; метка одна — подписи нет). Плашка лежит у выбранной метки с
/// той стороны, что дальше от метки «сейчас»; над диском.
struct SunARMarkLabels: View {
    let pickedLabel: String?
    let marks: [SunARMark]
    let screen: CGSize

    var body: some View {
        let nowMark = marks.first { $0.id == "sun.now" }
        let pickedMark = marks.first { $0.id == "sun.picked" }
        // Выбранная метка выше «сейчас» — подпись над ней, иначе под ней.
        let below = !(pickedMark != nil && nowMark != nil && pickedMark!.center.y < nowMark!.center.y)
        ZStack(alignment: .topLeading) {
            if let m = pickedMark, let text = pickedLabel {
                plate(text, weight: .medium,
                      at: CGPoint(x: m.center.x, y: m.center.y + (below ? 1 : -1) * (m.radius + SunARInk.markerLabelGap)),
                      fade: m.fade)
            }
        }
        .allowsHitTesting(false)
    }

    private func plate(_ text: String, weight: Font.Weight, at c: CGPoint, fade: Double) -> some View {
        Text(text)
            .font(.system(size: 12, weight: weight).monospacedDigit())
            .foregroundStyle(SunARInk.light)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(GlassPlate(shape: Capsule(), opacity: SunARInk.plateOpacity))
            .opacity(fade)
            .shotNode("ar.label.picked", text: text)
            .position(x: min(max(c.x, halfWidth(text) + 8), screen.width - halfWidth(text) - 8), y: c.y)
    }

    /// Половина ширины плашки по числу знаков (цифры одной ширины, 12 pt ≈ 7 pt на знак + поля) — чтобы плашка
    /// у края кадра не уезжала за экран.
    private func halfWidth(_ text: String) -> CGFloat { (CGFloat(text.count) * 7 + 16) / 2 }
}

// MARK: - Млечный Путь

/// Полоса Млечного Пути и ядро поверх кадра под дугами. Ночью — тихая светлая полоса из трёх слоёв (кромка,
/// середина, ось: края мягче, ось ярче); днём (солнце выше −6°) — призрак с непрозрачностью 0,25
/// (`MilkyWayAR.ghostOpacity`). Расчёт — ядра (`MilkyWay`), здесь только рисование.
struct SunARMilkyWayLayer: View {
    let scene: NightSkyARScene
    let coreLabel: String
    /// Диски меток: под ними полоса не рисуется — то, что видно сквозь линзу, рисует её копия (`LensRefraction`).
    var holes: [SunARHole] = []

    var body: some View {
        let k = scene.skyGhost ? MilkyWayAR.ghostOpacity : 1.0
        ZStack {
            SunARMilkyWayCanvas(scene: scene, holes: holes)
            if let c = scene.core {
                Text(coreLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SunARInk.light)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(GlassPlate(shape: Capsule(), opacity: SunARInk.plateOpacity))
                    .opacity(k)
                    .position(x: c.x, y: c.y + 30)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Круг на экране, внутри которого слой не рисуется (диск метки): центр и радиус в точках окна.
struct SunARHole: Equatable {
    var center: CGPoint
    var radius: CGFloat

    init(center: CGPoint, radius: CGFloat) { self.center = center; self.radius = radius }
    init(_ mark: SunARMark) { self.init(center: mark.center, radius: mark.radius) }

    /// Область «весь холст минус круги» — для обрезки по правилу чётности.
    static func clipArea(_ view: CGRect, holes: [SunARHole]) -> Path {
        var area = Path(view.insetBy(dx: -200, dy: -200))
        for h in holes {
            area.addEllipse(in: CGRect(x: h.center.x - h.radius, y: h.center.y - h.radius,
                                       width: 2 * h.radius, height: 2 * h.radius))
        }
        return area
    }
}

/// Полоса и ядро одним холстом. `origin` — левый верхний угол холста в окне экрана: копия под линзой рисует
/// тот же кадр в маленьком холсте.
struct SunARMilkyWayCanvas: View {
    let scene: NightSkyARScene
    var origin: CGPoint = .zero
    var holes: [SunARHole] = []

    var body: some View {
        let k = scene.skyGhost ? MilkyWayAR.ghostOpacity : 1.0
        Canvas { ctxIn, size in
            var ctx = ctxIn
            ctx.translateBy(x: -origin.x, y: -origin.y)
            if !holes.isEmpty {
                ctx.clip(to: SunARHole.clipArea(CGRect(origin: origin, size: size), holes: holes), style: FillStyle(eoFill: true))
            }
            for poly in scene.band where poly.count >= 4 {
                let n = poly.count / 2
                // Три слоя: полный, 65 % и 30 % ширины полосы — середина набирает яркость.
                for (share, alpha) in [(1.0, 0.07), (0.65, 0.07), (0.3, 0.09)] {
                    var p = Path()
                    func edge(_ i: Int) -> CGPoint {
                        let l = poly[i], r = poly[poly.count - 1 - i]
                        let mx = (l.x + r.x) / 2, my = (l.y + r.y) / 2
                        return CGPoint(x: mx + (l.x - mx) * share, y: my + (l.y - my) * share)
                    }
                    func back(_ i: Int) -> CGPoint {
                        let l = poly[i], r = poly[poly.count - 1 - i]
                        let mx = (l.x + r.x) / 2, my = (l.y + r.y) / 2
                        return CGPoint(x: mx + (r.x - mx) * share, y: my + (r.y - my) * share)
                    }
                    p.move(to: edge(0))
                    for i in 1..<n { p.addLine(to: edge(i)) }
                    for i in stride(from: n - 1, through: 0, by: -1) { p.addLine(to: back(i)) }
                    p.closeSubpath()
                    ctx.fill(p, with: .color(SunARInk.milkyWayTone.opacity(alpha * k)))
                }
            }
            if let c = scene.core {
                let r: CGFloat = 40
                let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                ctx.fill(Path(ellipseIn: rect),
                         with: .radialGradient(Gradient(colors: [SunARInk.coreTone.opacity(0.85 * k),
                                                                 SunARInk.coreTone.opacity(0.25 * k),
                                                                 SunARInk.coreTone.opacity(0)]),
                                               center: CGPoint(x: c.x, y: c.y), startRadius: 0, endRadius: r))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Значки включателей

/// Значок «Луна»: кружок с её фазой на выбранный момент.
struct MoonToggleIcon: View {
    let illuminated: Double
    let waxing: Bool

    var body: some View {
        MoonPhaseGlyph(illuminated: illuminated, waxing: waxing, limb: nil)
            .frame(width: 22, height: 22)
    }
}

/// Значок «Млечный Путь»: наклонная полоса с яркой точкой — ядром.
struct MilkyWayToggleIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            var band = Path(roundedRect: CGRect(x: -13, y: -4.5, width: 26, height: 9), cornerRadius: 4.5)
            band = band.applying(CGAffineTransform(rotationAngle: -.pi / 5).concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
            ctx.fill(band, with: .color(.white.opacity(0.55)))
            ctx.stroke(band, with: .color(.white.opacity(0.9)), lineWidth: 0.8)
            let core = CGPoint(x: c.x + 5.5, y: c.y - 4)
            ctx.fill(Path(ellipseIn: CGRect(x: core.x - 3.2, y: core.y - 3.2, width: 6.4, height: 6.4)),
                     with: .color(SunARInk.coreTone))
        }
        .frame(width: 26, height: 22)
    }
}

// MARK: - Стрелка за краем кадра

/// Светило, к которому ведёт стрелка у края.
struct SunARPointerItem: Identifiable, Equatable {
    enum Body: Equatable {
        case sun
        case moon(illuminated: Double, waxing: Bool)
        case core
    }

    let id: String
    let body: Body
    let pointer: EdgePointer
    /// «320° · +12°»: азимут и высота светила.
    let text: String
    let fade: Double
}

/// Стеклянный кружок со стрелкой на краю экрана в сторону светила и подпись «азимут · высота» (слово Алексея
/// 14.10 и запись задачи 29.8в.4). Стекло стоит ровно, поворачивается только стрелка внутри него.
struct SunARPointerView: View {
    let item: SunARPointerItem
    let screen: CGSize
    /// Нижняя граница, ниже которой подпись уходит над кружок (под ним панель).
    let labelFlipY: CGFloat

    var body: some View {
        let d = SunARInk.pointerDiameter
        let p = CGPoint(x: item.pointer.point.x, y: item.pointer.point.y)
        let dir = CGPoint(x: cos(item.pointer.angle), y: sin(item.pointer.angle))
        ZStack {
            Color.clear
                .frame(width: d, height: d)
                .glassEffect(SunARInk.buttonGlass, in: Circle())
            mini
                .offset(x: -dir.x * 4, y: -dir.y * 4)
            Icon("chevron", size: 14, line: 2.6)
                .foregroundStyle(SunARInk.light)
                .rotationEffect(.radians(item.pointer.angle))
                .offset(x: dir.x * (d / 2 - 9), y: dir.y * (d / 2 - 9))
        }
        .frame(width: d, height: d)
        .opacity(item.fade)
        // Узел — до `position`: рамка значка, а не всего экрана (по ней сверяется зазор между стрелками, 29.8в.6).
        .shotNode("ar.pointer." + item.id, text: item.text)
        .position(x: p.x, y: p.y)
        .overlay(alignment: .topLeading) {
            let w = (CGFloat(item.text.count) * 7 + 16)
            let below = p.y + d / 2 + 14 < labelFlipY
            Text(item.text)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(SunARInk.light)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(GlassPlate(shape: Capsule(), opacity: SunARInk.plateOpacity))
                .fixedSize()
                .shotNode("ar.pointerLabel." + item.id, text: item.text)
                .position(x: min(max(p.x, w / 2 + 8), screen.width - w / 2 - 8),
                          y: below ? p.y + d / 2 + 14 : p.y - d / 2 - 14)
                .opacity(item.fade)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private var mini: some View {
        switch item.body {
        case .sun:
            Circle().fill(SunARInk.sunTint).frame(width: 12, height: 12)
                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
        case .moon(let illuminated, let waxing):
            MoonPhaseGlyph(illuminated: illuminated, waxing: waxing, limb: nil).frame(width: 16, height: 16)
        case .core:
            Circle().fill(SunARInk.coreTone).frame(width: 11, height: 11)
                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
        }
    }
}
