import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Полоса «Документы» на «Съёмках» (итерация 28д, шаг 3а; справка `docs_reference.md` § 6.1)

/// Вход в «Документы» — под полосой мудборда. Свёрнутая ручка мудборда по размерам: 66 = 12 + 42 + 12,
/// подложка `sheet4` радиусом 20 с рамкой, плитка 42 со знаком, заголовок 16/650, подпись 12,5.
/// Не сворачивается (вход, а не раздел). Цифры — из `DocSections`: «всего» и «требуют внимания».
struct DocsStrip: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        let c = app.docCounts()
        Button { withAnimation(overlaySlide) { app.openDocs() } } label: {
            HStack(spacing: 14) {
                Icon("doc", size: 22, line: 1.6).foregroundStyle(pal.ink3)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(pal.sheet))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.t("doc.stripTitle")).font(webFont(16, 650)).tracking(-0.2).foregroundStyle(pal.ink)
                    subtitle(c, pal, t)
                }
                Spacer(minLength: 0)
                Icon("chevron", size: 16, line: 2.4).foregroundStyle(pal.ink4).rotationEffect(.degrees(90))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.sheet4)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(pal.hairline, lineWidth: 1))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24).padding(.top, 10)
        .shotNode("docs.strip", text: "\(c.total)/\(c.attention)")
    }

    /// «48 бумаг» или «48 бумаг · требуют внимания: 3» (число и слова янтарём, без свечения);
    /// бумаг нет — «Бумаги появятся здесь».
    @ViewBuilder private func subtitle(_ c: DocCounts, _ pal: Palette, _ t: Lexicon) -> some View {
        if c.total == 0 {
            Text(t.t("doc.stripEmpty")).font(webFont(12.5)).foregroundStyle(pal.ink4).lineLimit(1)
        } else if c.attention > 0 {
            (Text(t.count("doc.stripCount", c.total) + " · ").foregroundStyle(pal.ink4)
             + Text(t.t("doc.stripAttn", ["n": String(c.attention)])).foregroundStyle(pal.brassDeep))
                .font(webFont(12.5)).lineLimit(1)
        } else {
            Text(t.count("doc.stripCount", c.total)).font(webFont(12.5)).foregroundStyle(pal.ink4).lineLimit(1)
        }
    }
}
