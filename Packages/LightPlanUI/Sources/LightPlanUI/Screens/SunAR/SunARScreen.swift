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
        #if DEBUG
        // `-LPSunARStill 1`: кадр «Уменьшения движения» в симуляторе (статичная восьмёрка калибровки).
        if UserDefaults.standard.bool(forKey: "LPSunARStill") { PlanMotion.stillOverride = true }
        #endif
        _model = State(initialValue: SunARModel(target: target, source: SunARSources.attitude(),
                                                forceCalibration: SunARSources.forceCalibration))
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
                                        arc: model.arc, sun: sun, now: model.sunNow, pickedIsNow: model.pickedIsNow)
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
                SunAROverlay(scene: scene, clock: clock, cardinals: ["card.n", "card.e", "card.s", "card.w"].map { t.t($0) },
                             nowTag: t.t("ar.nowTag"), pickedLabel: pickedLabel(clock: clock))
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
                    .shotNode("ar.overlay", text: String(format: "marker=%@ now=%@ merged=%d arcSegments=%d hours=%d",
                                                         scene.marker.map { String(format: "%.1f,%.1f", $0.x, $0.y) } ?? "—",
                                                         scene.nowMarker.map { String(format: "%.1f,%.1f", $0.x, $0.y) } ?? "—",
                                                         scene.markerIsNow ? 1 : 0, scene.arc.count, scene.hours.count))
                controls(size: size, safe: safe, sun: sun, clock: clock)
                if model.calibrating {
                    SunARCalibrationView(progress: model.calibrationProgress, phase: model.calibrationPhase,
                                         accuracyEnough: model.calibration.accuracySufficient,
                                         lexicon: t, onSkip: { Task { await model.finishCalibration() } })
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity)
                        .task(id: model.calibrationPhase) {
                            // «Готово» и «нет датчика» экран не держит: показал итог — и дальше к камере.
                            switch model.calibrationPhase {
                            case .ready:
                                try? await Task.sleep(for: .milliseconds(900))
                                await model.finishCalibration()
                            case .noSensor:
                                try? await Task.sleep(for: .milliseconds(1800))
                                await model.finishCalibration()
                            case .measuring: break
                            }
                        }
                }
            }
            .animation(PlanMotion.pick(.easeOut(duration: 0.2)), value: model.calibrating)
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(look(size: size))
            .ignoresSafeArea()
        }
        .task { await model.start() }
        .task {
            // «Сейчас» едет, север мог стать истинным (включили геолокацию, пока экран открыт).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                model.refreshNow()
            }
        }
        .onDisappear { model.stop() }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Фон

    @ViewBuilder
    private func background(size: CGSize, sun: SunSample, pal: Palette) -> some View {
        #if DEBUG
        // Замер контраста (`-LPSunARBackdrop white|gray|black`): сплошной фон вместо кадра, чтобы по снимку
        // посчитать контраст дуги и подписей на самых тяжёлых фонах.
        if let b = UserDefaults.standard.string(forKey: "LPSunARBackdrop") {
            Color(white: b == "white" ? 1 : b == "gray" ? 0.5 : 0)
        } else { realBackground(size: size, sun: sun, pal: pal) }
        #else
        realBackground(size: size, sun: sun, pal: pal)
        #endif
    }

    @ViewBuilder
    private func realBackground(size: CGSize, sun: SunSample, pal: Palette) -> some View {
        #if os(iOS)
        if model.camera.isLive, let session = model.cameraSession {
            ARCameraPreview(session: session)
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
                HStack(alignment: .center, spacing: 8) {
                    backButton
                    Spacer(minLength: 8)
                    if model.hasSensor { calibrateButton }
                    headingChip(aim)
                }
                if model.magneticOnly {
                    // Тихая строка в левом углу: не модалка, поверх кадра, пропадает, когда север стал истинным.
                    HStack(spacing: 0) {
                        Text(t.t("ar.magnetic"))
                            .font(.system(size: 13)).multilineTextAlignment(.leading)
                            .foregroundStyle(SunARInk.light)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(SunARInk.plateOpacity)))
                            .frame(maxWidth: size.width * 0.8, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .shotNode("ar.magnetic", text: t.t("ar.magnetic"))
                        Spacer(minLength: 0)
                    }
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

    /// «Калибровка» — рядом с компасом: повторить восьмёрку, когда курс уплывает.
    private var calibrateButton: some View {
        Button { model.beginCalibration() } label: {
            Text(t.t("ar.calibrate")).font(.system(size: 14, weight: .medium))
                .foregroundStyle(SunARInk.light)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(SunARInk.plateOpacity)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .shotNode("ar.calibrate", text: t.t("ar.calibrate"))
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
        let atNow = model.pickedIsNow
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

    /// Подпись выбранной метки на дуге: время, а если день не сегодняшний — с датой («15 июн · 18:42»).
    /// `nil`, когда метка одна и это «сейчас».
    private func pickedLabel(clock: ClockText) -> String? {
        guard !model.pickedIsNow else { return nil }
        let time = clock.fmt(model.minutes)
        return dayCaption.map { "\($0) · \(time)" } ?? time
    }

    /// Дата под часами, когда день не сегодняшний — иначе «18:42» неоднозначно.
    private var dayCaption: String? {
        let today = model.nowTarget(now: model.nowMoment).day
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

    /// «Сейчас»: день сегодняшний в месте, минута плывёт к текущей; при «Уменьшении движения» — сразу.
    private func goNow() {
        glide?.cancel()
        model.refreshNow()
        let n = model.nowTarget(now: model.nowMoment)
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
    /// Подпись метки «сейчас» («сейчас»).
    let nowTag: String
    /// Подпись выбранной метки: время (и дата, если не сегодня); `nil` — метка одна и это «сейчас».
    let pickedLabel: String?

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
                // Солнце стоит на часе — подпись часа лежала бы под диском: её роль играет панель времени.
                if [scene.marker, scene.nowMarker].contains(where: { m in
                    m.map { hypot($0.x - h.point.x, $0.y - h.point.y) < 26 } ?? false
                }) { continue }
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
            // Метки солнца. «Сейчас» — залитый диск с подписью; выбранный момент — контур с подписью времени.
            // Слились (выбранный момент = сейчас) — один залитый диск и одна подпись «сейчас».
            let picked = scene.marker.map(CGPoint.init)
            let now = scene.markerIsNow ? picked : scene.nowMarker.map(CGPoint.init)
            let nowFade = scene.markerIsNow ? (scene.markerGhost ? 0.4 : 1.0) : (scene.nowGhost ? 0.4 : 1.0)
            let pickedFade = scene.markerGhost ? 0.4 : 1.0
            // Подписи не наезжают друг на друга: верхняя метка подписана сверху, нижняя — снизу.
            let nowAbove = !(picked != nil && now != nil && !scene.markerIsNow && picked!.y < now!.y)
            if !scene.markerIsNow, let c = picked, bounds.contains(c) {
                ring(&ctx, at: c, fade: pickedFade)
                if let text = pickedLabel {
                    label(&ctx, text, at: CGPoint(x: c.x, y: c.y + (nowAbove ? 1 : -1) * SunARInk.markerLabelOffset),
                          size: 12, opacity: pickedFade)
                }
            }
            if let c = now, bounds.contains(c) {
                disc(&ctx, at: c, fade: nowFade)
                label(&ctx, nowTag, at: CGPoint(x: c.x, y: c.y + (nowAbove ? -1 : 1) * SunARInk.markerLabelOffset),
                      size: 12, weight: .semibold, opacity: nowFade)
            }
        }
    }

    /// «Сейчас»: залитый диск солнца с белым кольцом на тёмной обводке.
    private func disc(_ ctx: inout GraphicsContext, at c: CGPoint, fade: Double) {
        let r = SunARInk.markerRadius
        let disc = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        ctx.fill(Path(ellipseIn: disc.insetBy(dx: -4, dy: -4)), with: .color(.black.opacity(SunARInk.outlineOpacity * fade)))
        ctx.fill(Path(ellipseIn: disc), with: .color(SunARInk.sunFill.opacity(fade)))
        ctx.stroke(Path(ellipseIn: disc), with: .color(SunARInk.light.opacity(fade)), lineWidth: 2.5)
    }

    /// Выбранный момент: контурная метка — кольцо того же размера без заливки, тёмная обводка снаружи и внутри.
    private func ring(_ ctx: inout GraphicsContext, at c: CGPoint, fade: Double) {
        let r = SunARInk.markerRadius
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        ctx.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(SunARInk.outlineOpacity * fade)), lineWidth: 6.5)
        ctx.stroke(Path(ellipseIn: rect), with: .color(SunARInk.light.opacity(fade)), lineWidth: 2.5)
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
        // `-LPSunARPose az,alt,roll[,точность]` (список через `;`), `-LPSunARNorth magnetic` — подставной курс
        // от магнитного севера: так в симуляторе видно плашку «Курс магнитный».
        let d = UserDefaults.standard
        if let list = d.string(forKey: "LPSunARPose"), let script = ScriptedAttitude.script(list) {
            let north: AttitudeNorth = d.string(forKey: "LPSunARNorth") == "magnetic" ? .magneticNorth : .trueNorth
            return ScriptedAttitude(poses: script.poses, accuracies: script.accuracies, north: north)
        }
        #endif
        #if os(iOS)
        return CoreMotionAttitude()
        #else
        return nil
        #endif
    }

    /// `-LPSunARCalib 1` (отладка): показать калибровку, даже если флаг «уже видел» стоит.
    static var forceCalibration: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "LPSunARCalib")
        #else
        false
        #endif
    }
}
