import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData
import LightPlanMapCanvas

/// Итерация 24а, черновик маршрута «Карты»: набор тапом (`routeNewSpot`),
/// тап по булавке (`routeToggle`), номера, `mapRoute` снимка — ключ веба, и
/// черновик переживает перезапуск.
@MainActor
struct MapRouteTests {

    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class Locator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    private func model(_ snapshot: Snapshot = Snapshot(), store: Store? = nil) -> AppModel {
        AppModel(snapshot: snapshot, store: store, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                 locator: Locator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
    }

    @Test func tapAddsNewSpotUnderHeadThenSavedOneWithoutDuplicates() {
        let app = model()
        app.moveFromMap(latitude: 53.3480, longitude: 83.7760)
        let a = app.routeAddHere(now: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(a.isNew)
        #expect(app.spots.count == 1 && app.spots[0].id == a.spot.id)
        #expect(app.spots[0].pinned == true)
        #expect(app.mapRoute == [a.spot.id])
        // Под головкой уже сохранённое — новое не заводится, дважды не встаёт.
        let again = app.routeAddHere()
        #expect(!again.isNew && again.spot.id == a.spot.id)
        #expect(app.spots.count == 1 && app.mapRoute == [a.spot.id])
        app.moveFromMap(latitude: 53.3550, longitude: 83.7900)
        let b = app.routeAddHere(now: Date(timeIntervalSince1970: 1_790_000_100))
        #expect(b.isNew && app.mapRoute == [a.spot.id, b.spot.id])
        #expect(app.routeNumber(of: a.spot.id) == 1 && app.routeNumber(of: b.spot.id) == 2)
        // Новое место — первым в «Моих местах», в черновике — последним.
        #expect(app.spots.first?.id == b.spot.id)
    }

    @Test func pinTapTogglesAndNumbersFollowLiveSpots() {
        var snap = Snapshot()
        snap.spots = [Spot(id: "a", name: "A", latitude: 53.34, longitude: 83.77),
                      Spot(id: "b", name: "B", latitude: 53.35, longitude: 83.78),
                      Spot(id: "c", name: "C", latitude: 53.36, longitude: 83.79)]
        let app = model(snap)
        #expect(app.routeToggle(id: "c"))
        #expect(app.routeToggle(id: "a"))
        #expect(app.mapRoute == ["c", "a"])
        #expect(!app.routeToggle(id: "c"))
        #expect(app.mapRoute == ["a"])
        #expect(app.routeToggle(id: "b"))
        // Удалённое место черновик переживает, но номера не занимает.
        app.removeSpot(id: "a")
        #expect(app.mapRoute == ["a", "b"])
        #expect(app.routeSpots.map(\.id) == ["b"])
        #expect(app.routeNumber(of: "b") == 1 && app.routeNumber(of: "a") == nil)
    }

    /// Файл веба: `mapRoute` — массив строк, прочие ключи не трогаются.
    @Test func readsWebKeyAndSurvivesRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-24a-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir, debounce: .milliseconds(1))
        var snap = Snapshot()
        snap.spots = [Spot(id: "a", name: "A", latitude: 53.34, longitude: 83.77),
                      Spot(id: "b", name: "B", latitude: 53.35, longitude: 83.78)]
        snap.extra["mapRoute"] = .array([.string("b")])
        snap.extra["mapWalk"] = .object(["b>a": .number(1)])
        let first = model(snap, store: store)
        #expect(first.mapRoute == ["b"])
        first.routeToggle(id: "a")
        await first.flush()
        let second = model(try await store.load(), store: store)
        #expect(second.mapRoute == ["b", "a"])
        #expect(second.snapshotForTests.extra["mapWalk"] == .object(["b>a": .number(1)]))
    }

    // MARK: - Шаг 2: полоса

    /// Три места Барнаула в черновике, по 1 км друг от друга.
    private func threeInRoute() -> (AppModel, [String]) {
        let app = model()
        var ids: [String] = []
        for (i, lat) in [53.3480, 53.3570, 53.3660].enumerated() {
            app.moveFromMap(latitude: lat, longitude: 83.7760)
            ids.append(app.routeAddHere(now: Date(timeIntervalSince1970: 1_790_000_000 + Double(i))).spot.id)
        }
        return (app, ids)
    }

    @Test func walkIsKeyedByPairLikeTheWeb() {
        let (app, ids) = threeInRoute()
        #expect(!app.isWalk(from: ids[0], to: ids[1]))
        app.toggleWalk(from: ids[0], to: ids[1])
        #expect(app.isWalk(from: ids[0], to: ids[1]))
        #expect(!app.isWalk(from: ids[1], to: ids[2]))
        guard case .object(let o)? = app.snapshot.extra["mapWalk"] else { Issue.record("нет mapWalk"); return }
        #expect(o == [ids[0] + ">" + ids[1]: .number(1)])
        app.toggleWalk(from: ids[0], to: ids[1])
        #expect(app.mapWalk.isEmpty)
    }

    @Test func clearOffersUndoAndUndoReturnsOnlyLiveSpots() {
        let (app, ids) = threeInRoute()
        app.clearRoute()
        #expect(app.mapRoute.isEmpty && app.spots.count == 3)
        #expect(app.undo?.isRoute == true)
        #expect(app.undo?.text == "Маршрут снят · 3 точки")
        // Место удалили, пока висела полоса, — возвращаются только живые.
        app.snapshot.spots.removeAll { $0.id == ids[1] }
        app.takeUndo()
        #expect(app.mapRoute == [ids[0], ids[2]])
        #expect(app.undo == nil)
    }

    @Test func newPointDropsRouteUndo() {
        let (app, _) = threeInRoute()
        app.clearRoute()
        app.dropRouteUndo()
        #expect(app.undo == nil)
    }

    @Test func makeShootPutsSpotsInOrderWithoutHoursAndKeepsDraft() {
        let (app, ids) = threeInRoute()
        app.toggleWalk(from: ids[1], to: ids[2])
        app.lastFormGenre = .wedding
        let day = CivilDate(year: 2026, month: 10, day: 3)
        #expect(app.makeRouteShoot(day: day, minute: 600))
        guard let f = app.form else { Issue.record("форма не открылась"); return }
        #expect(f.genre == .wedding)
        #expect(f.route.map(\.spotId) == ids)
        #expect(f.route.allSatisfy { $0.start == nil && $0.end == nil && $0.name.isEmpty })
        #expect(f.route.map(\.walk) == [false, true, false])
        #expect(f.sessionPlace.latitude == app.spots.first { $0.id == ids[0] }?.latitude)
        #expect(app.mapRoute == ids)
    }

    @Test func kmBetweenMatchesHaversine() {
        let a = GeoCoordinate(latitude: 53.3480, longitude: 83.7760)
        let b = GeoCoordinate(latitude: 53.3570, longitude: 83.7760)
        #expect(abs(kmBetween(a, b) - 1.00075) < 0.0001)
    }

    // MARK: шаг 3 — дорога и перестановка

    private func fourSpots() -> Snapshot {
        var snap = Snapshot()
        snap.spots = [Spot(id: "a", name: "A", latitude: 53.34, longitude: 83.77),
                      Spot(id: "b", name: "B", latitude: 53.35, longitude: 83.78),
                      // «c» в той же точке, что «b»: не переезд (`sameSpot`).
                      Spot(id: "c", name: "C", latitude: 53.3502, longitude: 83.7803),
                      Spot(id: "d", name: "D", latitude: 53.36, longitude: 83.79),
                      Spot(id: "e", name: "E", latitude: 53.37, longitude: 83.80)]
        snap.extra["mapRoute"] = .array(["a", "b", "c", "d", "e"].map { .string($0) })
        return snap
    }

    @Test func runsSplitByWayAndSkipSamePlace() {
        let app = model(fourSpots())
        // Всё на колёсах — один кусок, «c» на месте «b» не рвёт его.
        #expect(app.routeRuns.count == 1)
        #expect(app.routeRuns[0].mode == .car && app.routeRuns[0].points.count == 4)
        // d → e пешком: смена способа рвёт кусок.
        app.toggleWalk(from: "d", to: "e")
        let runs = app.routeRuns
        #expect(runs.map(\.mode) == [.car, .foot])
        #expect(runs[0].points.count == 3 && runs[1].points.count == 2)
        #expect(runs[1].points[0] == runs[0].points.last)
    }

    @Test func moveKeepsDeletedIdsInPlace() {
        var snap = fourSpots()
        snap.extra["mapRoute"] = .array(["a", "gone", "b", "d"].map { .string($0) })
        let app = model(snap)
        #expect(app.routeSpots.map(\.id) == ["a", "b", "d"])
        app.moveRoute(from: 2, to: 0)
        #expect(app.routeSpots.map(\.id) == ["d", "a", "b"])
        #expect(app.mapRoute == ["d", "gone", "a", "b"])
        app.moveRoute(from: 0, to: 2)
        #expect(app.routeSpots.map(\.id) == ["a", "b", "d"])
        app.moveRoute(from: 1, to: 1)
        app.moveRoute(from: 0, to: 9)
        #expect(app.routeSpots.map(\.id) == ["a", "b", "d"])
    }

    @Test func webRouterUrlsAndAnswerMatchTheWeb() throws {
        let pts = [MapCanvasCenter(latitude: 53.34, longitude: 83.77),
                   MapCanvasCenter(latitude: 53.35123456, longitude: 83.78)]
        #expect(RoadRouter.key(pts) == "83.77000,53.34000;83.78000,53.35123")
        #expect(RoadRouter.webURL(mode: .car, points: pts)?.absoluteString
                == "https://router.project-osrm.org/route/v1/driving/83.77000,53.34000;83.78000,53.35123?overview=full&geometries=geojson")
        let foot = try #require(RoadRouter.webURL(mode: .foot, points: pts))
        let json = try #require(URLComponents(url: foot, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "json" }?.value)
        let body = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(foot.host == "valhalla1.openstreetmap.de")
        #expect(body["costing"] as? String == "pedestrian" && body["format"] as? String == "osrm")
        #expect(body["shape_format"] as? String == "geojson" && body["directions_type"] as? String == "none")
        let answer = RoadRouter.parseOSRM(Data("""
            {"routes":[{"geometry":{"coordinates":[[83.77,53.34],[83.775,53.345],[83.78,53.35]]},
            "distance":2450,"duration":389}]}
            """.utf8))
        #expect(answer?.line.count == 3 && answer?.line[1].latitude == 53.345)
        #expect(answer?.km == 2.45 && answer?.min == 6)
        #expect(RoadRouter.parseOSRM(Data(#"{"code":"DistanceExceeded"}"#.utf8)) == nil)
    }
}
