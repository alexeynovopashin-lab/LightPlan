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

    public init(_ model: LightScreenModel) {
        self.model = model
    }

    public var body: some View {
        let telemetry = model.telemetry

        ScrollView {
            VStack(spacing: 0) {
                header(telemetry.header)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                domeAndReadout(telemetry)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)

                TimebarView(model.timebar)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                nextLight(telemetry)
                    .padding(.horizontal, 16)
                    .padding(.top, 22)

                telemetryList(telemetry)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)

                LightSpoilerView(groups: telemetry.proGroups, open: model.proMode, title: model.lexiconWord("today.details"))
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                actionButton(subtitle: telemetry.actionSubtitle)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
            }
        }
        .background(.black.opacity(0.92))
        .preferredColorScheme(.dark)
    }

    // MARK: - Шапка

    private func header(_ h: LightTelemetry.Header) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(h.locationName).font(.system(size: 19, weight: .semibold))
                    Icon("pin", size: 14, line: 1.8).foregroundStyle(LightScreenTheme.ink4(colorScheme))
                }
                Text(h.dateLabel).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LightScreenTheme.ink4(colorScheme))
                Text(h.note).font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(LightScreenTheme.ink4(colorScheme))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Icon(h.weatherIconName, size: 16, line: 1.6)
                    Text(h.temperature).font(.system(size: 19, weight: .semibold))
                }
                Text(h.condition).font(.system(size: 11, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(LightScreenTheme.ink4(colorScheme))
                HStack(spacing: 10) {
                    Text(h.low)
                    Text(h.high)
                }
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(LightScreenTheme.ink4(colorScheme))
            }
        }
    }

    // MARK: - Купол и показание

    private func domeAndReadout(_ t: LightTelemetry) -> some View {
        ZStack(alignment: .bottomTrailing) {
            DomeView(sun: model.timebar.solarDay, place: model.timebar.place,
                      date: model.timebar.machine.selectedDate, t: model.timebar.machine.viewMinute,
                      nowMinute: model.timebar.nowMinute, mode: moonModeBinding)
            if let readout = t.readout {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(readout.time).font(.system(size: 15, weight: .semibold).monospacedDigit())
                    Text(readout.phase).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LightScreenTheme.toneColor(t.tone, state: t.stateColor, scheme: colorScheme))
                    Text(readout.sense).font(.system(size: 12))
                        .foregroundStyle(LightScreenTheme.ink4(colorScheme))
                }
                .multilineTextAlignment(.trailing)
                .padding(.trailing, 44)
                .padding(.bottom, 8)
            }
        }
    }

    private var moonModeBinding: Binding<DomeSkyMode> {
        Binding(get: { model.moonMode ? .moon : .sun }, set: { model.moonMode = $0 == .moon })
    }

    // MARK: - «Что дальше»

    private func nextLight(_ t: LightTelemetry) -> some View {
        let nl = t.next
        return VStack(alignment: .leading, spacing: 5) {
            Text(nl.label).font(.system(size: 11, weight: .semibold)).textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(LightScreenTheme.ink4(colorScheme))
            Text(nl.value).font(.system(size: 26, weight: .semibold).monospacedDigit())
                .foregroundStyle(LightScreenTheme.toneColor(t.tone, state: t.stateColor, scheme: colorScheme))
            HStack(spacing: 8) {
                SparklineShape(values: nl.trend)
                    .stroke(LightScreenTheme.ink4(colorScheme), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 42, height: 14)
                Text(nl.trendWord).font(.system(size: 12))
            }
            .foregroundStyle(LightScreenTheme.ink4(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Телеметрия

    private func telemetryList(_ t: LightTelemetry) -> some View {
        let toneColor = LightScreenTheme.toneColor(t.tone, state: t.stateColor, scheme: colorScheme)
        return VStack(spacing: 0) {
            TelemetryRow(labelKey: "tele.cond", labelText: model.lexiconWord) {
                HStack(spacing: 9) {
                    LightGaugeView(gauge: t.condition.gauge, color: toneColor)
                    Text(t.condition.text)
                }
                .foregroundStyle(toneColor)
                .fontWeight(.semibold)
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
        }
    }

    private func rowWithIcon(labelKey: String, iconName: String, value: String) -> some View {
        TelemetryRow(labelKey: labelKey, labelText: model.lexiconWord) {
            HStack(spacing: 8) {
                Icon(iconName, size: 16, line: 1.5)
                Text(value)
            }
            .foregroundStyle(LightScreenTheme.ink(colorScheme))
        }
    }


    // MARK: - Кнопка съёмки

    private func actionButton(subtitle: String) -> some View {
        // Планировщик (итерация 13+) ещё не подключён — кнопка стоит на
        // месте, как в вебе, но пока без перехода: заглушка, а не притворство,
        // что действие уже есть (инвариант 13, план прямо запрещает трогать
        // планировщик в этой итерации).
        Button(action: {}) {
            HStack {
                Icon("clock", size: 18, line: 1.6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.lexiconWord("today.planShoot")).font(.system(size: 15, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(LightScreenTheme.ink4(colorScheme))
                }
                Spacer()
            }
            .padding(14)
            .background(LightScreenTheme.ink(colorScheme).opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .foregroundStyle(LightScreenTheme.ink(colorScheme))
    }
}

/// Одна строка телеметрии: подпись слева, значение справа, тонкая щель-разделитель
/// снизу (`ws:CLAUDE.md` «разделитель — это щель» — родственное правило для
/// прорезей плашек; здесь по месту достаточно обычного тонкого `Divider`,
/// щель как таковая — деталь других экранов).
private struct TelemetryRow<Value: View>: View {
    let labelKey: String
    let labelText: (String) -> String
    @ViewBuilder let value: () -> Value
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            Text(labelText(labelKey)).font(.system(size: 14))
                .foregroundStyle(LightScreenTheme.ink4(colorScheme))
            Spacer()
            value().font(.system(size: 14, weight: .medium))
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
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
                    Capsule()
                        .fill(i < level ? color : LightScreenTheme.meterOff(colorScheme))
                        .frame(width: 3, height: 6 + CGFloat(i) * 2)
                }
            }
        }
    }
}
