import SwiftUI
import LightPlanDomain

/// Кнопка мессенджера (шаг К4, справка `docs/clients_reference.md` § 7.1): нажатие открывает основной способ, долгое
/// нажатие — меню всех способов (позвонить, SMS, каждый мессенджер; у пары и семьи — по людям). Знаков сервисов в
/// библиотеке нет (`tools/icons.html`), рисовать чужие логотипы не стали: знак — нейтральное облачко `chat`, а какой
/// мессенджер — говорит подпись рядом (`titled`) или подпись для VoiceOver.
struct ReachButton: View {
    let plan: ReachPlan
    let pal: Palette
    /// В шапке карточки съёмки — облачко и название; в строке телефона карточки клиента — только облачко 48 × 48.
    var titled = true
    var node = "card.reach"
    /// Подпись для VoiceOver: «Написать: {way}».
    let write: (String) -> String
    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            ForEach(plan.sections) { sec in
                Section(sec.title) {
                    ForEach(sec.items) { it in
                        Button { openURL(it.url) } label: {
                            Text(it.title)
                            if !it.detail.isEmpty { Text(it.detail) }
                        }
                    }
                }
            }
        } label: {
            label
        } primaryAction: {
            Haptics.play(.segment)
            openURL(plan.primary.url)
        }
        .menuIndicator(.hidden)
        .menuOrder(.fixed)
        .accessibilityLabel(write(plan.primary.title))
        .shotNode(node, text: plan.primary.id)
    }

    @ViewBuilder private var label: some View {
        if titled {
            HStack(spacing: 6) {
                Icon("chat", size: 15)
                Text(plan.primary.title).font(webFont(15)).lineLimit(1)
            }
            .foregroundStyle(pal.brass)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .contentShape(Rectangle())
        } else {
            Icon("chat", size: 17).foregroundStyle(pal.brass).frame(width: 48, height: 48).contentShape(Rectangle())
        }
    }
}
