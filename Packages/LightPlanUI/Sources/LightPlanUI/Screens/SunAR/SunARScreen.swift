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
        // `-LPSunARReduceMotion 1`: как «Уменьшение движения» у системы — кадр статичной схемы калибровки.
        if UserDefaults.standard.bool(forKey: "LPSunARReduceMotion") { PlanMotion.stillOverride = true }
        #endif
        #if DEBUG
        // `-LPSunARStill 1`: кадр «Уменьшения движения» в симуляторе (статичная восьмёрка калибровки).
        if UserDefaults.standard.bool(forKey: "LPSunARStill") { PlanMotion.stillOverride = true }
        #endif
        // «Сейчас» — часы приложения: у снимков (`-LPShotNow`) и тестов оно подставное, у людей — настоящее.
        let appNow = app.now
        _model = State(initialValue: SunARModel(target: target, source: SunARSources.attitude(),
                                                clock: { Moment(appNow()) },
                                                forceCalibration: SunARSources.forceCalibration,
                                                language: app.language, clockPreference: app.light.clockPreference))
    }

    private var t: Lexicon { app.lexicon }

    private static var layersOpenAtStart: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "LPSunARLayersOpen")
        #else
        return false
        #endif
    }

    @State private var panelHeight: CGFloat = 200
    /// Стекло дисков: своё или системное (шаг 29.8в.9а; в отладке — переключатель на экране).
    @State private var glass = SunARGlassStyle.current()
    /// Низ нижней строки кнопок в окне экрана; `nil` — ещё не измерен (`SunARZones.visibleWindow`).
    @State private var buttonsBottom: CGFloat?
    /// Список «Слои» открыт. В отладке `-LPSunARLayersOpen 1` открывает его сразу (кадры).
    @State private var layersOpen = SunARScreen.layersOpenAtStart

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
            // Луна и Млечный Путь — только то, что включено: выключенное не считается и не рисуется.
            let night: NightSkyARScene? = (model.moonOn || model.milkyWayOn)
                ? model.nightScene(basis: model.aim, optics: model.optics, viewport: viewport) : nil
            let marks = SunARMarks.debugPlaced(SunARMarks.make(sun: scene, night: night, screen: size))
            let clock = ClockText(language: app.language, preference: app.light.clockPreference)
            // Слои снизу вверх (порядок — предмет замера 29.8в.5, `SunARLayers`): камера и слой Metal → полоса
            // Млечного Пути → дуга и подписи часов (у своего стекла в дисках вырезана) → по каждой метке линза и
            // налёт (своё стекло) или системное стекло (29.8в.9а) → подпись выбранного момента.
            ZStack(alignment: .topLeading) {
                if SunARLayers.shown(.camera) {
                    backdropStack(size: size, sun: sun, pal: pal, ground: scene.ground, marks: marks)
                        .shotNode("ar.background", text: "\(model.camera)")
                }
                SunARSkyStack(scene: scene, night: night, marks: marks, size: size, clock: clock,
                              cardinals: cardinalNames(), coreLabel: t.t("ar.mwCore"),
                              eventText: { eventText($0, clock: clock) },
                              mergedEvent: mergedEvent(scene: scene, clock: clock)?.kind,
                              pickedText: pickedLabel(clock: clock, scene: scene),
                              // Без камеры небо рисует SwiftUI, и его гнёт сама линза; с камерой — слой Metal.
                              sky: model.camera.isLive ? nil
                                  : AnyView(backdropStack(size: size, sun: sun, pal: pal, ground: scene.ground, marks: [])),
                              markText: markText, glass: glass)
                if SunARLayers.shown(.labels) {
                    SunARMarkLabels(pickedLabel: pickedLabel(clock: clock, scene: scene), marks: marks, screen: size)
                        .frame(width: size.width, height: size.height)
                }
                ForEach(pointerItems(sun: sun, night: night, size: size, safe: safe, viewport: viewport)) { item in
                    SunARPointerView(item: item, screen: size, labelFlipY: size.height - panelHeight - 40)
                }
                controls(size: size, safe: safe, sun: sun, clock: clock)
                if model.calibrating {
                    // Сама не закрывается: ни таймера, ни перехода по «Готово» — выход только кнопкой.
                    SunARCalibrationView(calibration: model.calibration, lexicon: t,
                                         onDone: { Task { await model.doneCalibration() } },
                                         onSkip: { Task { await model.finishCalibration() } },
                                         onRetry: { model.retryCalibration() })
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity)
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

    /// Строка узла для снимков: что за метка и где.
    private func markText(_ m: SunARMark) -> String {
        let kind: String
        switch m.kind {
        case .sun: kind = "sun"
        case .moon(let f, let waxing, let limb):
            kind = String(format: "moon f=%.3f %@ limb=%@", f, waxing ? "wax" : "wan",
                          limb.map { String(format: "%.1f", $0 * 180 / .pi) } ?? "—")
        }
        return String(format: "%@ d=%.0f at=%.1f,%.1f fade=%.1f", kind, m.diameter, m.center.x, m.center.y, m.fade)
    }

    /// Стрелки к светилам, ушедшим за кадр: солнце всегда, луна и ядро — когда включены. Рамка — окно без полос
    /// под кнопками сверху и под панелью снизу.
    private func pointerItems(sun: SunSample, night: NightSkyARScene?, size: CGSize, safe: EdgeInsets,
                              viewport: ScreenViewport) -> [SunARPointerItem] {
        guard !model.calibrating else { return [] }
        // Рамка учитывает размер самого значка: центр не ближе радиуса и просвета к краю, а сверху — ниже двух
        // рядов кнопок (курс и включатели могут встать в два ряда).
        let panelTop = size.height - panelHeight - max(safe.bottom, 12) - 4
        let box = SunARZones.pointerBox(size: size, safeTop: safe.top, panelTop: panelTop)
        // Светило, чей диск виден на экране между кнопками и панелью ЦЕЛИКОМ, стрелки не получает: она бы лежала на нём.
        // Диск, залезший краем под кнопки, под панель или за край экрана, виден не весь — стрелка нужна (29.8в.7;
        // в 29.8в.6 сверялся только центр диска).
        let shown = SunARZones.visibleWindow(size: size, safeTop: safe.top, buttonsBottom: buttonsBottom, panelTop: panelTop)
        func item(_ id: String, _ body: SunARPointerItem.Body, az: Double, alt: Double, text: String,
                  fade: Double, radius: CGFloat) -> SunARPointerItem? {
            if let p = SkyProjection.project(azimuth: az, altitude: alt, basis: model.aim, optics: model.optics,
                                             viewport: viewport),
               SunARZones.discFullyVisible(center: CGPoint(x: p.x, y: p.y), radius: radius, in: shown) { return nil }
            guard let p = EdgePointing.pointer(azimuth: az, altitude: alt, basis: model.aim, optics: model.optics,
                                               viewport: viewport, box: box) else { return nil }
            return SunARPointerItem(id: id, body: body, pointer: p, text: text, fade: fade)
        }
        func label(_ az: Double, _ alt: Double) -> String {
            let a = az.rounded() == 360 ? 0 : az.rounded()
            return String(format: "%.0f° · %+.0f°", a, alt.rounded())
        }
        var out: [SunARPointerItem] = []
        if let i = item("sun", .sun, az: sun.azimuth, alt: sun.apparentAltitude,
                        text: label(sun.azimuth, sun.altitude), fade: sun.altitude < SunTrack.visibleFrom ? 0.6 : 1,
                        radius: (model.pickedIsNow ? SunARInk.nowLensDiameter : SunARInk.pickedLensDiameter) / 2) {
            out.append(i)
        }
        if let m = night?.picked, let i = item("moon", .moon(illuminated: m.illuminated, waxing: m.waxing),
                                               az: m.azimuth, alt: m.altitude, text: label(m.azimuth, m.altitude),
                                               fade: m.ghost ? 0.6 : 1,
                                               radius: (night?.now == nil ? SunARInk.moonNowDiameter : SunARInk.moonPickedDiameter) / 2) {
            out.append(i)
        }
        if let night, night.milkyWayOn,
           let i = item("core", .core, az: night.coreAzimuth, alt: night.coreAltitude,
                        text: label(night.coreAzimuth, night.coreAltitude), fade: night.skyGhost ? 0.6 : 1,
                        radius: SunARInk.coreGlyphRadius) {
            out.append(i)
        }
        // Два светила в одной стороне (луна и ядро Млечного Пути) не встают друг на друга: раскладка по периметру.
        let spreadPoints = SunARPointerLayout.spread(
            out.map { (CGPoint(x: $0.pointer.point.x, y: $0.pointer.point.y), $0.text) },
            box: CGRect(x: box.minX, y: box.minY, width: box.maxX - box.minX, height: box.maxY - box.minY),
            screen: size, flipY: size.height - panelHeight - 40)
        return zip(out, spreadPoints).map { item, point in
            SunARPointerItem(id: item.id, body: item.body,
                             pointer: EdgePointer(point: ScreenPoint(x: point.x, y: point.y), angle: item.pointer.angle),
                             text: item.text, fade: item.fade)
        }
    }

    // MARK: - Фон

    /// Кадр под всем остальным: камера или небо, а без камеры ещё и «земля» под горизонтом. С камерой над
    /// превью лежит слой Metal, который гнёт кадр под дисками (`marks`); без неё кадр-небо гнёт `LensRefraction`.
    @ViewBuilder
    private func backdropStack(size: CGSize, sun: SunSample, pal: Palette, ground: [ScreenPoint]?,
                               marks: [SunARMark]) -> some View {
        ZStack {
            background(size: size, sun: sun, pal: pal, marks: marks)
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
    private func background(size: CGSize, sun: SunSample, pal: Palette, marks: [SunARMark]) -> some View {
        #if DEBUG
        // Замер контраста (`-LPSunARBackdrop white|gray|black|sky|asphalt|night`): сплошной фон вместо кадра, чтобы
        // по снимку посчитать контраст дуги, подписей и кнопок на самых тяжёлых фонах. Белое и голубое небо, асфальт
        // и ночное небо — четыре подложки кнопок (29.8в.9б), серый и чёрный — прежние (29.8в.4).
        if let b = UserDefaults.standard.string(forKey: "LPSunARBackdrop") {
            switch b {
            case "white": Color(white: 1)
            case "gray": Color(white: 0.5)
            case "sky": Color(.sRGB, red: 0.45, green: 0.68, blue: 0.93)
            case "asphalt": Color(white: 0.36)
            case "night": Color(.sRGB, red: 0.02, green: 0.04, blue: 0.10)
            case let g where g.hasPrefix("g"): Color(white: (Double(g.dropFirst()) ?? 0) / 100)
            default: Color(white: 0)
            }
        } else { realBackground(size: size, sun: sun, pal: pal, marks: marks) }
        #else
        realBackground(size: size, sun: sun, pal: pal, marks: marks)
        #endif
    }

    @ViewBuilder
    private func realBackground(size: CGSize, sun: SunSample, pal: Palette, marks: [SunARMark]) -> some View {
        #if os(iOS)
        if model.camera.isLive, let feed = model.cameraFeed {
            // Системное стекло гнёт кадр само: слою Metal дисков не дают.
            ARCameraBackdrop(feed: feed, lenses: glass == .own ? marks.map(\.lensSpec) : [])
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

    /// Кнопки AR — стандартное стекло `.glassEffect` в системной форме капсулы, высота касания 44 pt (слово
    /// Алексея 14.10: «кнопки стеклянные, в соответствии со стандартами»). Верхний ряд — в одном контейнере стекла.
    private func controls(size: CGSize, safe: EdgeInsets, sun: SunSample, clock: ClockText) -> some View {
        let aim = model.aim.aim
        return ZStack(alignment: .top) {
            VStack(spacing: 8) {
                // Ряд: «Назад» и «Место» слева; «Калибровка», курс и «Слои» справа. Подписи не переносятся
                // (`fixedSize`), поэтому не уместившийся ряд выбирает следующий вариант, а не ломает слова:
                // две строки («Слои» под курсом) или, на самых узких экранах (SE), «Калибровка» второй строкой
                // под курсом и «Слоями» — справа, под кнопками левого края ничего не лежит.
                GlassEffectContainer(spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 8) {
                            backButton
                            placeButton
                            Spacer(minLength: 8)
                            if model.hasSensor { calibrateButton }
                            headingChip(aim)
                            layersButton
                        }
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(alignment: .center, spacing: 8) {
                                backButton
                                placeButton
                                Spacer(minLength: 8)
                                if model.hasSensor { calibrateButton }
                                headingChip(aim)
                            }
                            layersButton
                        }
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(alignment: .center, spacing: 8) {
                                backButton
                                placeButton
                                Spacer(minLength: 8)
                                headingChip(aim)
                                layersButton
                            }
                            if model.hasSensor { calibrateButton }
                        }
                    }
                }
                // Низ кнопок в окне экрана: ниже него диск светила виден, выше — закрыт кнопками.
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { buttonsBottom = $0 }
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
                #if DEBUG
                glassSwitch
                #endif
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
                Text(t.t("nav.back")).font(webFont(15)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(SunARInk.buttonInk)
            .arInkShadow()
            .padding(.horizontal, 14)
            .frame(minHeight: SunARInk.touch)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(SunARInk.buttonGlass.interactive(), in: Capsule())
        .shotNode("ar.back", text: t.t("nav.back"))
    }

    /// Стрелка места (29.8в.12, как у Sun Surveyor): сплошная — место приложения следует за телефоном, контурная —
    /// выбрано руками. Касание открывает «Где снимаем» поверх AR. Экран AR считает небо там, где телефон, — смена
    /// места в листе его не двигает; метка «Место: …» ниже говорит, когда выбранное далеко.
    private var placeButton: some View {
        Button { app.placeSheetOpen = true } label: {
            PlaceFollowArrow(pal: Palette(.dark), following: app.followingLive, size: 17, ink: SunARInk.buttonInk)
                .arInkShadow()
                .frame(width: SunARInk.touch, height: SunARInk.touch)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(SunARInk.buttonGlass.interactive(), in: Circle())
        .accessibilityLabel(t.t("loc.title"))
        .shotNode("ar.follow", text: app.followingLive ? "on" : "off")
    }

    /// «Калибровка» — рядом с компасом: повторить восьмёрку, когда курс уплывает.
    private var calibrateButton: some View {
        Button { model.beginCalibration() } label: {
            Text(t.t("ar.calibrate")).font(.system(size: 14, weight: .medium)).lineLimit(1).fixedSize()
                .foregroundStyle(SunARInk.buttonInk)
                .arInkShadow()
                .padding(.horizontal, 14)
                .frame(minHeight: SunARInk.touch)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(SunARInk.buttonGlass.interactive(), in: Capsule())
        .shotNode("ar.calibrate", text: t.t("ar.calibrate"))
    }

    private func headingChip(_ aim: HorizontalPoint) -> some View {
        HStack(spacing: 6) {
            HeadingGlyph()
                .stroke(SunARInk.buttonInk, style: StrokeStyle(lineWidth: 1.8 * 15 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 15, height: 15)
            Text(String(format: "%.0f°", aim.azimuth.rounded() == 360 ? 0 : aim.azimuth.rounded()))
                .font(.system(size: 14, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(SunARInk.buttonInk)
        .arInkShadow()
        .padding(.horizontal, 14)
        .frame(minHeight: SunARInk.touch)
        .glassEffect(SunARInk.buttonGlass, in: Capsule())
        .shotNode("ar.heading", text: String(format: "%.0f", aim.azimuth))
    }

    /// Одна круглая кнопка «Слои» вместо двух включателей (29.8в.9б, слово Алексея 18.10): нажатие открывает список
    /// слоёв неба на системном стекле, у каждого свой переключатель. Состояние — те же флаги устройства, что и
    /// раньше (`SunARModel.setMoon` / `setMilkyWay`). Какие слои включены, видно по точкам под значком.
    private var layersButton: some View {
        let on = model.layersOn
        let names = on.map { t.t($0.labelKey) }.joined(separator: ", ")
        return Button { layersOpen.toggle() } label: {
            SunARLayersButtonLabel(on: on)
        }
        .buttonStyle(.plain)
        .glassEffect(SunARInk.buttonGlass.interactive(), in: Circle())
        .popover(isPresented: $layersOpen, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            SunARLayersList(model: model, lexicon: t)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(t.t("ar.layers"))
        .accessibilityValue(names)
        .shotNode("ar.layers", text: on.map(\.rawValue).joined(separator: ","))
    }

    #if DEBUG
    /// Опыт 29.8в.9а, только в отладочной сборке (её ставит `make phone`): какое стекло у дисков. Состояние —
    /// флаг устройства `lightplan.native.sunar.glass`, помнится между входами. Слова не из словаря: кнопка уйдёт,
    /// когда Алексей выберет стекло.
    private var glassSwitch: some View {
        HStack(spacing: 0) {
            Button {
                glass = glass == .own ? .system : .own
                SunARGlassStyle.set(glass)
            } label: {
                Text(verbatim: glass == .own ? "Стекло: своё" : "Стекло: системное")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SunARInk.buttonInk)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(SunARInk.buttonGlass.interactive(), in: Capsule())
            .shotNode("ar.glassSwitch", text: glass.rawValue)
            Spacer(minLength: 0)
        }
    }
    #endif

    private func plate(_ text: Text) -> some View {
        text
            .foregroundStyle(SunARInk.light)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(SunARInk.plateOpacity)))
    }

    // MARK: - Время

    /// Нижний блок — таймбар экрана «Свет» (`TimebarView`): те же цвета дня, стеклянная ручка, щелчки, срыв на
    /// соседние сутки. Над ним время, строка «до заката …» и мелко азимут с высотой. Матовое стекло и тёмная
    /// схема: камера всегда тёмная подложка, чернила светлые (светлая тема — не инверсия).
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
            TimebarView(model.timebar, showRibbon: false, bare: true, nowInk: SunARInk.nowTone, onNow: goNow)
                .padding(.horizontal, -16)
        }
        .foregroundStyle(SunARInk.light)
        .padding(.horizontal, 16).padding(.top, 12)
        // Матовое стекло — системное `.glassEffect` на скруглённой плашке (слово Алексея 14.10: «панель внизу
        // плохая, должно быть матовое стекло»). Размывает кадр под собой, чернила светлые.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
        .shotNode("ar.panel", text: "bottom panel")
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
    private func pickedLabel(clock: ClockText, scene: SunARScene) -> String? {
        // Момент совпал с закатом или восходом — одна подпись «закат 18:13» вместо двух друг на друге.
        SunARLabelLayout.pickedText(scene: scene, pickedIsNow: model.pickedIsNow, pickedMinutes: model.minutes, clock: clock,
                                    dayCaption: dayCaption, eventText: { eventText($0, clock: clock) })
    }

    private func mergedEvent(scene: SunARScene, clock: ClockText) -> SunARScene.HorizonEvent? {
        SunARLabelLayout.mergedEvent(in: scene, pickedIsNow: model.pickedIsNow, pickedMinutes: model.minutes, clock: clock)
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
/// `SunARScene` и `NightSkyARScene`, здесь только рисование. Метки светил — стеклянные диски, они лежат выше
/// (`SunARMarkPaint`).
struct SunAROverlay: View {
    let scene: SunARScene
    /// Дуга луны выбранного дня (пусто, когда луна выключена): тонкая серебристая линия.
    let moonArc: [[NightSkyARScene.ArcPoint]]
    /// Диски луны: под ними дуга самой луны не рисуется — линия через рисунок фазы читалась бы мусором.
    var moonDiscs: [(center: CGPoint, radius: CGFloat)] = []
    let clock: ClockText
    /// Восемь румбов от севера по часовой: С, СВ, В, ЮВ, Ю, ЮЗ, З, СЗ.
    let cardinals: [String]
    /// «закат 18:21» / «восход 06:12».
    let eventText: (SunARScene.HorizonEvent) -> String
    /// Событие, слитое с меткой момента: у горизонта его подписи нет (`SunARLabelLayout.mergedEvent`).
    var merged: SunARScene.HorizonEvent.Kind? = nil
    /// Подпись метки выбранного момента: её плашке раскладка оставляет место.
    var pickedText: String? = nil
    /// Левый верхний угол холста в окне экрана. Ноль — холст на весь экран; копия под линзой диска
    /// (`LensRefraction`) рисует тот же кадр в маленьком холсте, сдвинутом на эту точку.
    var origin: CGPoint = .zero
    /// Диски меток: внутри них оригинал не рисуется — вместо него гнутая копия под линзой.
    var holes: [SunARHole] = []
    /// Весь экран: подписи раскладываются по нему целиком, а не по окну холста, — иначе копия под линзой решала бы
    /// про подписи иначе, чем оригинал. `nil` — холст и есть экран.
    var screen: CGSize?

    var body: some View {
        Canvas { ctxIn, size in
            var ctx = ctxIn
            ctx.translateBy(x: -origin.x, y: -origin.y)
            // Видимая часть окна экрана в его же координатах: за её пределами отрезки дуги не красятся.
            let view = CGRect(origin: origin, size: size)
            let bounds = view.insetBy(dx: -40, dy: -40)
            if !holes.isEmpty {
                ctx.clip(to: SunARHole.clipArea(view, holes: holes), style: FillStyle(eoFill: true))
            }
            // Горизонт: тёмная обводка, под ней светлая линия.
            for run in scene.horizon where run.count > 1 {
                let p = polyline(run)
                ctx.stroke(p, with: .color(.black.opacity(SunARInk.outlineOpacity)),
                           style: StrokeStyle(lineWidth: SunARInk.horizonOutlineWidth, lineCap: .round, lineJoin: .round))
                ctx.stroke(p, with: .color(SunARInk.light.opacity(0.85)),
                           style: StrokeStyle(lineWidth: SunARInk.horizonWidth, lineCap: .round, lineJoin: .round))
            }
            // Дуга луны — тонкой линией, под горизонтом пунктиром; под дугой солнца.
            if !moonArc.isEmpty {
                ctx.drawLayer { layer in
                    let area = SunARHole.clipArea(view, holes: moonDiscs.map { SunARHole(center: $0.center, radius: $0.radius) })
                    layer.clip(to: area, style: FillStyle(eoFill: true))
                    for run in moonArc where run.count > 1 { drawMoonArc(&layer, run) }
                }
            }
            // Дуга солнца: цвет света по точкам, под горизонтом пунктиром.
            for run in scene.arc where run.count > 1 { drawArc(&ctx, run, view: view) }
            // Точки часов, восхода и заката — значки; подписи ставит раскладка (`SunARLabelLayout`): восход и закат
            // где стоят, стороны света, часы — только в свободное место.
            for h in scene.hours {
                let c = CGPoint(h.point)
                guard bounds.contains(c), !SunARLabelLayout.isUnderSun(h, scene: scene) else { continue }
                let dot = CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)
                ctx.fill(Path(ellipseIn: dot.insetBy(dx: -1.5, dy: -1.5)), with: .color(.black.opacity(SunARInk.outlineOpacity)))
                ctx.fill(Path(ellipseIn: dot), with: .color(SunARInk.light))
            }
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
            }
            for l in SunARLabelLayout.make(scene: scene, cardinals: cardinals, eventText: eventText, clock: clock,
                                       bounds: CGRect(origin: .zero, size: screen ?? size).insetBy(dx: -40, dy: -40),
                                       merged: merged, pickedText: pickedText) {
                label(&ctx, l.text, at: l.center, size: l.fontSize, weight: l.weight, opacity: l.opacity)
            }
        }
    }

    /// Дуга одного отрезка: тёмная обводка, белая кромка, цветная жила. Участки ниже горизонта — пунктиром
    /// (штрих и просвет одни на все три слоя, фаза сквозная). Цвет жилы плавно перетекает: каждый отрезок между
    /// точками дуги режется на `arcColorSteps` частей, высота между точками линейная.
    private func drawArc(_ ctx: inout GraphicsContext, _ run: [SunARScene.ArcPoint], view: CGRect) {
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
                // Отрезок вне видимого окна (с запасом на обводку) цвет не рисует; длину набираем, чтобы фаза
                // пунктира дальше совпала с полным холстом.
                let reach = SunARInk.arcOutlineWidth
                let box = CGRect(x: min(ax, bx) - reach, y: min(ay, by) - reach,
                                 width: abs(bx - ax) + 2 * reach, height: abs(by - ay) + 2 * reach)
                guard box.intersects(view) else {
                    length += hypot(bx - ax, by - ay)
                    continue
                }
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

    /// Дуга луны: тёмная обводка и тонкая серебристая жила; участки под горизонтом — пунктиром.
    private func drawMoonArc(_ ctx: inout GraphicsContext, _ run: [NightSkyARScene.ArcPoint]) {
        var i = 0
        while i < run.count - 1 {
            let dashed = run[i].isBelowHorizon && run[i + 1].isBelowHorizon
            var j = i + 1
            while j < run.count - 1, (run[j].isBelowHorizon && run[j + 1].isBelowHorizon) == dashed { j += 1 }
            let path = polyline(run[i...j].map(\.point))
            let cap: CGLineCap = dashed ? .butt : .round
            func style(_ w: CGFloat) -> StrokeStyle {
                StrokeStyle(lineWidth: w, lineCap: cap, lineJoin: .round, dash: dashed ? SunARInk.arcDash : [])
            }
            ctx.stroke(path, with: .color(.black.opacity(SunARInk.outlineOpacity)), style: style(SunARInk.moonArcOutlineWidth))
            ctx.stroke(path, with: .color(SunARInk.moonTint), style: style(SunARInk.moonArcWidth))
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

/// Откуда экран берёт поворот телефона: датчик на телефоне, подставной — в отладочной сборке по аргументу
/// `-LPSunARPose az,alt,roll` (или `az,alt,roll;az,alt,roll` — по очереди), иначе в симуляторе датчика нет.
@MainActor
enum SunARSources {
    static func attitude() -> (any AttitudeSource)? {
        #if DEBUG
        // `-LPSunARPose az,alt,roll[,точность]` (список через `;`), `-LPSunARNorth magnetic` — подставной курс
        // от магнитного севера: так в симуляторе видно плашку «Курс магнитный».
        let d = UserDefaults.standard
        // `-LPSunARCalibScript still|shake|eight[:масштаб]`, `-LPSunARCalibAcc вход,итог[,через_сек]` — подставной
        // поток для экрана калибровки: движение и точность, которые читает калибровка (шаг 29.8в.8).
        if let name = d.string(forKey: "LPSunARCalibScript"), let script = SunARCalibScripts.make(name, acc: d.string(forKey: "LPSunARCalibAcc")) {
            return ScriptedCalibrationAttitude(script: script)
        }
        if let list = d.string(forKey: "LPSunARPose"), let script = ScriptedAttitude.script(list) {
            let north: AttitudeNorth = d.string(forKey: "LPSunARNorth") == "magnetic" ? .magneticNorth : .trueNorth
            return ScriptedAttitude(poses: script.poses, accuracies: script.accuracies, north: north)
        }
        #endif
        #if os(iOS)
        // `-LPSunARSystemCalPanel 1` (отладка): показывать системную панель калибровки поверх экрана — для сравнения.
        var panel = false
        #if DEBUG
        panel = UserDefaults.standard.bool(forKey: "LPSunARSystemCalPanel")
        #endif
        return CoreMotionAttitude(showsSystemCalibrationPanel: panel)
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

#if DEBUG
/// Подставные сценарии калибровки по аргументам запуска (отладка, кадры симулятора).
enum SunARCalibScripts {
    /// `name`: `still`, `shake`, `eight` или `eight:0.3` (масштаб размаха). `acc`: `вход,итог[,через_сек]` — градусы
    /// погрешности при входе, итоговые и через сколько секунд движения система «отвечает» итоговыми.
    static func make(_ name: String, acc: String?) -> CalibrationScript? {
        let parts = name.split(separator: ":").map(String.init)
        let motion: CalibrationScript.Motion
        switch parts.first {
        case "still": motion = .still
        case "shake": motion = .shake
        case "eight": motion = .figureEight(scale: parts.count > 1 ? Double(parts[1]) ?? 1 : 1)
        default: return nil
        }
        let v = (acc ?? "").split(separator: ",").compactMap { Double($0) }
        guard v.count >= 2 else { return CalibrationScript(motion: motion) }
        let (entry, final, after) = (v[0], v[1], v.count > 2 ? v[2] : 6)
        return CalibrationScript(motion: motion) { t in (t < after ? entry : final, nil) }
    }
}
#else
enum SunARCalibScripts {
    static func make(_ name: String, acc: String?) -> CalibrationScript? { nil }
}
#endif
