import SwiftUI
import LightPlanCore
import LightPlanData

/// Экран «Настройки» — порт `#s-set` веба (итерация 19а).
///
/// Корень: переключатель Просто/Астро и главы: девять в порядке веба, нативная «Сеть» (28л.6) и нативные «Плейлисты» (поле-1)
/// (Профиль, Вид, Съёмки, Оповещения, Карта и места, Хранилище, Данные и
/// облако, Язык и регион, О приложении). План называл семь глав — это слепок
/// 26 августа; веб с тех пор разделил «Хранилище» и «Данные», вынес
/// «Оповещения», и сверяемся с ним, а не со слепком.
///
/// Справа у строки — состояние, а не подпись «что внутри» (`renderSetNav`):
/// с этим вопросом в настройки и приходят. Раскладка — системный список:
/// стекло и контролы в нативе системные (DECISIONS, «Стекло в нативе —
/// системное»).
public struct SettingsView: View {
    @Bindable var app: AppModel

    public init(app: AppModel) { self.app = app }

    enum Chapter: String, CaseIterable, Hashable {
        case profile, view, shoots, calendar, clients, alerts, places, store, data, network, locale, playlists, about

        var icon: String {
            switch self {
            case .profile: "phone"
            case .view: "sun_moon"
            case .shoots: "camera"
            case .calendar: "view_month"
            case .clients: "heart"
            case .alerts: "alarm"
            case .places: "pin"
            case .store: "briefcase"
            case .data: "cloud"
            case .network: "route"
            case .locale: "chat"
            case .playlists: "music"
            case .about: "aperture"
            }
        }

        /// Что лежит в главе, где состав важен тесту: календарь (30.5г — всё про Календарь iPhone в одной главе), «Данные»
        /// и «Съёмки» (сами строят своё тело, без календаря), «Хранилище» (К1 — организации ушли в «Клиенты»).
        enum Part: Equatable {
            /// Зеркало съёмок, «Другие календари» и списки галочек (`CalendarMirrorSection`).
            case calendarSection
            /// Строка чужой итерации: имя приглушённо, содержимого пока нет.
            case foreign(String)
            /// Остальное тело главы, построенное вручную.
            case body
            /// Строка «Клиенты» (шаг К1): открывает экран «Клиенты» слоем поверх вкладок. «Организации» теперь внутри него,
            /// на вкладке «Компании».
            case clientsLayer
            /// Строка «Мудборды» в «Хранилище».
            case moodboardRow
            /// Строка «Корзина» в «Хранилище».
            case binRow
        }

        var parts: [Part] {
            switch self {
            case .calendar: [.calendarSection, .foreign("set.icsImport")]
            case .clients: [.clientsLayer]
            case .store: [.moodboardRow, .binRow]
            case .data: [.foreign("set.data"), .foreign("cloud.title")]
            default: [.body]
            }
        }

        /// Строка главы открывает слой поверх вкладок, а не страницу настроек (шаг К1).
        var opensLayer: Bool { self == .clients }

        var titleKey: String {
            switch self {
            case .profile: "set.grpProfile"
            case .view: "set.grpView"
            case .shoots: "set.grpShoots"
            case .calendar: "set.calendar"
            case .clients: "set.clients"
            case .alerts: "set.grpAlerts"
            case .places: "set.grpPlaces"
            case .store: "set.storage"
            case .data: "set.grpData"
            case .network: "set.grpNet"
            case .locale: "set.grpLocale"
            case .playlists: "set.playlists"
            case .about: "set.grpAbout"
            }
        }
    }

    /// Что стоит под выбором режима (30г.8; опись 30г.2, раздел А; ответ 5 Алексея 05.11). Значения настроек от режима
    /// не зависят (ответ 2): меняется только то, как они разложены.
    enum Root: Equatable {
        /// «Просто»: один лист без глав (`SimpleSettingsSheet`, состав — `SimpleSheet.items`).
        case sheet
        /// «Про» и «Астро»: главы `Chapter.allCases`; в «Астро» над ними пять переключателей неба.
        case chapters(astroSwitches: Bool)
    }

    static func root(_ mode: AppMode) -> Root {
        switch mode {
        case .simple: .sheet
        case .pro: .chapters(astroSwitches: false)
        case .astro: .chapters(astroSwitches: true)
        }
    }

    /// Запас внизу прокрутки корня: часть панели вкладок над безопасной зоной прокрутки.
    static func tabBarReserve(bottomSafe: CGFloat) -> CGFloat { max(0, TabBarView.height - bottomSafe) }

    /// Якорь конца корня: снимки «лист прокручен до конца» (`-LPShotChapter end`, 30г.8).
    static let endAnchor = "settings.end"

    @Environment(\.colorScheme) private var colorScheme
    @State private var path: [Chapter] = []
    /// Низ безопасной зоны у прокрутки корня (полоса «домой»), для запаса под панель вкладок.
    @State private var bottomSafe: CGFloat = 0
    /// Небо на включении «Астро» (29.9): идёт ли оно сейчас и когда оно погаснет.
    @State private var sky: SkyRun?
    /// `sky-wait` беты: пока небо на экране, звёзды на кнопке погашены.
    @State private var skyWaiting = false
    @State private var skyTimer: Task<Void, Never>?

    struct SkyRun: Equatable {
        let id = UUID()
        let start: Date
        let scene: AstroSky.Scene
    }

    /// Корень — вид веба: шапка «Light Plan · v3 · прототип», сегмент
    /// Просто/Про/Астро с небом на «Астро» и пояснением, девять строк разделов.
    /// Главы открываются системным переходом.
    public var body: some View {
        let t = app.lexicon
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    SetHeader(title: "Light Plan", sub: t.t("set.proto"))
                    // Всё под шапкой проявляется при смене вкладки (S1); шапка не мигает.
                    Group {
                    VStack(spacing: 0) {
                        WebSeg(options: [(t.t("set.modeSimple"), AppMode.simple), (t.t("set.modePro"), .pro), (t.t("set.modeAstro"), .astro)],
                               selection: modeBinding, nodes: ["mode.simple", "mode.pro", "mode.astro"],
                               sky: app.seesStars && !skyWaiting)
                            .shotNode("mode")
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                        SetNote(text: t.t("set.modeNote." + app.settings.mode.rawValue), node: "mode.note")
                    }
                    .padding(.top, 4)
                    switch Self.root(app.settings.mode) {
                    case .sheet:
                        // «Просто» (30г.8, ответ 5): один лист без глав.
                        SimpleSettingsSheet(app: app)
                    case .chapters(let astroSwitches):
                        if astroSwitches { AstroSwitchRows(app: app) }
                        chapterRows
                    }
                    if app.showsBuildLine { BuildLine(info: BuildInfo.current(), lexicon: t) }
                    }
                    .tabRise()
                    Color.clear.frame(height: 0).id(Self.endAnchor)
                }
            }
            // Панель вкладок до прокрутки корня не доходит (замер 30г.8: конец прокрутки — край полосы «домой», 922 pt при панели
            // от 872): последняя строка — «О приложении» листа «Просто» и глав «Астро» — оставалась под панелью, пальцем её не
            // достать. Запас — то, что панель закрывает над полосой «домой»; дойди панель до прокрутки сама, запас станет 0.
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomSafe = $0 }
            .contentMargins(.bottom, Self.tabBarReserve(bottomSafe: bottomSafe), for: .scrollContent)
            .onAppear {
                // Снимки: корень прокручен до конца (30г.8 — лист «Просто» целиком, «прокрутка до конца»).
                guard app.startChapter == "end" else { return }
                app.startChapter = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    proxy.scrollTo(Self.endAnchor, anchor: .bottom)
                }
            }
            }
            .background(Palette(colorScheme).surface)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationDestination(for: Chapter.self) { ch in
                SettingsChapterView(app: app, chapter: ch)
            }
        }
        // Небо лежит поверх «Настроек» и касаний не ловит; тёмное затемнение
        // одно и то же в обеих темах (`rgba(0,0,0,.42)` беты).
        .overlay {
            if let run = sky {
                AstroSkyView(scene: run.scene, start: run.start)
                    .id(run.id)
                    .ignoresSafeArea()
                    .transition(.identity)
            }
        }
        .onAppear {
            SkyLog.note("settings appear mode=\(app.settings.mode.rawValue) layer=\(sky == nil ? "none" : "on")")
            if let c = app.startChapter, let ch = Chapter(rawValue: c) { path = [ch]; app.startChapter = nil }
        }
        // Глава закрывает панель вкладок, как у веба.
        .onChange(of: path, initial: true) {
            app.chapterOpen = !path.isEmpty
            // Небо лежит поверх корня «Настроек»; открылась глава — небо кончается сразу, иначе его
            // затемнение остаётся поверх главы до конца 2,4 с (ревью GPT к 442bd8e, хвост 29.9).
            if !path.isEmpty, sky != nil { endSky(reason: "chapter open") }
        }
    }

    /// Главы «Про» и «Астро» — как до 30г.8.
    private var chapterRows: some View {
        let t = app.lexicon
        return VStack(spacing: 0) {
            ForEach(Chapter.allCases, id: \.self) { ch in
                let v = Self.value(of: ch, app: app)
                if ch.opensLayer {
                    // «Клиенты» — не страница настроек, а слой, как «Организации» до К1.
                    Button { withAnimation(overlaySlide) { app.openClients() } } label: {
                        SetItemRow(icon: ch.icon, title: t.t(ch.titleKey), value: v)
                    }
                    .buttonStyle(.plain)
                    .shotNode("nav." + ch.rawValue, text: t.t(ch.titleKey) + v)
                } else {
                    NavigationLink(value: ch) {
                        SetItemRow(icon: ch.icon, title: t.t(ch.titleKey), value: v)
                    }
                    .buttonStyle(.plain)
                    .shotNode("nav." + ch.rawValue, text: t.t(ch.titleKey) + v)
                }
            }
        }
        .padding(.top, 2)
        .shotNode("nav")
    }

    /// Небо кончается: слой убирается, таймер снимается, звёзды на кнопке проявляются (как по концу срока).
    private func endSky(reason: String) {
        SkyLog.note("end \(reason)")
        skyTimer?.cancel()
        sky = nil
        withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.7)) { skyWaiting = false }
    }

    /// Порт `renderSetNav`. Чужие главы (оповещения, хранилище) до своих
    /// итераций молчат: сказать о них пока нечего.
    static func value(of ch: Chapter, app: AppModel) -> String {
        let t = app.lexicon, s = app.settings
        switch ch {
        case .profile:
            // Номер телефона ещё не перенесён — строка отвечает городом.
            return s.home.isEmpty ? t.t("set.myCityNone") : s.home.name
        case .view:
            return t.t(s.theme == .light ? "set.themeLight" : s.theme == .auto ? "set.themeAuto" : "set.themeDark")
        case .shoots:
            return t.t("set.step\(s.timeStep)")
        case .places:
            return app.spotCount > 0 ? String(app.spotCount) : t.t("card.none")
        case .data:
            return t.t("set.off")      // облака ещё нет (итерация 31) — честно «выкл»
        case .network:
            return t.t(app.netMode == .auto ? "net.auto" : "net.direct")
        case .locale:
            return SettingsText.languageName(app.language) + " · "
                + NumberText(language: app.language).currencySign(s.currency.rawValue)
        case .clients:
            return app.clientsValue
        case .playlists:
            // Состояние, а не подпись: какой плеер открывает кнопка у съёмки без своего плейлиста.
            return app.musicApp?.name ?? t.t("set.musicOff")
        case .calendar, .alerts, .store, .about:
            return ""
        }
    }

    /// Переключатель режима. Небо — только на ВКЛЮЧЕНИЕ «Астро» (на нажатие,
    /// а не на смену значения: второе нажатие подряд перезапускает слой, как у
    /// беты); «Просто», «Про» и запуск с уже включённым режимом неба не зовут.
    private var modeBinding: Binding<AppMode> {
        Binding(get: { app.settings.mode }, set: { m in
            app.update { $0.mode = m }
            // Небо — звёзды и созвездия: только со «Звёздами» (30г.7, опись № 3); режим уже записан выше.
            if app.seesStars { showSky() } else { SkyLog.note("tap \(m.rawValue): no sky") }
        })
    }

    private func showSky() {
        // Сцена — правило модели: созвездия по «Звёздам», луна в ней только с «Луной» (30г.10).
        let scene = app.astroSkyScene()
        // Анимация идёт по часам устройства: часы приложения в сценариях съёмок подменены.
        let run = SkyRun(start: Date(), scene: scene)
        SkyLog.note("start constellations=\(scene.constellations.count) lines=\(scene.lines.count) stars=\(scene.stars.count) moon=\(scene.moon == nil ? "no" : "yes") codes=\(scene.constellations.joined(separator: ","))")
        sky = run
        skyWaiting = true
        skyTimer?.cancel()
        let began = ProcessInfo.processInfo.systemUptime
        skyTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(AstroSkyView.lifetime))
            guard !Task.isCancelled, sky?.id == run.id else { return }
            SkyLog.note(String(format: "end alive=%.3f", ProcessInfo.processInfo.systemUptime - began))
            sky = nil
            // `.seg-sky { transition: opacity 0.7s ease }` — звёзды на кнопке проявляются, когда небо гаснет.
            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.7)) { skyWaiting = false }
        }
    }

    private func binding<V>(_ key: WritableKeyPath<AppSettings, V>) -> Binding<V> {
        Binding(get: { app.settings[keyPath: key] },
                set: { v in app.update { $0[keyPath: key] = v } })
    }
}

/// Имена и образцы, которые собирает код, а не словарь.
enum SettingsText {
    /// Языки названы на себе самих (`LANG_NAMES`): их узнают, не умея читать
    /// текущий язык интерфейса.
    static func languageName(_ code: String) -> String {
        ["ru": "Русский", "en-GB": "English (UK)", "en-US": "English (US)",
         "es": "Español", "ja": "日本語", "zh": "中文"][code] ?? code
    }
}

#Preview {
    @Previewable @State var app: AppModel?
    Group {
        if let app { SettingsView(app: app) } else { Color.clear }
    }
    .task { app = await AppModel.live() }
}
