import Foundation
import SwiftUI
import LightPlanCore
import LightPlanData
import LightPlanDomain
import LightPlanMapCanvas

/// Половина пары «веб / натив» (итерация 19б, § 5.4 плана): приложение
/// открывается в той же минуте, в том же месте, с той же погодой и теми же
/// настройками, что снимок `tools/shot.js`, и пишет рамки ключевых узлов под
/// теми же именами. Сверяет пару `native/Tools/shots/pair.js`.
///
/// Только Debug: аргументы запуска читаются в `RootView` под `#if DEBUG`,
/// в выпуске сценарий не собирается ни из чего.
///
/// Аргументы (`xcrun simctl launch … -LPShotNow … -LPShotSeed …`):
/// `LPShotNow` — момент ISO 8601 со смещением; `LPShotZone` — пояс IANA;
/// `LPShotSeed` — снимок данных в формате веба (тот же файл засевает
/// `localStorage` веба); `LPShotForecast`, `LPShotAir` — ответы Open-Meteo;
/// `LPShotName` — `{ "city", "sub" }` вместо геокодера; `LPShotScreen` —
/// `light` | `map` | `planner` | `settings`; `LPShotChapter` — глава настроек;
/// `LPShotScope` — вид «Съёмок» (`month` | `week` | `day`); `LPShotReport` —
/// куда записать рамки; `LPShotLiveMap` — холст карты с сетью (глазами, не
/// для пары: у веба в паре сети нет); `LPShotTapSpot`, `LPShotTapReport` —
/// приложение само тапает булавку и пишет, стоит ли полоса имени (20е,
/// `MapScreenView.shotTapSpot`, `Tools/tap_spot.js`). Подставной компас (21а,
/// `Tools/rotor.js`): `LPShotHeading` — углы через запятую, `LPShotHeadingHold`
/// — секунд на угол (3); `LPShotChapter compass` включает компас при запуске,
/// `LPShotVoid` — цвет пустоты под ротором (`#00FF00`), `LPShotHeadingReport` —
/// куда писать, на каком угле ротор встал (`MapScreenView.shotHeading`).
/// Лист места (21в): `LPShotSheet loc` открывает «Где снимаем» над экраном,
/// `LPShotWay` — путь (`addr` | `geo`), без него — развилка. «Съёмки» (22):
/// `LPShotSheet year | year12 | stats | search` — слой, `bin` — корзина, `card` — карточка,
/// `blk` — «Занять время» на выбранный день.
public struct ShotScenario: Sendable {
    public enum Screen: String, Sendable { case light, map, planner, settings }

    public let now: Date
    public let zone: TimeZone
    public let seed: URL
    public let forecast: URL
    public let air: URL?
    public let name: URL?
    public let screen: Screen
    /// Глава настроек (`view`, `locale`…) — открыта поверх корня.
    public let chapter: String?
    /// Вид «Съёмок» при запуске (итерация 21).
    public let scope: CalScope?
    /// Дата закреплённой недели дня, 0 — понедельник (`LPShotPick`).
    public let pick: Int?
    public let report: URL?
    /// Углы подставного компаса (`LPShotHeading`), секунд на угол.
    public let heading: [Double]?
    public let headingHold: Double
    /// Лист поверх экрана (`loc`) и его путь.
    public let sheet: String?
    public let way: String?

    public static func fromLaunch(_ defaults: UserDefaults = .standard) -> ShotScenario? {
        guard let nowText = defaults.string(forKey: "LPShotNow"),
              let now = ISO8601DateFormatter().date(from: nowText),
              let seed = defaults.string(forKey: "LPShotSeed"),
              let forecast = defaults.string(forKey: "LPShotForecast") else { return nil }
        let url = { (key: String) in defaults.string(forKey: key).map { URL(fileURLWithPath: $0) } }
        return ShotScenario(
            now: now,
            zone: defaults.string(forKey: "LPShotZone").flatMap(TimeZone.init(identifier:)) ?? .current,
            seed: URL(fileURLWithPath: seed), forecast: URL(fileURLWithPath: forecast),
            air: url("LPShotAir"), name: url("LPShotName"),
            screen: defaults.string(forKey: "LPShotScreen").flatMap(Screen.init(rawValue:)) ?? .light,
            chapter: defaults.string(forKey: "LPShotChapter"),
            scope: defaults.string(forKey: "LPShotScope").flatMap(CalScope.init(rawValue:)),
            pick: defaults.object(forKey: "LPShotPick") == nil ? nil : defaults.integer(forKey: "LPShotPick"),
            report: url("LPShotReport"),
            heading: ScriptedHeading.angles(defaults.string(forKey: "LPShotHeading") ?? ""),
            headingHold: defaults.object(forKey: "LPShotHeadingHold") == nil ? 3 : defaults.double(forKey: "LPShotHeadingHold"),
            sheet: defaults.string(forKey: "LPShotSheet"), way: defaults.string(forKey: "LPShotWay"))
    }
}

extension AppModel {
    /// Приложение сценария: снимок из файла и только в памяти (на диск не
    /// пишет), часы с прибитого момента идут дальше своим ходом — как
    /// `page.clock.install` у веба.
    static func shot(_ s: ShotScenario) -> AppModel {
        var snapshot = (try? Data(contentsOf: s.seed)).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
            ?? Snapshot()
        // Экраны мудборда (28): первый запуск заводит пустую папку каждому жанру, как на телефоне и в вебе (`mbSeeded`).
        if ["mbgallery", "mbshelf", "mbfolder"].contains(s.sheet ?? "") {
            _ = RefLibrary.seedGenreFolders(in: &snapshot.extra, genres: Moodboard.enabledGenres(snapshot.genres).map(\.rawValue),
                                            newId: { UUID().uuidString.lowercased() })
        }
        let start = Date(), fixed = s.now
        let name = (try? Data(contentsOf: s.name ?? URL(fileURLWithPath: "/dev/null")))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
        let app = AppModel(snapshot: snapshot, store: nil, language: AppLanguage.current, zone: s.zone,
                           locator: ShotLocator(),
                           geocoder: ShotGeocoder(city: name?["city"], sub: name?["sub"], zone: s.zone.identifier),
                           cityLookup: ShotCityLookup(), placeSearch: ShotPlaceSearch(),
                           weatherSource: FileWeatherSource(forecast: s.forecast, air: s.air),
                           headingSource: s.heading.map { ScriptedHeading(angles: $0, hold: .seconds(s.headingHold)) },
                           now: { fixed.addingTimeInterval(Date().timeIntervalSince(start)) })
        app.tab = switch s.screen {
        case .settings: .settings
        case .map: .map
        case .planner: .planner
        case .light: .light
        }
        if let scope = s.scope { app.planner.setScope(scope) }
        if let k = s.pick, (0..<7).contains(k) {
            app.planner.pickInStrip(app.planner.week[k])
            _ = app.planner.consumeDayShift()
        }
        app.mapOffline = !UserDefaults.standard.bool(forKey: "LPShotLiveMap")
        if let mode = UserDefaults.standard.string(forKey: "LPShotRoads") { app.roads.useShotRoads(RoadBook.shotRouter(mode)) }
        // 28л.6: состояние детектора без сети — для снимков раздела «Сеть» (`reachable` | `unreachable` | `unknown`).
        if let raw = UserDefaults.standard.string(forKey: "LPShotNet"), let state = ForeignReach(rawValue: raw) {
            app.useShotNetwork(state)
        }
        app.startChapter = s.chapter
        app.showsBuildLine = false
        // Лист «Когда смотрим» (19в) открыт сразу, как после тапа по показаниям.
        if s.screen == .light, s.chapter == "pick" { app.light.pickerOpen = true }
        // Карточка (25): `LPShotSheet card`, запись — `LPShotWay <id>` (без него — первая съёмка дня).
        if s.sheet == "card" {
            let id = s.way ?? app.sessions.first { $0.day == app.planner.selected && $0.kind == .shoot }?.id
            if let id { app.openCard(id: id) }
            // Лист перестановки (26): `LPShotTune 1` — как после тапа по «ползункам».
            if id != nil, UserDefaults.standard.bool(forKey: "LPShotTune") { app.toggleCardTuning() }
            // Свёртка маршрута (27): `LPShotFold route` — как после тапа по строке «Маршрут дня».
            if id != nil, UserDefaults.standard.string(forKey: "LPShotFold") == "route" { app.toggleCardFold(.route) }
            // Референсы (27): `LPShotRefs full` — полный экран, `view` — ещё и первый кадр в просмотрщике.
            if let id, let mode = UserDefaults.standard.string(forKey: "LPShotRefs"),
               let sess = app.sessions.first(where: { $0.id == id }) {
                app.openRefsFull(sess)
                if mode == "view", let f = app.refSections(sess).viewable.first { _ = app.openRefFrame(f.id, in: sess) }
            }
        }
        // Форма записи (23): `LPShotSheet form`, жанр — `LPShotWay` (без него — последний). Черновик
        // только в памяти: прогон не должен писать на диск симулятора.
        if s.sheet == "form" {
            app.draftStore = MemoryDraftStore()
            // Форма читает качество неба дня: ждём, пока погода из файла придёт (у веба она уже на месте).
            Task { @MainActor in
                await app.light.weather.settled()
                // Черновик другого дня (28о): `LPShotDraft ask|continue|new` — на диске черновик от 27 сентября
                // с набранным текстом, просят 29 октября (как у Алексея): окно вопроса / ответ «продолжить» /
                // ответ «новая». `LPShotFormDay yyyy-mm-dd` — форма на этот день без черновика (порядок блоков, предупреждение).
                if let mode = UserDefaults.standard.string(forKey: "LPShotDraft") {
                    app.openForm(day: CivilDate(year: 2026, month: 9, day: 27))
                    app.form?.notes = "рано утром"
                    app.closeForm()
                    app.openForm(day: CivilDate(year: 2026, month: 10, day: 29))
                    if mode == "continue" { app.continueDraft() } else if mode == "new" { app.startNewOverDraft() }
                } else if let d = UserDefaults.standard.string(forKey: "LPShotFormDay")?.split(separator: "-").compactMap({ Int($0) }), d.count == 3 {
                    let start = UserDefaults.standard.string(forKey: "LPShotFormStart").flatMap { Int($0) }   // минуты суток
                    app.openForm(day: CivilDate(year: d[0], month: d[1], day: d[2]), start: start, fromLight: start == nil)
                } else {
                    app.openForm(day: app.planner.selected)
                }
                if let g = s.way.flatMap(Genre.init(rawValue:)) { app.pickFormGenre(g) }
                // Город формы (шаг 4б): `defaults write … LPShotFormCity Москва` — строки выезда и дороги.
                if let c = UserDefaults.standard.string(forKey: "LPShotFormCity") {
                    app.setFormCity(c)
                    app.editForm { $0.setTrip(true) }   // родного города в засеве нет — выезд руками
                }
                // Путь «Фотостудия» точки (шаг 4б): `defaults write … LPShotFormStudio 1`.
                if UserDefaults.standard.bool(forKey: "LPShotFormStudio") {
                    if app.form?.route.isEmpty == true { app.addFormStop() }
                    app.openStopPlace(0, way: .studio)
                }
            }
        }
        // Слои «Съёмок» и листы (22): слои открывает сам экран при появлении
        // (у него они в своём состоянии), листы — здесь. Корзину засевает файл.
        if ["year", "year12", "stats", "search"].contains(s.sheet ?? "") { app.startChapter = s.sheet }
        if s.sheet == "bin" { app.binOpen = true }
        if s.sheet == "blk" { app.openBlockSheet(day: app.planner.selected) }
        // Итерация 28: мудборды, организации, «Контакты», опросник, встреча. `LPShotWay` — жанр полки,
        // код подборки, код организации или записи; без него — первая из засева.
        switch s.sheet {
        case "mbgallery": app.openMbGallery(backKey: "nav.settings")   // дверь веба: строка «Мудборды» в «Настройках»
        case "mbshelf": app.openMbShelf(s.way ?? "wedding")
        case "mbfolder": if let id = s.way { app.openMbFolder(boardId: id) }
        case "orgs": app.openOrgs()
        case "docs":
            // Экран «Документы» (28д, шаг 3а): `LPShotWay` — раздел (`attention|recent|bySession|byOrg|byKind|byMonth|mine|bin`),
            // после плюса — вид (`list|table|months`), `q=слово` — запрос поиска (шаг 3б), `paper` — открыть
            // первую бумагу раздела или результата, `deal` — первую бумагу съёмки с блоком сделки, `trash`, `add`, `edit` — см. ниже; без `LPShotWay` — список разделов.
            app.docsPrefsStore = MemoryDraftStore()
            app.openDocs()
            let parts = (s.way ?? "").split(separator: "+").map(String.init)
            if let sec = parts.first.flatMap(DocSection.init(rawValue:)) { app.openDocSection(sec) }
            for p in parts {
                if let l = DocsLayout(rawValue: p) { app.editDocsPrefs { $0.layout = l } }
                if p.hasPrefix("q=") { app.docsNav.query = String(p.dropFirst(2)) }
            }
            // Шаг 4: `trash` — две первые бумаги в корзину (кадр корзины), `add` — лист «+», `edit` — правка первой бумаги.
            if parts.contains("trash") { for d in app.docArea(.recent).prefix(2) { app.trashDoc(d.doc.id) }; app.undo = nil }
            if parts.contains("add") { app.openDocAdd() }
            if parts.contains("edit"), let d = app.docArea(app.docsNav.section ?? .recent).first { app.openDocEdit(d.doc.id) }
            // `deal` — бумага съёмки, у которой блок сделки показывается (звено цепочки, «Закрывает звено…»).
            if parts.contains("deal"), let d = app.docArea(.recent).first(where: { x in
                x.sessionId.flatMap { id in app.docLibrary.sessions.first { $0.id == id } }
                    .map { DealChain.isShown(genre: $0.genre, practice: app.dealPractice) } ?? false
            }) { app.openDocPaper(d) }
            if parts.contains("paper"), let d = app.docSearching ? app.docSearchResults().first : app.docArea(app.docsNav.section ?? .recent).first {
                app.openDocPaper(d)
            }
        case "orgcard": if let id = s.way ?? app.orgs.first?.id { app.openOrgCard(id: id) }
        case "contacts": app.openContacts()
        case "quest":
            if let sess = app.sessions.first(where: { $0.id == s.way }) ?? app.sessions.first(where: { $0.kind == .shoot }) {
                app.openQuest(for: sess)
            }
        case "meet":
            app.draftStore = MemoryDraftStore()
            Task { @MainActor in
                await app.light.weather.settled()
                app.openForm(day: app.planner.selected, start: 14 * 60, fromLight: false, mode: .meet)
            }
        default: break
        }
        if s.sheet == "loc" {
            app.placeSheetStart = s.way.flatMap(PlaceSheetForm.Way.init(rawValue:)) ?? .fork
            app.placeSheetOpen = true
        }
        return app
    }
}

private struct ShotLocator: DeviceLocating {
    func currentFix() async -> DeviceFix { .denied }
    var isAlreadyAuthorized: Bool { false }
}

private struct ShotGeocoder: ReverseGeocoding {
    let city: String?, sub: String?, zone: String
    func answer(for coordinate: GeoCoordinate) async throws -> GeocodeAnswer {
        GeocodeAnswer(locality: city, region: sub, country: nil, zoneIdentifier: zone)
    }
}

private struct ShotCityLookup: CityLookup {
    func cities(matching query: String) async throws -> [CityHit] { [] }
}

private struct ShotPlaceSearch: PlaceSearch {
    func places(matching query: String) async throws -> [PlaceHit] { [] }
}

// MARK: - Рамки узлов

/// Рамки узлов экрана в точках окна — та же система, что `getBoundingClientRect`
/// веба на странице во весь экран. Пишется в файл один раз, когда экран
/// улёгся; снимок симулятора делается после появления файла.
@MainActor
public final class ShotProbe {
    public static let shared = ShotProbe()

    struct Node: Encodable { var x, y, w, h: Double; var text: String? }

    private(set) var enabled = false
    private var nodes: [String: Node] = [:]
    private var texts: [String: String] = [:]
    private var safe = EdgeInsets()
    private var size = CGSize.zero

    func start(report: URL?, screen: ShotScenario.Screen) {
        // Стенд жеста «назад» (`-LPEdgeBackBench`, Debug) идёт как обычное приложение на телефоне: без записи рамок.
        enabled = !UserDefaults.standard.bool(forKey: "LPEdgeBackBench")
        guard let report else { return }
        Task { @MainActor in
            // Экран, погода из файла и имя места от заглушки приходят за доли
            // секунды; три секунды — с запасом на анимацию вкладки. Молчащие
            // серверы маршрутов (`LPShotRoads none`) отвечают отказом через
            // 3 + 3 + 4 с и очередь в секунду — `LPShotReportDelay` ждёт дольше.
            let delay = UserDefaults.standard.object(forKey: "LPShotReportDelay") == nil
                ? 3 : UserDefaults.standard.double(forKey: "LPShotReportDelay")
            try? await Task.sleep(for: .seconds(delay))
            self.write(to: report, screen: screen)
        }
    }

    /// Кто записал узел: у «Света» и «Карты» общие имена (`header.name`,
    /// `timebar`…), и спрятанная вкладка не должна стирать рамку видимой
    /// (найдено в 20а: шапка и таймбар карты пропадали из отчёта).
    private var owners: [String: UUID] = [:]

    func record(_ name: String, _ rect: CGRect, owner: UUID) {
        guard enabled, !name.isEmpty else { return }
        owners[name] = owner
        let r = { (v: CGFloat) in (Double(v) * 2).rounded() / 2 }
        nodes[name] = Node(x: r(rect.minX), y: r(rect.minY), w: r(rect.width), h: r(rect.height))
    }

    func record(_ name: String, text: String?) { if enabled { texts[name] = text } }

    func forget(_ name: String, owner: UUID) {
        guard enabled, owners[name] == owner else { return }
        nodes[name] = nil
        owners[name] = nil
    }

    func window(_ w: ShotWindow) {
        guard enabled else { return }
        safe = w.safe
        size = w.size
    }

    private func write(to url: URL, screen: ShotScenario.Screen) {
        struct Report: Encodable {
            let screen: String
            let size: [Double]
            let safe: [Double]
            let nodes: [String: Node]
        }
        var all = nodes
        for (k, t) in texts where all[k] != nil { all[k]?.text = t }
        let report = Report(screen: screen.rawValue, size: [size.width, size.height],
                            safe: [safe.top, safe.bottom], nodes: all)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(report).write(to: url, options: .atomic)
    }
}

/// Окно приложения: отступы выреза и полосы «домой» — их же `tools/shot.js`
/// вписывает в CSS беты вместо `env(safe-area-inset-*)`.
struct ShotWindow: Equatable {
    var safe: EdgeInsets
    var size: CGSize
}

extension View {
    /// Узел пары «веб / натив» — имя из `tools/shot.js` (`NODES`). В выпуске
    /// ничего не делает; в Debug пишет рамку, только когда запущен сценарий.
    func shotNode(_ name: String, text: String? = nil) -> some View {
        #if DEBUG
        modifier(ShotNodeModifier(name: name, text: text))
        #else
        self
        #endif
    }
}

extension EnvironmentValues {
    /// Экран спрятан под видимым (панель вкладок веба держит оба живыми):
    /// его узлы в отчёт пары не пишутся — раньше соседнюю вкладку уводила
    /// за край системная панель, и `pair.js` отбрасывал её по краю экрана.
    @Entry var shotSilent = false
}

#if DEBUG
private struct ShotNodeModifier: ViewModifier {
    let name: String
    let text: String?
    @Environment(\.shotSilent) private var silent
    @State private var id = UUID()

    private struct Seen: Equatable { var rect: CGRect; var silent: Bool }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Seen.self) { Seen(rect: $0.frame(in: .global), silent: silent) } action: { seen in
                if seen.silent { ShotProbe.shared.forget(name, owner: id) } else { ShotProbe.shared.record(name, seen.rect, owner: id) }
            }
            .onChange(of: text, initial: true) { _, t in if !silent { ShotProbe.shared.record(name, text: t) } }
            .onDisappear { ShotProbe.shared.forget(name, owner: id) }
    }
}
#endif

extension RoadBook {
    /// Снимки маршрута (`LPShotRoads`): настоящий клиент с настоящей цепочкой
    /// серверов и сроками, но вместо сети — `ok` отвечает дорогой с изгибом
    /// в формате OSRM, `none` молчит до отмены (как сервер без отклика).
    static func shotRouter(_ mode: String) -> Router {
        let client = RoadClient { req in
            guard mode == "ok" else {
                try await Task.sleep(for: .seconds(3600))
                throw URLError(.timedOut)
            }
            // «…/driving/lon,lat;lon,lat?…» — точки из пути запроса.
            let path = req.url?.path ?? ""
            let pts: [(Double, Double)] = (path.split(separator: "/").last.map(String.init) ?? "")
                .split(separator: ";").compactMap { p in
                    let c = p.split(separator: ",").compactMap { Double($0) }
                    return c.count == 2 ? (c[0], c[1]) : nil
                }
            var line: [[Double]] = []
            var meters = 0.0
            for i in 0 ..< max(0, pts.count - 1) {
                let (a, b) = (pts[i], pts[i + 1])
                let mid = [(a.0 + b.0) / 2 + (b.1 - a.1) * 0.12, (a.1 + b.1) / 2 - (b.0 - a.0) * 0.12]
                line += [[a.0, a.1], mid]
                meters += 1.3 * 111_000 * ((b.0 - a.0) * (b.0 - a.0) * 0.36 + (b.1 - a.1) * (b.1 - a.1)).squareRoot()
            }
            if let l = pts.last { line.append([l.0, l.1]) }
            let body: [String: Any] = ["routes": [["geometry": ["coordinates": line],
                                                   "distance": meters, "duration": meters / 1.2]]]
            return (try JSONSerialization.data(withJSONObject: body), 200)
        }
        return { _, run in await client.ask(mode: run.mode, points: run.points) }
    }
}
