import Testing
import SwiftUI
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData

#if os(iOS)
/// 31.5в (Алексей 18.11, вариант «А», DECISIONS 18.11): у оснований дуги крупнее подпись той стороны, у которой оценка — события наверху.
/// Нашёл Алексей на телефоне 19.11: «рассвет» под сегодняшним восходом (кнопка) 118 px, под завтрашним (не кнопка) 146 px — ×0,81. Замер
/// до правки (кадры симулятора, Томск 18.11): высота подписи в кнопке 11,5 pt (12 pt × 0,8 — `minimumScaleFactor`), вне кнопки 14,5.
/// Экран «Свет» рисуется в окне, рамки подписей — узлы `.shotNode` (Debug). Томск 18.11, `Fixtures/open_meteo_tomsk_2026-11-18.json`:
/// утренний золотой час кончается в 10:12, закат 17:05. Набор собран из API `437fd8d0`: на старом коде падает проверками (узел старого
/// имени `edge.cap` — запасной).
@MainActor
struct DawnCaptionSizeTests {

    private struct Silent: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer { GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil) }
    }
    private struct NoCities: CityLookup { func cities(matching query: String) async throws -> [CityHit] { [] } }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }
    private struct Node: Decodable { var x, y, w, h: Double; var text: String? }

    /// Строка кегля `size` (тот же шрифт, что у подписи).
    static func line(_ size: CGFloat) -> Double { Double(UIFont.systemFont(ofSize: size, weight: .medium).lineHeight) }

    private func app(at hhmm: String, blocks: Bool = true) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-11-18T\(hhmm):00+07:00")!
        var snap = Snapshot()
        snap.extra["me"] = .object(["city": .string("Томск"), "cityLat": .number(56.49), "cityLon": .number(84.95), "met": .bool(true)])
        snap.extra["zones"] = .object(["56.5,85.0": .string("Asia/Tomsk")])
        let forecast = TextFixtures.root.appendingPathComponent("Fixtures/open_meteo_tomsk_2026-11-18.json")
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Tomsk")!, locator: NoLocator(),
                           geocoder: Silent(), cityLookup: NoCities(), weatherSource: FileWeatherSource(forecast: forecast, air: nil),
                           now: { now })
        app.light.blocks = blocks
        return app
    }

    /// Рамки узлов экрана «Свет» в окне 440 × 956.
    private func nodes(_ app: AppModel) async throws -> [String: Node] {
        await app.light.weather.settled()
        ShotProbe.shared.start(report: nil, screen: .light)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        window.rootViewController = UIHostingController(rootView: LightScreenView(app.light))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(700))
        UserDefaults.standard.set(0.1, forKey: "LPShotReportDelay")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lp-caption-\(UUID().uuidString).json")
        ShotProbe.shared.start(report: url, screen: .light)
        try await Task.sleep(for: .milliseconds(500))
        struct Report: Decodable { var nodes: [String: Node] }
        return try JSONDecoder().decode(Report.self, from: Data(contentsOf: url)).nodes
    }

    private func caption(_ n: [String: Node], _ side: String) throws -> Node {
        try #require(n["edge.cap.\(side)"] ?? n["edge.cap"], "нет подписи \(side): \(n.keys.filter { $0.hasPrefix("edge") }.sorted())")
    }

    @Test("09:21 — рассвет наверху: «с цветом» 12 pt (кнопка), «закат» 10 pt")
    func morningTheDawnSideIsBig() async throws {
        try await ProbeLock.run {
            let n = try await nodes(app(at: "09:21"))
            let rise = try caption(n, "rise"), set = try caption(n, "set")
            #expect(abs(rise.h - Self.line(12)) < 0.4, "подпись рассвета (главная, кнопка) не 12 pt: h \(rise.h)")
            #expect(abs(set.h - Self.line(10)) < 0.4, "подпись заката (вторая) не 10 pt: h \(set.h)")
            print("31.5в 09:21: rise «\(rise.text ?? "")» \(rise.w)×\(rise.h), set «\(set.text ?? "")» \(set.w)×\(set.h)")
        }
    }

    @Test("12:00 и 17:56 — закат наверху: его слово 12 pt; «рассвет» 10 pt и в кнопке (сегодня), и вне её (завтра) — одной ширины")
    func afternoonTheSunsetSideIsBigAndTheDawnWordIsTheSameButtonOrNot() async throws {
        try await ProbeLock.run {
            let noon = try await nodes(app(at: "12:00")), eve = try await nodes(app(at: "17:56"))
            let set = try caption(noon, "set"), setEve = try caption(eve, "set")
            #expect(abs(set.h - Self.line(12)) < 0.4 && abs(setEve.h - Self.line(12)) < 0.4, "слово заката не 12 pt: \(set.h), \(setEve.h)")
            let riseNoon = try #require(noon["edge.cap.rise"]), riseEve = try #require(eve["edge.cap.rise"])
            #expect(riseNoon.text == "рассвет" && riseEve.text == "рассвет")
            #expect(abs(riseNoon.h - Self.line(10)) < 0.4 && abs(riseEve.h - Self.line(10)) < 0.4, "«рассвет» не 10 pt: \(riseNoon.h), \(riseEve.h)")
            #expect(abs(riseNoon.w - riseEve.w) < 0.5, "«рассвет» в кнопке \(riseNoon.w) pt, вне кнопки \(riseEve.w) pt")
            print("31.5в 12:00: rise «рассвет» \(riseNoon.w)×\(riseNoon.h) (кнопка); 17:56: \(riseEve.w)×\(riseEve.h) (не кнопка); set «\(set.text ?? "")» \(set.w)×\(set.h)")
        }
    }

    @Test("без блоков: слово балла у главной стороны — 11 pt, и в кнопке заката тоже")
    func flatViewWordIsTheFlatMainSize() async throws {
        try await ProbeLock.run {
            let am = try await nodes(app(at: "09:21", blocks: false)), pm = try await nodes(app(at: "12:00", blocks: false))
            let rise = try #require(am["edge.word.rise"]), set = try #require(pm["edge.word.set"])
            #expect(am["edge.word.set"] == nil && pm["edge.word.rise"] == nil, "вторая сторона без слова")
            #expect(abs(rise.h - Self.line(11)) < 0.4 && abs(set.h - Self.line(11)) < 0.4, "слово не 11 pt: \(rise.h), \(set.h)")
        }
    }
}
#endif

/// Правило кегля 31.5в (новое API).
struct DawnCaptionRuleTests {
    @Test func sizesFollowTheEventOnTop() {
        #expect(LightScreenView.baseCaptionSize(main: true) == 12 && LightScreenView.baseCaptionSize(main: false) == 10)
        #expect(LightScreenView.baseCaptionSize(main: true, flat: true) == 11)
        #expect(abs(LightScreenView.baseCaptionSize(main: true, flat: true) / LightScreenView.baseCaptionSize(main: false, flat: true) - 1.2) < 1e-9)
        #expect(LightScreenView.baseCaptionIsMain(.dawn, event: .dawn) && !LightScreenView.baseCaptionIsMain(.sunset, event: .dawn))
        #expect(LightScreenView.baseCaptionIsMain(.sunset, event: .sunset) && !LightScreenView.baseCaptionIsMain(.dawn, event: .sunset))
        #expect(LightScreenView.baseCaptionIsMain(.dawn, event: nil) && LightScreenView.baseCaptionIsMain(.sunset, event: nil))
    }
}
