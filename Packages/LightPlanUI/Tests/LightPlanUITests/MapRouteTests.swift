import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

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
}

