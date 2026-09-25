import SwiftUI
import LightPlanCore
import LightPlanDomain
import LightPlanMapCanvas

/// Экран «Карта» (итерация 20а): холст во весь экран, над ним ночная вуаль,
/// прибор и белая головка — в середине свободного окна между стеклом шапки и
/// стеклом дока (строка показания + таймбар), как `measureMapOptic` веба.
/// Итерация 20б: сводка под строкой показания (`MapSummary`), меню слоёв,
/// ротор с живым компасом (`MapRotor`), сохранённые точки.
struct MapScreenView: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var colorScheme

    /// Низ стекла шапки, верх таймбара и высота строки показания в точках
    /// экрана. Верх дока для окна прибора — по свёрнутой сводке
    /// (`measureMapOptic`: центр считается по свёрнутому низу, иначе карта
    /// поехала бы от раскрытого свода).
    @State private var headerBottom: CGFloat = 150
    /// Сколько раз поставили булавку — на смену отвечает отдача.
    @State private var spotDrops = 0
    @State private var timebarTop: CGFloat = 760
    @State private var readoutHeight: CGFloat = 60
    @State private var foldContentHeight: CGFloat = 0
    /// Верх строки показания — живой низ окна: кружки карты уворачиваются от
    /// раскрытого свода (`--ctl-bot`), центр прибора — нет.
    @State private var readoutTop: CGFloat = 700
    @State private var layersOpen = false
    private var dockTop: CGFloat { timebarTop - readoutHeight }
    @State private var chip: MapInstrument.Chip?
    @State private var chipTask: Task<Void, Never>?
    @State private var cache = MapDayCache()
    @State private var rotor: CompassRotor
    /// Камера холста для булавок — своим объектом, чтобы кадр жеста
    /// пересобирал только знаки (`MapCameraFeed`).
    @State private var feed = MapCameraFeed()
    /// Полоса имени точки: какая точка названа, набранное, обратный отсчёт
    /// «тихой» полосы (`snbTimer`, 5 с).
    @State private var barSpot: String?
    @State private var barText = ""
    @State private var barTimer: Task<Void, Never>?
    @FocusState private var barFocus: Bool

    init(app: AppModel) {
        self.app = app
        _rotor = State(initialValue: CompassRotor(source: app.heading))
    }

    private static let space = "mapScreen"

    var body: some View {
        let pal = Palette(colorScheme)
        let light = app.light
        let timebar = light.timebar
        let telemetry = light.telemetry
        let layers = app.mapLayers
        let lightTheme = !pal.dark
        let minute = timebar.machine.viewMinute
        let date = timebar.machine.selectedDate
        let solar = timebar.solarDay
        let place = timebar.place
        let clock = ClockText(language: app.language, preference: light.clockPreference)
        let input = MapInstrument.Input(
            date: date, minute: minute, solar: solar, place: place, layers: layers, pro: light.proMode,
            lightTheme: lightTheme, chip: chip, clock: { clock.fmt($0) },
            cardinals: ["card.n", "card.e", "card.s", "card.w"].map { app.lexicon.t($0) })
        let scene = MapInstrument.scene(input, day: cache.day(date: date, place: place, solar: solar))
        let cy = (headerBottom + dockTop) / 2
        // Вуаль по высоте солнца до −18°; со звёздами глубже (`nightVeil`).
        let deep = max(0, min(1, -solar.elevation(at: minute) / 18))
        let veil = deep * (layers.mw ? 0.72 : 0.5)
        let darkCanvas = !MapInstrument.lightCanvas(lightTheme: lightTheme, layers: layers)
        // Подложка — цвет контейнера карты у веба: виден, пока стиль не встал
        // (в светлой теме без белой вспышки), и в снимке пары. Со звёздами холст
        // уходит в ночь и в светлой теме (`body.mw-sky`).
        let ground = darkCanvas ? pal.canvas : Color(hex: 0xE8E3DA)

        GeometryReader { g in
            let safe = g.safeAreaInsets
            let size = CGSize(width: g.size.width + safe.leading + safe.trailing,
                              height: g.size.height + safe.top + safe.bottom)
            ZStack(alignment: .topLeading) {
                // Ротор (`.map-rotor`): карта, вуаль и прибор одним слоем —
                // живой компас крутит их вокруг наблюдателя. Карта и вуаль —
                // квадрат `MapRotor.side`, чтобы на любом угле не открылся клин.
                let side = MapRotor.side(width: size.width, height: size.height, cy: cy)
                // Центр камеры в квадрате ротора — под головкой наблюдателя.
                let anchor = CGPoint(x: side / 2, y: cy - size.height / 2 + side / 2)
                ZStack(alignment: .topLeading) {
                    Group {
                        // В снимке пары холста нет: у веба сеть закрыта, библиотека
                        // карты не грузится, и под прибором голая подложка. Холст
                        // сверен числами в итерации 4 (земля #15191C, вода #24343A).
                        if app.mapOffline {
                            ground
                        } else {
                            MapCanvasView(source: app.mapSource,
                                          center: MapCanvasCenter(latitude: place.latitude, longitude: place.longitude),
                                          zoom: 14, dark: darkCanvas, labels: app.mapLabels, language: app.language,
                                          panEnabled: !rotor.live, focusShift: ((size.height / 2 - cy) * 2).rounded(),
                                          onMove: { app.moveFromMap(latitude: $0.latitude, longitude: $0.longitude) },
                                          onCamera: { cam in
                                              feed.camera = cam
                                              // Карту двинули пальцем — полоса точки уходит.
                                              if cam.byHand, barSpot != nil { closeBar() }
                                          },
                                          onTap: { tapMap($0, anchor: anchor, side: side) })
                                .background(ground)
                        }
                    }
                    .frame(width: side, height: side)
                    .position(x: size.width / 2, y: size.height / 2)
                    #if DEBUG
                    // Кадр сменился — отсчёт сценария заново: тап только по улёгшемуся.
                    .task(id: "\(anchor.x),\(anchor.y),\(side)") { await shotTapSpot(anchor: anchor, side: side) }
                    #endif

                    Color(hex: 0x05070C)
                        .opacity(veil)
                        .animation(.linear(duration: 0.18), value: veil)
                        .frame(width: side, height: side)
                        .position(x: size.width / 2, y: size.height / 2)
                        .allowsHitTesting(false)
                        .shotNode("map.veil", text: String(format: "%.3f", veil))

                    // Булавки своих мест — над вуалью и под прибором: город ночью
                    // темнеет, свои точки — нет. Слой — квадрат ротора, как холст.
                    if layers.spots {
                        MapSpotsLayer(spots: app.spots, feed: feed, fallback: fallbackCamera(place),
                                      anchor: anchor, here: app.place.coordinate, pal: pal)
                            .frame(width: side, height: side)
                            .position(x: size.width / 2, y: size.height / 2)
                    }

                    MapInstrumentView(scene: scene, optic: optic(size), onTapSun: { tap(.tapSun(az: $0, alt: $1)) },
                                      onTapMoon: { tap(.tapMoon(az: $0, alt: $1)) })
                    #if DEBUG
                    // Метка севера сценария компаса (21а): в роторе, в 120 pt к северу
                    // от оси — `Tools/rotor.js` мерит по ней угол на снимке.
                    if Self.shotMarks {
                        Circle().fill(Color(hex: 0xFF00FF)).frame(width: 8, height: 8)
                            .position(x: size.width / 2, y: cy - 120).allowsHitTesting(false)
                    }
                    #endif
                }
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(-rotor.angle), anchor: UnitPoint(x: 0.5, y: cy / max(1, size.height)))

                pin(pal).position(x: size.width / 2, y: cy)

                Text("© CARTO · © OpenStreetMap")
                    .font(.system(size: 9)).tracking(0.2)
                    .foregroundStyle(pal.ink7)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(pal.bar2)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 7, style: .continuous)))
                    .shotNode("map.credit")
                    .frame(width: size.width - 8, alignment: .trailing)
                    .padding(.top, headerBottom + 8)
                    .opacity(app.mapSource == .mapLibre ? 1 : 0)
                    .allowsHitTesting(false)

                layersButton(pal, on: layers.sun || layers.moon || layers.mw, darkCanvas: darkCanvas)
                    .position(x: 12 + 17, y: readoutTop - 12 - 17)

                headingButton(pal, darkCanvas: darkCanvas)
                    .position(x: 12 + 17, y: headerBottom + 12 + 17)

                VStack(spacing: 0) {
                    header(light, telemetry, pal, top: safe.top)
                    Spacer(minLength: 0).allowsHitTesting(false)
                    dock(light, telemetry, summary(date: date, minute: minute, solar: solar, place: place, clock: clock),
                         pal, cy: cy).padding(.bottom, safe.bottom)
                }
            }
            .overlay(alignment: .top) {
                // Полоса имени — у верха окна прибора, над картой и кружками.
                if let id = barSpot, let sp = app.spots.first(where: { $0.id == id }) {
                    SpotNameBar(text: $barText, focus: $barFocus, coord: sp.coordinate.text, lexicon: app.lexicon,
                                pal: pal, onDelete: deleteBar, onDone: commitBar, onTouch: holdBar)
                        .padding(.horizontal, 10)
                        .padding(.top, headerBottom + 10)
                }
            }
            .overlay {
                if layersOpen {
                    ZStack(alignment: .bottomLeading) {
                        // Скрим — тап мимо меню закрывает его (`#mapLayersScrim`).
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { withAnimation(.easeOut(duration: 0.16)) { layersOpen = false } }
                        // Растёт вверх от кнопки, 8 над её верхом: вниз мешают
                        // край кадра и док.
                        layersMenu(pal, layers, darkCanvas: darkCanvas)
                            .fixedSize()
                            .padding(.leading, 12)
                            .padding(.bottom, max(0, size.height - (readoutTop - 12 - 34 - 8)))
                            .transition(.scale(scale: 0.94, anchor: .bottomLeading).combined(with: .opacity))
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            #if DEBUG
            .background(Self.shotVoid)
            #endif
            .coordinateSpace(.named(Self.space))
            .ignoresSafeArea()
        }
        .onChange(of: timebar.touches) { showChip(.drag, life: 1.2) }
        .sensoryFeedback(.impact(weight: .medium), trigger: spotDrops)
        // Фокус в поле — отсчёт снят; ушёл — имя записано (`blur` веба).
        .onChange(of: barFocus) { _, focused in
            if focused { holdBar() } else if barSpot != nil { commitBar() }
        }
        // Уходя с карты, гасим датчик — он не нужен нигде больше (веб так же).
        .onDisappear { northUp() }
        .onAppear {
            // Снимок пары открывает меню слоёв, как палец (`--chapter layers`).
            if app.startChapter == "layers" { layersOpen = true; app.startChapter = nil }
            // …и нажимает закладку (`--chapter spot`): точка и полоса её имени.
            if app.startChapter == "spot" { app.startChapter = nil; saveTapped(keyboard: false) }
            // …и включает компас (`--chapter compass`, 21а): курс — подставной.
            if app.startChapter == "compass" { app.startChapter = nil; rotor.setLive(true) }
        }
        #if DEBUG
        .task { await shotHeading() }
        #endif
    }

    /// Окно прибора: поля 16 по бокам, сверху низ шапки, снизу верх дока.
    private func optic(_ size: CGSize) -> CGRect {
        CGRect(x: 16, y: headerBottom, width: max(0, size.width - 32), height: max(0, dockTop - headerBottom))
    }

    // MARK: - Шапка на стекле

    /// `#s-map > .header`: место (16/600) со знаком, область (11), дата
    /// (11/500 прописными) — на стекле `--bar` с волоском снизу и полем 16.
    private func header(_ light: LightScreenModel, _ t: LightTelemetry, _ pal: Palette, top: CGFloat) -> some View {
        // `#mapLoc` — кнопка на место, область и дату: открывает лист места.
        Button { app.placeSheetOpen = true } label: {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(light.locationName)
                    .font(.system(size: 16, weight: .semibold)).tracking(-0.2)
                    .foregroundStyle(pal.ink)
                    .shotNode("header.name", text: light.locationName)
                    .frame(height: 18)
                PlacePin(pal: pal)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            }
            if !light.locationSub.isEmpty {
                Text(light.locationSub)
                    .font(.system(size: 11)).tracking(0.1)
                    .foregroundStyle(pal.ink4)
                    .shotNode("header.sub", text: light.locationSub)
                    .frame(height: 13)
                    .padding(.top, 1)
            }
            Text(t.header.dateLabel)
                .font(.system(size: 11, weight: .medium)).tracking(0.6).textCase(.uppercase)
                .foregroundStyle(pal.ink4)
                .shotNode("header.date", text: t.header.dateLabel)
                .frame(height: 13)
                .padding(.top, 3)
        }
        .contentShape(Rectangle())
        }
        .buttonStyle(PlaceButtonStyle())
        .accessibilityLabel(app.lexicon.t("today.changePlace"))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, top + 24)
        .padding(.bottom, 16)
        // Закладка в правом углу шапки (`.map-save`, поля −6 сверху и −8 справа).
        .overlay(alignment: .topTrailing) {
            MapSaveButton(on: app.spotHere != nil, lexicon: app.lexicon, pal: pal, action: { saveTapped() })
                .padding(.top, top + 24 - 6)
                .padding(.trailing, 24 - 8)
        }
        .background { glass(pal, outside: [.top, .horizontal]) }
        .overlay(alignment: .bottom) { Rectangle().fill(pal.hair).frame(height: 1) }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).maxY } action: { headerBottom = $0 }
    }

    // MARK: - Док на стекле

    /// Строка показания (`.map-read`), свод (`.map-fold`) и таймбар — одним
    /// стеклом (`.map-frame::after`). Шеврон сворачивает всё, кроме времени.
    private func dock(_ light: LightScreenModel, _ t: LightTelemetry, _ summary: MapSummary,
                      _ pal: Palette, cy: CGFloat) -> some View {
        let time = t.readout?.time ?? "", phase = t.readout?.phase ?? ""
        let shut = app.mapFoldShut
        // Потолок свода: стекло не накрывает белую головку (`--fold-max`).
        let foldMax = max(120, (timebarTop - readoutHeight - cy - 20).rounded())
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.4)) { app.setMapFold(shut: !shut) }
            } label: {
                HStack(alignment: .top, spacing: 11) {
                    Text(time)
                        .font(.system(size: 34, weight: .ultraLight).monospacedDigit()).tracking(-0.5)
                        .foregroundStyle(pal.ink)
                        .shotNode("readout.time", text: time)
                        .frame(height: 34)
                    Text(phase)
                        .font(.system(size: 11, weight: .semibold)).tracking(1.4).textCase(.uppercase)
                        .foregroundStyle(pal.dark ? Color(t.stateColor) : pal.ink3)
                        .shotNode("readout.phase", text: phase)
                        .frame(minHeight: 15)
                        .padding(.top, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // `.mr-chev`: 16, `--ink-4`, линия 2,4; раскрытая смотрит
                    // вниз, свёрнутая — вверх.
                    Icon("chevron", size: 16, line: 2.4)
                        .foregroundStyle(pal.ink4)
                        .rotationEffect(.degrees(shut ? -90 : 90))
                        .shotNode("readout.chev")
                        .frame(height: 34)
                }
                .padding(EdgeInsets(top: 13, leading: 24, bottom: 12, trailing: 24))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) { Rectangle().fill(pal.hair).frame(height: 1) }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { readoutHeight = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY } action: { readoutTop = $0 }

            if !shut {
                // Что не поместилось под потолок — прокручивается внутри свода,
                // карта под ним не двигается.
                ScrollView(.vertical) {
                    fold(summary, light: light, pal)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { foldContentHeight = $0 }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(foldContentHeight, foldMax))
                .clipped()
                .transition(.opacity)
                .shotNode("map.fold")
            }

            TimebarView(light.timebar, showRibbon: light.proMode, bare: true)
                .shotNode("timebar")
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY } action: { timebarTop = $0 }
        }
        .background { glass(pal, outside: [.bottom, .horizontal]) }
        .overlay(alignment: .top) { Rectangle().fill(pal.hair).frame(height: 1) }
    }

    /// `.telemetry` (поле 24) и `.pro` со спойлером «Подробно» (только астро).
    private func fold(_ summary: MapSummary, light: LightScreenModel, _ pal: Palette) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(summary.rows, id: \.label) { row in
                    TelemetryRow(labelKey: row.label, labelText: { app.lexicon.t($0) }) {
                        Text(row.text)
                            .foregroundStyle(color(row.tone, pal))
                            .shotNode("fold." + row.label.dropFirst(4), text: row.text)
                    }
                }
            }
            .padding(.horizontal, 24)
            LightSpoilerView(groups: summary.pro, open: light.proMode, title: app.lexicon.t("today.details"))
                .padding(.horizontal, 24)
        }
    }

    private func color(_ tone: MapSummary.Tone, _ pal: Palette) -> Color {
        switch tone {
        case .ink: pal.ink
        case .ink2: pal.ink2
        case .ink4: pal.ink4
        case .terra: pal.terra
        case .violet: Color(hex: 0xC6AAE8)
        case .warm: Color(hex: 0xE2A44C)
        case .shade: Color(hex: 0x8A8478)
        }
    }

    /// Свод на минуту ползунка. Окно Млечного Пути и помеха луны — раз на
    /// сутки и место, и только при включённом слое.
    private func summary(date: CivilDate, minute: Minutes, solar: SolarDay, place: Place, clock: ClockText) -> MapSummary {
        let mw: MapSummary.MilkyWayInput? = app.mapLayers.mw ? {
            let (w, moon) = cache.milkyWay(date: date, place: place)
            return MapSummary.MilkyWayInput(
                window: w, moon: moon, sky: app.light.weather.milkyWaySky(for: date, window: w),
                nextDark: { AstroNight.next(after: date, latitude: place.latitude,
                                            utcOffsetHours: place.zone.utcOffsetHours(on: date)) })
        }() : nil
        let zone = TimeZone(identifier: place.zone.identifier) ?? .current
        let dates = DateText(language: app.language, timeZone: zone)
        return MapSummary.build(
            date: date, t: minute, sun: solar, place: place,
            utcOffset: place.zone.utcOffsetHours(on: app.light.timebar.todayInPlace), pro: app.light.proMode,
            glow: app.glow.ratio, mw: mw,
            dateShort: { dates.dMonShort(DateText.carrier(year: $0.year, month: $0.month - 1, day: $0.day, in: zone)) },
            lexicon: app.lexicon, clock: clock)
    }

    // MARK: - Слои

    /// `.map-here.map-layers-btn`: кружок 34, знак 18, линия 1,8, `--ink-3`,
    /// латунью — когда светится хоть одно светило. Стекло — встроенное, как у
    /// веера (20в), а не подделка веба (`--bar-2`, блик дугой, тень).
    private func layersButton(_ pal: Palette, on: Bool, darkCanvas: Bool) -> some View {
        let ink = MapGlassCircle.ink(pal, darkCanvas: darkCanvas)
        return Button {
            withAnimation(.easeOut(duration: 0.16)) { layersOpen.toggle() }
        } label: {
            LayersGlyph()
                .stroke(on ? ink.brass : ink.ink3, style: StrokeStyle(lineWidth: 1.8 * 18 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 18, height: 18)
                .frame(width: 34, height: 34)
                .modifier(MapGlassCircle(pal: pal, darkCanvas: darkCanvas))
        }
        .buttonStyle(.plain)
        .shotNode("map.layersBtn")
    }

    /// `.map-heading-btn`: тот же кружок, что у слоёв, у верха окна прибора
    /// слева; включённый — латунью и дышит (1 ↔ 0,55 за 1,6 с).
    private func headingButton(_ pal: Palette, darkCanvas: Bool) -> some View {
        let ink = MapGlassCircle.ink(pal, darkCanvas: darkCanvas)
        return Button {
            if rotor.live { northUp() } else { rotor.setLive(true) }
        } label: {
            HeadingGlyph()
                .stroke(rotor.live ? ink.brass : ink.ink3,
                        style: StrokeStyle(lineWidth: 1.8 * 18 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 18, height: 18)
                .phaseAnimator([1.0, 0.55]) { v, k in v.opacity(rotor.live ? k : 1) } animation: { _ in
                    .easeInOut(duration: 0.8)
                }
                .frame(width: 34, height: 34)
                .modifier(MapGlassCircle(pal: pal, darkCanvas: darkCanvas))
        }
        .buttonStyle(.plain)
        .shotNode("map.headingBtn")
    }

    /// Компас выключен — карта возвращается на север за 0,3 с.
    private func northUp() {
        rotor.setLive(false)
        withAnimation(.easeInOut(duration: 0.3)) { rotor.angle = 0 }
    }

    /// `.scope-menu.map-layers-menu`: стекло карты (`--map-glass`, размытие
    /// 5), радиус 16, поле 6, ширина от 208; пункт — поле 12, зазор 10,
    /// 15 pt. Галочка 16 латунью (линия 2,2) видна у включённого, знак 19
    /// (линия 1,5) — `--ink-4`, у включённого `--ink`.
    private func layersMenu(_ pal: Palette, _ layers: MapLayers, darkCanvas: Bool) -> some View {
        let items: [(MapLayers.Key, String, String)] = [
            (.sun, "sun", "layer.sun"), (.moon, "moon", "layer.moon"), (.mw, "stars", "layer.mw"),
            (.compass, "compass", "layer.compass"), (.spots, "pin", "layer.spots"),
        ]
        return VStack(spacing: 0) {
            ForEach(items, id: \.0) { key, icon, word in
                let on = layers[key]
                Button {
                    app.setMapLayer(key, !on)
                } label: {
                    HStack(spacing: 10) {
                        Icon("check", size: 16, line: 2.2).foregroundStyle(pal.brass).opacity(on ? 1 : 0)
                        Icon(icon, size: 19, line: 1.5).foregroundStyle(on ? pal.ink : pal.ink4)
                        Text(app.lexicon.t(word)).font(.system(size: 15)).foregroundStyle(pal.ink)
                            .shotNode(word, text: app.lexicon.t(word))
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 208 - 12)
        .padding(6)
        // Вид прототипа на встроенном стекле, как панель вкладок: тон веба
        // поверх системного стекла (материал осветлял карту: Δ 45–107 к вебу).
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.mapGlass)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Тема стекла — по холсту под ним: со звёздами холст ночной и в
            // светлой теме, а системное стекло светлой темы его осветляло.
            .environment(\.colorScheme, darkCanvas ? .dark : .light))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 18)
        .shotNode("map.layers")
    }

    /// Шапка и док — рецепт панели вкладок (19б): тон веба `--bar` поверх
    /// встроенного стекла. Системное стекло светит кромкой по всему контуру,
    /// а у веба край один — волосок к карте; остальные края — за экраном.
    private func glass(_ pal: Palette, outside: Edge.Set) -> some View {
        Rectangle().fill(pal.bar).glassEffect(.regular, in: Rectangle())
            .padding(outside, -4)
    }

    // MARK: - Сохранённые точки

    /// Камера, пока холст не сказал своей (нет сети в паре, первый кадр):
    /// место приложения на уровне веба 14.
    private func fallbackCamera(_ place: Place) -> MapCanvasCamera {
        MapCanvasCamera(center: MapCanvasCenter(latitude: place.latitude, longitude: place.longitude), zoom: 14)
    }

    /// Тап по холсту (`lmap.on("click")`): по булавке — переезд на точку и
    /// тихая полоса с её именем; мимо — открытая полоса закрывается и больше
    /// ничего. Точка под головкой в тап не идёт: ехать некуда.
    private func tapMap(_ p: CGPoint, anchor: CGPoint, side: CGFloat) {
        guard let id = MapSpots.hit(p, marks: spotMarks(anchor: anchor, side: side)),
              let sp = app.spots.first(where: { $0.id == id }),
              let la = sp.latitude, let lo = sp.longitude else {
            if barSpot != nil { closeBar() }
            return
        }
        app.moveFromMap(latitude: la, longitude: lo)
        openBar(sp, edit: true, quiet: true)
    }

    /// Булавки на кадре в координатах холста — их острия ловят тап.
    private func spotMarks(anchor: CGPoint, side: CGFloat) -> [(id: String, tip: CGPoint, labelWidth: CGFloat)] {
        guard app.mapLayers.spots else { return [] }
        let cam = feed.camera ?? fallbackCamera(app.light.timebar.place)
        let here = app.place.coordinate
        let bounds = CGSize(width: side, height: side)
        return app.spots.compactMap { sp in
            guard let la = sp.latitude, let lo = sp.longitude, !sp.coordinate.isSameSpot(as: here) else { return nil }
            let d = MapSpots.offset(latitude: la, longitude: lo, camera: cam)
            let tip = CGPoint(x: anchor.x + d.x, y: anchor.y + d.y)
            guard MapSpots.onScreen(tip, in: bounds) else { return nil }
            return (sp.id, tip, feed.labelWidths[sp.id] ?? 0)
        }
    }

    #if DEBUG
    /// Пустота под ротором (21а): в сценарии `-LPShotVoid` — яркий цвет, которого
    /// нет ни на карте, ни в приборе; открылся клин — `Tools/rotor.js` найдёт его
    /// на снимке экрана. С ним же в роторе — метка севера. Без аргумента — ничего.
    private static let shotMarks = UserDefaults.standard.string(forKey: "LPShotVoid") != nil
    private static let shotVoid: Color = {
        guard let hex = UserDefaults.standard.string(forKey: "LPShotVoid"),
              let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) else { return .clear }
        return Color(hex: v)
    }()

    /// Сценарий подставного компаса (21а): для каждого угла `-LPShotHeading`
    /// ждёт, пока ротор встанет (в 0,2° от угла), и дописывает в
    /// `-LPShotHeadingReport`, на каком угле стоит, — `Tools/rotor.js` по этой
    /// записи снимает экран. Первый угол — после 1,5 с раскладки экрана. Не
    /// встал за три выдержки и 15 с сверху — пишет `settled: false` (в 21а
    /// ротор раз простоял на 0° 10 с после запуска: 9 с было мало).
    private func shotHeading() async {
        guard let out = UserDefaults.standard.string(forKey: "LPShotHeadingReport"),
              let s = ShotScenario.fromLaunch(), let angles = s.heading else { return }
        let hold = s.headingHold
        try? await Task.sleep(for: .seconds(1.5))
        var rows: [[String: Any]] = []
        let write = {
            let json = try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys])
            try? json?.write(to: URL(fileURLWithPath: out), options: .atomic)
        }
        for (i, target) in angles.enumerated() {
            let start = Date()
            var off = 360.0
            while !Task.isCancelled, Date().timeIntervalSince(start) < hold * 3 + 15 {
                off = rotor.angle - target
                off -= 360 * (off / 360).rounded()
                if rotor.live, abs(off) < 0.2 { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            guard !Task.isCancelled else { return }
            rows.append(["i": i, "target": target, "angle": rotor.angle, "live": rotor.live,
                         "cy": Double((headerBottom + dockTop) / 2),
                         "settled": abs(off) < 0.2, "ms": Int(Date().timeIntervalSince(start) * 1000)])
            write()
        }
    }

    /// Сценарий `-LPShotTapSpot <id>` (итерация 20е): когда кадр три секунды
    /// стоит, приложение само тапает острие булавки тем же `tapMap`, что и
    /// распознаватель холста, и пишет в `-LPShotTapReport`, стоит ли полоса
    /// имени через 1 и 4 с и ушла ли через 6,5 с (тихая живёт 5 с). Камеру
    /// ведёт живой холст (`-LPShotLiveMap`) — ошибка 20е жила в нём.
    private func shotTapSpot(anchor: CGPoint, side: CGFloat) async {
        let d = UserDefaults.standard
        guard let id = d.string(forKey: "LPShotTapSpot"), let out = d.string(forKey: "LPShotTapReport") else { return }
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled, feed.camera != nil else { return }
        guard let mark = spotMarks(anchor: anchor, side: side).first(where: { $0.id == id }) else {
            try? Data(#"{"error":"no pin on screen"}"#.utf8).write(to: URL(fileURLWithPath: out))
            return
        }
        tapMap(mark.tip, anchor: anchor, side: side)
        var seen: [String: Bool] = [:]
        for (key, wait) in [("bar1", 1.0), ("bar4", 3.0), ("bar6_5", 2.5)] {
            try? await Task.sleep(for: .seconds(wait))
            seen[key] = barSpot == id
        }
        seen["moved"] = app.place.coordinate.isSameSpot(as: app.spots.first { $0.id == id }?.coordinate ?? .init(latitude: 0, longitude: 0))
        let json = try? JSONSerialization.data(withJSONObject: seen, options: [.sortedKeys])
        try? json?.write(to: URL(fileURLWithPath: out))
    }
    #endif

    /// Закладка шапки: новая точка — полоса с пустым полем и клавиатурой
    /// (`openSpotName(spots[0])`); повторный тап убирает точку.
    /// `keyboard: false` — снимок пары: у веба в безголовом браузере клавиатуры
    /// нет, и полоса стоит без неё и без обратного отсчёта.
    private func saveTapped(keyboard: Bool = true) {
        guard let sp = app.toggleSpotHere() else { return }
        spotDrops += 1
        MapClick.play()
        openBar(sp, edit: false, quiet: false, keyboard: keyboard)
    }

    /// `openSpotName`: `edit` — в поле нынешнее имя; `quiet` — тап «что это
    /// за точка»: клавиатура не поднимается, полоса гаснет через 5 с.
    private func openBar(_ sp: Spot, edit: Bool, quiet: Bool, keyboard: Bool = true) {
        holdBar()
        barSpot = sp.id
        barText = edit ? sp.name : ""
        if quiet {
            barFocus = false
            barTimer = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { closeBar() }
            }
        } else if keyboard {
            // Поле появляется этим же проходом — фокус на следующем.
            Task { @MainActor in barFocus = true }
        }
    }

    private func holdBar() { barTimer?.cancel(); barTimer = nil }

    /// Закрытие без записи (`closeSpotName`); набранное записывает уход фокуса.
    private func closeBar() {
        holdBar()
        if barFocus { barFocus = false } else { barSpot = nil }
    }

    /// Галочка, «Готово» клавиатуры, уход фокуса (`commitSpotName`).
    private func commitBar() {
        guard let id = barSpot else { return }
        holdBar()
        barSpot = nil
        barFocus = false
        app.renameSpot(id: id, to: barText)
    }

    /// Корзина (`spotNameDel`): точка уходит, набранное не пишется.
    private func deleteBar() {
        guard let id = barSpot else { return }
        holdBar()
        barSpot = nil
        barFocus = false
        app.removeSpot(id: id)
    }

    // MARK: - Головка

    /// `.map-pin i`: центр компаса — матовое стекло ручки ползунка
    /// (`KnobGlass`, 20д), 20 pt — как головка булавки, которая из него
    /// вырастает (20г: «окружность как у центра компаса»). Прежде — светлый
    /// шарик 13 pt с кольцами до тех же 20.
    private func pin(_ pal: Palette) -> some View {
        KnobGlass(shape: Circle(), pal: pal)
            .frame(width: MapSpots.headDiameter, height: MapSpots.headDiameter)
            .shotNode("map.pin")
            .allowsHitTesting(false)
    }

    // MARK: - Чип

    private func tap(_ c: MapInstrument.Chip) { showChip(c, life: 2.2) }

    private func showChip(_ c: MapInstrument.Chip, life: Double) {
        chip = c
        chipTask?.cancel()
        chipTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(life))
            if !Task.isCancelled { chip = nil }
        }
    }
}

/// Сутки прибора — раз на день и место (путь солнца, луна, трек ядра);
/// ползунок пересчитывает только то, что зависит от минуты.
final class MapDayCache {
    private var key: (CivilDate, Place)?
    private var value: MapInstrument.Day?
    private var mwKey: (CivilDate, Place)?
    private var mwValue: (MilkyWayWindow, MoonVsStars)?

    func milkyWay(date: CivilDate, place: Place) -> (MilkyWayWindow, MoonVsStars) {
        if let mwKey, let mwValue, mwKey.0 == date, mwKey.1 == place { return mwValue }
        let v = (MilkyWayWindow(date: date, place: place), MoonVsStars(date: date, place: place))
        mwKey = (date, place)
        mwValue = v
        return v
    }

    func day(date: CivilDate, place: Place, solar: SolarDay) -> MapInstrument.Day {
        if let key, let value, key.0 == date, key.1 == place { return value }
        let d = MapInstrument.Day(date: date, place: place, solar: solar)
        key = (date, place)
        value = d
        return d
    }
}

/// Знак слоёв — свой SVG в разметке веба (`M12 3l9 5-9 5-9-5 9-5z M3 13l9 5 9-5`),
/// не из `icons.js`.
private struct LayersGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        var p = Path()
        p.move(to: CGPoint(x: 12, y: 3)); p.addLine(to: CGPoint(x: 21, y: 8)); p.addLine(to: CGPoint(x: 12, y: 13))
        p.addLine(to: CGPoint(x: 3, y: 8)); p.closeSubpath()
        p.move(to: CGPoint(x: 3, y: 13)); p.addLine(to: CGPoint(x: 12, y: 18)); p.addLine(to: CGPoint(x: 21, y: 13))
        return p.applying(CGAffineTransform(scaleX: k, y: k)).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Знак живого компаса — свой SVG в разметке веба: круг r 8,5 и стрелка
/// `M15 9l-2 5-4 1 2-5z`.
private struct HeadingGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        var p = Path(ellipseIn: CGRect(x: 3.5, y: 3.5, width: 17, height: 17))
        p.move(to: CGPoint(x: 15, y: 9)); p.addLine(to: CGPoint(x: 13, y: 14)); p.addLine(to: CGPoint(x: 9, y: 15))
        p.addLine(to: CGPoint(x: 11, y: 10)); p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: k, y: k)).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Кружок кнопки «Карты» на встроенном стекле — рецепт веера (20в): тон
/// `mapGlass` поверх системного стекла, тема стекла — по холсту под ним.
/// `interactive` даёт отклик на нажатие, как у системного стекла; свой блик
/// и тень не рисуются — у стекла они свои.
private struct MapGlassCircle: ViewModifier {
    let pal: Palette
    let darkCanvas: Bool

    /// Палитра знака: на ночном холсте стекло тёмное и в светлой теме, и
    /// тёмные чернила светлой темы на нём теряются (#55504A на #535353) —
    /// знак берёт чернила и латунь тёмной темы.
    static func ink(_ pal: Palette, darkCanvas: Bool) -> Palette {
        darkCanvas ? Palette(.dark) : pal
    }

    func body(content: Content) -> some View {
        content
            .background(Circle().fill(pal.mapGlass))
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle())
            .environment(\.colorScheme, darkCanvas ? .dark : .light)
    }
}
