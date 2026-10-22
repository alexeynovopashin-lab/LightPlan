import SwiftUI
import LightPlanDomain

/// Баннер внутри приложения (веб `#notif`, шаг 30.6): «прогноз переменился» при запуске и возврате. Вид беты —
/// плашка уведомления сверху: знак латунью, «LIGHT PLAN · сейчас», заголовок и текст; въезжает сверху за 0,5 с,
/// стоит 5,2 с. Нажатие открывает карточку съёмки. Матовая, как полоса «Вернуть»: тон `--overlay-3` поверх стекла.
struct NoticeBanner: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        ZStack(alignment: .top) {
            if app.noticeShown, let n = app.notices.current, let text = app.noticeText {
                Button { withAnimation(Self.slide) { app.tapNotice() } } label: {
                    HStack(alignment: .top, spacing: 11) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LinearGradient(colors: [pal.brass, pal.brassDark], startPoint: .top, endPoint: .bottom))
                            .frame(width: 34, height: 34)
                            .overlay(Icon("sun", size: 20, line: 2).foregroundStyle(pal.onBrass))
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("LIGHT PLAN").font(.system(size: 11, weight: .semibold)).kerning(0.7).foregroundStyle(pal.ink3)
                                Spacer(minLength: 0)
                                Text(app.lexicon.t("notif.now")).font(.system(size: 11)).foregroundStyle(pal.ink4)
                            }
                            Text(n.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(pal.ink)
                                .padding(.top, 3)
                                .shotNode("notice.title", text: n.title)
                            Text(text).font(.system(size: 13)).foregroundStyle(pal.ink2b).lineSpacing(2)
                                .padding(.top, 1)
                                .fixedSize(horizontal: false, vertical: true)
                                .shotNode("notice.text", text: text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 13).padding(.horizontal, 15)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(pal.overlay3))
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 15, y: 12)
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .shotNode("notice")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Self.slide, value: app.noticeShown)
    }

    /// `transform 0.5s cubic-bezier(0.25,1,0.4,1)` веба.
    static let slide = Animation.timingCurve(0.25, 1, 0.4, 1, duration: 0.5)
}
