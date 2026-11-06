import SwiftUI
import LightPlanData

/// Пять переключателей неба сразу под выбором режима, только в «Астро» (30г.4; рисунок `docs/30g2_prostoe_sketch.png`,
/// колонка «Астро»). Работают все пять: «Термины» (30г.4), «Азимуты» (30г.5), «Луна» (30г.6), «Звёзды» и «Млечный Путь» (30г.7).
/// Строки под ними нет, как на рисунке: за последней строкой сразу главы.
struct AstroSwitchRows: View {
    let app: AppModel
    @Environment(\.colorScheme) private var colorScheme

    /// Переключатели, у которых уже есть работа: с 30г.7 все пять.
    static let working: Set<AstroSwitch> = [.moon, .stars, .azimuths, .terms, .milkyWay]

    var body: some View {
        let t = app.lexicon, pal = Palette(colorScheme)
        VStack(spacing: 0) {
            ForEach(AstroSwitch.allCases, id: \.self) { sw in
                let on = app.settings.astro[sw]
                HStack(spacing: 12) {
                    Text(t.t("set.astro." + sw.rawValue)).font(.system(size: 15)).foregroundStyle(pal.ink)
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(get: { app.settings.astro[sw] },
                                             set: { v in app.update { $0.astro[sw] = v } }))
                        .labelsHidden().tint(pal.brass)
                        .frame(height: 31)
                        .disabled(!Self.working.contains(sw))
                        .shotNode("astro." + sw.rawValue + ".toggle", text: on ? "on" : "off")
                }
                // `.item` веба с переключателем: поля 15 · 24, переключатель 31 и волосок 1 снизу — 62, как «Названия улиц».
                .padding(.horizontal, 24)
                .padding(.top, 15)
                .padding(.bottom, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(pal.hair2).frame(height: 1) }
                .shotNode("astro." + sw.rawValue)
            }
        }
        .padding(.top, 2)
        .shotNode("astro")
    }
}
