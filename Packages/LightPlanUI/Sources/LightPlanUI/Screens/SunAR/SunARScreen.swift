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
                                                forceCalibration: SunARSources.forceCalibration,
                                                language: app.language, clockPreference: app.light.clockPreference))
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
                                        arc: model.arc, sun: sun, now: model.sunNow, pickedIsNow: model.pickedIsNow,
                                        solar: model.solar)
            let clock = ClockText(language: app.language, preference: app.light.clockPreference)
            ZStack(alignment: .topLeading) {
                backdropStack(size: size, sun: sun, pal: pal, ground: scene.ground)
                    .shotNode("ar.background", text: "\(model.camera)")
                SunAROverlay(scene: scene, clock: clock, cardinals: cardinalNames(),
                             eventText: { eventText($0, clock: clock) })
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
                    .shotNode("ar.overlay", text: String(format: "marker=%@ now=%@ merged=%d arcSegments=%d hours=%d events=%d",
                                                         scene.marker.map { String(format: "%.1f,%.1f", $0.x, $0.y) } ?? "—",
                                                         scene.nowMarker.map { String(format: "%.1f,%.1f", $0.x, $0.y) } ?? "—",
                                                         scene.markerIsNow ? 1 : 0, scene.arc.count, scene.hours.count,
                                                         scene.events.count))
                SunARMarkers(scene: scene, pickedAltitude: sun.altitude, nowAltitude: model.sunNow.altitude,
                             nowTag: t.t("ar.nowTag"), pickedLabel: pickedLabel(clock: clock),
                             backdrop: model.camera.isLive ? nil
                                 : AnyView(backdropStack(size: size, sun: sun, pal: pal, ground: scene.ground)),
                             screen: size)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
                controls(size: size, safe: safe, sun: sun, clock: clock)
                if model.calibrating {
                    SunARCalibrationView(progress: model.calibrationProgress, phase: model.calibrationPhase,
                                         accuracyEnough: model.calibration.accuracySufficient,
                                         lexicon: t, onSkip: { Task { await model.finishCalibration() } })
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity)
                        .task(id: model.calibrationPhase) {
                            // «Готово» и «нет датчика» экран не держит: показал итог — и дальше к камере.
                            // Закрыли экран, пока «Готово» на виду, — задача отменена, калибровку не завершаем.
                            let dwell: Duration
                            switch model.calibrationPhase {
                            case .ready: dwell = .milliseconds(900)
                            case .noSensor: dwell = .milliseconds(1800)
                            case .measuring: return
                            }
                            do { try await Task.sleep(for: dwell) } catch { return }
                            await model.finishCalibration()
                        }
                }
            }
            .animation(PlanMotion.pick(.easeOut(duration: 0.2)), value: model.calibrating)
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(look(size: size))
            .ignoresSafeArea()
        }
        .onChange(of: model.minutes) { _, _ in model.minuteMoved() }
        .onChange(of: model.timebar.touches) { _, _ in glide?.cancel() }
        .onChange(of: target.choice) { _, new in model.apply(choice: new) }
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

    /// Кадр под всем остальным: камера или небо, а без камеры ещё и «земля» под горизонтом. Тот же набор подаётся
    /// в линзы: у кромки они гнут именно его (живое превью камеры — вид UIKit, шейдер его не читает).
    @ViewBuilder
    private func backdropStack(size: CGSize, sun: SunSample, pal: Palette, ground: [ScreenPoint]?) -> some View {
        ZStack {
            background(size: size, sun: sun, pal: pal)
            if !model.camera.isLive, let ground {
                Path { p in
                    p.move(to: CGPoint(ground[0]))
                    for q in ground.dropFirst() { p.addLine(to: CGPoint(q)) }
                    p.closeSubpath()
                }
                .fill(Color.black.opacity(SunARInk.groundOpacity))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Восемь румбов из словаря «Света» (`dirs` — шестнадцать через запятую): С, СВ, В, ЮВ, Ю, ЮЗ, З, СЗ.
    private func cardinalNames() -> [String] {
        let dirs = t.t("dirs").split(separator: ",").map(String.init)
        guard dirs.count == 16 else { return ["card.n", "card.e", "card.s", "card.w"].flatMap { [t.t($0), ""] } }
        return (0..<8).map { dirs[$0 * 2] }
    }

    /// «закат 18:21» / «восход 06:12» — время по часам места.
    private func eventText(_ e: SunARScene.HorizonEvent, clock: ClockText) -> String {
        t.t(e.kind == .sunset ? "ar.sunsetAt" : "ar.sunriseAt", ["t": clock.fmt(e.minutes)])
    }

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
                if let note = placeNote {
                    // Откуда место: телефон положения не дал — или выбранное в приложении далеко от телефона.
                    HStack(spacing: 0) {
                        Text(note)
                            .font(.system(size: 13)).multilineTextAlignment(.leading)
                            .foregroundStyle(SunARInk.light)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(GlassPlate(shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                                   opacity: SunARInk.plateOpacity))
                            .frame(maxWidth: size.width * 0.8, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .shotNode("ar.place", text: note)
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

    /// Слово о месте: `nil` — считаем для телефона, а выбранное в приложении рядом (в пределах 50 км).
    private var placeNote: String? {
        switch model.choice {
        case .chosen: return t.t("ar.placeChosen")
        case .phone(_, let far?):
            let n = NumberText(language: app.language)
            let d = far < 10 ? n.num(far, digits: 1) : n.num(far.rounded(), digits: 0)
            return t.t("ar.placePhoneFar", ["d": t.t("pro.distKm", ["n": d])])
        case .phone: return nil
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

    /// Нижний блок — таймбар экрана «Свет» (`TimebarView`): те же цвета дня, стеклянная ручка, щелчки, срыв на
    /// соседние сутки. Над ним время, строка «до заката …» и мелко азимут с высотой. Тёмная поверхность и
    /// тёмная схема: камера всегда тёмная подложка, чернила светлые (светлая тема — не инверсия).
    private func timePanel(sun: SunSample, clock: ClockText) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(clock.fmt(model.minutes)).font(.system(size: 22, weight: .medium).monospacedDigit())
                    .shotNode("ar.time", text: clock.fmt(model.minutes))
                if let date = dayCaption { Text(date).font(.system(size: 13)).opacity(0.8) }
                Spacer(minLength: 8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(eventNoteText)
                    .font(.system(size: 13).monospacedDigit()).opacity(0.9)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .shotNode("ar.note", text: eventNoteText)
                Spacer(minLength: 8)
                Text(String(format: "%@ %.0f° · %@ %+.0f°", t.t("pro.azimuth"), sun.azimuth, t.t("pro.altitude"), sun.altitude))
                    .font(.system(size: 11).monospacedDigit()).opacity(0.7)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .shotNode("ar.sunPos", text: String(format: "%.1f %.1f", sun.azimuth, sun.altitude))
            }
            TimebarView(model.timebar, showRibbon: false, bare: true, onNow: goNow)
                .padding(.horizontal, -16)
        }
        .foregroundStyle(SunARInk.light)
        .padding(.horizontal, 16).padding(.top, 12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SunARInk.panelColor.opacity(SunARInk.panelOpacity)))
        .environment(\.colorScheme, .dark)
    }

    /// «до заката 1 ч 27 мин» / «после заката 0 ч 12 мин» / «до рассвета …»; в полярные сутки — слово «Света».
    private var eventNoteText: String {
        switch model.eventNote {
        case .untilSunrise(let m): return t.t("ar.untilDawn", ["d": duration(m)])
        case .untilSunset(let m): return t.t("ar.untilSunset", ["d": duration(m)])
        case .afterSunset(let m): return t.t("ar.afterSunset", ["d": duration(m)])
        case .polarDay: return t.t("sun.noSetFull")
        case .polarNight: return t.t("sun.noRiseFull")
        }
    }

    private func duration(_ minutes: Double) -> String {
        let whole = max(0, Int(minutes.rounded()))
        if whole < 60 { return t.t("durS.minutes", ["m": "\(whole)"]) }
        let h = whole / 60, m = whole % 60
        return m == 0 ? t.t("durS.hours", ["h": "\(h)"]) : t.t("ar.durHM", ["h": "\(h)", "m": "\(m)"])
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

    /// «↺ сейчас» таймбара: день сегодняшний в месте, ручка плавно едет к текущей минуте (кадр за кадром, чтобы
    /// стекло ручки и щелчки шли за ней); при «Уменьшении движения» — сразу.
    private func goNow() {
        glide?.cancel()
        model.refreshNow()
        let n = model.wallNow
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

/// Горизонт, дуга цветом света, часы, стороны света, восход и закат — одним `Canvas`: всё считано в
/// `SunARScene`, здесь только рисование. Метки солнца — линзы, они лежат выше (`SunARMarkers`).
struct SunAROverlay: View {
    let scene: SunARScene
    let clock: ClockText
    /// Восемь румбов от севера по часовой: С, СВ, В, ЮВ, Ю, ЮЗ, З, СЗ.
    let cardinals: [String]
    /// «закат 18:21» / «восход 06:12».
    let eventText: (SunARScene.HorizonEvent) -> String

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
            // Дуга солнца: цвет света по точкам, под горизонтом пунктиром.
            for run in scene.arc where run.count > 1 { drawArc(&ctx, run) }
            // Точки часов и подписи.
            for h in scene.hours {
                let c = CGPoint(h.point)
                guard bounds.contains(c) else { continue }
                // Солнце стоит на часе — подпись часа лежала бы под линзой: её роль играет панель времени.
                if [scene.marker, scene.nowMarker].contains(where: { m in
                    m.map { hypot($0.x - h.point.x, $0.y - h.point.y) < 36 } ?? false
                }) { continue }
                let dot = CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)
                ctx.fill(Path(ellipseIn: dot.insetBy(dx: -1.5, dy: -1.5)), with: .color(.black.opacity(SunARInk.outlineOpacity)))
                ctx.fill(Path(ellipseIn: dot), with: .color(SunARInk.light))
                label(&ctx, clock.fmt(Double(h.hour * 60)), at: CGPoint(x: c.x, y: c.y - 17), size: 11,
                      opacity: h.altitude < 0 ? 0.75 : 1)
            }
            // Стороны света: основные крупнее, промежуточные мелко.
            for c in scene.cardinals {
                let p = CGPoint(c.point)
                guard bounds.contains(p), c.index < cardinals.count, !cardinals[c.index].isEmpty else { continue }
                label(&ctx, cardinals[c.index], at: CGPoint(x: p.x, y: p.y + (c.isMain ? 18 : 15)),
                      size: c.isMain ? 13 : 10.5, weight: c.isMain ? .semibold : .medium, opacity: c.isMain ? 1 : 0.9)
            }
            // Восход и закат: малая метка на линии горизонта и подпись над ней.
            for e in scene.events {
                guard let pt = e.point else { continue }
                let c = CGPoint(pt)
                guard bounds.contains(c) else { continue }
                let r = SunARInk.eventDot / 2
                let dot = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                let tint = SunARInk.stateColor(altitude: -0.833)
                ctx.fill(Path(ellipseIn: dot.insetBy(dx: -1.5, dy: -1.5)), with: .color(.black.opacity(SunARInk.outlineOpacity)))
                ctx.fill(Path(ellipseIn: dot), with: .color(tint))
                ctx.stroke(Path(ellipseIn: dot), with: .color(SunARInk.light), lineWidth: 1.5)
                label(&ctx, eventText(e), at: CGPoint(x: c.x, y: c.y - 20), size: 11, weight: .semibold)
            }
        }
    }

    /// Дуга одного отрезка: тёмная обводка, белая кромка, цветная жила. Участки ниже горизонта — пунктиром
    /// (штрих и просвет одни на все три слоя, фаза сквозная). Цвет жилы плавно перетекает: каждый отрезок между
    /// точками дуги режется на `arcColorSteps` частей, высота между точками линейная.
    private func drawArc(_ ctx: inout GraphicsContext, _ run: [SunARScene.ArcPoint]) {
        var i = 0
        while i < run.count - 1 {
            // Подряд идущие отрезки одного вида — одна ломаная.
            let dashed = run[i].isBelowHorizon && run[i + 1].isBelowHorizon
            var j = i + 1
            while j < run.count - 1, (run[j].isBelowHorizon && run[j + 1].isBelowHorizon) == dashed { j += 1 }
            let part = Array(run[i...j])
            let path = polyline(part.map(\.point))
            let cap: CGLineCap = dashed ? .butt : .round
            func style(_ w: CGFloat) -> StrokeStyle {
                StrokeStyle(lineWidth: w, lineCap: cap, lineJoin: .round, dash: dashed ? SunARInk.arcDash : [])
            }
            ctx.stroke(path, with: .color(.black.opacity(SunARInk.outlineOpacity)), style: style(SunARInk.arcOutlineWidth))
            ctx.stroke(path, with: .color(SunARInk.light), style: style(SunARInk.arcWidth))
            // Жила.
            var length: CGFloat = 0
            let n = SunARInk.arcColorSteps
            for k in 0..<(part.count - 1) {
                let a = part[k], b = part[k + 1]
                let ax = CGFloat(a.point.x), ay = CGFloat(a.point.y), bx = CGFloat(b.point.x), by = CGFloat(b.point.y)
                for q in 0..<n {
                    let t0 = CGFloat(q) / CGFloat(n), t1 = CGFloat(q + 1) / CGFloat(n)
                    let p0 = CGPoint(x: ax + (bx - ax) * t0, y: ay + (by - ay) * t0)
                    let p1 = CGPoint(x: ax + (bx - ax) * t1, y: ay + (by - ay) * t1)
                    let mid = a.altitude + (b.altitude - a.altitude) * Double(t0 + t1) / 2
                    var seg = Path()
                    seg.move(to: p0)
                    seg.addLine(to: p1)
                    var st = StrokeStyle(lineWidth: SunARInk.arcCoreWidth, lineCap: cap, lineJoin: .round)
                    if dashed { st.dash = SunARInk.arcDash; st.dashPhase = length }
                    ctx.stroke(seg, with: .color(SunARInk.stateColor(altitude: mid)), style: st)
                    length += hypot(p1.x - p0.x, p1.y - p0.y)
                }
            }
            i = j
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

/// Метки солнца — стеклянные линзы (шаг 29.8в.3): «сейчас» 48 pt, выбранный момент 34 pt; кольцо окрашено светом
/// этого момента, середина прозрачна один к одному — настоящее светило видно в ней как есть. Подписи — на
/// стеклянных плашках. Слились (выбранный момент = сейчас) — одна линза 48 pt и одна подпись «сейчас».
struct SunARMarkers: View {
    let scene: SunARScene
    let pickedAltitude: Double
    let nowAltitude: Double
    let nowTag: String
    let pickedLabel: String?
    /// Кадр, который кромка линзы гнёт; `nil` у живой камеры.
    let backdrop: AnyView?
    let screen: CGSize

    var body: some View {
        let bounds = CGRect(origin: .zero, size: screen).insetBy(dx: -60, dy: -60)
        let picked = scene.marker.map { CGPoint(x: $0.x, y: $0.y) }
        let now = scene.markerIsNow ? picked : scene.nowMarker.map { CGPoint(x: $0.x, y: $0.y) }
        let nowFade = scene.markerIsNow ? (scene.markerGhost ? 0.4 : 1.0) : (scene.nowGhost ? 0.4 : 1.0)
        let pickedFade = scene.markerGhost ? 0.4 : 1.0
        // Подписи не наезжают друг на друга: верхняя метка подписана сверху, нижняя — снизу.
        let nowAbove = !(picked != nil && now != nil && !scene.markerIsNow && picked!.y < now!.y)
        let nowD = SunARInk.nowLensDiameter, pickedD = SunARInk.pickedLensDiameter
        ZStack(alignment: .topLeading) {
            if !scene.markerIsNow, let c = picked, bounds.contains(c) {
                lens(c, diameter: pickedD, altitude: pickedAltitude, fade: pickedFade)
                if let text = pickedLabel {
                    plate(text, weight: .medium, at: CGPoint(x: c.x, y: c.y + (nowAbove ? 1 : -1) * (pickedD / 2 + SunARInk.markerLabelGap)),
                          fade: pickedFade)
                }
            }
            if let c = now, bounds.contains(c) {
                lens(c, diameter: nowD, altitude: scene.markerIsNow ? pickedAltitude : nowAltitude, fade: nowFade)
                plate(nowTag, weight: .semibold, at: CGPoint(x: c.x, y: c.y + (nowAbove ? -1 : 1) * (nowD / 2 + SunARInk.markerLabelGap)),
                      fade: nowFade)
            }
        }
    }

    private func lens(_ c: CGPoint, diameter d: CGFloat, altitude: Double, fade: Double) -> some View {
        LensGlass(diameter: d, tint: SunARInk.stateColor(altitude: altitude), backdrop: backdrop,
                  origin: CGPoint(x: c.x - d / 2, y: c.y - d / 2), screen: screen, fade: fade)
            .position(x: c.x, y: c.y)
    }

    private func plate(_ text: String, weight: Font.Weight, at c: CGPoint, fade: Double) -> some View {
        Text(text)
            .font(.system(size: 12, weight: weight).monospacedDigit())
            .foregroundStyle(SunARInk.light)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(GlassPlate(shape: Capsule(), opacity: SunARInk.plateOpacity))
            .opacity(fade)
            .position(x: min(max(c.x, halfWidth(text) + 8), screen.width - halfWidth(text) - 8), y: c.y)
    }

    /// Половина ширины плашки по числу знаков (цифры одной ширины, 12 pt ≈ 7 pt на знак + поля) — чтобы плашка
    /// у края кадра не уезжала за экран.
    private func halfWidth(_ text: String) -> CGFloat { (CGFloat(text.count) * 7 + 16) / 2 }
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
