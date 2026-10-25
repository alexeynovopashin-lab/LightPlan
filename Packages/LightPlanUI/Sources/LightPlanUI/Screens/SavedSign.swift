import SwiftUI

/// Короткий знак «Сохранено» (поле-1, п. 6, слово Алексея 25.10: «у пользователя нет подкрепления действий, сохранились
/// данные или нет»): после галочки досье клиента появляется сверху на 1,4 с и гаснет. Включает `org.savedSign`; сам себя
/// выключает, поэтому и закрытая карточка его не обрывает. Слово — `form.saved`, как у формы записи.
struct SavedSign: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme

    /// Сколько знак стоит, секунд.
    static let standing = 1.4
    #if DEBUG
    /// Отладка: `-LPSavedSignHold <секунды>` держит знак дольше для снимка.
    static var hold: Double { UserDefaults.standard.object(forKey: "LPSavedSignHold") == nil ? standing : UserDefaults.standard.double(forKey: "LPSavedSignHold") }
    #else
    static var hold: Double { standing }
    #endif

    var body: some View {
        let pal = Palette(scheme)
        ZStack(alignment: .top) {
            if app.org.savedSign {
                HStack(spacing: 8) {
                    Icon("check", size: 17, line: 2.2).foregroundStyle(pal.brass)
                    Text(app.lexicon.t("form.saved")).font(webFont(15, 600)).foregroundStyle(pal.ink)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Capsule().fill(pal.overlay3))
                .glassEffect(.regular, in: Capsule())
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
                .shotNode("savedSign", text: app.lexicon.t("form.saved"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.25), value: app.org.savedSign)
        .allowsHitTesting(false)
        .task(id: app.org.savedSignTick) {
            guard app.org.savedSign else { return }
            try? await Task.sleep(for: .seconds(Self.hold))
            if !Task.isCancelled { app.org.savedSign = false }
        }
    }
}
