import SwiftUI
import LightPlanCore
import LightPlanData

/// Хозяин приложения: поднимает `AppModel` (снимок с диска, настройки, город
/// по умолчанию) и раскладывает экраны по вкладкам. Панель — веба
/// (`TabBarView`), все четыре вкладки; экранов три — «Свет», «Карта»
/// (итерация 20а) и «Настройки»; «Съёмки» (21) встанут перед настройками.
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
        .task {
            guard app == nil else { return }
            #if DEBUG
            if let shot = ShotScenario.fromLaunch() {
                ShotProbe.shared.start(report: shot.report, screen: shot.screen)
                app = AppModel.shot(shot)
                return
            }
            #endif
            app = await AppModel.live()
        }
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
        // Экраны живут оба, виден выбранный: у системной `TabView` так же
        // сохранялись прокрутка и глава при смене вкладки.
        ZStack {
            screen(.light) { LightScreenView(app.light) }
            screen(.map) { MapScreenView(app: app) }
            screen(.settings) { SettingsView(app: app) }
        }
        // Панель веба 84 pt вместе с полосой «домой»: над безопасной зоной
        // из неё видно 84 − низ зоны, остальное уходит под полосу.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !app.chapterOpen {
                GeometryReader { geo in
                    TabBarView(tab: $app.tab, lexicon: app.lexicon)
                        .shotNode("tabbar")
                        .frame(height: TabBarView.height)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
                .frame(height: max(0, TabBarView.height - bottomInset))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .onGeometryChange(for: ShotWindow.self) { ShotWindow(safe: $0.safeAreaInsets, size: $0.size) } action: {
            ShotProbe.shared.window($0)
        }
        .environment(\.drumSlot, app.settings.drumSlot)
        // «Система» — отказ выбирать: телефон сам знает, вечер или день.
        .preferredColorScheme(app.settings.theme == .dark ? .dark : app.settings.theme == .light ? .light : nil)
        .sheet(isPresented: $app.showStartSheet, onDismiss: { app.finishStart() }) {
            StartSheet(app: app)
        }
    }

    @State private var bottomInset: CGFloat = 34

    private func screen(_ tab: AppTab, @ViewBuilder _ content: () -> some View) -> some View {
        let shown = app.tab == tab
        return content()
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .environment(\.shotSilent, !shown)
    }
}

#Preview {
    RootView()
}
