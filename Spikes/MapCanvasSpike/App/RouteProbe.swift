import Foundation
import MapKit

/// Замер маршрутов Apple. Вопрос один: заменяет ли `MKDirections` ту пару
/// сервисов, на которой живёт веб (демо-OSRM для машины, Valhalla для троп).
/// Считается съёмочный день Томска: три городские точки и дальняя природная.
/// Отрезки считаются по очереди — путевых точек `MKDirections` не знает вовсе,
/// один запрос это всегда «отсюда досюда».
@MainActor
@Observable
final class RouteProbe {
    struct Leg: Identifiable {
        let id = UUID()
        let name: String
        let mode: String
        var km: Double?
        var min: Int?
        var error: String?
    }

    private(set) var legs: [Leg] = []
    private(set) var running = false
    private(set) var elapsed: Double = 0

    private let points: [(String, CLLocationCoordinate2D)] = [
        ("Лагерный сад",        .init(latitude: 56.4515, longitude: 84.9536)),
        ("Губернаторский",      .init(latitude: 56.4847, longitude: 84.9482)),
        ("Белое озеро",         .init(latitude: 56.4931, longitude: 84.9723)),
        ("Таловские чаши",      .init(latitude: 56.2350, longitude: 84.9840))
    ]

    func run() async {
        guard !running else { return }
        running = true
        legs = []
        let t0 = Date()
        for mode in [("машина", MKDirectionsTransportType.automobile),
                     ("пешком", MKDirectionsTransportType.walking)] {
            for i in 0..<(points.count - 1) {
                let a = points[i], b = points[i + 1]
                var leg = Leg(name: "\(a.0) → \(b.0)", mode: mode.0)
                let req = MKDirections.Request()
                req.source = MKMapItem(placemark: MKPlacemark(coordinate: a.1))
                req.destination = MKMapItem(placemark: MKPlacemark(coordinate: b.1))
                req.transportType = mode.1
                req.requestsAlternateRoutes = false
                do {
                    let resp = try await MKDirections(request: req).calculate()
                    if let r = resp.routes.first {
                        leg.km = r.distance / 1000
                        leg.min = Int((r.expectedTravelTime / 60).rounded())
                    } else {
                        leg.error = "пусто"
                    }
                } catch {
                    let ns = error as NSError
                    leg.error = "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
                }
                legs.append(leg)
            }
        }
        elapsed = Date().timeIntervalSince(t0)
        running = false
    }
}
