import SwiftUI
import LightPlanDomain

/// Кнопка мессенджера (шаг К4, справка `docs/clients_reference.md` § 7.1): нажатие открывает основной способ, долгое
/// нажатие — меню всех способов (позвонить, SMS, каждый мессенджер; у пары и семьи — по людям). Знак на кнопке —
/// знак главного способа (поле-1, п. 5): Telegram, WhatsApp, VK, Instagram, MAX одним цветом, как остальные знаки карточки
/// (`MessengerGlyph`, мимо генерируемой библиотеки); SMS — прежнее облачко `chat`. Какой именно — говорит и подпись
/// рядом (`titled`), и подпись для VoiceOver.
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

    /// Знак главного способа: мессенджер — его силуэт, SMS — облачко.
    @ViewBuilder private func glyph(_ size: CGFloat) -> some View {
        if let kind = plan.primary.messenger {
            Icon(messenger: kind, size: size, line: 1.6)
        } else {
            Icon("chat", size: size)
        }
    }

    @ViewBuilder private var label: some View {
        if titled {
            HStack(spacing: 6) {
                glyph(15)
                Text(plan.primary.title).font(webFont(15)).lineLimit(1)
            }
            .foregroundStyle(pal.brass)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .contentShape(Rectangle())
        } else {
            glyph(17).foregroundStyle(pal.brass).frame(width: 48, height: 48).contentShape(Rectangle())
        }
    }
}
