import SwiftUI
import LightPlanCore

/// Плашка перед системным окном уведомлений (шаг 30а.2). Вариант «В» Алексея 14.10: сначала наша плашка, потом
/// системное окно; не просить право молча. Вид — как плашка входа в AR («простая полупрозрачная плашка на матовом
/// стекле»): системное `.glassEffect`, своей подделки стекла нет (`Tools/check_glass.sh`). Две кнопки: «Да» зовёт
/// системное окно, «Нет» (и касание мимо плашки) просто закрывает; больше плашка сама не появляется.
struct StudioAlertAskPlate: View {
    @Bindable var app: AppModel

    private var t: Lexicon { app.lexicon }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { app.answerStudioAlertAsk(yes: false) }
            VStack(spacing: 16) {
                Text(t.t("studio.askT"))
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .shotNode("studio.ask.text", text: t.t("studio.askT"))
                HStack(spacing: 10) {
                    answer("studio.askNo", yes: false)
                    answer("studio.askYes", yes: true)
                }
            }
            .foregroundStyle(.primary)
            .padding(20)
            .frame(maxWidth: 360)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shotNode("studio.ask")
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    private func answer(_ key: String, yes: Bool) -> some View {
        let label = t.t(key)
        return Button { app.answerStudioAlertAsk(yes: yes) } label: {
            Text(label)
                .font(.system(size: 16, weight: yes ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: SunARInk.touch)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(yes ? .regular.tint(SunARInk.sunTint.opacity(0.35)).interactive() : .regular.interactive(), in: Capsule())
        .shotNode(yes ? "studio.ask.yes" : "studio.ask.no", text: label)
    }
}
