import SwiftUI
import LightPlanDomain

/// «+» в шапке экрана «Документы» и разделов бумаг (справка § 6.2): 36×36, радиус 12, знак `plus`.
/// Тап открывает лист быстрого «+» (`DocEditSheet`).
struct DocPlusButton: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        Button { app.openDocAdd() } label: {
            Icon("plus", size: 18, line: 1.8).foregroundStyle(pal.ink3)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pal.sheet))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.lexicon.t("doc.addTitle"))
        .shotNode("docs.plus")
    }
}
