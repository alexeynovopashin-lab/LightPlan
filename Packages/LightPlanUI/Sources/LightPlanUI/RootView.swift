import SwiftUI
import LightPlanCore
import LightPlanData

/// Хозяин приложения: поднимает `AppModel` (снимок с диска, настройки, город
/// по умолчанию) и раскладывает экраны по вкладкам. Вкладок пока две —
/// «Свет» и «Настройки»; «Карта» (итерация 20) и «Съёмки» (21) встанут между
/// ними, в порядке веба.
public struct RootView: View {
    @State private var app: AppModel?
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        Group {
            if let app {
                Shell(app: app)
            } else {
                // Снимок читается доли секунды — пустой фон, а не заглушка.
                Color(white: 0.06).ignoresSafeArea()
            }
        }
        .task { if app == nil { app = await AppModel.live() } }
        .onChange(of: scenePhase) { _, phase in
            // Ушли в фон — отложенная запись дописывается сейчас: система
            // может закрыть приложение, не дождавшись дебаунса.
            if phase == .background, let app { Task { await app.flush() } }
        }
    }
}

private struct Shell: View {
    @Bindable var app: AppModel

    var body: some View {
        TabView {
            Tab(app.lexicon.t("nav.light"), systemImage: "sun.max") {
                LightScreenView(app.light)
            }
            Tab(app.lexicon.t("nav.settings"), systemImage: "gearshape") {
                SettingsView(app: app)
            }
        }
        .environment(\.drumSlot, app.settings.drumSlot)
        // «Система» — отказ выбирать: телефон сам знает, вечер или день.
        .preferredColorScheme(app.settings.theme == .dark ? .dark : app.settings.theme == .light ? .light : nil)
        .sheet(isPresented: $app.showStartSheet, onDismiss: { app.finishStart() }) {
            StartSheet(app: app)
        }
    }
}

#Preview {
    RootView()
}
