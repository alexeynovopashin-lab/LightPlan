import SwiftUI
import LightPlanCore
import LightPlanData
#if os(iOS)
import AVFoundation
#endif

/// Слой AR: дуга солнца на выбранный день поверх живого кадра (шаг 29.8в).
///
/// Экран получает только `SunARTarget` — место и момент — и ничего не знает о том, откуда его открыли
/// (слово Алексея 14.10: вход пересматриваемый). Камера — превью без выхода кадров; поворот — `CoreMotion`
/// от истинного севера; проекция — чистая функция `SkyProjection` в Core. Без камеры (симулятор, отказ,
/// ограничение) фон — спокойный градиент неба, а дуга и компас работают так же.
struct SunARScreen: View {
    @Bindable var app: AppModel
    let target: SunARTarget
    @State private var model: SunARModel
    @State private var lookStart: SunARModel.Look?
    @State private var glide: Task<Void, Never>?
    @Environment(\.colorScheme) private var scheme

    init(app: AppModel, target: SunARTarget) {
        self.app = app
        self.target = target
        _model = State(initialValue: SunARModel(target: target, source: SunARSources.attitude()))
    }

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        GeometryReader { g in
            let safe = g.safeAreaInsets
            let size = CGSize(width: g.size.width + safe.leading + safe.trailing,
                              height: g.size.height + safe.top + safe.bottom)
            let viewport = ScreenViewport(width: size.width, height: size.height)
            let sun = model.sun
            let scene = SunARScene.make(basis: model.aim, optics: model.optics, viewport: viewport,
                                        arc: model.arc, sun: sun)
            let clock = ClockText(language: app.language, preference: app.light.clockPreference)
            ZStack(alignment: .topLeading) {
                background(size: size, sun: sun, pal: pal)
                    .shotNode("ar.background", text: "\(model.camera)")
                if !model.camera.isLive, let ground = scene.ground {
                    Path { p in
                        p.move(to: CGPoint(ground[0]))
                        for q in ground.dropFirst() { p.addLine(to: CGPoint(q)) }
                        p.closeSubpath()
                    }
                    .fill(Color.black.opacity(SunARInk.groundOpacity))
                    .allowsHitTesting(false)
                }
                SunAROverlay(scene: scene, clock: clock, cardinals: ["card.n", "card.e", "card.s", "card.w"].map { t.t($0) })
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
                    .shotNode("ar.overlay", text: String(format: "marker=%@ arcSegments=%d hours=%d",
                                                         scene.marker.map { String(format: "%.1f,%.1f", $0.x, $0.y) } ?? "—",
                                                         scene.arc.count, scene.hours.count))
                controls(size: size, safe: safe, sun: sun, clock: clock)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(look(size: size))
            .ignoresSafeArea()
        }
        .task { await model.start() }
        .onDisappear { model.stop() }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Фон

    @ViewBuilder
    private func background(size: CGSize, sun: SunSample, pal: Palette) -> some View {
        #if os(iOS)
        if model.camera.isLive {
            ARCameraPreview(session: model.cameraSession)
        } else {
            skyGradient(sun: sun, pal: pal)
        }
        #else
        skyGradient(sun: sun, pal: pal)
        #endif
    }

    /// Спокойный градиент неба по высоте солнца в выбранный момент — тот же, что у купола «Астро».
    private func skyGradient(sun: SunSample, pal: Palette) -> some View {
        let sky = DomeSky(astro: true, elevation: sun.altitude, morning: model.minutes < 720,
                          lightTheme: !pal.dark, palette: nil)
        let zenith = sky.map { Color(red: Double($0.zenith.r) / 255, green: Double($0.zenith.g) / 255, blue: Double($0.zenith.b) / 255) } ?? Color(white: 0.06)
        let horizon = sky.map { Color(red: Double($0.horizon.r) / 255, green: Double($0.horizon.g) / 255, blue: Double($0.horizon.b) / 255) } ?? Color(white: 0.12)
        return LinearGradient(colors: [zenith, horizon], startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Взгляд пальцем (нет датчика)

    private func look(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                guard !model.hasSensor else { return }
                if lookStart == nil { lookStart = model.look }
                // Градусов на точку — по высоте кадра: длинная сторона кадра видна целиком по вертикали.
                let perPoint = model.optics.longSideFOV / max(1, size.height)
                model.drag(dx: v.translation.width, dy: v.translation.height, perPoint: perPoint, from: lookStart!)
            }
            .onEnded { _ in lookStart = nil }
    }

    // MARK: - Кнопки

    private func controls(size: CGSize, safe: EdgeInsets, sun: SunSample, clock: ClockText) -> some View {
        let aim = model.aim.aim
        return ZStack(alignment: .top) {
            VStack(spacing: 8) {
                HStack(alignment: .center) {
                    backButton
                    Spacer(minLength: 8)
                    headingChip(aim)
                }
                if model.unsteady {
                    plate(Text(t.t("ar.figure8")).font(.system(size: 13)))
                        .transition(.opacity)
                        .shotNode("ar.figure8", text: t.t("ar.figure8"))
                }
                if let why = cameraNote {
                    VStack(spacing: 4) {
                        Text(why)
                        if !model.hasSensor { Text(t.t("ar.drag")) }
                    }
                    .font(.system(size: 12)).multilineTextAlignment(.center)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(SunARInk.light)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(SunARInk.plateOpacity)))
                    .padding(.horizontal, 16)
                    .shotNode("ar.cameraNote", text: why)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, safe.top + 8)
            .padding(.horizontal, 12)
            .animation(PlanMotion.pick(.easeOut(duration: 0.2)), value: model.unsteady)
            VStack {
                Spacer()
                timePanel(sun: sun, clock: clock)
                    .padding(.horizontal, 12)
                    .padding(.bottom, max(safe.bottom, 12) + 4)
            }
        }
    }

    private var cameraNote: String? {
        switch model.camera {
        case .starting, .running: return nil
        case .noDevice: return t.t("ar.noCamera")
        case .denied: return t.t("ar.cameraDenied")
        case .restricted: return t.t("ar.cameraRestricted")
        case .failed: return t.t("ar.cameraFailed")
        }
    }

    private var backButton: some View {
        Button {
            withAnimation(PlanMotion.pick(PlanMotion.overlay)) { app.closeSunAR() }
        } label: {
            HStack(spacing: 6) {
                Icon("chevron", size: 16, line: 2.4).rotationEffect(.degrees(180))
                Text(t.t("nav.back")).font(webFont(15))
            }
            .foregroundStyle(SunARInk.light)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(SunARInk.plateOpacity)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .shotNode("ar.back", text: t.t("nav.back"))
    }

    private func headingChip(_ aim: HorizontalPoint) -> some View {
        HStack(spacing: 6) {
            HeadingGlyph()
                .stroke(SunARInk.light, style: StrokeStyle(lineWidth: 1.8 * 15 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 15, height: 15)
            Text(String(format: "%.0f°", aim.azimuth.rounded() == 360 ? 0 : aim.azimuth.rounded()))
                .font(.system(size: 14, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(SunARInk.light)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(SunARInk.plateOpacity)))
        .shotNode("ar.heading", text: String(format: "%.0f", aim.azimuth))
    }

    private func plate(_ text: Text) -> some View {
        text
            .foregroundStyle(SunARInk.light)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(SunARInk.plateOpacity)))
    }

    // MARK: - Время

    private func timePanel(sun: SunSample, clock: ClockText) -> some View {
        let atNow = isNow
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(SunARInk.sunFill).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(SunARInk.light, lineWidth: 1.5))
                Text(clock.fmt(model.minutes)).font(.system(size: 22, weight: .medium).monospacedDigit())
                    .shotNode("ar.time", text: clock.fmt(model.minutes))
                if let date = dayCaption { Text(date).font(.system(size: 13)).opacity(0.8) }
                Spacer(minLength: 8)
                Text(String(format: "%@ %.0f° · %@ %+.0f°", t.t("pro.azimuth"), sun.azimuth, t.t("pro.altitude"), sun.altitude))
                    .font(.system(size: 12).monospacedDigit()).opacity(0.9)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .shotNode("ar.sunPos", text: String(format: "%.1f %.1f", sun.azimuth, sun.altitude))
            }
            HStack(spacing: 12) {
                Slider(value: Binding(get: { model.minutes }, set: { glide?.cancel(); model.set(minutes: $0) }),
                       in: 0...1440, step: 1)
                    .tint(SunARInk.light)
                    .accessibilityLabel(t.t("ar.time"))
                Button(action: goNow) {
                    Text(t.t("ar.now")).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SunARInk.light)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(atNow ? 0.12 : 0.24)))
                        .overlay(Capsule().stroke(SunARInk.light.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .shotNode("ar.now", text: t.t("ar.now"))
            }
        }
        .foregroundStyle(SunARInk.light)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(SunARInk.plateOpacity)))
    }

    /// Дата под часами, когда день не сегодняшний — иначе «18:42» неоднозначно.
    private var dayCaption: String? {
        let today = model.nowTarget().day
        guard model.day != today else { return nil }
        var parts = DateComponents()
        parts.year = model.day.year; parts.month = model.day.month; parts.day = model.day.day
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let d = cal.date(from: parts) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: app.language)
        f.timeZone = cal.timeZone
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: d)
    }

    private var isNow: Bool {
        let n = model.nowTarget()
        return n.day == model.day && abs(n.minutes - model.minutes) < 1
    }

    /// «Сейчас»: день сегодняшний в месте, минута плывёт к текущей; при «Уменьшении движения» — сразу.
    private func goNow() {
        glide?.cancel()
        let n = model.nowTarget()
        model.jump(to: n.day, minutes: model.minutes)
        let from = model.minutes, to = n.minutes
        guard !PlanMotion.still, abs(to - from) > 1 else { model.set(minutes: to); return }
        glide = Task { @MainActor in
            let frames = 18
            for i in 1...frames {
                guard !Task.isCancelled else { return }
                let k = Double(i) / Double(frames)
                let eased = 1 - pow(1 - k, 3)
                model.set(minutes: from + (to - from) * eased)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}

private extension CGPoint {
    init(_ p: ScreenPoint) { self.init(x: p.x, y: p.y) }
}

/// Дуга, горизонт, подписи, маркер — одним `Canvas`: всё считано в `SunARScene`, здесь только рисование.
struct SunAROverlay: View {
    let scene: SunARScene
    let clock: ClockText
    let cardinals: [String]

    var body: some View {
        Canvas { ctx, size in
            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -40, dy: -40)
            // Горизонт: тёмная обводка, под ней светлая линия.
            for run in scene.horizon where run.count > 1 {
                let p = polyline(run)
                ctx.stroke(p, with: .color(.black.opacity(SunARInk.outlineOpacity)),
                           style: StrokeStyle(lineWidth: SunARInk.horizonOutlineWidth, lineCap: .round, lineJoin: .round))
                ctx.stroke(p, with: .color(SunARInk.light.opacity(0.85)),
                           style: StrokeStyle(lineWidth: SunARInk.horizonWidth, lineCap: .round, lineJoin: .round))
            }
            // Дуга солнца.
            for run in scene.arc where run.count > 1 {
                let p = polyline(run)
                ctx.stroke(p, with: .color(.black.opacity(SunARInk.outlineOpacity)),
                           style: StrokeStyle(lineWidth: SunARInk.arcOutlineWidth, lineCap: .round, lineJoin: .round))
                ctx.stroke(p, with: .color(SunARInk.light),
                           style: StrokeStyle(lineWidth: SunARInk.arcWidth, lineCap: .round, lineJoin: .round))
            }
            // Точки часов и подписи.
            for h in scene.hours {
                let c = CGPoint(h.point)
                guard bounds.contains(c) else { continue }
                let dot = CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)
                ctx.fill(Path(ellipseIn: dot.insetBy(dx: -1.5, dy: -1.5)), with: .color(.black.opacity(SunARInk.outlineOpacity)))
                ctx.fill(Path(ellipseIn: dot), with: .color(SunARInk.light))
                label(&ctx, clock.fmt(Double(h.hour * 60)), at: CGPoint(x: c.x, y: c.y - 17), size: 11,
                      opacity: h.altitude < 0 ? 0.75 : 1)
            }
            // Стороны света.
            for c in scene.cardinals {
                let p = CGPoint(c.point)
                guard bounds.contains(p), c.index < cardinals.count else { continue }
                label(&ctx, cardinals[c.index], at: CGPoint(x: p.x, y: p.y + 18), size: 13, weight: .semibold)
            }
            // Солнце в выбранный момент.
            if let m = scene.marker {
                let c = CGPoint(m)
                if bounds.contains(c) {
                    let r = 11.0
                    let disc = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                    let fade = scene.markerGhost ? 0.4 : 1.0
                    ctx.fill(Path(ellipseIn: disc.insetBy(dx: -4, dy: -4)), with: .color(.black.opacity(SunARInk.outlineOpacity * fade)))
                    ctx.fill(Path(ellipseIn: disc), with: .color(SunARInk.sunFill.opacity(fade)))
                    ctx.stroke(Path(ellipseIn: disc), with: .color(SunARInk.light.opacity(fade)), lineWidth: 2.5)
                }
            }
        }
    }

    private func polyline(_ pts: [ScreenPoint]) -> Path {
        var p = Path()
        p.move(to: CGPoint(pts[0]))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(q)) }
        return p
    }

    private func label(_ ctx: inout GraphicsContext, _ text: String, at c: CGPoint, size: CGFloat,
                       weight: Font.Weight = .medium, opacity: Double = 1) {
        let resolved = ctx.resolve(Text(text).font(.system(size: size, weight: weight).monospacedDigit()).foregroundStyle(SunARInk.light))
        let s = resolved.measure(in: CGSize(width: 200, height: 40))
        let pill = CGRect(x: c.x - s.width / 2 - 6, y: c.y - s.height / 2 - 3, width: s.width + 12, height: s.height + 6)
        ctx.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(.black.opacity(SunARInk.plateOpacity * opacity)))
        ctx.draw(resolved, at: c, anchor: .center)
    }
}

/// Откуда экран берёт поворот телефона: датчик на телефоне, подставной — в отладочной сборке по аргументу
/// `-LPSunARPose az,alt,roll` (или `az,alt,roll;az,alt,roll` — по очереди), иначе в симуляторе датчика нет.
@MainActor
enum SunARSources {
    static func attitude() -> (any AttitudeSource)? {
        #if DEBUG
        if let list = UserDefaults.standard.string(forKey: "LPSunARPose"), let poses = ScriptedAttitude.poses(list) {
            return ScriptedAttitude(poses: poses)
        }
        #endif
        #if os(iOS)
        return CoreMotionAttitude()
        #else
        return nil
        #endif
    }
}
