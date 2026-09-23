import SwiftUI
import LightPlanCore
import LightPlanMapCanvas

/// Экран «Карта» (итерация 20а): холст во весь экран, над ним ночная вуаль,
/// прибор и белая головка — в середине свободного окна между стеклом шапки и
/// стеклом дока (строка показания + таймбар), как `measureMapOptic` веба.
/// Сводка, меню слоёв, ротор и сохранённые точки — итерация 20б.
struct MapScreenView: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var colorScheme

    /// Низ стекла шапки и верх дока в точках экрана.
    @State private var headerBottom: CGFloat = 150
    @State private var dockTop: CGFloat = 700
    @State private var chip: MapInstrument.Chip?
    @State private var chipTask: Task<Void, Never>?
    @State private var cache = MapDayCache()

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
                // В снимке пары холста нет: у веба сеть закрыта, библиотека карты
                // не грузится, и под прибором голая подложка. Холст сверен
                // числами в итерации 4 (земля #15191C, вода #24343A).
                if app.mapOffline {
                    ground
                } else {
                    MapCanvasView(source: app.mapSource,
                                  center: MapCanvasCenter(latitude: place.latitude, longitude: place.longitude),
                                  zoom: 14, dark: darkCanvas, focusShift: ((size.height / 2 - cy) * 2).rounded(),
                                  onMove: { app.moveFromMap(latitude: $0.latitude, longitude: $0.longitude) })
                        .background(ground)
                }

                Color(hex: 0x05070C)
                    .opacity(veil)
                    .animation(.linear(duration: 0.18), value: veil)
                    .allowsHitTesting(false)
                    .shotNode("map.veil", text: String(format: "%.3f", veil))

                MapInstrumentView(scene: scene, optic: optic(size), onTapSun: { tap(.tapSun(az: $0, alt: $1)) },
                                  onTapMoon: { tap(.tapMoon(az: $0, alt: $1)) })

                pin(pal).position(x: size.width / 2, y: cy)

                Text("© CARTO · © OpenStreetMap")
                    .font(.system(size: 9)).tracking(0.2)
                    .foregroundStyle(pal.ink7)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(pal.bar2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .shotNode("map.credit")
                    .frame(width: size.width - 8, alignment: .trailing)
                    .padding(.top, headerBottom + 8)
                    .opacity(app.mapSource == .mapLibre ? 1 : 0)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    header(light, telemetry, pal, top: safe.top)
                    Spacer(minLength: 0).allowsHitTesting(false)
                    dock(light, telemetry, pal).padding(.bottom, safe.bottom)
                }
            }
            .frame(width: size.width, height: size.height)
            .coordinateSpace(.named(Self.space))
            .ignoresSafeArea()
        }
        .onChange(of: timebar.touches) { showChip(.drag, life: 1.2) }
    }

    /// Окно прибора: поля 16 по бокам, сверху низ шапки, снизу верх дока.
    private func optic(_ size: CGSize) -> CGRect {
        CGRect(x: 16, y: headerBottom, width: max(0, size.width - 32), height: max(0, dockTop - headerBottom))
    }

    // MARK: - Шапка на стекле

    /// `#s-map > .header`: место (16/600) со знаком, область (11), дата
    /// (11/500 прописными) — на стекле `--bar` с волоском снизу и полем 16.
    private func header(_ light: LightScreenModel, _ t: LightTelemetry, _ pal: Palette, top: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(light.locationName)
                    .font(.system(size: 16, weight: .semibold)).tracking(-0.2)
                    .foregroundStyle(pal.ink)
                    .shotNode("header.name", text: light.locationName)
                    .frame(height: 18)
                Icon("pin", size: 13, line: 1.6).foregroundStyle(pal.ink6)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, top + 24)
        .padding(.bottom, 16)
        .background { glass(pal) }
        .overlay(alignment: .bottom) { Rectangle().fill(pal.hair).frame(height: 1) }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).maxY } action: { headerBottom = $0 }
    }

    // MARK: - Док на стекле

    /// Строка показания (`.map-read` свёрнутой) и таймбар — одним стеклом
    /// (`.map-frame::after`). Верх дока — низ окна прибора.
    private func dock(_ light: LightScreenModel, _ t: LightTelemetry, _ pal: Palette) -> some View {
        let time = t.readout?.time ?? "", phase = t.readout?.phase ?? ""
        return VStack(spacing: 0) {
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
                    .frame(height: 15)
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(EdgeInsets(top: 13, leading: 24, bottom: 12, trailing: 24))
            .overlay(alignment: .bottom) { Rectangle().fill(pal.hair).frame(height: 1) }
            TimebarView(light.timebar, showRibbon: light.proMode, bare: true)
                .shotNode("timebar")
        }
        .background { glass(pal) }
        .overlay(alignment: .top) { Rectangle().fill(pal.hair).frame(height: 1) }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY } action: { dockTop = $0 }
    }

    /// Стекло веба: `--bar` поверх размытия 20 px.
    private func glass(_ pal: Palette) -> some View {
        ZStack { Rectangle().fill(.ultraThinMaterial); Rectangle().fill(pal.bar) }
    }

    // MARK: - Головка

    /// `.map-pin i`: 13 pt, светлая. В тёмной теме — гнездо: кольцо цвета
    /// холста 2 pt и кольцо чернил 1,5 pt снаружи. В светлой те же кольца
    /// читались чёрной обводкой (Алексей: «спорит с общим визуалом») — там
    /// тёплая кромка 1 pt и тень под предметом в два слоя `--glass-cast`:
    /// `0 1px 2px` и `0 2px 6px`.
    @ViewBuilder
    private func pin(_ pal: Palette) -> some View {
        let head = Circle().fill(pal.knob).frame(width: 13, height: 13)
        Group {
            if pal.dark {
                head
                    .background(Circle().fill(pal.pinRing).padding(-2))
                    .background(Circle().fill(pal.inkA40).padding(-3.5))
            } else {
                // Тень каждого слоя — от самой головки, а не от соседней тени:
                // под головкой два её двойника, каждый со своей тенью.
                head
                    .background(Circle().fill(pal.knobEdge).padding(-1))
                    .background(Circle().fill(pal.knob).shadow(color: pal.glassCast, radius: 1, x: 0, y: 1))
                    .background(Circle().fill(pal.knob).shadow(color: pal.glassCast, radius: 3, x: 0, y: 2))
            }
        }
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

    func day(date: CivilDate, place: Place, solar: SolarDay) -> MapInstrument.Day {
        if let key, let value, key.0 == date, key.1 == place { return value }
        let d = MapInstrument.Day(date: date, place: place, solar: solar)
        key = (date, place)
        value = d
        return d
    }
}
