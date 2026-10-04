import Foundation

/// Публичный сервер маршрутов в формате ответа OSRM (`routes[0]`).
public struct RoadServer: Sendable {
    public let id: String
    public let modes: Set<RoadMode>
    /// Сколько ждать ответа целиком, секунд, потом — следующий сервер.
    public let timeout: TimeInterval
    let make: @Sendable (RoadMode, [MapCanvasCenter]) -> URLRequest?

    public init(id: String, modes: Set<RoadMode>, timeout: TimeInterval,
                make: @escaping @Sendable (RoadMode, [MapCanvasCenter]) -> URLRequest?) {
        self.id = id
        self.modes = modes
        self.timeout = timeout
        self.make = make
    }

    public func request(mode: RoadMode, points: [MapCanvasCenter]) -> URLRequest? {
        guard modes.contains(mode), var r = make(mode, points) else { return nil }
        r.setValue(RoadServers.userAgent, forHTTPHeaderField: "User-Agent")
        // Страховка к гонке с таймером в `RoadClient`: срок не зависит от того,
        // как быстро завершится отменённая задача (ревью GPT к 0fdca61).
        r.timeoutInterval = timeout
        return r
    }
}

/// Очередь серверов (28л.5, курс 04.10: приложение бесплатное, платных
/// сервисов и своих серверов нет, DECISIONS «Смена курса» 2026-10-04). Условия
/// публичных серверов — некоммерческое использование, «не для магазина»
/// (справка 24а); см. комментарий у `RoadRouter.askWeb`.
///
/// Замер 04.10 на одной паре точек (Барнаул): OSRM demo `foot` и `driving`
/// дали одно и то же, 3705,8 м и 286,8 с — у демо-сервера только профиль
/// машины, поэтому пешком он не спрашивается. FOSSGIS `routed-foot`: 2752 м,
/// Valhalla `pedestrian`: 2745 м. Ответы 0,45–0,61 с по Wi-Fi.
///
/// Правила FOSSGIS (routing.openstreetmap.de/about.html): пометка об
/// источнике и ссылка «fix the map» там, где показан маршрут; настоящий
/// User-Agent; не чаще запроса в секунду. Ссылка — `RoadServers.fixTheMap`.
public enum RoadServers {
    public static let fixTheMap = URL(string: "https://www.openstreetmap.org/fixthemap")!

    /// `LightPlan/<версия>` и адрес открытого репозитория.
    public static var userAgent: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "LightPlan/\(v) (+https://github.com/alexeynovopashin-lab/LightPlan)"
    }

    private static func coords(_ pts: [MapCanvasCenter]) -> String { RoadRouter.key(pts) }
    private static let geojson = "?overview=full&geometries=geojson"

    /// Таймауты 3 / 3 / 4 с, худший случай 10 с на кусок. Подобраны по замеру
    /// Wi-Fi (0,4–0,6 с, запас ×5–7); на мобильной сети не мерено.
    public static let osrmDemo = RoadServer(id: "osrm-demo", modes: [.car], timeout: 3) { _, pts in
        URL(string: "https://router.project-osrm.org/route/v1/driving/" + coords(pts) + geojson)
            .map { URLRequest(url: $0) }
    }

    public static let fossgisOSRM = RoadServer(id: "fossgis-osrm", modes: [.car, .foot], timeout: 3) { mode, pts in
        let profile = mode == .car ? "routed-car" : "routed-foot"
        return URL(string: "https://routing.openstreetmap.de/\(profile)/route/v1/driving/" + coords(pts) + geojson)
            .map { URLRequest(url: $0) }
    }

    public static let valhalla = RoadServer(id: "fossgis-valhalla", modes: [.car, .foot], timeout: 4) { mode, pts in
        let locs = pts.map { ["lat": $0.latitude, "lon": $0.longitude] }
        let body: [String: Any] = ["locations": locs, "costing": mode == .car ? "auto" : "pedestrian",
                                   "format": "osrm", "shape_format": "geojson", "directions_type": "none"]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        var c = URLComponents(string: "https://valhalla1.openstreetmap.de/route")
        c?.queryItems = [URLQueryItem(name: "json", value: json)]
        return c?.url.map { URLRequest(url: $0) }
    }

    public static let all: [RoadServer] = [osrmDemo, fossgisOSRM, valhalla]
}

/// Не чаще одного запроса в секунду на сервер: место в очереди резервируется
/// сразу, поэтому два куска подряд встают друг за другом, а не оба «сейчас».
public actor RoadThrottle {
    private let gap: Duration
    private let clock = ContinuousClock()
    private var next: [String: ContinuousClock.Instant] = [:]

    public init(gap: Duration = .seconds(1)) { self.gap = gap }

    public func wait(_ id: String) async {
        let now = clock.now
        let at = max(now, next[id] ?? now)
        next[id] = at.advanced(by: gap)
        if at > now { try? await clock.sleep(until: at) }
    }
}

/// Спрашивает серверы по очереди. `fetch` подменяется в тестах.
public final class RoadClient: Sendable {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)

    public static let shared = RoadClient()

    private let servers: [RoadServer]
    private let fetch: Fetch
    private let throttle: RoadThrottle

    public init(servers: [RoadServer] = RoadServers.all, gap: Duration = .seconds(1),
                fetch: @escaping Fetch = RoadClient.live) {
        self.servers = servers
        self.fetch = fetch
        self.throttle = RoadThrottle(gap: gap)
    }

    public static let live: Fetch = { req in
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    public func ask(mode: RoadMode, points: [MapCanvasCenter]) async -> RoadAnswer? {
        guard points.count >= 2 else { return nil }
        for server in servers {
            guard !Task.isCancelled else { return nil }
            guard let req = server.request(mode: mode, points: points) else { continue }
            await throttle.wait(server.id)
            if let a = await attempt(server, req) { return a }
        }
        return nil
    }

    /// Ответ или `nil`: сбой сети, код не 200, пустая линия и время вышло —
    /// одно и то же, дальше следующий сервер.
    private func attempt(_ server: RoadServer, _ req: URLRequest) async -> RoadAnswer? {
        let fetch = self.fetch
        return await withTaskGroup(of: RoadAnswer?.self) { group in
            group.addTask {
                guard let (data, code) = try? await fetch(req), code == 200 else { return nil }
                return RoadRouter.parseOSRM(data)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(server.timeout))
                return nil
            }
            // Первым завершается либо ответ, либо таймер. Ответ с линией берём
            // сразу; пустой ответ (сбой) — это тоже конец, таймер не ждём.
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
