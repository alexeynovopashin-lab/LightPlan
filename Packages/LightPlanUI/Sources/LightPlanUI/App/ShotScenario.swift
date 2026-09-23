import Foundation
import SwiftUI
import LightPlanCore
import LightPlanData

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
/// `light` | `settings`; `LPShotChapter` — глава настроек; `LPShotReport` —
/// куда записать рамки.
public struct ShotScenario: Sendable {
    public enum Screen: String, Sendable { case light, settings }

    public let now: Date
    public let zone: TimeZone
    public let seed: URL
    public let forecast: URL
    public let air: URL?
    public let name: URL?
    public let screen: Screen
    /// Глава настроек (`view`, `locale`…) — открыта поверх корня.
    public let chapter: String?
    public let report: URL?

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
            report: url("LPShotReport"))
    }
}

extension AppModel {
    /// Приложение сценария: снимок из файла и только в памяти (на диск не
    /// пишет), часы с прибитого момента идут дальше своим ходом — как
    /// `page.clock.install` у веба.
    static func shot(_ s: ShotScenario) -> AppModel {
        let snapshot = (try? Data(contentsOf: s.seed)).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
            ?? Snapshot()
        let start = Date(), fixed = s.now
        let name = (try? Data(contentsOf: s.name ?? URL(fileURLWithPath: "/dev/null")))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
        let app = AppModel(snapshot: snapshot, store: nil, language: AppLanguage.current, zone: s.zone,
                           locator: ShotLocator(),
                           geocoder: ShotGeocoder(city: name?["city"], sub: name?["sub"], zone: s.zone.identifier),
                           cityLookup: ShotCityLookup(),
                           weatherSource: FileWeatherSource(forecast: s.forecast, air: s.air),
                           now: { fixed.addingTimeInterval(Date().timeIntervalSince(start)) })
        app.tab = s.screen == .settings ? .settings : .light
        app.startChapter = s.chapter
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
        enabled = true
        guard let report else { return }
        Task { @MainActor in
            // Экран, погода из файла и имя места от заглушки приходят за доли
            // секунды; три секунды — с запасом на анимацию вкладки.
            try? await Task.sleep(for: .seconds(3))
            self.write(to: report, screen: screen)
        }
    }

    func record(_ name: String, _ rect: CGRect) {
        guard enabled, !name.isEmpty else { return }
        let r = { (v: CGFloat) in (Double(v) * 2).rounded() / 2 }
        nodes[name] = Node(x: r(rect.minX), y: r(rect.minY), w: r(rect.width), h: r(rect.height))
    }

    func record(_ name: String, text: String?) { if enabled { texts[name] = text } }

    func forget(_ name: String) { if enabled { nodes[name] = nil } }

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
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
            ShotProbe.shared.record(name, rect)
        }
        .onChange(of: text, initial: true) { _, t in ShotProbe.shared.record(name, text: t) }
        .onDisappear { ShotProbe.shared.forget(name) }
        #else
        self
        #endif
    }
}
