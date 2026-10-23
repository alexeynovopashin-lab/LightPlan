import SwiftUI
import LightPlanCore
import LightPlanData

/// Экран «Настройки» — порт `#s-set` веба (итерация 19а).
///
/// Корень: переключатель Просто/Астро и десять глав: девять в порядке веба и нативная «Сеть» (28л.6)
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
        case profile, view, shoots, calendar, clients, alerts, places, store, data, network, locale, about

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
            case .about: "set.grpAbout"
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var path: [Chapter] = []
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
    /// Просто/Астро с небом на «Астро» и пояснением, девять строк разделов.
    /// Главы открываются системным переходом.
    public var body: some View {
        let t = app.lexicon
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 0) {
                    SetHeader(title: "Light Plan", sub: t.t("set.proto"))
                    // Всё под шапкой проявляется при смене вкладки (S1); шапка не мигает.
                    Group {
                    VStack(spacing: 0) {
                        WebSeg(options: [(t.t("set.modeSimple"), false), (t.t("set.modePro"), true)],
                               selection: modeBinding, nodes: ["mode.simple", "mode.pro"], sky: app.settings.pro && !skyWaiting)
                            .shotNode("mode")
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                        SetNote(text: t.t("set.modeNote"), node: "mode.note")
                    }
                    .padding(.top, 4)
                    VStack(spacing: 0) {
                        ForEach(Chapter.allCases, id: \.self) { ch in
                            if ch.opensLayer {
                                // «Клиенты» — не страница настроек, а слой, как «Организации» до К1.
                                Button { withAnimation(overlaySlide) { app.openClients() } } label: {
                                    SetItemRow(icon: ch.icon, title: t.t(ch.titleKey), value: value(of: ch))
                                }
                                .buttonStyle(.plain)
                                .shotNode("nav." + ch.rawValue, text: t.t(ch.titleKey) + value(of: ch))
                            } else {
                                NavigationLink(value: ch) {
                                    SetItemRow(icon: ch.icon, title: t.t(ch.titleKey), value: value(of: ch))
                                }
                                .buttonStyle(.plain)
                                .shotNode("nav." + ch.rawValue, text: t.t(ch.titleKey) + value(of: ch))
                            }
                        }
                    }
                    .padding(.top, 2)
                    .shotNode("nav")
                    if app.showsBuildLine { BuildLine(info: BuildInfo.current(), lexicon: t) }
                    }
                    .tabRise()
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
            SkyLog.note("settings appear pro=\(app.settings.pro) layer=\(sky == nil ? "none" : "on")")
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

    /// Небо кончается: слой убирается, таймер снимается, звёзды на кнопке проявляются (как по концу срока).
    private func endSky(reason: String) {
        SkyLog.note("end \(reason)")
        skyTimer?.cancel()
        sky = nil
        withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.7)) { skyWaiting = false }
    }

    /// Порт `renderSetNav`. Чужие главы (оповещения, хранилище) до своих
    /// итераций молчат: сказать о них пока нечего.
    private func value(of ch: Chapter) -> String {
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
        case .calendar, .alerts, .store, .about:
            return ""
        }
    }

    /// Переключатель режима. Небо — только на ВКЛЮЧЕНИЕ «Астро» (на нажатие,
    /// а не на смену значения: второе нажатие подряд перезапускает слой, как у
    /// беты); «Просто» и запуск с уже включённым режимом неба не зовут.
    private var modeBinding: Binding<Bool> {
        Binding(get: { app.settings.pro }, set: { v in
            app.update { $0.pro = v }
            if v { showSky() } else { SkyLog.note("tap simple: no sky") }
        })
    }

    private func showSky() {
        let place = app.place.place
        let now = app.now()
        let moon = MoonSample(date: app.today, minutes: Double(app.nowMinute), place: place)
        let scene = AstroSky.scene(
            days: AstroSky.days(of: now), latitude: place.latitude, longitude: place.longitude,
            moon: HorizontalPoint(altitude: moon.altitude, azimuth: moon.azimuth))
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
