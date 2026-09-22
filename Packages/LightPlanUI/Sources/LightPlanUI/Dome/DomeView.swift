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

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    paint(&context, size: size, now: timeline.date)
                }
            }
            SkySwapButton(mode: $mode)
                .padding(.trailing, 8)
                .padding(.bottom, 4)
        }
        .aspectRatio(CGFloat(DomeGeometry.viewWidth / DomeGeometry.viewHeight), contentMode: .fit)
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
        context.scaleBy(x: size.width / CGFloat(g.viewWidth), y: size.height / CGFloat(g.viewHeight))

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
        context.stroke(arcPath(), with: .linearGradient(arcGradient(moon: false),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: CGFloat(g.viewWidth), y: 0)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round))

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

        if e > 0.5 {
            var drop = Path()
            drop.move(to: p)
            drop.addLine(to: CGPoint(x: p.x, y: CGFloat(g.horizonY)))
            context.stroke(drop, with: .color(ink6), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
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
        // Тень как свойство слоя — допустимое улучшение против радиального
        // градиента веба (риск плана, итерация 18): нужна ровно там, где
        // светлое сливается со светлым, то есть только на светлой теме.
        if colorScheme == .light {
            let shadowAlpha = v * g.shadeNeed(color) * 0.4
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(shadowAlpha), radius: 4, x: 0, y: 2))
                layer.fill(corePath, with: .color(ink.opacity(v)))
                layer.stroke(corePath, with: .color(surfaceColor.opacity(v)), lineWidth: 2.5)
            }
        } else {
            context.fill(corePath, with: .color(ink.opacity(v)))
            context.stroke(corePath, with: .color(surfaceColor.opacity(v)), lineWidth: 2.5)
        }
    }

    private func paintNowRing(_ context: inout GraphicsContext, at pos: CGPoint) {
        let rect = CGRect(x: pos.x - 11, y: pos.y - 11, width: 22, height: 22)
        context.stroke(Path(ellipseIn: rect), with: .color(nowRingColor), lineWidth: 1.2)
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
