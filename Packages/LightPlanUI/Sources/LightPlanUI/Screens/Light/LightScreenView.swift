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
    /// Рамка купола и показаний в ней — светило пальцем (19в).
    @State private var domeSize = CGSize(width: 0, height: DomeView.height)
    @State private var readoutFrame = CGRect.null
    /// 29.8в.27: сколько необязательных строк («Тени», «Небо», «Ветер») поместилось в закрытый список «Астро» (`LightCollapsedList`).
    @State private var fitRows = 0
    /// Шапка «Астро» сжата до двух строк слева (только если без этого не помещается важный набор) и на сколько pt (0…12) поднята полоса
    /// под дугой сверх 22. Всё это выбирает `LightCollapsedList.plan` по измеренной высоте; «Просто» не затрагивается.
    @State private var headerCompact = false
    @State private var extraTuck: CGFloat = 0
    @State private var rowHeights: [LightCollapsedList.Row: CGFloat] = [:]
    /// Низ кнопки «Подробно» в координатах содержимого прокрутки и высота кнопки съёмки — по ним считается запас высоты.
    @State private var spoilerBottom: CGFloat = 0
    /// Сколько необязательных строк стояло в закрытом списке, когда измерен `spoilerBottom` (из той же отрисовки): по нему из
    /// низа кнопки вычитается высота стоявших строк — иначе измерение и число строк расходились на проход раскладки.
    @State private var spoilerRows = 0
    @State private var spoilerCompact = false
    @State private var spoilerExtraTuck: CGFloat = 0
    @State private var actionHeight: CGFloat = 0

    public init(_ model: LightScreenModel, onPlace: @escaping () -> Void = {},
                onPlan: @escaping (CivilDate, Int) -> Void = { _, _ in }) {
        self.model = model
        self.onPlace = onPlace
        self.onPlan = onPlan
    }

    /// Вёрстка — числа `#s-today` беты (вычисленные стили, снимок пары 19б):
    /// поля экрана 24, шапка сразу под безопасной зоной (29.2г: у веба там +24 от размытия часов iOS 27, у натива его нет), купол во всю ширину высотой 240,
    /// «что дальше» 72, строки телеметрии по 35, кнопка съёмки у низа,
    /// таймбар прибит над вкладками. До 19б это был стенд: поля 16, таймбар
    /// посреди прокрутки, свой набор кеглей.
    public var body: some View {
        let telemetry = model.telemetry
        let pal = Palette(colorScheme)
        let tuckNow = model.proMode ? extraTuck : 0
        let layoutNow = LightCollapsedList.Layout(
            rows: LightCollapsedList.shown(astro: model.proMode, fit: fitRows, hasForecast: telemetry.sky != nil || telemetry.wind != nil).count,
            compact: model.proMode && headerCompact, extraTuck: tuckNow)

        ScrollView {
            VStack(spacing: 0) {
                header(telemetry.header, note: telemetry.forecastNote, pal)
                    .padding(.horizontal, 24)

                // Всё под шапкой проявляется при смене вкладки (S1); шапка не мигает.
                Group {
                    dome(telemetry, pal)
                        .padding(.bottom, -Self.domeTuck(extra: tuckNow))

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

                    // `.screen-action { margin-top: auto }`: в «Просто» кнопка
                    // ложится к низу, в «Астро» содержимое длиннее экрана и
                    // зазора нет вовсе.
                    Spacer(minLength: 0)

                    actionButton(subtitle: telemetry.actionSubtitle, pal)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionHeight = $0; refreshCollapsedRows() }
                        .padding(.horizontal, 24)
                }
                .tabRise()
            }
            .frame(minHeight: visibleHeight, alignment: .top)
            .coordinateSpace(.named(LightCollapsedList.contentSpace))
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0; refreshCollapsedRows() }
        .onChange(of: model.proMode) { _, pro in
            // В «Просто» спойлера нет и ничего не прячется; в «Астро» число строк решит новое измерение.
            if !pro { fitRows = 0; headerCompact = false; extraTuck = 0; spoilerBottom = 0 }
        }
        // Прогноз приходит позже первой раскладки: у «Неба» и «Ветра» появляется строка, а кнопка «Подробно» не сдвинулась — пересчитать.
        .onChange(of: model.telemetry.sky != nil || model.telemetry.wind != nil) { _, _ in refreshCollapsedRows() }
        // Место и погода тоже приходят позже: от них зависит, сколько pt даёт сжатая шапка (`headerGain`).
        .onChange(of: model.locationSub.isEmpty) { _, _ in refreshCollapsedRows() }
        .onChange(of: model.telemetry.header.weather != nil) { _, _ in refreshCollapsedRows() }
        .safeAreaInset(edge: .bottom, spacing: 8) {
            TimebarView(model.timebar, showRibbon: model.proMode)
                .shotNode("timebar")
                .tabRise()
        }
        .background(pal.surface)
    }

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
                if !model.locationSub.isEmpty && !(model.proMode && headerCompact) {
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
                    if model.proMode && headerCompact {
                        // «Астро», только когда без этого не помещается важный набор (29.8в.27): состояние и ↓↑ в одной строке — две строки погоды вместо трёх.
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

    private func dome(_ t: LightTelemetry, _ pal: Palette) -> some View {
        DomeView(sun: model.timebar.solarDay, place: model.timebar.place,
                 date: model.timebar.machine.selectedDate, t: model.timebar.machine.viewMinute,
                 nowMinute: model.timebar.nowMinute,
                 skyPalette: SkyPalette(weather: model.weather.day(for: model.timebar.machine.selectedDate)),
                 astro: model.proMode,
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
            .coordinateSpace(.named(Self.domeSpace))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { domeSize = $0 }
            .contentShape(Rectangle())
            .modifier(DomeDragModifier(gesture: DomeDragGesture(
                accepts: { domeAccepts($0) },
                onMove: { model.dragDome(at: $0, in: domeSize) })))
    }

    private static let domeSpace = "dome"

    /// Низ кнопки измерен вместе с тем, что стояло на экране в этой раскладке.
    private func measureSpoiler(_ m: LightCollapsedList.Measurement) {
        spoilerBottom = m.bottom
        spoilerRows = m.layout.rows
        spoilerCompact = m.layout.compact
        spoilerExtraTuck = m.layout.extraTuck
        refreshCollapsedRows()
    }

    /// 29.8в.27: пересчёт числа строк закрытого списка «Астро» по свежим измерениям.

    private func refreshCollapsedRows() {
        guard model.proMode, spoilerBottom > 0, visibleHeight > 0, actionHeight > 0 else { return }
        let hasForecast = model.telemetry.sky != nil || model.telemetry.wind != nil
        let present = LightCollapsedList.present(hasForecast: hasForecast)
        let heights = present.map { rowHeights[$0] ?? LightCollapsedList.defaultRowHeight }
        let gain = LightCollapsedList.headerGain(hasPlaceSub: !model.locationSub.isEmpty, hasWeather: model.telemetry.header.weather != nil)
        // Низ «Подробно» приводится к базе: без необязательных строк, шапка в четыре строки, полоса 22 — как была бы раскладка,
        // не зная, какая из них сейчас на экране (иначе решение мигало бы).
        let baseline = spoilerBottom - heights.prefix(spoilerRows).reduce(CGFloat(0), +)
            + (spoilerCompact ? gain : 0) + spoilerExtraTuck
        let plan = LightCollapsedList.plan(visibleHeight: visibleHeight, baselineBottom: baseline, actionHeight: actionHeight,
                                           rowHeights: heights, headerGain: gain)
        if plan.rows != fitRows { fitRows = plan.rows }
        if plan.compactHeader != headerCompact { headerCompact = plan.compactHeader }
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
        let sky = DomeSky(astro: model.proMode, elevation: sun.elevation(at: minute), morning: minute < sun.solarNoon,
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
                .font(.system(size: 30, weight: .light).monospacedDigit()).tracking(-0.5)
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
            let shown = LightCollapsedList.shown(astro: model.proMode, fit: fitRows, hasForecast: t.sky != nil || t.wind != nil)
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

    /// `.action`: волосок `--hair-4` сверху, поля 13 · 0 · 2; знак 22
    /// латунью, подпись 16/600, справа окно 13 (`--ink-4`, цифры одной
    /// ширины). Тап — форма новой съёмки на выбранный день с началом по свету
    /// (`planShoot`, веб `#planToday`).
    private func actionButton(subtitle: String, _ pal: Palette) -> some View {
        Button(action: { let r = model.planShoot; onPlan(r.day, r.start) }) {
            HStack(spacing: 13) {
                PlanShootGlyph()
                    .stroke(pal.brass, style: StrokeStyle(lineWidth: 1.6 * 22 / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: 22, height: 22)
                Text(model.lexiconWord("today.planShoot"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(pal.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(subtitle)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(pal.ink4)
                    .lineLimit(1)
                    .shotNode("action.sub", text: subtitle)
            }
            // Волосок 1 + поле 13 сверху, как `border-top` и `padding-top` веба.
            .padding(.top, 14).padding(.bottom, 2)
            .overlay(alignment: .top) { Rectangle().fill(pal.hair4).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("action")
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
/// уходят «Ветер», потом «Небо», потом «Тени», потом сжимается шапка (две строки слева), потом полоса под дугой поднимается до 12 pt
/// к горизонту (`plan`). Ушедшее лежит в раскрытом списке: «Ветер» и «Небо» — «Погода» (`pro.wind` с тем же текстом `windLine`,
/// `pro.sky`, облачность); у теней там только длина («Солнце сейчас»). Осадки и так в погодном виджете шапки. В «Просто» спойлера нет,
/// прятать некуда — три строки, шапка и полоса (22) прежние.
enum LightCollapsedList {
    enum Row: CaseIterable { case shadow, sky, wind }
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

    /// Шапка «Астро» в две строки слева и две справа вместо четырёх и трёх: 66 → 52 pt (замер 29.8в.27: `make lightfit`, 124,5 → 110,5).
    /// Выигрыш есть, пока есть что убирать: строка «область» слева (66 → 52) или третья строка погоды справа (65,5 → 47,5, при
    /// трёх строках слева 51,5 высоту держит правая). Нет ни места, ни погоды — шапка и так в три строки, выигрыша нет.
    static func headerGain(hasPlaceSub: Bool, hasWeather: Bool) -> CGFloat { hasPlaceSub || hasWeather ? 14 : 0 }
    /// Полоса под дугой: сверх 22 pt можно поднять не больше чем на 12 (подпись остаётся в 12 pt от горизонта).
    static let maxExtraTuck: CGFloat = 12
    /// Запас на округление: у `make lightfit` кнопка съёмки на 393 pt вышла на 1 pt под панель при расчёте «нужно 14» (замер 29.8в.27) —
    /// измеренные в содержимом рамки и раскладка расходятся на доли точки. Плана хватает на 1 pt больше.
    static let slack: CGFloat = 1

    /// Что стояло на экране в раскладке, где измерен низ «Подробно»: число необязательных строк, сжатая ли шапка, подъём полосы.
    struct Layout: Equatable {
        var rows = 0
        var compact = false
        var extraTuck: CGFloat = 0
    }

    /// Низ «Подробно» (в координатах содержимого) вместе с раскладкой, при которой он измерен.
    struct Measurement: Equatable {
        var bottom: CGFloat
        var layout: Layout
    }

    struct Plan: Equatable {
        var rows: Int
        var compactHeader: Bool
        var extraTuck: CGFloat
    }

    /// Что жертвовать, чтобы кнопка «Запланировать съёмку» стояла над панелью с зазором 8 pt (слова Алексея 21.10). `baselineBottom` —
    /// низ «Подробно» в базе: без необязательных строк, шапка в четыре строки, полоса 22; запас = высота прокрутки − (база + кнопка).
    /// Порядок: запас ≥ 0 — важный набор («Условия», «Закат», «Золотой час», «Свет») помещается как есть, остаток отдаётся строкам по
    /// очереди «Тени» → «Небо» → «Ветер» (первым уходит «Ветер»); иначе сначала сжимается шапка, потом поднимается полоса под дугой до
    /// 12 pt к горизонту. Пока нехватка не покрыта, строк нет вовсе. Считается от базы, поэтому решение не зависит от того, что на экране.
    static func plan(visibleHeight: CGFloat, baselineBottom: CGFloat, actionHeight: CGFloat, rowHeights: [CGFloat], headerGain: CGFloat = 14) -> Plan {
        var spare = visibleHeight - (baselineBottom + actionHeight) - slack
        if spare < 0 {
            let need = -spare
            if need <= headerGain { return Plan(rows: 0, compactHeader: true, extraTuck: 0) }
            return Plan(rows: 0, compactHeader: headerGain > 0, extraTuck: min(maxExtraTuck, need - headerGain))
        }
        var count = 0
        for h in rowHeights {
            guard spare >= h else { break }
            spare -= h
            count += 1
        }
        return Plan(rows: count, compactHeader: false, extraTuck: 0)
    }
}
