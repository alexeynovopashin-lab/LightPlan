import SwiftUI

/// Слой неба в AR, который включается руками (шаг 29.8в.9б). Одна круглая кнопка «Слои» открывает список: по
/// строке на каждый слой, который уже есть, у каждого свой значок и переключатель. Новый слой добавляет случай сюда и строку в `SunARModel`.
enum SunARSkyLayer: String, CaseIterable, Identifiable {
    case moon
    case milkyWay
    case stars
    case constellations
    case planets

    var id: String { rawValue }

    /// Слово слоя — то же, что у веба (`layer.moon`, `layer.mw`).
    var labelKey: String {
        switch self {
        case .moon: return "layer.moon"
        case .milkyWay: return "layer.mw"
        case .stars: return "layer.stars"
        case .constellations: return "layer.constellations"
        case .planets: return "layer.planets"
        }
    }

    /// Тон слоя: точка на кнопке «Слои» и тон переключателя.
    var tint: Color {
        switch self {
        case .moon: return SunARInk.moonTint
        case .milkyWay: return SunARInk.milkyWayTone
        case .stars: return SunARInk.starTone
        case .constellations: return SunARInk.constellationTone
        case .planets: return SunARInk.planetTone
        }
    }

    /// Имя узла строки в отчёте снимков.
    var node: String {
        switch self {
        case .moon: return "ar.layer.moon"
        case .milkyWay: return "ar.layer.mw"
        case .stars: return "ar.layer.stars"
        case .constellations: return "ar.layer.constellations"
        case .planets: return "ar.layer.planets"
        }
    }
}

extension SunARModel {
    func isOn(_ layer: SunARSkyLayer) -> Bool {
        switch layer {
        case .moon: return moonOn
        case .milkyWay: return milkyWayOn
        case .stars: return starsOn
        case .constellations: return constellationsOn
        case .planets: return planetsOn
        }
    }

    /// Флаги устройства: `lightplan.native.sunar.moon` / `.milkyWay` / `.stars` / `.constellations`, через `setMoon` и далее.
    func set(_ layer: SunARSkyLayer, on: Bool) {
        switch layer {
        case .moon: setMoon(on)
        case .milkyWay: setMilkyWay(on)
        case .stars: setStars(on)
        case .constellations: setConstellations(on)
        case .planets: setPlanets(on)
        }
    }

    /// Включённые слои, в порядке списка.
    var layersOn: [SunARSkyLayer] { SunARSkyLayer.allCases.filter { isOn($0) } }
}

/// Круглая кнопка «Слои»; знак тот же, что у кнопки слоёв «Карты» (`LayersGlyph`, свой SVG веба). По виду видно, какие слои включены: под значком точка тоном каждого включённого слоя;
/// когда включённых нет — значок без точек. Размер не меняется: касание 44 pt.
struct SunARLayersButtonLabel: View {
    let on: [SunARSkyLayer]

    var body: some View {
        ZStack {
            LayersGlyph()
                .stroke(SunARInk.buttonInk, style: StrokeStyle(lineWidth: 1.8 * 22 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 22, height: 22)
                .arInkShadow()
            HStack(spacing: 3) {
                ForEach(on) { layer in
                    Circle().fill(layer.tint).frame(width: 5, height: 5)
                        .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
                }
            }
            .offset(y: 15.5)
        }
        .frame(width: SunARInk.touch, height: SunARInk.touch)
        .contentShape(Circle())
    }
}

/// Список слоёв в поповере: на системном стекле, по строке на слой. Тёмная схема: значки рисуются светлыми
/// (как на экране AR), а поповер iOS 26 сам стеклянный.
struct SunARLayersList: View {
    let model: SunARModel
    let lexicon: Lexicon
    /// Часы места: время в строках Млечного Пути пишется так же, как на подписях дуги.
    var clock = ClockText(language: "ru")

    var body: some View {
        VStack(spacing: 0) {
            ForEach(SunARSkyLayer.allCases) { layer in
                row(layer)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(width: 320)
        .preferredColorScheme(.dark)
    }

    /// Мелкие строки под словом слоя.
    private func notes(_ layer: SunARSkyLayer) -> [String] {
        switch layer {
        case .moon, .stars, .constellations: return []
        case .planets:
            // Планеты (29.8в.15): днём их нет; ночью каждая, что ближе 15° к Солнцу, подписана честно.
            let status = model.planetStatus
            if status.daylight { return [lexicon.t("ar.planetsDay")] }
            return status.nearSun.map { lexicon.t("ar.planetNearSun", ["name": lexicon.t($0.nameKey)]) }
        case .milkyWay:
            // Млечный Путь (29.8в.17б): ядро над горизонтом и темнота, справка о видимости глазом (не условие
            // рисования), окно съёмки и подпись про формулу.
            return SunARMilkyWayNotes.lines(plan: model.milkyWayPlan, eye: model.milkyWayEyeNote, clock: clock, lexicon: lexicon)
        }
    }

    private func row(_ layer: SunARSkyLayer) -> some View {
        let label = lexicon.t(layer.labelKey)
        let on = model.isOn(layer)
        let small = notes(layer)
        return HStack(spacing: 12) {
            icon(layer).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: small.isEmpty ? 1 : 3) {
                Text(label).font(.system(size: 16)).lineLimit(1).minimumScaleFactor(0.8)
                ForEach(small, id: \.self) { note in
                    // Без обрезки: строки Млечного Пути длинные («ядро над горизонтом 6:11 – 10:54 PM · dark from …»),
                    // многоточие съедало самое нужное — время (29.8в.17б).
                    Text(note).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle(label, isOn: Binding(get: { on }, set: { model.set(layer, on: $0) }))
                .labelsHidden()
                .tint(layer.tint)
        }
        .frame(minHeight: SunARInk.touch)
        .padding(.vertical, small.isEmpty ? 0 : 4)
        .shotNode(layer.node, text: ([label] + small).joined(separator: " | ") + (on ? " on" : " off"))
    }

    @ViewBuilder private func icon(_ layer: SunARSkyLayer) -> some View {
        switch layer {
        case .moon:
            let m = model.moonPicked.phase
            MoonToggleIcon(illuminated: m.fraction, waxing: m.cycle < 0.5)
        case .milkyWay:
            MilkyWayToggleIcon()
        case .stars:
            StarsToggleIcon()
        case .constellations:
            ConstellationsToggleIcon()
        case .planets:
            PlanetsToggleIcon()
        }
    }
}
