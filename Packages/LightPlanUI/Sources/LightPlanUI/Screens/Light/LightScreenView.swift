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
    @Environment(\.colorScheme) private var colorScheme
    /// Видимая высота прокрутки — чтобы кнопка съёмки легла к низу, как
    /// `.screen-action { margin-top: auto }` веба.
    @State private var visibleHeight: CGFloat = 0
    /// Рамка купола и показаний в ней — светило пальцем (19в).
    @State private var domeSize = CGSize(width: 0, height: DomeView.height)
    @State private var readoutFrame = CGRect.null

    public init(_ model: LightScreenModel) {
        self.model = model
    }

    /// Вёрстка — числа `#s-today` беты (вычисленные стили, снимок пары 19б):
    /// поля экрана 24, шапка 24 от выреза, купол во всю ширину высотой 240,
    /// «что дальше» 72, строки телеметрии по 35, кнопка съёмки у низа,
    /// таймбар прибит над вкладками. До 19б это был стенд: поля 16, таймбар
    /// посреди прокрутки, свой набор кеглей.
    public var body: some View {
        let telemetry = model.telemetry
        let pal = Palette(colorScheme)

        ScrollView {
            VStack(spacing: 0) {
                header(telemetry.header, pal)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                dome(telemetry, pal)

                nextLight(telemetry, pal)
                    .padding(.horizontal, 24)
                    .padding(.top, 2)
                    .frame(height: 72, alignment: .top)

                telemetryList(telemetry, pal)
                    .padding(.horizontal, 24)

                LightSpoilerView(groups: telemetry.proGroups, open: model.proMode, title: model.lexiconWord("today.details"))
                    .padding(.horizontal, 24)

                // `.screen-action { margin-top: auto }`: в «Просто» кнопка
                // ложится к низу, в «Астро» содержимое длиннее экрана и
                // зазора нет вовсе.
                Spacer(minLength: 0)

                actionButton(subtitle: telemetry.actionSubtitle, pal)
                    .padding(.horizontal, 24)
            }
            .frame(minHeight: visibleHeight, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0 }
        .safeAreaInset(edge: .bottom, spacing: 8) {
            TimebarView(model.timebar, showRibbon: model.proMode)
                .shotNode("timebar")
        }
        .background(pal.surface)
    }

    // MARK: - Шапка

    /// `.header`: слева место (16/600), область (11), дата (11/500
    /// прописными, разрядка 0,6), «сегодня» (11/500, `--ink-6`); справа
    /// погода — знак 22 и 24/600, состояние 14 (`--ink-2`), ↓↑ 13 (`--ink-4`).
    private func header(_ h: LightTelemetry.Header, _ pal: Palette) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(h.locationName)
                        .font(.system(size: 16, weight: .semibold)).tracking(-0.2)
                        .foregroundStyle(pal.ink)
                        .shotNode("header.name", text: h.locationName)
                        .frame(height: 18)
                    Icon("pin", size: 13, line: 1.6).foregroundStyle(pal.ink6)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                }
                if !model.locationSub.isEmpty {
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
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                // Знак и градусы: 22 + поле 8 (`.wx` у знака) + зазор 7 = 15
                // между ними; знак на 1,5 выше середины строки, как у веба.
                HStack(spacing: 15) {
                    Icon(h.weatherIconName, size: 22, line: 1.5)
                        .foregroundStyle(pal.ink)
                        .shotNode("wx.icon")
                        .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] + 1.5 }
                    Text(h.temperature)
                        .font(.system(size: 24, weight: .semibold).monospacedDigit()).tracking(-0.5)
                        .foregroundStyle(pal.ink)
                        .shotNode("wx.temp", text: h.temperature)
                }
                Text(h.condition)
                    .font(.system(size: 14))
                    .foregroundStyle(pal.ink2)
                    .shotNode("wx.cond", text: h.condition)
                HStack(spacing: 10) {
                    Text(h.low).shotNode("wx.lo", text: h.low)
                    Text(h.high).shotNode("wx.hi", text: h.high)
                }
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(pal.ink4)
            }
        }
    }

    // MARK: - Купол и показание

    private func dome(_ t: LightTelemetry, _ pal: Palette) -> some View {
        DomeView(sun: model.timebar.solarDay, place: model.timebar.place,
                 date: model.timebar.machine.selectedDate, t: model.timebar.machine.viewMinute,
                 nowMinute: model.timebar.nowMinute, mode: moonModeBinding)
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
        VStack(spacing: 0) {
            Text(r.time)
                .font(.system(size: 46, weight: .thin).monospacedDigit()).tracking(-0.5)
                .foregroundStyle(pal.ink)
                .shotNode("readout.time", text: r.time)
                .frame(height: 46)
            Text(r.phase)
                .font(.system(size: 11, weight: .semibold)).tracking(1.4).textCase(.uppercase)
                .foregroundStyle(pal.dark ? Color(t.stateColor) : pal.ink3)
                .shotNode("readout.phase", text: r.phase)
                .frame(height: 13)
                .padding(.top, 7)
            Text(r.sense)
                .font(.system(size: 12))
                .foregroundStyle(pal.ink4)
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
            HStack(spacing: 8) {
                SparklineShape(values: nl.trend)
                    .stroke(pal.ink4, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 42, height: 14)
                    .shotNode("next.spark")
                Text(nl.trendWord).font(.system(size: 12))
                    .shotNode("next.word", text: nl.trendWord)
            }
            .foregroundStyle(pal.ink4)
            .padding(.top, 5)
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
            plainRow(labelKey: "tele.shadow", value: t.shadow)
            rowWithIcon(labelKey: "tele.sky", iconName: t.sky.iconName, value: t.sky.text)
            plainRow(labelKey: "tele.wind", value: t.wind)
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
    /// ширины). Кнопка ещё без перехода — планировщика нет (инвариант 13).
    private func actionButton(subtitle: String, _ pal: Palette) -> some View {
        Button(action: {}) {
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
