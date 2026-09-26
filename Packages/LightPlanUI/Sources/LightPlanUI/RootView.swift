import SwiftUI
import LightPlanCore
import LightPlanData

/// Хозяин приложения: поднимает `AppModel` (снимок с диска, настройки, город
/// по умолчанию) и раскладывает экраны по вкладкам. Панель — веба
/// (`TabBarView`), все четыре вкладки: «Свет», «Карта» (итерация 20а),
/// «Съёмки» (21) и «Настройки».
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
            screen(.light) { LightScreenView(app.light, onPlace: { app.placeSheetOpen = true }) }
            screen(.map) { MapScreenView(app: app) }
            screen(.planner) { PlannerScreenView(app: app) }
            screen(.settings) { SettingsView(app: app) }
            // Затемнение под листом места (`.scrim` веба, чёрный 0,55): лист
            // iOS 26 на неполной высоте экран под собой не затемняет.
            Color.black.opacity(app.placeSheetOpen ? 0.55 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.3), value: app.placeSheetOpen)
            // «Вернуть» после удаления (22) — над любой вкладкой, 14 над панелью.
            UndoBar(app: app)
        }
        // Панель веба 84 pt вместе с полосой «домой»: над безопасной зоной
        // из неё видно 84 − низ зоны, остальное уходит под полосу.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !app.chapterOpen && !app.plannerPageOpen {
                GeometryReader { geo in
                    TabBarView(tab: $app.tab, lexicon: app.lexicon)
                        .shotNode("tabbar")
                        .frame(height: TabBarView.height)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
                .frame(height: max(0, TabBarView.height - bottomInset))
            }
        }
        // Лист «Когда смотрим» (19в) лежит над панелью вкладок, как `#sheet`
        // веба (z-index 70 над `.tabbar`).
        .overlay { MomentSheetHost(model: app.light) }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .onGeometryChange(for: ShotWindow.self) { ShotWindow(safe: $0.safeAreaInsets, size: $0.size) } action: {
            ShotProbe.shared.window($0)
            windowHeight = $0.size.height + $0.safe.top + $0.safe.bottom
        }
        .environment(\.drumSlot, app.settings.drumSlot)
        // «Система» — отказ выбирать: телефон сам знает, вечер или день.
        .preferredColorScheme(app.settings.theme == .dark ? .dark : app.settings.theme == .light ? .light : nil)
        .sheet(isPresented: $app.showStartSheet, onDismiss: { app.finishStart() }) {
            StartSheet(app: app)
        }
        // Форма записи (23): на всю высоту, как `#formOverlay` веба.
        .modifier(FormCover(app: app))
        // Лист «Где снимаем» (21в) — с кнопки места «Света» и «Карты».
        .sheet(isPresented: $app.placeSheetOpen, onDismiss: { app.placeSheetStart = .fork }) {
            PlaceSheet(app: app, windowHeight: windowHeight)
        }
        // Корзина и «Занять время» (22): из «Съёмок» и настроек.
        .sheet(isPresented: $app.binOpen) { BinSheet(app: app, windowHeight: windowHeight) }
        .sheet(item: $app.blockSheet) { d in BlockSheet(app: app, draft: d, windowHeight: windowHeight) }
    }

    @State private var bottomInset: CGFloat = 34
    @State private var windowHeight: CGFloat = 956

    private func screen(_ tab: AppTab, @ViewBuilder _ content: () -> some View) -> some View {
        let shown = app.tab == tab
        return content()
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .environment(\.shotSilent, !shown)
    }
}

/// Форма поверх вкладок. На Mac (хост сборки пакета) — обычный лист.
private struct FormCover: ViewModifier {
    @Bindable var app: AppModel
    func body(content: Content) -> some View {
        let shown = Binding(get: { app.form != nil }, set: { if !$0 { app.closeForm() } })
        #if os(iOS)
        content.fullScreenCover(isPresented: shown) { FormScreen(app: app) }
        #else
        content.sheet(isPresented: shown) { FormScreen(app: app) }
        #endif
    }
}

#Preview {
    RootView()
}
