import Foundation
import MapKit

/// Способ перехода куска маршрута: у веба `run.mode` — `car` или `foot`.
public enum RoadMode: String, Sendable {
    case car, foot
}

/// Ответ маршрутизатора на кусок: линия по дорогам, километры, минуты
/// (`roadCache` веба: `{ line, km, min }`).
public struct RoadAnswer: Equatable, Sendable {
    public let line: [MapCanvasCenter]
    public let km: Double
    public let min: Int
    public init(line: [MapCanvasCenter], km: Double, min: Int) {
        self.line = line
        self.km = km
        self.min = min
    }
}

/// Дорога между точками черновика (итерация 24а). Две реализации по источнику
/// карты (Алексей, 28.09, DECISIONS): у MapLibre — те же серверы, что у веба
/// (`roadUrl`), у MapKit — карты Apple. Выше модуля видны только координаты.
/// `nil` — не ответили или ответ без линии; кусок тогда остаётся прямой.
public enum RoadRouter {
    public static func ask(source: MapCanvasSource, mode: RoadMode,
                           points: [MapCanvasCenter]) async -> RoadAnswer? {
        guard points.count >= 2 else { return nil }
        switch source {
        case .mapLibre: return await askWeb(mode: mode, points: points)
        case .mapKit: return await askApple(mode: mode, points: points)
        }
    }

    /// `roadKey` веба: «lon,lat;lon,lat» по пять знаков.
    public static func key(_ points: [MapCanvasCenter]) -> String {
        points.map { String(format: "%.5f,%.5f", $0.longitude, $0.latitude) }.joined(separator: ";")
    }

    // MARK: MapLibre — OSRM / Valhalla, как у веба

    /// `roadUrl` веба: машина — демо-сервер OSRM, пешком — Valhalla FOSSGIS
    /// в формате OSRM. Сервер на своих правилах не для магазина — к выпуску
    /// (34) нужен свой или платный (справка 24а).
    public static func webURL(mode: RoadMode, points: [MapCanvasCenter]) -> URL? {
        let pts = key(points)
        if mode == .car {
            return URL(string: "https://router.project-osrm.org/route/v1/driving/" + pts
                       + "?overview=full&geometries=geojson")
        }
        let locs = points.map { ["lat": $0.latitude, "lon": $0.longitude] }
        let body: [String: Any] = ["locations": locs, "costing": "pedestrian", "format": "osrm",
                                   "shape_format": "geojson", "directions_type": "none"]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        var c = URLComponents(string: "https://valhalla1.openstreetmap.de/route")
        c?.queryItems = [URLQueryItem(name: "json", value: json)]
        return c?.url
    }

    /// Разбор ответа в формате OSRM: `routes[0].geometry.coordinates`, метры, секунды.
    public static func parseOSRM(_ data: Data) -> RoadAnswer? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = (j["routes"] as? [[String: Any]])?.first,
              let g = r["geometry"] as? [String: Any],
              let coords = g["coordinates"] as? [[Double]] else { return nil }
        let line = coords.compactMap { c in c.count >= 2 ? MapCanvasCenter(latitude: c[1], longitude: c[0]) : nil }
        guard line.count >= 2 else { return nil }
        let m = (r["distance"] as? Double) ?? 0, s = (r["duration"] as? Double) ?? 0
        return RoadAnswer(line: line, km: m / 1000, min: Int((s / 60).rounded()))
    }

    private static func askWeb(mode: RoadMode, points: [MapCanvasCenter]) async -> RoadAnswer? {
        guard let url = webURL(mode: mode, points: points),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return parseOSRM(data)
    }

    // MARK: MapKit — карты Apple

    /// Переход A → B картами Apple.
    @MainActor
    static func askAppleLeg(mode: RoadMode, from a: MapCanvasCenter, to b: MapCanvasCenter) async -> RoadLeg? {
        let req = MKDirections.Request()
        req.source = item(a)
        req.destination = item(b)
        req.transportType = mode == .foot ? .walking : .automobile
        guard let route = try? await MKDirections(request: req).calculate().routes.first else { return nil }
        let n = route.polyline.pointCount
        var cs = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: n)
        route.polyline.getCoordinates(&cs, range: NSRange(location: 0, length: n))
        return RoadLeg(line: cs.map { MapCanvasCenter(latitude: $0.latitude, longitude: $0.longitude) },
                       meters: route.distance, seconds: route.expectedTravelTime)
    }

    @MainActor
    private static func askApple(mode: RoadMode, points: [MapCanvasCenter]) async -> RoadAnswer? {
        await RoadLegs.shared.run(mode: mode, points: points)
    }

    @MainActor
    private static func item(_ p: MapCanvasCenter) -> MKMapItem {
        MKMapItem(location: CLLocation(latitude: p.latitude, longitude: p.longitude), address: nil)
    }
}

/// Переход A → B картами Apple: линия, метры, секунды.
public struct RoadLeg: Equatable, Sendable {
    public let line: [MapCanvasCenter]
    public let meters: Double
    public let seconds: Double
    public init(line: [MapCanvasCenter], meters: Double, seconds: Double) {
        self.line = line
        self.meters = meters
        self.seconds = seconds
    }
}

/// Кусок картами Apple: `MKDirections` строит путь A → B, а не цепочку, и
/// кусок спрашивается переходами по одному, подряд (не разом — у Apple предел
/// частоты, `MKError.loadingThrottled`). Не ответил один переход — нет куска.
/// Переход кэшируется по паре точек и способу (справка 24а): точка в конце
/// куска спрашивает один новый переход, а не все заново. Сбой не кэшируется —
/// предел частоты проходит; сам кусок при сбое в сеансе не переспрашивают
/// (`RoadBook`, как веб).
@MainActor
public final class RoadLegs {
    public typealias Ask = @MainActor (RoadMode, MapCanvasCenter, MapCanvasCenter) async -> RoadLeg?

    public static let shared = RoadLegs { await RoadRouter.askAppleLeg(mode: $0, from: $1, to: $2) }

    private let ask: Ask
    private var cache: [String: RoadLeg] = [:]

    public init(ask: @escaping Ask) {
        self.ask = ask
    }

    public func run(mode: RoadMode, points: [MapCanvasCenter]) async -> RoadAnswer? {
        guard points.count >= 2 else { return nil }
        var line: [MapCanvasCenter] = []
        var meters = 0.0, seconds = 0.0
        for i in 0 ..< points.count - 1 {
            let key = mode.rawValue + "|" + RoadRouter.key([points[i], points[i + 1]])
            let got: RoadLeg?
            if let hit = cache[key] { got = hit } else { got = await ask(mode, points[i], points[i + 1]) }
            guard let leg = got else { return nil }
            cache[key] = leg
            line += line.isEmpty ? leg.line : Array(leg.line.dropFirst())
            meters += leg.meters
            seconds += leg.seconds
        }
        guard line.count >= 2 else { return nil }
        return RoadAnswer(line: line, km: meters / 1000, min: Int((seconds / 60).rounded()))
    }
}
