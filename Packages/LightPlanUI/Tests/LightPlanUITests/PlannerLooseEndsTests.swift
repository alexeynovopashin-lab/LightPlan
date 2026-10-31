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

    // MARK: - 2. Одна кнопка прыжка в поиске

    /// Экран поиска листается общей кнопкой `.scrollJump`; второй, своей, у него нет (раньше рядом висел дубль «шеврон-стекло»).
    @Test func searchHasOnlyTheSharedJumpButton() throws {
        let src = try source("PlannerSearchView.swift")
        let code = src.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        #expect(code.components(separatedBy: ".scrollJump(").count - 1 == 1, "ровно одна общая кнопка")
        #expect(!code.contains("se.jump"), "своя кнопка стояла под узлом se.jump")
        #expect(!code.contains("mb.jumpEnd") && !code.contains("mb.jumpTop"), "слова прыжка — только в общем компоненте")
        #expect(!code.contains(".glassEffect"), "стеклянный круг рисует общий компонент")
    }

    // MARK: - 3. Цвет значка поиска

    /// Три значка шапки одного вида: «+» и статистика — латунь, поиск — чернила; в «Съёмках» и в ленте года одинаково.
    @Test func theSearchGlyphIsInkInBothHeaders() throws {
        func searchColour(_ file: String, _ call: String) throws -> String? {
            let src = try source(file)
            guard let r = src.range(of: call) else { return nil }
            let tail = src[r.upperBound...]
            return tail.prefix(60).components(separatedBy: CharacterSet(charactersIn: ",)")).first.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        #expect(try searchColour("PlannerScreenView.swift", "action(.search, ") == "pal.ink")
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

    /// На настоящем экране поиска: после ввода букв список длинный, и кнопка прыжка одна — общая (`sj.search`), своя (`se.jump`)
    /// не рисуется. Раньше рядом висела вторая: два шеврона-стекла.
    @Test func searchShowsOneJumpButton() async throws {
        try await ProbeLock.run {
            ShotProbe.shared.start(report: nil, screen: .planner)
            UserDefaults.standard.set("а", forKey: "LPSearchQuery")   // запрос без клавиатуры (Debug-ввод экрана)
            defer { UserDefaults.standard.removeObject(forKey: "LPSearchQuery") }
            let app = seededApp()
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 700))
            window.rootViewController = UIHostingController(rootView: PlannerSearchView(app: app, f: PlannerFacts(app: app, dark: true), nav: PlannerNav()))
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await Task.sleep(for: .milliseconds(500))
            try await Task.sleep(for: .milliseconds(500))
            let scroll = try #require(descendants(window).compactMap { $0 as? UIScrollView }.max { $0.contentSize.height < $1.contentSize.height })
            // Список длиннее окна. Порог кнопки (0,6 окна) здесь не пересчитываем: раньше высоту прокрутки ужимала полоса кнопки
            // (555 из 700 pt), без полосы она 700, а окно правила считает сама кнопка — его проверяет то, что `sj.search` нарисована.
            let range = scroll.contentSize.height - scroll.bounds.height
            try #require(range > 0, "список вышел коротким: прокрутки \(range) pt")
            let n = try await probe()
            let shared = try #require(n["sj.search"], "общая кнопка прыжка не нарисована")
            #expect(shared.text == "down", "от начала кнопка ведёт вниз: \(shared.text ?? "-")")
            #expect(n["se.jump"] == nil, "вторая, своя кнопка прыжка ещё рисуется")
            #expect(shared.y > 400, "кнопка внизу экрана: y \(shared.y)")
        }
    }
    #endif
}
