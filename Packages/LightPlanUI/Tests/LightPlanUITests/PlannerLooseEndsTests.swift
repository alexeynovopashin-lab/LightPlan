import Testing
import SwiftUI
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// 30.2, хвосты 2 и 3 (Алексей 30.10: «берем 2»).
/// 2. На экране поиска одна кнопка «в конец / в начало» — общая `.scrollJump`; своя убрана.
/// 3. Значок поиска в шапке ленты года — чернила, как в «Съёмках» (был латунный).
@MainActor
struct PlannerLooseEndsTests {
    private func sourceDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LightPlanUI/Screens/Planner")
    }

    private func source(_ name: String) throws -> String {
        try String(contentsOf: sourceDir().appendingPathComponent(name), encoding: .utf8)
    }

    // MARK: - 2. Результаты поиска без своей кнопки прыжка

    /// Поиск стал панелью над плашкой пульта (30и.4): листается внутри панели, а общая кнопка «Наверх» лежит на самих «Съёмках»
    /// и пока плашка развёрнута спрятана. Своей, второй, у панели нет (раньше рядом висел дубль «шеврон-стекло»).
    @Test func searchPanelHasNoJumpButtonOfItsOwn() throws {
        let src = try source("PlannerSearchView.swift")
        let code = src.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        #expect(!code.contains(".scrollJump("), "кнопку прыжка рисует экран «Съёмок», не панель")
        #expect(!code.contains("se.jump"), "своя кнопка стояла под узлом se.jump")
        let screen = try source("PlannerScreenView.swift")
        #expect(screen.contains("hidden: nav.searchOpen"), "пока плашка поиска развёрнута, «Наверх» спрятана")
    }

    // MARK: - 3. Цвет значка поиска

    /// Лупа — чернила: в пульте «Съёмок» и в ленте года одинаково; в шапке «Съёмок» её больше нет (30и.4).
    @Test func theSearchGlyphIsInkOnTheConsoleAndTheYearHeader() throws {
        func searchColour(_ file: String, _ call: String) throws -> String? {
            let src = try source(file)
            guard let r = src.range(of: call) else { return nil }
            let tail = src[r.upperBound...]
            return tail.prefix(60).components(separatedBy: CharacterSet(charactersIn: ",)")).first.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        #expect(try source("PlannerScreenView.swift").contains("action(.search, ") == false, "лупа ушла из шапки в пульт")
        #expect(try searchColour("PlannerConsole.swift", ".stroke(") == "pal.ink")
        #expect(try searchColour("PlannerYearView.swift", "OverlayIconButton(kind: .search, color: ") == "pal.ink")
        // Остальные кнопки ленты не тронуты.
        #expect(try searchColour("PlannerYearView.swift", "OverlayIconButton(kind: .add, color: ") == "pal.brass")
        #expect(try searchColour("PlannerYearView.swift", "OverlayIconButton(kind: .stats, color: ") == "pal.brass")
    }

    /// Чернила держат ≥ 4,5 : 1 на странице и на подложке шапки в обеих темах (значок — единственная графика кнопки).
    @Test(arguments: [false, true]) func inkGlyphContrastOnTheHeader(_ dark: Bool) {
        func lum(_ c: Color) -> Double {
            var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
            UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
            func lin(_ v: CGFloat) -> Double { let x = Double(v); return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
        func ratio(_ a: Color, _ b: Color) -> Double { let (x, y) = (lum(a), lum(b)); return (max(x, y) + 0.05) / (min(x, y) + 0.05) }
        let pal = Palette(dark ? .dark : .light)
        #expect(ratio(pal.ink, pal.surface) >= 4.5, "ink на странице, dark=\(dark): \(ratio(pal.ink, pal.surface))")
        #expect(ratio(pal.ink, pal.bar) >= 4.5, "ink на шапке, dark=\(dark): \(ratio(pal.ink, pal.bar))")
    }

    #if os(iOS)
    private struct Doubles {
        struct NoWeather: WeatherSource {
            struct Offline: Error {}
            func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
            func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
        }
        struct SilentGeocoder: ReverseGeocoding {
            func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
                GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
            }
        }
        struct NoCities: CityLookup { func cities(matching query: String) async throws -> [CityHit] { [] } }
        final class NoLocator: DeviceLocating {
            var isAlreadyAuthorized: Bool { false }
            func currentFix() async -> DeviceFix { .unavailable }
        }
    }

    private func seededApp() -> AppModel {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        u.appendPathComponent("Fixtures/shots/seed_planner.json")
        let snap = try! JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: u))
        let now = ISO8601DateFormatter().date(from: "2026-10-29T13:00:00+07:00")!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                        locator: Doubles.NoLocator(), geocoder: Doubles.SilentGeocoder(), cityLookup: Doubles.NoCities(),
                        weatherSource: Doubles.NoWeather(), now: { now })
    }

    private func descendants(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(descendants) }

    private struct Node: Decodable { var x, y, w, h: Double; var text: String? }

    private func probe() async throws -> [String: Node] {
        UserDefaults.standard.set(0.1, forKey: "LPShotReportDelay")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lp-probe-\(UUID().uuidString).json")
        ShotProbe.shared.start(report: url, screen: .planner)
        try await Task.sleep(for: .milliseconds(500))
        struct Report: Decodable { var nodes: [String: Node] }
        return try JSONDecoder().decode(Report.self, from: Data(contentsOf: url)).nodes
    }

    /// Панель результатов на настоящем экране: после ввода букв она нарисована, листается внутри себя (кнопки прыжка в ней нет) и не
    /// выше `PlannerSearchView.maxHeight`.
    @Test func searchPanelShowsHitsAndStaysShort() async throws {
        try await ProbeLock.run {
            ShotProbe.shared.start(report: nil, screen: .planner)
            let app = seededApp()
            let nav = PlannerNav()
            nav.searchOpen = true
            nav.searchQuery = "а"
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 700))
            window.rootViewController = UIHostingController(rootView: PlannerSearchView(app: app, f: PlannerFacts(app: app, dark: true), nav: nav))
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await Task.sleep(for: .milliseconds(500))
            try await Task.sleep(for: .milliseconds(500))
            let n = try await probe()
            let panel = try #require(n["se.panel"], "панель результатов не нарисована")
            #expect(panel.h <= PlannerSearchView.maxHeight + 1, "панель выше предела: \(panel.h)")
            #expect(panel.h > 44, "панель пустая: \(panel.h)")
            #expect(n["se.row.0"] != nil, "нет первой строки результата")
            #expect(n["se.jump"] == nil && n["sj.search"] == nil, "в панели нет кнопки прыжка")
        }
    }

    /// Из стопки дня карточка открывается с краями дня внизу (`.fan`, 30и.5), из одиночной строки — как раньше (`.day`).
    @Test func fanStackKeepsTheOthersBelow() throws {
        let app = seededApp()
        // Долг открывается со стопкой долгов (К5) и от стопки дня не зависит: берём два будущих дня.
        let day = CivilDate(year: 2026, month: 12, day: 1)
        app.snapshot.sessions.append(Session(id: "fan1", kind: .shoot, day: day, start: 600, duration: 60))
        app.snapshot.sessions.append(Session(id: "fan2", kind: .shoot, day: day, start: 900, duration: 60))
        let two = app.sessions.filter { $0.day == day }
        let id = two[0].id
        app.openCardFromCalendar(id: id, grow: nil, fromStack: true)
        #expect(app.cardStackMode == .fan)
        #expect(CardStack<EmptyView>.edges(app, of: try #require(app.card)).isEmpty, "над листом пусто")
        #expect(!app.stack(of: try #require(app.card)).isEmpty, "соседи дня — внизу")
        app.closeCard()
        app.openCardFromCalendar(id: id, grow: nil, fromStack: false)
        #expect(app.cardStackMode == .day)
        #expect(!CardStack<EmptyView>.edges(app, of: try #require(app.card)).isEmpty, "обычная карточка — края над листом, как было")
    }
    #endif
}
