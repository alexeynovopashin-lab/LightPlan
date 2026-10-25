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
                app?.sweepMbBins()
                return
            }
            #endif
            // Одна модель с фоновой задачей (30.6): iOS могла уже поднять её в фоне ради прогноза.
            app = await AppModel.sharedLive()
            app?.sweepMbBins()          // самоочистка корзин мудбордов: при запуске (29б)
            // «Прогноз переменился» (30.6): полторы секунды форы — первый экран рисуется раньше баннера (веб 1500 мс).
            try? await Task.sleep(for: .milliseconds(1500))
            app?.watchWeather(force: true)
        }
        .onChange(of: scenePhase) { _, phase in
            app?.sceneActive = phase == .active
            // Ушли в фон — отложенная запись дописывается сейчас: система
            // может закрыть приложение, не дождавшись дебаунса.
            // Открытая карточка организации (и клиента, К2) сверяет номера и в фоне: закрытие может не наступить
            // (ошибка веба 29 — ушедший номер писался только при «Назад»).
            if phase == .background, let app { app.commitOrgTels(); app.commitClientTels(); Task { await app.flush() } }
            // Ушли в фон — попросить iOS разбудить нас ради прогноза (30.6) или снять просьбу, если следить не за чем.
            if phase == .background, let app { app.scheduleWeatherWake(); app.debugWeatherBackgroundRun() }
            // Вернулись на экран — если прогноза или воздуха всё ещё нет, спросить сразу (28ж): раньше один
            // сорвавшийся запрос оставлял приложение без прогноза до перезапуска.
            if phase == .active, let app { app.light.weather.resume(); app.sweepMbBins() }
            // И расписание студийного часа сверяется с данными и с разрешением (его могли дать в настройках iPhone).
            if phase == .active, let app { app.syncAlerts(force: true) }
            // И Календарь iPhone сверяется с данными: событие могли удалить руками, право — выдать или отнять (30.3).
            if phase == .active, let app { app.syncCalendarMirror(force: true); app.syncContacts(force: true); if app.ghostWanted { app.scheduleGhostReload() } }
            // Доступ к геопозиции могли дать или отнять в настройках iPhone; слежение берёт свежую точку (29.8в.12).
            if phase == .active, let app { app.placeBecameActive() }
            // Прогноз к съёмкам переменился, пока нас не было (30.6): баннер; чаще получаса в сеть не ходим.
            if phase == .active, let app {
                app.offerPendingWeatherAlerts()     // плашка, не дождавшаяся сцены (30.6b)
                Task { try? await Task.sleep(for: .milliseconds(900)); app.watchWeather(force: false) }
            }
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
                screen(.light) { LightScreenView(app.light, onPlace: { app.placeSheetOpen = true },
                                                onPlan: { day, start in app.openForm(day: day, start: start, fromLight: true) }) }
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
                // Список долгов (К5, вид 2) — над карточкой долга; свайп от края и «✕» возвращают к ней.
                if app.debtsListOpen {
                    DebtsListScreen(app: app)
                        .edgeBack(app, z: BackZ.debtsList) { app.closeDebtsList() }
                        .transition(.move(edge: .bottom))
                        .zIndex(BackZ.debtsList)
                }
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
                    .binSubject(app, "mbfolder." + (app.mb.folder ?? ""))
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
            // «Клиенты» (К1): «Частные» и «Компании» (организации, 28 шаг 6) из настроек; карточка организации поверх.
            if app.org.listOpen {
                ClientsScreen(app: app)
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
            // Карточка частного клиента (К2): над «Клиентами» и «Контактами», под карточкой организации.
            if let id = app.org.clientCardId {
                ClientCardScreen(app: app, id: id, onBack: {
                    withAnimation(overlaySlide) { app.closeClientCard() }
                }, onDone: {
                    withAnimation(overlaySlide) { app.doneClientCard() }
                })
                .edgeBack(app, z: BackZ.clientCard) { app.closeClientCard() }
                .transition(.move(edge: .trailing))
                .zIndex(BackZ.clientCard)
            }
            if let id = app.org.cardId {
                OrgCardScreen(app: app, id: id, backTitle: app.lexicon.t("org.tabOrgs")) {
                    withAnimation(overlaySlide) { app.closeOrgCard() }
                }
                .edgeBack(app, z: BackZ.orgCard) { app.closeOrgCard() }
                .transition(.move(edge: .trailing))
                .zIndex(BackZ.orgCard)
            }
            // Плашка перед входом в AR (29.8в.4): геолокации нет или место далеко. Над картой, под самим AR.
            if let entry = app.sunAREntry {
                SunAREntryPlate(app: app, entry: entry)
                    .zIndex(BackZ.sunAR - 0.05)
            }
            // Плашка перед системным окном уведомлений (30а.2): после первого сохранения съёмки со студией.
            if app.studioAlertAsk {
                StudioAlertAskPlate(app: app)
                    .zIndex(BackZ.sunAR - 0.04)
            }
            // Та же плашка после первого баннера о смене прогноза (30.6b).
            if app.weatherAlertAsk {
                WeatherAlertAskPlate(app: app)
                    .zIndex(BackZ.sunAR - 0.04)
            }
            // Слой AR (29.8в): дуга солнца поверх камеры; вход — место и момент, откуда открыли, экрану безразлично.
            if let target = app.sunAR {
                SunARScreen(app: app, target: target)
                    .edgeBack(app, z: BackZ.sunAR) { app.closeSunAR() }
                    .transition(.move(edge: .bottom))
                    .zIndex(BackZ.sunAR)
            }
            // Затемнение под листом места (`.scrim` веба, чёрный 0,55): лист
            // iOS 26 на неполной высоте экран под собой не затемняет.
            Color.black.opacity(app.placeSheetOpen ? 0.55 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.3), value: app.placeSheetOpen)
                // Лист открывается и со стрелки AR (29.8в.12): затемнение — над ним.
                .zIndex(BackZ.sunAR + 0.01)
            // «Вернуть» после удаления (22) — над любой вкладкой, 14 над панелью.
            UndoBar(app: app)
                .zIndex(2)
        }
        // Панель веба 84 pt вместе с полосой «домой»: над безопасной зоной
        // из неё видно 84 − низ зоны, остальное уходит под полосу.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !app.chapterOpen && !app.plannerPageOpen && app.card == nil && !app.mb.isOpen && !app.org.isOpen && !app.docsNav.isOpen && app.sunAR == nil {
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
        // Круг корзины (29.7, `#binTarget`): над всеми слоями оболочки, от нижнего края экрана, как у беты.
        .overlay { BinTarget(flight: app.binFlight, host: .shell).ignoresSafeArea() }
        // Обложка, летящая в шапку папки мудборда (29.3в, `.mb-fly` z-index 9999): над всеми слоями, в координатах окна.
        .overlay { MbFlyLayer(fly: app.mbFly).ignoresSafeArea() }
        // Баннер «прогноз переменился» (30.6, `#notif` z-index 95): над слоями оболочки, под формой и листами.
        .overlay { NoticeBanner(app: app) }
        // Знак «Сохранено» после галочки досье клиента (поле-1, п. 6): карточка уже закрыта, знак живёт над слоями.
        .overlay { SavedSign(app: app) }
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
        // Тап по событию в Календаре iPhone (30.2): ссылка `lightplan://shoot/<id>` открывает съёмку; остальные
        // ссылки своей схемы — ответ клиента.
        .onOpenURL { if !app.openShootLink($0), !app.openDayLink($0) { app.openQuestLink($0) } }
        // Календарь «Light Plan» удалили в Календаре iPhone (30.3): заново — только когда человек скажет «да».
        .alert(app.lexicon.t("calm.goneT"), isPresented: $app.calendarGoneAsk) {
            Button(app.lexicon.t("calm.goneYes")) { app.answerCalendarGone(yes: true) }
            Button(app.lexicon.t("calm.goneNo"), role: .cancel) { app.answerCalendarGone(yes: false) }
        } message: {
            Text(app.lexicon.t("calm.goneM"))
        }
        // Жест «назад» от левого края (28з): один распознаватель на окно, слои записываются `.edgeBack`.
        .background { EdgeBackHost(app: app) }
        #if os(iOS)
        // Сортировка мудборда (29.3б): тап мимо плиток верхнего слоя выводит из режима (веб `mbTapUp`);
        // поверх листа мудборда — нет: лист закрывается первым.
        .background {
            MbSortTapOutHost(sorting: { [weak app] in app?.mbSort.on == true },
                             keeps: { [weak app] p in app.map { $0.mb.sheet != nil || $0.mbSort.keeps(p, layer: $0.mbSortLayer) } ?? true },
                             leave: { [weak app] in app?.mbSort.off() })
        }
        #endif
        // Escape выводит из режима, если поверх нет листа (веб `mbSortKey`). Отдельным видом: флаг режима,
        // прочитанный в этом теле, пересобирал бы при входе в режим весь корень (замер 29.3б: 49,8 мс CPU на кадр).
        .background { MbSortEscape(app: app) }
        // Ушли с экрана — вышли из режима (веб `go` → `mbSortOff`).
        .onChange(of: app.tab) { app.mbSort.off() }
        #if DEBUG && os(iOS)
        // Свидетель касаний (29.4): кто взял жест — только при `-LPMapGestureLog`.
        .background { TouchWitnessHost() }
        #endif
        .onAppear {
            #if DEBUG
            app.debugOpenSunAR()
            app.debugShowStudioAsk()
            app.debugShowWeatherAsk()
            #endif
            // Слои «Съёмок» лежат под вкладкой в дереве всегда: берём их, только пока вкладка выбрана.
            app.edgeBack.isLive = { [weak app] l in l.z >= EdgeBackRule.shellFloor || app?.tab == .planner }
        }
        // Пока открыта форма, лист «Занять время» показывает она сама (строка «Время в пути»).
        .sheet(item: Binding(get: { app.form == nil ? app.blockSheet : nil }, set: { app.blockSheet = $0 })) { d in
            BlockSheet(app: app, draft: d, windowHeight: windowHeight)
        }
        // Чужие календари призраками (30.5): лист события и вопрос перед системным запросом.
        .modifier(GhostPresenters(app: app, windowHeight: windowHeight))
    }

    @State private var bottomInset: CGFloat = 34
    @State private var windowHeight: CGFloat = 956

    private func screen(_ tab: AppTab, @ViewBuilder _ content: () -> some View) -> some View {
        let shown = app.tab == tab
        return content()
            // Под слоем, который ведёт палец, вкладка стоит на 30 % левее (28з): едет только видимая, спрятанные
            // стоят — сдвиг всего стека стоил ≈ 9 мс главного потока на кадр (замер 28з.5).
            .edgeBackBase(app, .tabs, shown: shown)
            // Экран появляется и гаснет сразу: шапка вкладки не мигает. Проявление и подъём на 8 pt за 0,45 с E1 (S1)
            // несёт содержимое под шапкой — `.tabRise()` внутри каждой вкладки (по `screenShown`).
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .environment(\.shotSilent, !shown)
            .environment(\.screenShown, shown)
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
