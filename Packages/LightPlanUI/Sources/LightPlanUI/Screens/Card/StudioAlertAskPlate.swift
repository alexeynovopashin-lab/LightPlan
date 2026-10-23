import SwiftUI
import LightPlanCore

/// Плашка перед системным окном уведомлений (шаг 30а.2). Вариант «В» Алексея 14.10: сначала наша плашка, потом
/// системное окно; не просить право молча. Вид — как плашка входа в AR («простая полупрозрачная плашка на матовом
/// стекле»): системное `.glassEffect`, своей подделки стекла нет (`Tools/check_glass.sh`). Две кнопки: «Да» зовёт
/// системное окно, «Нет» (и касание мимо плашки) просто закрывает; больше плашка сама не появляется.
struct StudioAlertAskPlate: View {
    @Bindable var app: AppModel

    var body: some View {
        AlertAskPlate(app: app, text: "studio.askT", no: "studio.askNo", yes: "studio.askYes", node: "studio.ask") {
            app.answerStudioAlertAsk(yes: $0)
        }
    }
}

/// «Сообщать и когда приложение закрыто?» (шаг 30.6b, вариант «Б» Алексея 23.10): после первого баннера о смене
/// прогноза — та же плашка, что у студийного часа; «Да» зовёт системное окно, «Не сейчас» закрывает навсегда
/// (кнопка «Разрешить уведомления» в настройках остаётся).
struct WeatherAlertAskPlate: View {
    @Bindable var app: AppModel

    var body: some View {
        AlertAskPlate(app: app, text: "wx.askT", no: "wx.askLater", yes: "studio.askYes", node: "wx.ask") {
            app.answerWeatherAlertAsk(yes: $0)
        }
    }
}

/// Сама плашка: текст, две кнопки, касание мимо — как «нет». Один вид на все вопросы о праве уведомлять.
struct AlertAskPlate: View {
    @Bindable var app: AppModel
    let text: String
    let no: String
    let yes: String
    let node: String
    let answer: (Bool) -> Void

    private var t: Lexicon { app.lexicon }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { answer(false) }
            VStack(spacing: 16) {
                Text(t.t(text))
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .shotNode(node + ".text", text: t.t(text))
                HStack(spacing: 10) {
                    button(no, yes: false)
                    button(yes, yes: true)
                }
            }
            .foregroundStyle(.primary)
            .padding(20)
            .frame(maxWidth: 360)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shotNode(node)
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    private func button(_ key: String, yes: Bool) -> some View {
        let label = t.t(key)
        return Button { answer(yes) } label: {
            Text(label)
                .font(.system(size: 16, weight: yes ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: SunARInk.touch)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(yes ? .regular.tint(SunARInk.sunTint.opacity(0.35)).interactive() : .regular.interactive(), in: Capsule())
        .shotNode(yes ? node + ".yes" : node + ".no", text: label)
    }
}
