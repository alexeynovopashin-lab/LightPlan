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
            // Открытая карточка организации сверяет номера и в фоне: закрытие может не наступить
            // (ошибка веба 29 — ушедший номер писался только при «Назад»).
            if phase == .background, let app { app.commitOrgTels(); Task { await app.flush() } }
            // Вернулись на экран — если прогноза или воздуха всё ещё нет, спросить сразу (28ж): раньше один
            // сорвавшийся запрос оставлял приложение без прогноза до перезапуска.
            if phase == .active, let app { app.light.weather.resume() }
        }
    }
}

private struct Shell: View {
    @Bindable var app: AppModel

    var body: some View {
        // Экраны живут оба, виден выбранный: у системной `TabView` так же
        // сохранялись прокрутка и глава при смене вкладки.
        ZStack {
            ZStack {
                screen(.light) { LightScreenView(app.light, onPlace: { app.placeSheetOpen = true }) }
                screen(.map) { MapScreenView(app: app) }
                screen(.planner) { PlannerScreenView(app: app) }
                screen(.settings) { SettingsView(app: app) }
            }
            // Карточка события (25) — над вкладками и панелью, как `#cardOverlay`
            // веба; форма и листы открываются поверх неё.
            if let s = app.card {
                CardScreen(app: app, s: s)
                    .edgeBack(app, z: BackZ.card) { app.closeCard() }
                    .transition(.move(edge: .bottom))
                    .zIndex(BackZ.card)
                // Полный экран референсов (27) — поверх карточки, `z-index 92` веба.
                if app.refsFull != nil {
                    RefsFullScreen(app: app, s: s)
                        .edgeBack(app, z: BackZ.refs) { app.closeRefsFull() }
                        .transition(.move(edge: .bottom))
                        .zIndex(BackZ.refs)
                }
            }
            // Галерея и полка мудборда (28) — слои поверх вкладок, `z-index 80` веба.
            if app.mb.galleryOpen {
                MoodboardGallery(app: app)
                    .edgeBack(app, z: BackZ.gallery) { app.closeMbGallery() }
                    .transition(.move(edge: .trailing))
                    .zIndex(BackZ.gallery)
            }
            if let g = app.mb.shelf {
                MoodboardShelf(app: app, genre: g)
                    .edgeBack(app, z: BackZ.shelf) { app.closeMbShelf() }
                    .transition(.move(edge: .trailing))
                    .zIndex(BackZ.shelf)
            }
            if app.mb.folder != nil {
                MoodboardFolder(app: app)
                    .edgeBack(app, z: BackZ.folder) { app.closeMbFolder() }
                    .transition(.move(edge: .trailing))
                    .zIndex(BackZ.folder)
            }
            // «Документы» (28д, шаг 3а): экран под полосой мудборда. Ниже карточки съёмки (zIndex 1): тап по
            // строке «Требуют внимания» открывает карточку поверх, «Назад» возвращает сюда.
            if app.docsNav.isOpen {
                DocsScreen(app: app)
                    .edgeBack(app, z: BackZ.docs) { app.closeDocs() }
                    .transition(.move(edge: .trailing))
                    .zIndex(BackZ.docs)
            }
            // Организации (28, шаг 6): список из настроек и карточка поверх него.
            if app.org.listOpen {
                OrgListScreen(app: app)
                    .edgeBack(app, z: BackZ.orgList) { app.closeOrgs() }
                    .transition(.move(edge: .trailing))
                    .zIndex(BackZ.orgList)
            }
            // «Контакты» (28, шаг 7): слой из профиля настроек.
            if app.org.contactsOpen {
                ContactsScreen(app: app)
                    .edgeBack(app, z: BackZ.contacts) { app.closeContacts() }
                    .transition(.move(edge: .trailing))
                    .zIndex(BackZ.contacts)
            }
            if let id = app.org.cardId {
                OrgCardScreen(app: app, id: id, backTitle: app.lexicon.t("org.tabOrgs")) {
                    withAnimation(overlaySlide) { app.closeOrgCard() }
                }
                .edgeBack(app, z: BackZ.orgCard) { app.closeOrgCard() }
                .transition(.move(edge: .trailing))
                .zIndex(BackZ.orgCard)
            }
            // Затемнение под листом места (`.scrim` веба, чёрный 0,55): лист
            // iOS 26 на неполной высоте экран под собой не затемняет.
            Color.black.opacity(app.placeSheetOpen ? 0.55 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.3), value: app.placeSheetOpen)
            // «Вернуть» после удаления (22) — над любой вкладкой, 14 над панелью.
            UndoBar(app: app)
                .zIndex(2)
        }
        // Панель веба 84 pt вместе с полосой «домой»: над безопасной зоной
        // из неё видно 84 − низ зоны, остальное уходит под полосу.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !app.chapterOpen && !app.plannerPageOpen && app.card == nil && !app.mb.isOpen && !app.org.isOpen && !app.docsNav.isOpen {
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
        .mbSheets(app)
        // Опросник клиенту (28, шаг 9): лист с QR и вставкой ответа; ответ по своей схеме `lightplan://…?ans=`.
        .questSheet(app)
        .onOpenURL { app.openQuestLink($0) }
        // Жест «назад» от левого края (28з): один распознаватель на окно, слои записываются `.edgeBack`.
        .background { EdgeBackHost(app: app) }
        .onAppear {
            // Слои «Съёмок» лежат под вкладкой в дереве всегда: берём их, только пока вкладка выбрана.
            app.edgeBack.isLive = { [weak app] l in l.z >= EdgeBackRule.shellFloor || app?.tab == .planner }
        }
        // Пока открыта форма, лист «Занять время» показывает она сама (строка «Время в пути»).
        .sheet(item: Binding(get: { app.form == nil ? app.blockSheet : nil }, set: { app.blockSheet = $0 })) { d in
            BlockSheet(app: app, draft: d, windowHeight: windowHeight)
        }
    }

    @State private var bottomInset: CGFloat = 34
    @State private var windowHeight: CGFloat = 956

    private func screen(_ tab: AppTab, @ViewBuilder _ content: () -> some View) -> some View {
        let shown = app.tab == tab
        return content()
            // Под слоем, который ведёт палец, вкладка стоит на 30 % левее (28з): едет только видимая, спрятанные
            // стоят — сдвиг всего стека стоил ≈ 9 мс главного потока на кадр (замер 28з.5).
            .edgeBackBase(app, .tabs, shown: shown)
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
        let asking = Binding(get: { app.draftAsk != nil }, set: { _ in })   // закрывают сами кнопки
        let ask = app.draftAsk
        #if os(iOS)
        content.fullScreenCover(isPresented: shown) {
            FormScreen(app: app).edgeBack(app, z: BackZ.form) { app.closeForm() }
                // Подложку покрытия система красит сама и во время жеста «назад» она осталась бы на месте
                // (28з): у формы своё полотно, под ней — «Съёмки».
                .presentationBackground(.clear)
        }
        .alert(ask.map(app.draftAskTitle) ?? "", isPresented: asking) { draftAskButtons(ask) }
        #else
        content.sheet(isPresented: shown) { FormScreen(app: app) }
            .alert(ask.map(app.draftAskTitle) ?? "", isPresented: asking) { draftAskButtons(ask) }
        #endif
    }

    /// Вопрос 28о: системное окно, как у других подтверждений (`.alert`); обе кнопки отвечают, отмены нет.
    @ViewBuilder
    private func draftAskButtons(_ ask: DraftAsk?) -> some View {
        if let ask {
            Button(app.lexicon.t("form.draftContinue")) { app.continueDraft() }
            Button(app.draftAskNewTitle(ask)) { app.startNewOverDraft() }
        }
    }
}

#Preview {
    RootView()
}
