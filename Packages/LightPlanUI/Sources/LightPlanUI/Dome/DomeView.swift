import SwiftUI
import LightPlanCore

/// Купол — главный прибор экрана «Свет». Порт `.dome` (веб): дуга дня,
/// светило с плоским диском, зарево у горизонта, свет ушедшего светила,
/// звёзды, метеоры, кольцо «сейчас», лунный диск с фазой, тумблер
/// солнце/луна. Композицию и вёрстку экрана вокруг него не трогает —
/// это дело «Света» (итерация 19).
///
/// Рисует один `Canvas` в модельных координатах `viewBox` веба (390×240,
/// `DomeGeometry`), а не дерево `View`/`Shape` на каждую деталь: план прямо
/// называет холст, и купол живёт от минуты, а не от жеста, так что дешёвый
/// перерасчёт на кадр важнее послойной иерархии.
///
/// **Тень светила — не радиальный градиент, а свойство слоя** (`GraphicsContext`
/// `.shadow` у `drawLayer`), как и предупреждал план (риск, итерация 18):
/// мягкость другая, чем у веба, и это записанное решение, а не недосмотр —
/// см. DECISIONS «Тень купола — свойство слоя».
public struct DomeView: View {
    let sun: SolarDay
    let place: Place
    let date: CivilDate
    let t: Minutes
    /// `nil`, если смотрим не сегодняшний день — кольца «сейчас» тогда нет.
    let nowMinute: Minutes?
    @Binding var mode: DomeSkyMode

    @Environment(\.colorScheme) private var colorScheme
    @State private var meteors = DomeMeteorController()

    public init(sun: SolarDay, place: Place, date: CivilDate, t: Minutes, nowMinute: Minutes?, mode: Binding<DomeSkyMode>) {
        self.sun = sun
        self.place = place
        self.date = date
        self.t = t
        self.nowMinute = nowMinute
        self._mode = mode
    }

    /// Высота купола — `.dome { height: 240px }` веба. Холст вписывается в
    /// рамку как `viewBox` с `meet`: масштаб по меньшей стороне, по центру.
    /// На 440 pt ширины (17 Pro Max) это масштаб 1 и поля по 25 pt — до
    /// 19б купол растягивался на всю ширину (×1,046) и был выше на 11 pt.
    public static let height: CGFloat = 240

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    paint(&context, size: size, now: timeline.date)
                }
            }
            #if DEBUG
            DomeProbe(sun: sun, t: t, nowMinute: nowMinute, moon: mode == .moon)
            #endif
            // `.sky-swap`: сверху справа, 26 pt от верха купола, 12 от края,
            // своё поле 7 pt вокруг знака 52×26.
            SkySwapButton(mode: $mode)
                .padding(7)
                .shotNode("dome.swap")
                .padding(.top, 26)
                .padding(.trailing, 12)
        }
        .frame(height: Self.height)
        .onAppear {
            refreshMeteorStarsOpacity()
            meteors.start()
        }
        .onDisappear { meteors.stop() }
        .onChange(of: t) {
            // Свежая на каждый сдвиг минуты: замыкание, схваченное однажды в
            // `onAppear`, держало бы то время, каким купол появился на
            // экране, и звезда падала бы по тому небу, а не по нынешнему.
            refreshMeteorStarsOpacity()
            meteors.noteActivity()
        }
        .onChange(of: mode) { meteors.noteActivity() }
    }

    private func refreshMeteorStarsOpacity() {
        meteors.starsOpacity = { [sun, t] in
            DomeGeometry.clamp((-sun.elevation(at: t) - 8) / 8, 0, 1)
        }
    }

    // MARK: - Токены темы

    /// Купол ещё не заведён в общий словарь тем экрана (итерация 19) — эти
    /// несколько цветов нужны только ему, взяты из CSS веба буквально.
    private var surfaceColor: Color {
        colorScheme == .light ? Color(red: 0xFA / 255, green: 0xF8 / 255, blue: 0xF3 / 255)
                               : Color(red: 0x0F / 255, green: 0x0E / 255, blue: 0x0C / 255)
    }
    private var ink6: Color {
        colorScheme == .light ? Color(red: 0x8C / 255, green: 0x85 / 255, blue: 0x78 / 255)
                               : Color(red: 0x63 / 255, green: 0x5E / 255, blue: 0x54 / 255)
    }
    private var hairColor: Color {
        colorScheme == .light ? Color.black.opacity(0.07) : Color.white.opacity(0.05)
    }
    private var nowRingColor: Color {
        colorScheme == .light ? Color(red: 0x17 / 255, green: 0x15 / 255, blue: 0x0F / 255).opacity(0.2)
                               : Color(red: 0xEF / 255, green: 0xEA / 255, blue: 0xE0 / 255).opacity(0.2)
    }
    private var arcMid: Color {
        colorScheme == .light ? Color(red: 0x17 / 255, green: 0x15 / 255, blue: 0x0F / 255)
                               : Color(red: 0xEF / 255, green: 0xEA / 255, blue: 0xE0 / 255)
    }
    private var moonDark: Color { Color(red: 0x16 / 255, green: 0x16 / 255, blue: 0x1A / 255) }

    // MARK: - Рисование

    private func paint(_ context: inout GraphicsContext, size: CGSize, now: Date) {
        let g = DomeGeometry.self
        let fit = DomeFit(size: size)
        context.translateBy(x: fit.origin.x, y: fit.origin.y)
        context.scaleBy(x: fit.scale, y: fit.scale)

        let moon = mode == .moon
        let e = sun.elevation(at: t)
        let state = sun.state(at: t)
        let p = g.posAt(t, sun: sun)

        paintStarsAndMeteors(&context, e: e, now: now)
        paintHorizonGlow(&context, atX: Double(p.x), color: state.color, glowAmount: state.glow)
        paintHorizonLine(&context)

        if moon {
            paintMoon(&context)
        } else {
            paintSun(&context, e: e, p: p, state: state)
        }
    }

    // MARK: Звёзды и метеоры (только над горизонтом)

    private func paintStarsAndMeteors(_ context: inout GraphicsContext, e: Degrees, now: Date) {
        let opacity = DomeGeometry.clamp((-e - 8) / 8, 0, 1)
        guard opacity > 0.002 else { return }
        let g = DomeGeometry.self
        context.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: 0, y: 0, width: CGFloat(g.viewWidth), height: CGFloat(g.horizonY))))
            // Небо неспешно вращается вокруг центра купола вместе со сдвигом
            // времени — та же формула, что в вебе (`0.25°` в минуту).
            let angle = (t - sun.mint) * 0.25 * .pi / 180
            let ca = cos(angle), sa = sin(angle)
            for star in DomeStars.points {
                let dx = star.x - g.cx, dy = star.y - g.cy
                let x = g.cx + dx * ca - dy * sa
                let y = g.cy + dx * sa + dy * ca
                let rect = CGRect(x: CGFloat(x - star.radius), y: CGFloat(y - star.radius),
                                   width: CGFloat(star.radius * 2), height: CGFloat(star.radius * 2))
                layer.opacity = star.opacity * opacity
                layer.fill(Path(ellipseIn: rect), with: .color(Color(red: 0xCB / 255, green: 0xD7 / 255, blue: 0xEA / 255)))
            }
            layer.opacity = 1
            for meteor in meteors.active {
                guard let head = meteor.head(at: now) else { continue }
                var line = Path()
                line.move(to: head.point)
                let tail = meteor.tail
                line.addLine(to: CGPoint(x: head.point.x + tail.x, y: head.point.y + tail.y))
                layer.stroke(line, with: .color(Color(red: 0xDD / 255, green: 0xE6 / 255, blue: 0xF2 / 255).opacity(head.opacity)),
                             style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
        }
    }

    private func paintHorizonLine(_ context: inout GraphicsContext) {
        let g = DomeGeometry.self
        var line = Path()
        line.move(to: CGPoint(x: 18, y: CGFloat(g.horizonY)))
        line.addLine(to: CGPoint(x: 372, y: CGFloat(g.horizonY)))
        context.stroke(line, with: .color(hairColor), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
    }

    private func paintHorizonGlow(_ context: inout GraphicsContext, atX x: Double, color: SkyColor, glowAmount: Double) {
        let g = DomeGeometry.self
        let cx = g.clamp(x, 60, 330)
        let glowK = colorScheme == .light ? 0.42 : 1.0
        let opacity = g.clamp(glowAmount * glowK, 0, 1)
        guard opacity > 0.002 else { return }
        context.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: 0, y: 0, width: CGFloat(g.viewWidth), height: CGFloat(g.horizonY))))
            layer.translateBy(x: CGFloat(cx), y: CGFloat(g.horizonY))
            layer.scaleBy(x: 130.0 / 62.0, y: 1)
            let r: CGFloat = 62
            let rect = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
            layer.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [Color(color).opacity(opacity * 0.32), Color(color).opacity(0)]),
                center: .zero, startRadius: 0, endRadius: r))
        }
    }

    // MARK: Солнце

    /// Статичная дуга-градиент: те же неизменные стопы, что у веба
    /// (`#dayLight`/`#moonLight`) — не пересчитывается по минуте, дуга не
    /// красит текущее состояние света, она обрамляет купол.
    private func arcGradient(moon: Bool) -> Gradient {
        if moon {
            let c = Color(red: 0xA8 / 255, green: 0xBD / 255, blue: 0xD8 / 255)
            return Gradient(stops: [
                .init(color: c.opacity(0.5), location: 0),
                .init(color: arcMid.opacity(0.2), location: 0.3),
                .init(color: arcMid.opacity(0.2), location: 0.7),
                .init(color: c.opacity(0.5), location: 1),
            ])
        }
        let c = Color(red: 0xE2 / 255, green: 0xA4 / 255, blue: 0x4C / 255)
        return Gradient(stops: [
            .init(color: c, location: 0), .init(color: c, location: 0.1),
            .init(color: arcMid.opacity(0.28), location: 0.3),
            .init(color: arcMid.opacity(0.28), location: 0.7),
            .init(color: c, location: 0.9), .init(color: c, location: 1),
        ])
    }

    private func arcPath() -> Path {
        let g = DomeGeometry.self
        var path = Path()
        let steps = 96
        for i in 0...steps {
            let deg = 180 - Double(i) / Double(steps) * 180
            let th = deg * .pi / 180
            let point = CGPoint(x: CGFloat(g.cx + g.rx * cos(th)), y: CGFloat(g.cy - g.ry * sin(th)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    private func paintSun(_ context: inout GraphicsContext, e: Degrees, p: CGPoint, state: LightState) {
        let g = DomeGeometry.self
        // Светлая тема: дуга приподнята тенью 0 5 10 (`#arcPath` веба,
        // `drop-shadow(... rgba(23,21,15,0.18))`) — край неба, а не предмет.
        context.drawLayer { layer in
            if colorScheme == .light {
                layer.addFilter(.shadow(color: Color(hex: 0x17150F, alpha: 0.18), radius: 5, x: 0, y: 5))
            }
            layer.stroke(arcPath(), with: .linearGradient(arcGradient(moon: false),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: CGFloat(g.viewWidth), y: 0)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }

        // Отвес — под телом светила, как `#drop` в разметке веба (до 19б
        // рисовался поверх и резал диск штрихом).
        if e > 0.5 {
            var drop = Path()
            drop.move(to: p)
            drop.addLine(to: CGPoint(x: p.x, y: CGFloat(g.horizonY)))
            context.stroke(drop, with: .color(ink6), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
        }

        // Свет ушедшего светила: до −18° своё небо, глубже — чужой рассвет
        // на другой стороне планеты (высота там ровно −e), светлая тема
        // берёт его на ступень темнее.
        let below = -e - 18
        var deepColor = state.color
        if below > 0 {
            var other = LightPalette.skyColor(elevation: -e)
            if colorScheme == .light {
                other = SkyColor(Int((Double(other.r) * 0.55).rounded()),
                                  Int((Double(other.g) * 0.55).rounded()),
                                  Int((Double(other.b) * 0.55).rounded()))
            }
            deepColor = LightPalette.lerp(state.color, other, g.clamp(below / 6, 0, 1))
        }

        let polar = sun.polar != .normal
        if polar {
            let polP = g.polarAt(t, sun: sun)
            paintBody(&context, at: polP.p, eD: min(e, g.geoDegrees(polP.p)), weight: polP.k,
                      color: state.color, deepColor: deepColor)
            paintBody(&context, at: polP.twin, eD: min(e, g.geoDegrees(polP.twin)), weight: 1 - polP.k,
                      color: state.color, deepColor: deepColor)
        } else {
            paintBody(&context, at: p, eD: e, weight: 1, color: state.color, deepColor: deepColor)
        }

        if let nowMinute, sun.elevation(at: nowMinute) > 0.5 {
            paintNowRing(&context, at: g.posAt(nowMinute, sun: sun))
        }
    }

    /// Один свод рисуется дважды: тело и то, что стоит у другого конца
    /// портала (полярные сутки). `weight` — доля света на это тело; сумма
    /// тела и двойника всегда единица.
    private func paintBody(_ context: inout GraphicsContext, at pos: CGPoint, eD: Degrees, weight k: Double,
                            color: SkyColor, deepColor: SkyColor) {
        let g = DomeGeometry.self
        let v = (eD < 0 ? max(0, 1 - (-eD / 3)) : 1) * k
        let ink = Color(color)

        // Свет ушедшего светила: просвечивающее пятно без кромки.
        let deepFactor = g.deepOf(eD) * k
        if deepFactor > 0.002 {
            context.drawLayer { layer in
                layer.opacity = deepFactor
                let r: CGFloat = 34
                let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
                layer.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(deepColor).opacity(0.34), location: 0),
                        .init(color: Color(deepColor).opacity(0.13), location: 0.42),
                        .init(color: Color(deepColor).opacity(0), location: 1),
                    ]), center: pos, startRadius: 0, endRadius: r))
            }
        }
        guard v > 0.002 || k > 0.002 else { return }

        // Диск: заливка держит массу, кромка её очерчивает, обе гаснут со
        // светилом. Свечение вокруг ослабевает отдельно от диска (`k`, не `v`
        // — у портала двойник светится ещё до того, как диск проступит).
        if k > 0.002 {
            let glowRect = CGRect(x: pos.x - 16, y: pos.y - 16, width: 32, height: 32)
            context.fill(Path(ellipseIn: glowRect), with: .color(ink.opacity(0.18 * v)))
            context.stroke(Path(ellipseIn: glowRect), with: .color(ink.opacity(0.34 * v)), lineWidth: 1)
        }

        guard v > 0.002 else { return }
        let coreRect = CGRect(x: pos.x - 6.5, y: pos.y - 6.5, width: 13, height: 13)
        let corePath = Path(ellipseIn: coreRect)
        // Тень светила — нарисованная, как у веба (`#sunShade`, `.lit-shade`):
        // круг 14,5 с градиентом «0,42 тьмы до 42 % радиуса → ноль», только в
        // светлой теме, сила — `shadeNeed`. Итерация 18 заменила её тенью
        // слоя (мягче и светлее); пара снимков 19б показала разницу числом —
        // фон вокруг диска #faf8f3 против #dcd7cc у веба, Δ 59, — и тень
        // вернулась к вебу буквально.
        if colorScheme == .light {
            let shade = v * g.shadeNeed(color)
            if shade > 0.002 {
                let r: CGFloat = 14.5
                let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
                context.drawLayer { layer in
                    layer.opacity = shade
                    layer.fill(Path(ellipseIn: rect), with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color(hex: 0x17150F, alpha: 0.42), location: 0.42),
                            .init(color: Color(hex: 0x17150F, alpha: 0), location: 1),
                        ]), center: pos, startRadius: 0, endRadius: r))
                }
            }
        }
        context.fill(corePath, with: .color(ink.opacity(v)))
        context.stroke(corePath, with: .color(surfaceColor.opacity(v)), lineWidth: 2.5)
    }

    private func paintNowRing(_ context: inout GraphicsContext, at pos: CGPoint) {
        let rect = CGRect(x: pos.x - 11, y: pos.y - 11, width: 22, height: 22)
        // Светлая тема: лёгкая тень 0 1 2 (`#nowRing` веба) — подсказка, не предмет.
        context.drawLayer { layer in
            if colorScheme == .light {
                layer.addFilter(.shadow(color: Color(hex: 0x17150F, alpha: 0.16), radius: 1, x: 0, y: 1))
            }
            layer.stroke(Path(ellipseIn: rect), with: .color(nowRingColor), lineWidth: 1.2)
        }
    }

    // MARK: Луна

    private func paintMoon(_ context: inout GraphicsContext) {
        let g = DomeGeometry.self
        context.stroke(arcPath(), with: .linearGradient(arcGradient(moon: true),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: CGFloat(g.viewWidth), y: 0)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round))

        let moonDay = MoonDay(date: date, place: place)
        let arc = moonDay.arc(at: t)
        let sample = MoonSample(date: date, minutes: t, place: place)
        let phase = sample.phase
        let pos = arc.map { g.posOn(t, $0.rise, $0.set) } ?? g.posOn(t, sun.mint, sun.maxt)
        let visibility = sample.altitude < 0 ? max(0, 1 + sample.altitude / 3) : 1
        guard visibility > 0.002 else { return }

        let mirrored = phase.cycle >= 0.5
        let discRadius: CGFloat = 7.5
        let discRect = CGRect(x: pos.x - discRadius, y: pos.y - discRadius, width: discRadius * 2, height: discRadius * 2)

        context.drawLayer { layer in
            layer.opacity = visibility

            if colorScheme == .light {
                layer.drawLayer { shadowLayer in
                    shadowLayer.addFilter(.shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2))
                    shadowLayer.fill(Path(ellipseIn: discRect), with: .color(moonDark))
                }
            }

            // Ореол растёт вместе с освещённой долей.
            let haloRect = CGRect(x: pos.x - 17, y: pos.y - 17, width: 34, height: 34)
            layer.opacity = visibility * phase.fraction
            layer.fill(Path(ellipseIn: haloRect), with: .color(Color(red: 0xA8 / 255, green: 0xBD / 255, blue: 0xD8 / 255).opacity(0.10)))
            layer.opacity = visibility

            layer.fill(Path(ellipseIn: discRect), with: .color(moonDark))
            layer.stroke(Path(ellipseIn: discRect), with: .color(surfaceColor), lineWidth: 2.5)

            // Освещённая доля: растущая луна светит справа, убывающая —
            // зеркалится (`MoonGlyph`, тот же знак, что в ячейке барабана).
            let litRect = CGRect(x: pos.x - discRadius, y: pos.y - discRadius, width: discRadius * 2, height: discRadius * 2)
            if mirrored {
                layer.drawLayer { lit in
                    lit.translateBy(x: pos.x, y: pos.y)
                    lit.scaleBy(x: -1, y: 1)
                    lit.translateBy(x: -pos.x, y: -pos.y)
                    lit.fill(MoonGlyph(fraction: phase.fraction).path(in: litRect),
                             with: .color(Color(red: 0xCF / 255, green: 0xD6 / 255, blue: 0xDE / 255)))
                }
            } else {
                layer.fill(MoonGlyph(fraction: phase.fraction).path(in: litRect),
                           with: .color(Color(red: 0xCF / 255, green: 0xD6 / 255, blue: 0xDE / 255)))
            }
        }

        if let nowMinute, let arc, MoonSample(date: date, minutes: nowMinute, place: place).altitude > 0.5 {
            paintNowRing(&context, at: g.posOn(nowMinute, arc.rise, arc.set))
        }
    }
}

/// Вписывание `viewBox` 390×240 в рамку купола, как `preserveAspectRatio`
/// по умолчанию у SVG веба (`xMidYMid meet`).
struct DomeFit {
    let scale: CGFloat
    let origin: CGPoint

    init(size: CGSize) {
        let g = DomeGeometry.self
        let k = min(size.width / CGFloat(g.viewWidth), size.height / CGFloat(g.viewHeight))
        scale = k
        origin = CGPoint(x: (size.width - CGFloat(g.viewWidth) * k) / 2,
                         y: (size.height - CGFloat(g.viewHeight) * k) / 2)
    }

    func point(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }
}

#if DEBUG
/// Рамки деталей купола для пары «веб / натив»: холст — один `Canvas`, и
/// узлов внутри у него нет. Прозрачные прямоугольники стоят там, где веб
/// держит `#sunCore` (r 6,5), `#nowRing` (r 11) и `#arcPath`.
private struct DomeProbe: View {
    let sun: SolarDay
    let t: Minutes
    let nowMinute: Minutes?
    let moon: Bool

    var body: some View {
        GeometryReader { geo in
            let fit = DomeFit(size: geo.size)
            let g = DomeGeometry.self
            let p = fit.point(g.posAt(t, sun: sun))
            let arc0 = fit.point(CGPoint(x: 32, y: CGFloat(g.horizonY) - 148))
            ZStack(alignment: .topLeading) {
                // Место — полями, а не `.offset`: смещение рисуется, но рамку
                // в раскладке не двигает, и отчёт видел бы узел в углу.
                mark("dome.arc", x: arc0.x, y: arc0.y, w: 326 * fit.scale, h: 148 * fit.scale)
                if !moon, sun.elevation(at: t) > -0.5 {
                    mark("dome.sun", x: p.x - 6.5 * fit.scale, y: p.y - 6.5 * fit.scale, w: 13 * fit.scale, h: 13 * fit.scale)
                    mark("dome.sunGlow", x: p.x - 16 * fit.scale, y: p.y - 16 * fit.scale, w: 32 * fit.scale, h: 32 * fit.scale)
                }
                if !moon, let nowMinute, sun.elevation(at: nowMinute) > 0.5 {
                    let r = fit.point(g.posAt(nowMinute, sun: sun))
                    mark("dome.ring", x: r.x - 11 * fit.scale, y: r.y - 11 * fit.scale, w: 22 * fit.scale, h: 22 * fit.scale)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }

    private func mark(_ name: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        Color.clear.frame(width: w, height: h).shotNode(name)
            .padding(.leading, x).padding(.top, y)
    }
}
#endif
