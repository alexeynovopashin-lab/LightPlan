import SwiftUI

/// Слой неба в AR, который включается руками (шаг 29.8в.9б). Одна круглая кнопка «Слои» открывает список: по
/// строке на каждый слой, который уже есть, у каждого свой значок и переключатель. Слой, которого ещё нет (звёзды,
/// созвездия, планеты), строки не имеет: следующий шаг добавляет случай сюда и строку в `SunARModel`.
enum SunARSkyLayer: String, CaseIterable, Identifiable {
    case moon
    case milkyWay

    var id: String { rawValue }

    /// Слово слоя — то же, что у веба (`layer.moon`, `layer.mw`).
    var labelKey: String {
        switch self {
        case .moon: return "layer.moon"
        case .milkyWay: return "layer.mw"
        }
    }

    /// Тон слоя: точка на кнопке «Слои» и тон переключателя.
    var tint: Color {
        switch self {
        case .moon: return SunARInk.moonTint
        case .milkyWay: return SunARInk.milkyWayTone
        }
    }

    /// Имя узла строки в отчёте снимков.
    var node: String {
        switch self {
        case .moon: return "ar.layer.moon"
        case .milkyWay: return "ar.layer.mw"
        }
    }
}

extension SunARModel {
    func isOn(_ layer: SunARSkyLayer) -> Bool {
        switch layer {
        case .moon: return moonOn
        case .milkyWay: return milkyWayOn
        }
    }

    /// Те же флаги устройства, что и раньше (`lightplan.native.sunar.moon` / `.milkyWay`), через `setMoon`/`setMilkyWay`.
    func set(_ layer: SunARSkyLayer, on: Bool) {
        switch layer {
        case .moon: setMoon(on)
        case .milkyWay: setMilkyWay(on)
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

    var body: some View {
        VStack(spacing: 0) {
            ForEach(SunARSkyLayer.allCases) { layer in
                row(layer)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(width: 284)
        .preferredColorScheme(.dark)
    }

    private func row(_ layer: SunARSkyLayer) -> some View {
        let label = lexicon.t(layer.labelKey)
        let on = model.isOn(layer)
        return HStack(spacing: 12) {
            icon(layer).frame(width: 28, height: 28)
            Text(label).font(.system(size: 16)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Toggle(label, isOn: Binding(get: { on }, set: { model.set(layer, on: $0) }))
                .labelsHidden()
                .tint(layer.tint)
        }
        .frame(minHeight: SunARInk.touch)
        .shotNode(layer.node, text: label + (on ? " on" : " off"))
    }

    @ViewBuilder private func icon(_ layer: SunARSkyLayer) -> some View {
        switch layer {
        case .moon:
            let m = model.moonPicked.phase
            MoonToggleIcon(illuminated: m.fraction, waxing: m.cycle < 0.5)
        case .milkyWay:
            MilkyWayToggleIcon()
        }
    }
}
