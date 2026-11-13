import SwiftUI
import LightPlanCore

/// Экран «Свет» — первый настоящий экран приложения (итерация 19). Порт
/// `#s-today` веба: шапка, купол с показанием, «что дальше» со спарклайном,
/// телемерия семью строками, спойлер «Подробно», кнопка съёмки.
///
/// Купол (итерация 18) и таймбар (итерация 17) не переписаны — экран
/// оборачивает их в композицию веба, добавляя то, чего вокруг них ещё не
/// было: показание, шапку, телеметрию, спойлер, кнопку.
public struct LightScreenView: View {
    @Bindable var model: LightScreenModel
    /// Кнопка места в шапке (`#todayLoc`): открывает лист «Где снимаем».
    var onPlace: () -> Void
    /// Кнопка «Запланировать съёмку»: день и минута начала из `model.planShoot`.
    var onPlan: (CivilDate, Int) -> Void
    @Environment(\.colorScheme) private var colorScheme
    /// Видимая высота прокрутки — чтобы кнопка съёмки легла к низу, как
    /// `.screen-action { margin-top: auto }` веба.
    @State private var visibleHeight: CGFloat = 0
    /// Нижняя кромка плашки «условия» (в видимой части и в содержимом) — по ней решается, сколько строк помещается в покое.
    @State private var plateProbe = PlateProbe()
    /// Верх плашки «время» в `viewportSpace` (30з.2а): ниже него, за вычетом зазора между плашками, плашка «условия» в покое не уходит.
    @State private var plate3Top: CGFloat = .infinity
    /// Рамка купола и показаний в ней — светило пальцем (19в).
    @State private var domeSize = CGSize(width: 0, height: DomeView.height)
    @State private var readoutFrame = CGRect.null
    /// 29.8в.27: сколько необязательных строк («Тени», «Небо», «Ветер») поместилось в закрытый список «Астро» (`LightCollapsedList`).
    @State private var fitRows = 0
    /// На сколько pt (0…12) поднята полоса под дугой сверх 22: только когда без этого не помещается важный набор. Выбирает
    /// `LightCollapsedList.plan` по измеренной высоте; «Просто» не затрагивается. Шапка «Астро» сжата всегда (слово Алексея 21.10).
    @State private var extraTuck: CGFloat = 0
    /// 30з.2: на низких экранах, когда даже без необязательных строк и с полосой 12 плашка «условия» не помещается над щелью «↺ Сейчас», купол
    /// поднят на столько pt (0…`maxDomeLift`) под низ шапки: над дугой есть пустое небо, шапка по бокам его не касается.
    @State private var domeLift: CGFloat = 0
    @State private var rowHeights: [LightCollapsedList.Row: CGFloat] = [:]
    /// Низ кнопки «Подробно» в координатах содержимого прокрутки и высота кнопки съёмки — по ним считается запас высоты.
    @State private var spoilerBottom: CGFloat = 0
    /// Сколько необязательных строк стояло в закрытом списке, когда измерен `spoilerBottom` (из той же отрисовки): по нему из
    /// низа кнопки вычитается высота стоявших строк — иначе измерение и число строк расходились на проход раскладки.
    @State private var spoilerRows = 0
    @State private var spoilerExtraTuck: CGFloat = 0

    public init(_ model: LightScreenModel, onPlace: @escaping () -> Void = {},
                onPlan: @escaping (CivilDate, Int) -> Void = { _, _ in }) {
        self.model = model
        self.onPlace = onPlace
        self.onPlan = onPlan
    }

    /// Два вида (30з.2а, настройка «Экран „Свет“»): «С блоками» — небо и три плашки, «Без блоков» — плоский вид 30з.1.
    public var body: some View {
        Group { if model.blocks { blocksBody } else { flatBody } }
            .onChange(of: model.blocks) { _, _ in
                // Вид переключён на ходу: измерения прежнего вида не годятся новому.
                fitRows = 0; extraTuck = 0; domeLift = 0; spoilerBottom = 0
                refreshCollapsedRows()
            }
    }

    /// Вёрстка — числа `#s-today` беты (вычисленные стили, снимок пары 19б):
    /// поля экрана 24, шапка сразу под безопасной зоной (29.2г: у веба там +24 от размытия часов iOS 27, у натива его нет), купол во всю ширину высотой 240,
    /// «что дальше» 72, строки телеметрии по 35, кнопка съёмки у низа,
    /// таймбар прибит над вкладками. До 19б это был стенд: поля 16, таймбар
    /// посреди прокрутки, свой набор кеглей.
    @ViewBuilder private var blocksBody: some View {
        let telemetry = model.telemetry
        let pal = Palette(colorScheme)
        let tuckNow = model.proMode && LightCollapsedList.shortensByHeight ? extraTuck : 0
        let layoutNow = LightCollapsedList.Layout(
            rows: LightCollapsedList.shown(astro: model.proMode, fit: shownFit, hasForecast: telemetry.sky != nil || telemetry.wind != nil).count,
            extraTuck: tuckNow)

        // 30з.2 (макет 4 Алексея 12.11): небо шире купола — подложка «шапка + купол» с чёрной виньеткой по углам; три плашки
        // матового стекла: «сейчас» (от линии горизонта), «условия» (список + ручка «Подробно»), «время» (пульт, лента дат и шкала, внизу).
        let sun = model.timebar.solarDay
        let minute = model.timebar.machine.viewMinute
        let skyNow = DomeSky(astro: model.look.domeSky, elevation: sun.elevation(at: minute), morning: minute < sun.solarNoon,
                             lightTheme: !pal.dark, palette: SkyPalette(weather: model.weather.day(for: model.timebar.machine.selectedDate)))
        let presence = DomeGeometry.clamp((sun.elevation(at: minute) + 18) / 6, 0, 1)
        let headPal = Self.headerPalette(pal, sky: skyNow, presence: presence)

        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    header(telemetry.header, note: telemetry.forecastNote, headPal)
                        .padding(.horizontal, 24)
                        .zIndex(1)

                    dome(telemetry, pal, skyFill: skyNow == nil)
                        .padding(.top, -domeLift)
                        .padding(.bottom, -Self.domeTuck(extra: tuckNow))
                        .tabRise()
                }
                .frame(maxWidth: .infinity)
                .background(alignment: .top) { skyBackdrop(skyNow, pal, tuck: Self.domeTuck(extra: tuckNow), presence: presence) }

                // Всё под шапкой проявляется при смене вкладки (S1); шапка не мигает.
                Group {
                    // 30з.2: «сейчас» — плашка стекла от линии горизонта, времена у оснований дуги внутри неё.
                    nowPlate(telemetry, pal, tuck: Self.domeTuck(extra: tuckNow))

                    // 30з.2: плашка «условия» (список + ручка «Подробно») и под ней каждая рубрика «Подробно» — своя плашка (`LightSpoilerView`).
                    LightSpoilerView(groups: telemetry.proGroups, open: model.proMode, title: model.lexiconWord("today.details"),
                                     openTitle: model.lexiconWord("today.hide"),
                                     measureTag: layoutNow, onMeasure: { measureSpoiler($0) },
                                     windLabel: model.lexiconWord("pro.wind"),
                                     above: AnyView(telemetryList(telemetry, pal)), plated: true, probe: plateProbe,
                                     onPlate: { refreshCollapsedRows() })
                        .padding(.top, Self.plateGap)
                }
                .tabRise()
            }
            // 30з.2а: растяжки по высоте экрана нет — страница не длиннее своего содержимого, и пока оно (в покое, «Подробно» закрыт)
            // помещается над плашкой «время», она не прокручивается (`.basedOnSize`). Дальше содержимое уходит под плашку «время».
            .coordinateSpace(.named(LightCollapsedList.contentSpace))
        }
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: Bool.self) { abs($0.contentOffset.y + $0.contentInsets.top) < 0.5 } action: { _, atRest in
            plateProbe.atRest = atRest
            plateProbe.refresh()
            refreshCollapsedRows()
        }
        .shotNode("light.scroll")
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0; refreshCollapsedRows() }
        .onChange(of: model.proMode) { _, pro in
            // В «Просто» спойлера нет и ничего не прячется; в «Астро» число строк решит новое измерение.
            if !pro { fitRows = 0; extraTuck = 0; spoilerBottom = 0 }
            refreshCollapsedRows()
        }
        // Прогноз приходит позже первой раскладки: у «Неба» и «Ветра» появляется строка, а кнопка «Подробно» не сдвинулась — пересчитать.
        .onChange(of: model.telemetry.sky != nil || model.telemetry.wind != nil) { _, _ in refreshCollapsedRows() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // 30з.2а: третья плашка — пульт (капсула «Запланировать съёмку» и «↺»), лента дат и шкала на стекле; от краёв 8, от нижней
            // панели 8, от плашки «условия» (в покое) 8 — обычный зазор между плашками, не коридор.
            VStack(spacing: 0) {
                Color.clear.frame(height: Self.plateGap)
                TimebarView(model.timebar, showRibbon: model.look.dayRibbon, showEdges: false, plate: true,
                            console: AnyView(actionButton(pal)))
                    .shotNode("timebar")
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.viewportSpace)).minY } action: {
                        if abs($0 - plate3Top) > 0.25 { plate3Top = $0; refreshCollapsedRows() }
                    }
                    .padding(.horizontal, 8).padding(.bottom, Self.plateGap)
            }
            .tabRise()
        }
        .coordinateSpace(.named(Self.viewportSpace))
        .background(pal.surface)
    }

    /// Вид «Без блоков» (30з.2а): экран 30з.1 как в `e6a5ccd` — плоский, без плашек и без подложки неба; кнопка съёмки парящая капсула и «↺» в одной строке над
    /// лентой. Не улучшается; от вида с блоками отличается только этим телом, расчётом строк и кнопкой.
    @ViewBuilder private var flatBody: some View {
        let telemetry = model.telemetry
        let pal = Palette(colorScheme)
        let tuckNow = model.proMode ? extraTuck : 0
        let layoutNow = LightCollapsedList.Layout(
            rows: LightCollapsedList.shown(astro: model.proMode, fit: fitRows, hasForecast: telemetry.sky != nil || telemetry.wind != nil).count,
            extraTuck: tuckNow)

        ScrollView {
            VStack(spacing: 0) {
                header(telemetry.header, note: telemetry.forecastNote, pal)
                    .padding(.horizontal, 24)

                // Всё под шапкой проявляется при смене вкладки (S1); шапка не мигает.
                Group {
                    dome(telemetry, pal, skyFill: true, flatTimes: true)
                        .padding(.bottom, -Self.domeTuck(extra: tuckNow))

                    // 30з.1 (макет 4 Алексея 12.11): под куполом «до …» между основаниями дуги → «Запланировать съёмку» → список.
                    nextLight(telemetry, pal)
                        .padding(.horizontal, 24)
                        .padding(.top, 2)
                        .frame(height: 72, alignment: .top)

                    telemetryList(telemetry, pal)
                        .padding(.horizontal, 24)

                    LightSpoilerView(groups: telemetry.proGroups, open: model.proMode, title: model.lexiconWord("today.details"),
                                     openTitle: model.lexiconWord("today.hide"),
                                     measureTag: layoutNow, onMeasure: { measureSpoiler($0) },
                                     windLabel: model.lexiconWord("pro.wind"))
                        .padding(.horizontal, 24)

                    // Кнопки внизу больше нет: остаток экрана уходит под список.
                    Spacer(minLength: 0)
                }
                .tabRise()
            }
            .frame(minHeight: max(0, visibleHeight - Self.actionReserve), alignment: .top)
            .coordinateSpace(.named(LightCollapsedList.contentSpace))
        }
        .scrollBounceBehavior(.basedOnSize)
        // 30з.1 (слово Алексея 13.11: «под большой палец, … парящей, над интерфейсом»): кнопка съёмки — парящая капсула над лентой дат и
        // шкалой; список уходит под неё, низ прокрутки отступает на её высоту, чтобы последняя строка доставалась.
        .safeAreaPadding(.bottom, Self.actionReserve)
        .overlay(alignment: .bottom) {
            flatActionRow(pal)
                .tabRise()
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0; refreshCollapsedRows() }
        .onChange(of: model.proMode) { _, pro in
            // В «Просто» спойлера нет и ничего не прячется; в «Астро» число строк решит новое измерение.
            if !pro { fitRows = 0; extraTuck = 0; spoilerBottom = 0 }
        }
        // Прогноз приходит позже первой раскладки: у «Неба» и «Ветра» появляется строка, а кнопка «Подробно» не сдвинулась — пересчитать.
        .onChange(of: model.telemetry.sky != nil || model.telemetry.wind != nil) { _, _ in refreshCollapsedRows() }
        .safeAreaInset(edge: .bottom, spacing: 8) {
            TimebarView(model.timebar, showRibbon: model.look.dayRibbon, showEdges: false)
                .shotNode("timebar")
                .tabRise()
        }
        .background(pal.surface)
    }

    /// Сколько необязательных строк стоит в закрытом списке: все, пока укорочение по высоте выключено (30з.2).
    private var shownFit: Int { LightCollapsedList.shortensByHeight ? fitRows : Int.max }

    // MARK: - Шапка

    /// `.header`: слева место (16/600), область (11), дата (11/500
    /// прописными, разрядка 0,6), «сегодня» (11/500, `--ink-6`); справа
    /// погода — знак 22 и 24/600, состояние 14 (`--ink-2`), ↓↑ 13 (`--ink-4`).
    private func header(_ h: LightTelemetry.Header, note forecastNote: String?, _ pal: Palette) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // `.loc` веба — кнопка на всю левую колонку: место, область, дата.
            Button(action: onPlace) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(h.locationName)
                        .font(.system(size: 16, weight: .semibold)).tracking(-0.2)
                        .foregroundStyle(pal.ink)
                        .shotNode("header.name", text: h.locationName)
                        .frame(height: 18)
                    PlaceFollowArrow(pal: pal, following: model.placeFollowing)
                        .shotNode("header.follow", text: model.placeFollowing ? "on" : "off")
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                }
                // 29.8в.27, «Астро»: строки «область» нет (слово Алексея 21.10; данные модели целы), дата и «сегодня» — как были,
                // каждая в своей строке. Адаптация натива, веб не менялся; в «Просто» шапка прежняя.
                if !model.locationSub.isEmpty && !model.proMode {
                    Text(model.locationSub)
                        .font(.system(size: 11)).tracking(0.1)
                        .foregroundStyle(pal.ink4)
                        .shotNode("header.sub", text: model.locationSub)
                        .frame(height: 13)
                        .padding(.top, 1)
                }
                Text(h.dateLabel)
                    .font(.system(size: 11, weight: .medium)).tracking(0.6).textCase(.uppercase)
                    .foregroundStyle(pal.ink4)
                    .shotNode("header.date", text: h.dateLabel)
                    .frame(height: 13)
                    .padding(.top, 3)
                Text(h.note)
                    .font(.system(size: 11, weight: .medium)).tracking(0.4).textCase(.uppercase)
                    .foregroundStyle(pal.ink6)
                    .shotNode("header.note", text: h.note)
                    .frame(height: 13)
                    .padding(.top, 4)
            }
            .contentShape(Rectangle())
            }
            .buttonStyle(PlaceButtonStyle())
            .accessibilityLabel(model.lexiconWord("today.changePlace"))
            Spacer(minLength: 0)
            if let w = h.weather {
                // Тап по блоку погоды — принудительная загрузка прогноза (28ж.3в).
                Button { model.weather.refreshNow() } label: {
                VStack(alignment: .trailing, spacing: 2) {
                    // Знак и градусы: 22 + поле 8 (`.wx` у знака) + зазор 7 = 15
                    // между ними; знак на 1,5 выше середины строки, как у веба.
                    HStack(spacing: 15) {
                        Icon(w.iconName, size: 22, line: 1.5)
                            .foregroundStyle(pal.ink)
                            .shotNode("wx.icon")
                            .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] + 1.5 }
                        Text(w.temperature)
                            .font(.system(size: 24, weight: .semibold).monospacedDigit()).tracking(-0.5)
                            .foregroundStyle(pal.ink)
                            .shotNode("wx.temp", text: w.temperature)
                    }
                    if model.proMode {
                        // «Астро» (29.8в.27): состояние и ↓↑ в одной строке — две строки погоды вместо трёх.
                        HStack(spacing: 8) {
                            // Сжимается только слово состояния; ↓↑ не теряются (замечание ревью GPT к 017a9ba).
                            Text(w.condition)
                                .font(.system(size: 14))
                                .foregroundStyle(pal.ink2)
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .shotNode("wx.cond", text: w.condition)
                            HStack(spacing: 6) {
                                Text(w.low).shotNode("wx.lo", text: w.low)
                                Text(w.high).shotNode("wx.hi", text: w.high)
                            }
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(pal.ink4)
                            .fixedSize()
                        }
                    } else {
                    Text(w.condition)
                        .font(.system(size: 14))
                        .foregroundStyle(pal.ink2)
                        .shotNode("wx.cond", text: w.condition)
                    HStack(spacing: 10) {
                        Text(w.low).shotNode("wx.lo", text: w.low)
                        Text(w.high).shotNode("wx.hi", text: w.high)
                    }
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(pal.ink4)
                    }
                }
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
            } else if let forecastNote {
                // Прогноза нет — честная надпись на месте погоды; выдуманное не рисуем (28ж).
                // Тап по ней — принудительная загрузка прогноза (28ж.3в).
                Button { model.weather.refreshNow() } label: {
                Text(forecastNote)
                    .font(.system(size: 14))
                    .foregroundStyle(pal.ink4)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 150, alignment: .trailing)
                    .shotNode("wx.none", text: forecastNote)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Купол и показание

    private func dome(_ t: LightTelemetry, _ pal: Palette, skyFill: Bool, flatTimes: Bool = false) -> some View {
        DomeView(sun: model.timebar.solarDay, place: model.timebar.place,
                 date: model.timebar.machine.selectedDate, t: model.timebar.machine.viewMinute,
                 nowMinute: model.timebar.nowMinute,
                 skyPalette: SkyPalette(weather: model.weather.day(for: model.timebar.machine.selectedDate)),
                 astro: model.look.domeSky,
                 swap: model.moon,
                 skyFill: skyFill,
                 mode: moonModeBinding)
            .shotNode("dome")
            .overlay {
                if let readout = t.readout {
                    GeometryReader { geo in
                        // Тап по показаниям — лист «Когда смотрим» (19в).
                        Button { model.pickerOpen = true } label: { readoutView(readout, t, pal) }
                            .buttonStyle(.plain)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.domeSpace)) } action: {
                                readoutFrame = $0
                            }
                            .position(x: geo.size.width / 2, y: 124)
                    }
                }
            }
            .overlay { if flatTimes { flatBaseTimes(pal: Palette(colorScheme)) } }
            .coordinateSpace(.named(Self.domeSpace))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { domeSize = $0 }
            .contentShape(Rectangle())
            .modifier(DomeDragModifier(gesture: DomeDragGesture(
                accepts: { domeAccepts($0) },
                onMove: { model.dragDome(at: $0, in: domeSize) })))
    }

    private static let domeSpace = "dome"

    /// 30з.2: промежуток между плашками и от плашек до краёв — 8 pt, поля плашки по бокам 8 (содержимое внутри стоит на прежних 24).
    static let plateGap: CGFloat = 8
    /// Знак рассвета и заката у оснований дуги (было 19) и высота стопки «знак → время → подпись»: 26 + 2 + 15 + 2 + 13.
    /// Размеры подобраны на равновесие плашки, а не списаны с рисунка (Алексей: «делал на глаз»): знак 28, время 13, подпись 12 — боковые
    /// колонки по весу близки к числу в центре (оно стало легче: 30 → 28 pt); стопка чуть опущена к середине плашки.
    static let baseIconSize: CGFloat = 28
    static let baseStackTop: CGFloat = 10
    /// Центр стопки у основания дуги не ближе к краю плашки: полуширина подписи 28 + поле 12.
    static let baseEdgeInset: CGFloat = 40
    static let baseStackHeight: CGFloat = 28 + 2 + 16 + 2 + 15
    /// Низ плашки «сейчас» ниже блока «до …».
    private static let nowPlateBottom: CGFloat = 10

    /// Отступ безопасной зоны сверху у окна: внутри прокрутки `GeometryProxy` его не отдаёт (шов под строкой состояния на первом кадре 30з.2).
    private static var windowSafeTop: CGFloat {
        #if os(iOS)
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .first(where: \.isKeyWindow)?.safeAreaInsets.top ?? 0
        #else
        0
        #endif
    }

    /// Подложка неба за шапкой и куполом (`LightSkyBackdrop`): рамка и положение зенита и горизонта — из размера зоны и вписывания купола.
    @ViewBuilder
    private func skyBackdrop(_ sky: DomeSky?, _ pal: Palette, tuck: CGFloat, presence: Double) -> some View {
        if let sky {
            GeometryReader { geo in
                let fit = DomeFit(size: CGSize(width: max(1, geo.size.width), height: DomeView.height))
                let domeTop = geo.size.height + tuck - DomeView.height
                LightSkyBackdrop(sky: sky, pal: pal, zoneSize: geo.size,
                                 zenithY: domeTop + fit.point(CGPoint(x: 0, y: CGFloat(DomeGeometry.cy - DomeGeometry.ry))).y,
                                 horizonY: domeTop + fit.point(CGPoint(x: 0, y: CGFloat(DomeGeometry.horizonY))).y,
                                 safeTop: Self.windowSafeTop, presence: presence)
            }
        }
    }

    /// Шапка стоит на небе: в светлой теме тёмное небо сумерек просит светлые чернила (порог — равный контраст тёмных и светлых чернил,
    /// L ≈ 0,17). В тёмной теме чернила светлые на любом небе.
    static func headerPalette(_ pal: Palette, sky: DomeSky?, presence: Double) -> Palette {
        guard !pal.dark, let sky else { return pal }
        let page = SkyColor(237, 237, 240)
        let seen = LightPalette.lerp(page, sky.zenith, presence)
        return DomeSky.luminance(seen) > 0.17 ? pal : Palette(.dark)
    }

    /// Плашка «сейчас» (30з.2): от линии горизонта вниз; внутри — «до …» по центру и время рассвета и заката у оснований дуги, знак над
    /// временем. Основания — концы дуги на горизонте (`cx ∓ rx`, `cy` в `viewBox` купола), через `DomeFit` — на любой ширине. После
    /// заката слева завтрашний рассвет (`baseRiseEdge`). Кнопки в плашке нет: она парит над лентой.
    private func nowPlate(_ t: LightTelemetry, _ pal: Palette, tuck: CGFloat) -> some View {
        let fit = DomeFit(size: CGSize(width: max(1, domeSize.width), height: DomeView.height))
        // От верха блока «до …» (низ рамки «шапка + купол») вверх до горизонта: купол 240 − подъём 22 − горизонт у 196 → 22 pt.
        let rise = max(0, DomeView.height - tuck - fit.point(CGPoint(x: 0, y: CGFloat(DomeGeometry.horizonY))).y)
        return nextLight(t, pal)
            .padding(.top, 2)
            .frame(height: 72, alignment: .top)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) { baseTimes(pal: pal, rise: rise) }
            .padding(.bottom, Self.nowPlateBottom)
            .background(alignment: .top) {
                Color.clear.glassPlate(pal).padding(.top, -rise)
            }
            .shotNode("plate.now")
            .padding(.horizontal, 8)
    }

    /// Времена у оснований дуги: координаты блока «до …» (его левый край — x = 8 экрана, верх — `rise` ниже горизонта). Касаний не ловят.
    private func baseTimes(pal: Palette, rise: CGFloat) -> some View {
        let fit = DomeFit(size: CGSize(width: max(1, domeSize.width), height: DomeView.height))
        let g = DomeGeometry.self
        // Стопка на сторону (слово Алексея 16.11): знак → время → подпись; верх стопки на `baseStackTop` ниже горизонта.
        let y = Self.baseStackTop + Self.baseStackHeight / 2 - rise
        // Стопка шире знака («рассвет» ≈ 50 pt): на 390 pt основание дуги стоит у самого края плашки — центр не ближе `edgeInset` к краям.
        let blockWidth = max(1, domeSize.width - 16)
        let left = max(fit.point(CGPoint(x: g.cx - g.rx, y: 0)).x - 8, Self.baseEdgeInset)
        let right = min(fit.point(CGPoint(x: g.cx + g.rx, y: 0)).x - 8, blockWidth - Self.baseEdgeInset)
        let tb = model.timebar
        return ZStack(alignment: .topLeading) {
            baseLabel(tb.baseRiseEdge, pal, caption: model.lexiconWord("light.baseRise")).shotNode("edge.rise").position(x: left, y: y)
            if let setEdge = tb.setEdge { baseLabel(setEdge, pal, caption: model.lexiconWord("light.baseSet")).shotNode("edge.set").position(x: right, y: y) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func baseLabel(_ content: TimebarState.EdgeContent, _ pal: Palette, caption: String) -> some View {
        switch content {
        case .time(let icon, let minutes):
            // Знак 19 → 28 pt (×1,47), время 12 → 13, подпись 12 под временем цветом акцента (текст — `brassInk`); время серое как было.
            VStack(spacing: 2) {
                Icon(icon, size: Self.baseIconSize, line: 1.6).foregroundStyle(pal.brassDeep)
                Text(model.timebar.clockString(minutes))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(pal.ink4)
                Text(caption)
                    .font(.system(size: 12, weight: .medium)).tracking(0.2)
                    .foregroundStyle(pal.brassInk)
                    .lineLimit(1)
                    .shotNode("edge.cap", text: caption)
            }
        case .text(let text):
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(pal.ink4)
                .multilineTextAlignment(.center).lineLimit(2)
                .frame(width: 84)
        }
    }

    /// Вид «Без блоков» (30з.1, `e6a5ccd`): время рассвета и заката — у оснований дуги, знак над временем, в пустой полосе купола под
    /// горизонтом. Основания — концы дуги на горизонте (`cx ∓ rx`, `cy` в `viewBox` купола), через `DomeFit`. После заката слева
    /// завтрашний рассвет (`baseRiseEdge`). Не ловят касаний; рамку купола не меняют.
    private func flatBaseTimes(pal: Palette) -> some View {
        let fit = DomeFit(size: CGSize(width: max(1, domeSize.width), height: DomeView.height))
        let g = DomeGeometry.self
        let y = fit.point(CGPoint(x: 0, y: g.horizonY)).y + 6
        let left = fit.point(CGPoint(x: g.cx - g.rx, y: 0)).x
        let right = fit.point(CGPoint(x: g.cx + g.rx, y: 0)).x
        let tb = model.timebar
        return ZStack(alignment: .topLeading) {
            flatBaseLabel(tb.baseRiseEdge, pal).shotNode("edge.rise").position(x: left, y: y + 17.5)
            if let setEdge = tb.setEdge { flatBaseLabel(setEdge, pal).shotNode("edge.set").position(x: right, y: y + 17.5) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func flatBaseLabel(_ content: TimebarState.EdgeContent, _ pal: Palette) -> some View {
        switch content {
        case .time(let icon, let minutes):
            VStack(spacing: 2) {
                Icon(icon, size: 19, line: 1.6).foregroundStyle(pal.brassDeep)
                Text(model.timebar.clockString(minutes))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(pal.ink4)
            }
        case .text(let text):
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(pal.ink4)
                .multilineTextAlignment(.center).lineLimit(2)
                .frame(width: 84)
        }
    }

    /// Низ кнопки измерен вместе с тем, что стояло на экране в этой раскладке.
    private func measureSpoiler(_ m: LightCollapsedList.Measurement) {
        spoilerBottom = m.bottom
        spoilerRows = m.layout.rows
        spoilerExtraTuck = m.layout.extraTuck
        refreshCollapsedRows()
    }

    /// 29.8в.27: пересчёт числа строк закрытого списка «Астро» по свежим измерениям.
    private func refreshCollapsedRows() {
        guard model.blocks else { refreshFlatRows(); return }
        guard LightCollapsedList.shortensByHeight, visibleHeight > 0, plate3Top.isFinite else { return }
        // 30з.2а: плашка «условия» в покое кончается не ниже верха плашки «время» минус обычный зазор между плашками.
        let limit = plate3Top - Self.plateGap
        guard model.proMode else {
            // «Просто»: ручки и спрятанных строк нет — все на месте; нехватку берёт на себя подъём купола. Измерение — низ плашки в покое
            // (вид из видимой части), приведённый к раскладке без подъёма.
            guard plateProbe.atRest, plateProbe.vp.isFinite else { return }
            let deficit = plateProbe.vp + domeLift - limit + LightCollapsedList.slack
            let lift = min(LightCollapsedList.maxDomeLift, max(0, deficit))
            if abs(lift - domeLift) > 0.25 { domeLift = lift }
            return
        }
        guard spoilerBottom > 0, plateProbe.contentTop.isFinite else { return }
        let hasForecast = model.telemetry.sky != nil || model.telemetry.wind != nil
        let present = LightCollapsedList.present(hasForecast: hasForecast)
        let heights = present.map { rowHeights[$0] ?? LightCollapsedList.defaultRowHeight }
        // Низ «Подробно» приводится к базе: без необязательных строк, полоса 22 — как была бы раскладка, не зная, какая из них сейчас
        // на экране (иначе решение мигало бы). Шапка «Астро» сжата всегда, в базу входит сжатой.
        let baseline = spoilerBottom - heights.prefix(spoilerRows).reduce(CGFloat(0), +) + spoilerExtraTuck + domeLift
        // Ручка «Подробно» стоит у самой нижней кромки плашки «условия»: после неё в плашке ничего нет (`tail` = 0).
        let room = limit - plateProbe.contentTop
        let plan = LightCollapsedList.plan(visibleHeight: room, baselineBottom: baseline, actionHeight: 0, rowHeights: heights)
        if plan.rows != fitRows { fitRows = plan.rows }
        if plan.extraTuck != extraTuck { extraTuck = plan.extraTuck }
        // Даже без строк и с полосой 12 не помещается — остаток берёт подъём купола.
        let spare = room - baseline - LightCollapsedList.slack
        let lift = min(LightCollapsedList.maxDomeLift, max(0, -spare - LightCollapsedList.maxExtraTuck))
        if abs(lift - domeLift) > 0.25 { domeLift = lift }
    }

    /// Вид «Без блоков»: расчёт 30з.1 как был.
    private func refreshFlatRows() {
        guard model.proMode, spoilerBottom > 0, visibleHeight > 0 else { return }
        let hasForecast = model.telemetry.sky != nil || model.telemetry.wind != nil
        let present = LightCollapsedList.present(hasForecast: hasForecast)
        let heights = present.map { rowHeights[$0] ?? LightCollapsedList.defaultRowHeight }
        let baseline = spoilerBottom - heights.prefix(spoilerRows).reduce(CGFloat(0), +) + spoilerExtraTuck
        let plan = LightCollapsedList.plan(visibleHeight: visibleHeight - Self.actionReserve, baselineBottom: baseline, actionHeight: 0, rowHeights: heights)
        if plan.rows != fitRows { fitRows = plan.rows }
        if plan.extraTuck != extraTuck { extraTuck = plan.extraTuck }
    }

    /// 29.8в.26: от горизонта дуги (196 из 240 в `viewBox`) до подписи «до золотого часа» у веба 44 + 2 pt — пустая
    /// полоса, из-за которой на 15 Pro Max «Подробно» уходило под нижнюю панель (замер: −16,5 pt). Рамка купола
    /// остаётся 240 (дуга, показание, перетаскивание светила и призрак под строками стоят как были), весь список
    /// ниже поднят на столько: 22 — слово Алексея 21.10 (база, «Просто» остаётся на ней). В «Астро» 29.8в.27 добавляет `extra`
    /// (0…12) только когда без этого не помещается важный набор; подпись остаётся не ближе 12 pt к горизонту (46 − 34).
    /// Веб тут не менялся — пара «Свет» расходится на это число.
    static let domeTuckBase: CGFloat = 22
    static func domeTuck(extra: CGFloat) -> CGFloat { domeTuckBase + extra }

    /// Касание купола — наше, если оно над горизонтом и мимо показаний и
    /// тумблера светила (`closest("#readout")`, `closest("#skySwap")` веба).
    /// Тумблер — 52×26 с полем 7, на 26 от верха и 12 от правого края.
    private func domeAccepts(_ p: CGPoint) -> Bool {
        let swap = CGRect(x: domeSize.width - 12 - 66, y: 26, width: 66, height: 40)
        if swap.contains(p) || readoutFrame.contains(p) { return false }
        return model.domeMinute(at: p, in: domeSize) != nil
    }

    /// `.dome-readout`: середина — 124 pt от верха купола; время 46 тонким
    /// (`font-weight: 200`), строка 46; фаза 11/600 прописными, разрядка
    /// 1,4, цвет — состояние неба в тёмной теме и `--ink-3` в светлой
    /// (`labelColor` веба); смысл 12, `--ink-4`.
    private func readoutView(_ r: LightTelemetry.Readout, _ t: LightTelemetry, _ pal: Palette) -> some View {
        let sun = model.timebar.solarDay
        let minute = model.timebar.machine.viewMinute
        let sky = DomeSky(astro: model.look.domeSky, elevation: sun.elevation(at: minute), morning: minute < sun.solarNoon,
                          lightTheme: !pal.dark, palette: SkyPalette(weather: model.weather.day(for: model.timebar.machine.selectedDate)))
        // Text layout stays unchanged; only ink follows its actual height in the sky.
        let fit = DomeFit(size: CGSize(width: max(1, domeSize.width), height: DomeView.height))
        func ink(at y: CGFloat, fallback: Color) -> Color {
            guard let sky else { return fallback }
            let modelY = (y - fit.origin.y) / fit.scale
            return Color(sky.ink(at: (Double(modelY) - (DomeGeometry.cy - DomeGeometry.ry)) / DomeGeometry.ry))
        }
        return VStack(spacing: 0) {
            Text(r.time)
                .font(.system(size: 46, weight: .thin).monospacedDigit()).tracking(-0.5)
                .foregroundStyle(ink(at: 105, fallback: pal.ink))
                .shotNode("readout.time", text: r.time)
                .frame(height: 46)
            Text(r.phase)
                .font(.system(size: 11, weight: .semibold)).tracking(1.4).textCase(.uppercase)
                .foregroundStyle(ink(at: 141, fallback: pal.dark ? Color(t.stateColor) : pal.ink3))
                .shotNode("readout.phase", text: r.phase)
                .frame(height: 13)
                .padding(.top, 7)
            Text(r.sense)
                .font(.system(size: 12))
                .foregroundStyle(ink(at: 160, fallback: pal.ink4))
                .shotNode("readout.sense", text: r.sense)
                .frame(height: 15)
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)
        .padding(.vertical, 8).padding(.horizontal, 14)
        .fixedSize()
    }

    private var moonModeBinding: Binding<DomeSkyMode> {
        Binding(get: { model.moonMode ? .moon : .sun }, set: { model.moonMode = $0 == .moon })
    }

    // MARK: - «Что дальше»

    /// `.next-light`: по центру; подпись 11/600 прописными, разрядка 1,4;
    /// число 30 светлым (`300`), строка 1,05; тренд — искра 42×14 и слово 12.
    private func nextLight(_ t: LightTelemetry, _ pal: Palette) -> some View {
        let nl = t.next
        return VStack(spacing: 0) {
            Text(nl.label)
                .font(.system(size: 11, weight: .semibold)).tracking(1.4).textCase(.uppercase)
                .foregroundStyle(pal.ink4)
                .shotNode("next.label", text: nl.label)
                .frame(height: 13)
            Text(nl.value)
                .font(.system(size: 28, weight: .light).monospacedDigit()).tracking(-0.5)
                .foregroundStyle(LightScreenTheme.toneColor(t.tone, state: t.stateColor, scheme: colorScheme))
                .shotNode("next.value", text: nl.value)
                .frame(height: 31.5)
                .padding(.top, 3)
            if let trend = nl.trend, let word = nl.trendWord {
                HStack(spacing: 8) {
                    SparklineShape(values: trend)
                        .stroke(pal.ink4, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .frame(width: 42, height: 14)
                        .shotNode("next.spark")
                    Text(word).font(.system(size: 12))
                        .shotNode("next.word", text: word)
                }
                .foregroundStyle(pal.ink4)
                .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Телеметрия

    private func telemetryList(_ t: LightTelemetry, _ pal: Palette) -> some View {
        let toneColor = LightScreenTheme.toneColor(t.tone, state: t.stateColor, scheme: colorScheme)
        return VStack(spacing: 0) {
            TelemetryRow(labelKey: "tele.cond", labelText: model.lexiconWord) {
                HStack(spacing: 9) {
                    LightGaugeView(gauge: t.condition.gauge, color: toneColor)
                    Text(t.condition.text)
                }
                .foregroundStyle(toneColor)
                .fontWeight(.semibold)
                .shotNode("tele.rec", text: t.condition.text)
            }
            plainRow(labelKey: "tele.sunset", value: t.sunset.text, color: LightScreenTheme.sunsetColor(t.sunset.tone, scheme: colorScheme))
            plainRow(labelKey: "tele.golden", value: t.golden)
            plainRow(labelKey: "tele.light", value: t.light)
            // «Тени», «Небо», «Ветер» — необязательные строки: в «Астро» стоит столько первых, сколько помещается (`LightCollapsedList`).
            let shown = LightCollapsedList.shown(astro: model.proMode, fit: shownFit, hasForecast: t.sky != nil || t.wind != nil)
            if shown.contains(.shadow) {
                plainRow(labelKey: "tele.shadow", value: t.shadow)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeights[.shadow] = $0; refreshCollapsedRows() }
            }
            // Небо и ветер — из прогноза: нет прогноза — нет строк (надпись уже в «Закате» и в шапке).
            if let sky = t.sky, shown.contains(.sky) {
                rowWithIcon(labelKey: "tele.sky", iconName: sky.iconName, value: sky.text)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeights[.sky] = $0; refreshCollapsedRows() }
            }
            if let wind = t.wind, shown.contains(.wind) {
                plainRow(labelKey: "tele.wind", value: wind)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeights[.wind] = $0; refreshCollapsedRows() }
            }
            if let air = t.air {
                plainRow(labelKey: "tele.air", value: air)
            }
        }
    }

    private func plainRow(labelKey: String, value: String, color: Color? = nil) -> some View {
        TelemetryRow(labelKey: labelKey, labelText: model.lexiconWord) {
            Text(value).foregroundStyle(color ?? LightScreenTheme.ink(colorScheme))
                .shotNode(labelKey, text: value)
        }
    }

    /// Знак неба (`.wx`): 17×17, зазор 8.
    private func rowWithIcon(labelKey: String, iconName: String, value: String) -> some View {
        TelemetryRow(labelKey: labelKey, labelText: model.lexiconWord) {
            HStack(spacing: 8) {
                Icon(iconName, size: 17, line: 1.5)
                Text(value)
            }
            .foregroundStyle(LightScreenTheme.ink(colorScheme))
            .shotNode(labelKey, text: value)
        }
    }

    // MARK: - Кнопка съёмки

    /// Строка под дугой: ширина дуги (326 из 440), высота 40 с полем 3, знак 22 латунью,
    /// подпись 16/600, справа время с ползунка. Тап — новая съёмка ровно на это время (`planShoot`).
    private func actionButton(_ pal: Palette, flat: Bool = false) -> some View {
        let time = model.planShootTime
        return Button(action: { let r = model.planShoot; onPlan(r.day, r.start) }) {
            HStack(spacing: 13) {
                PlanShootGlyph()
                    .stroke(pal.brass, style: StrokeStyle(lineWidth: 1.6 * 22 / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: 22, height: 22)
                Text(model.lexiconWord("today.planShoot"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(pal.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(time)
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(pal.brassInk)
                    .lineLimit(1)
                    .shotNode("action.sub", text: time)
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            // Системное стекло, как у других плавающих кнопок (30з.1). Ни затемнения, ни затухания рядом с ней нет (слово Алексея 16.11).
            .glassEffect(.regular, in: Capsule())
            .flatGlass(Capsule(), light: !pal.dark)
            // Светлая тема: капсула на белой плашке без тени — тонкий кант, чтобы её край читался (кант, не тень).
            .overlay { if !pal.dark && !flat { Capsule().strokeBorder(pal.hair4, lineWidth: 1).allowsHitTesting(false) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        #if DEBUG
        // Замер шага 30д: `-LPShotNoAction 1` — кнопки не видно, место то же.
        .opacity(UserDefaults.standard.string(forKey: "LPShotNoAction") == nil ? 1 : 0)
        #endif
        .shotNode("action")
    }

    /// Вид «Без блоков» (слово Алексея 13.11: «перенесём кнопку „сегодня“ в одну строку с „Запланировать съёмку“, сможем перенести кнопку ниже»):
    /// капсула съёмки и круглая «↺» в одной строке над лентой; строки «↺ Сейчас» между ними и лентой больше нет. Ширина строки — дуга
    /// (`actionWidth`) и место под «↺» (40 + 8), не шире экрана без полей 16.
    private func flatActionRow(_ pal: Palette) -> some View {
        HStack(spacing: 8) {
            actionButton(pal, flat: true)
            NowResetButton(state: model.timebar, pal: pal)
        }
        .frame(width: min(Self.actionWidth(dome: domeSize.width) + 48, max(0, domeSize.width - 32)))
        .padding(.vertical, 3)
    }

    /// Кнопка шириной по дуге и подтянута к горизонту (схема А, 04.11). Дуга — 326 из 390 единиц купола,
    /// а купол мельче единицы только на экранах уже 390 (`DomeView`, «масштаб по меньшей стороне»).
    static func actionWidth(dome width: CGFloat) -> CGFloat { 326 * min(max(width, 1) / 390, 1) }
    /// Вид «Без блоков»: высота строки капсулы и «↺» (40 + поля 3 · 2) — на столько отступает низ прокрутки.
    static let actionReserve: CGFloat = 46
    static let viewportSpace = "lightViewport"
    static func actionVeil(_ scheme: ColorScheme) -> Color {
        // 28к.3: в светлой кнопка поднята — белая вуаль (светлее фона) и тень под ней (`raisedStyle`); в тёмной — как была.
        scheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(PlateTokens.glassVeil)
    }
}

/// Знак кнопки съёмки — календарь с плюсом из разметки веба (`#planToday
/// .ic`, свой SVG, не из `icons.js`): рамка 18×17 со скруглением 2,5, линия
/// шапки, два ушка и плюс. В библиотеке знаков такого нет, а `clock`, который
/// стоял здесь до 19б, — другой знак.
private struct PlanShootGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 3, y: 4.5, width: 18, height: 17), cornerSize: CGSize(width: 2.5, height: 2.5))
        for (a, b) in [((3.0, 9.5), (21.0, 9.5)), ((8.0, 2.5), (8.0, 6.5)), ((16.0, 2.5), (16.0, 6.5)),
                       ((12.0, 12.5), (12.0, 17.5)), ((9.5, 15.0), (14.5, 15.0))] {
            p.move(to: CGPoint(x: a.0, y: a.1)); p.addLine(to: CGPoint(x: b.0, y: b.1))
        }
        return p.applying(CGAffineTransform(scaleX: k, y: k)).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Одна строка телеметрии: подпись слева, значение справа, тонкая щель-разделитель
/// снизу (`ws:CLAUDE.md` «разделитель — это щель» — родственное правило для
/// прорезей плашек; здесь по месту достаточно обычного тонкого `Divider`,
/// щель как таковая — деталь других экранов).
struct TelemetryRow<Value: View>: View {
    let labelKey: String
    let labelText: (String) -> String
    @ViewBuilder let value: () -> Value
    @Environment(\.colorScheme) private var colorScheme

    /// `.t-row`: поля 9 · 8, волосок `--hair-2` снизу, 14 pt; подпись
    /// `--ink-4`, значение 14/500 с разрядкой 0,1. Строка 35 pt, как в вебе.
    var body: some View {
        let pal = Palette(colorScheme)
        HStack(spacing: 12) {
            Text(labelText(labelKey)).font(.system(size: 14))
                .foregroundStyle(pal.ink4)
            Spacer(minLength: 0)
            value().font(.system(size: 14, weight: .medium)).tracking(0.1)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 17)
        // 9 · 8 и волосок 1 снизу — он у веба в высоте строки (35, не 34).
        .padding(.top, 9).padding(.bottom, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(pal.hair2).frame(height: 1) }
    }
}

/// Экспонометр (деления) или звёздный знак — порт `meterHTML`/`starGlyph`.
private struct LightGaugeView: View {
    let gauge: LightTelemetry.Gauge
    let color: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch gauge {
        case .stars:
            // Веб заливает звезду сплошь (`fill, stroke: none`) — библиотека
            // знаков несёт только контурные пути (итерация 15), заливки без
            // контура в ней нет; веду то же начертание, что у остальных
            // строк телеметрии, а не завожу второй, закрашенный вариант ради
            // одного глифа.
            Icon("star", size: 15, line: 1.6).foregroundStyle(color)
        case .level(let level):
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    // `.meter i`: 3 pt, скругление 1, высоты 6…14 через 2.
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < level ? color : LightScreenTheme.meterOff(colorScheme))
                        .frame(width: 3, height: 6 + CGFloat(i) * 2)
                }
            }
        }
    }
}

/// Жест светила: на iOS распознаватель UIKit, на Mac — протяжка SwiftUI
/// (`DomeDragGesture`).
private struct DomeDragModifier: ViewModifier {
    let gesture: DomeDragGesture
    #if !os(iOS)
    @State private var axis = DomeDrag.Axis.pending
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content.gesture(gesture)
        #else
        content.gesture(gesture.gesture(axis: $axis))
        #endif
    }
}

/// 29.8в.27 — адаптация натива, веба тут нет. В вебе в закрытой части «Тени», «Небо» и «Ветер» всегда стоят (`#tShadow`, `#tSky`,
/// `#tWind`), а длинный экран прокручивается. Слова Алексея 21.10: экраны подстраиваются под измеренную высоту, не под модель
/// телефона (в коде моделей нет), и оптимизированы под новые iPhone. В «Астро» важный набор («Условия», «Закат», «Золотой час», «Свет»)
/// стоит всегда; «Тени», «Небо», «Ветер» — пока кнопка «Запланировать съёмку» помещается над нижней панелью с зазором 8 pt. Не хватает —
/// уходят «Ветер», потом «Небо», потом «Тени», потом полоса под дугой поднимается до 12 pt к горизонту (`plan`). Шапка «Астро» сжата
/// всегда (слово Алексея 21.10: «Астро» просит больше сведений): слева «Место ◁», дата, «сегодня», справа две строки погоды. Ушедшее лежит в раскрытом списке: «Ветер» и «Небо» — «Погода» (`pro.wind` с тем же текстом `windLine`,
/// `pro.sky`, облачность); у теней там только длина («Солнце сейчас»). Осадки и так в погодном виджете шапки. В «Просто» спойлера нет,
/// прятать некуда — три строки, шапка и полоса (22) прежние.
enum LightCollapsedList {
    enum Row: CaseIterable { case shadow, sky, wind }
    /// 30з.2 (слово Алексея 13.11: «парящая кнопка решила проблему места, пользователь сам прокрутит список и достанет информацию из-под
    /// кнопки»): укорочение закрытого списка «Астро» по высоте экрана выключено — оно существовало, чтобы кнопка «Запланировать съёмку»,
    /// стоявшая в потоке, помещалась над нижней панелью. Теперь кнопка парит, список показывает все строки режима на любой модели и
    /// уезжает под капсулу прокруткой; низ прокрутки отступает на капсулу (`actionReserve`), чтобы последнюю строку можно было вытянуть.
    /// Правила `plan` / `shown(fit:)` и их тесты целы: вернуть укорочение — `true`.
    static let shortensByHeight = true
    static let contentSpace = "lightContent"
    /// Строка телеметрии 35 pt (`TelemetryRow`), пока настоящая высота не измерена.
    static let defaultRowHeight: CGFloat = 35

    /// Строки, которые у экрана вообще есть: «Тени» всегда, «Небо» и «Ветер» — только с прогнозом.
    static func present(hasForecast: Bool) -> [Row] { hasForecast ? [.shadow, .sky, .wind] : [.shadow] }

    /// Какие необязательные строки стоят в закрытом списке. «Просто» — все; «Астро» — первые `fit` из имеющихся.
    static func shown(astro: Bool, fit: Int, hasForecast: Bool) -> Set<Row> {
        let all = present(hasForecast: hasForecast)
        return Set(astro ? Array(all.prefix(max(0, fit))) : all)
    }

    /// Полоса под дугой: сверх 22 pt можно поднять не больше чем на 12 (подпись остаётся в 12 pt от горизонта).
    static let maxExtraTuck: CGFloat = 12
    /// 30з.2: сколько pt купол можно поднять под шапку, когда ничего другого не осталось.
    static let maxDomeLift: CGFloat = 30
    /// Запас на округление: у `make lightfit` кнопка съёмки на 393 pt вышла на 1 pt под панель при расчёте «нужно 14» (замер 29.8в.27) —
    /// измеренные в содержимом рамки и раскладка расходятся на доли точки. Плана хватает на 1 pt больше.
    static let slack: CGFloat = 1

    /// Что стояло на экране в раскладке, где измерен низ «Подробно»: число необязательных строк и подъём полосы.
    struct Layout: Equatable {
        var rows = 0
        var extraTuck: CGFloat = 0
    }

    /// Низ «Подробно» (в координатах содержимого) вместе с раскладкой, при которой он измерен.
    struct Measurement: Equatable {
        var bottom: CGFloat
        var layout: Layout
    }

    struct Plan: Equatable {
        var rows: Int
        var extraTuck: CGFloat
    }

    /// Что отдать строкам и что пожертвовать, чтобы кнопка «Запланировать съёмку» стояла над панелью с зазором 8 pt (слова Алексея 21.10).
    /// `baselineBottom` — низ «Подробно» в базе: без необязательных строк, шапка «Астро» сжата, полоса 22; запас = высота прокрутки −
    /// (база + кнопка). Запас ≥ 0 — важный набор («Условия», «Закат», «Золотой час», «Свет») помещается, всё свободное отдаётся строкам по
    /// очереди «Тени» → «Небо» → «Ветер» (первым уходит «Ветер»). Нехватка — строк нет, полоса под дугой поднимается до 12 pt к горизонту.
    /// Считается от базы, поэтому решение не зависит от того, что на экране.
    static func plan(visibleHeight: CGFloat, baselineBottom: CGFloat, actionHeight: CGFloat, rowHeights: [CGFloat]) -> Plan {
        var spare = visibleHeight - (baselineBottom + actionHeight) - slack
        if spare < 0 { return Plan(rows: 0, extraTuck: min(maxExtraTuck, -spare)) }
        var count = 0
        for h in rowHeights {
            guard spare >= h else { break }
            spare -= h
            count += 1
        }
        return Plan(rows: count, extraTuck: 0)
    }
}

/// Где в покое нижняя кромка плашки «условия» (30з.2).
@Observable
final class PlateProbe {
    @ObservationIgnored var atRest = true
    /// Нижняя кромка плашки в координатах экрана (`viewportSpace`) и в координатах содержимого (последние измерения).
    @ObservationIgnored var vp: CGFloat = .infinity
    @ObservationIgnored var contentMax: CGFloat = .infinity
    /// Где на экране стоит начало содержимого в покое (разность двух систем координат).
    @ObservationIgnored var contentTop: CGFloat = .infinity

    func refresh() {
        guard atRest, vp.isFinite, contentMax.isFinite else { return }
        contentTop = vp - contentMax
    }
}
