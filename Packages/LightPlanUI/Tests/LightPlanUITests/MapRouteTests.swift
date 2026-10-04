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

    private struct BarnaulGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: "Барнаул", region: nil, country: "Россия", zoneIdentifier: nil)
        }
    }

    /// Точка сразу после сдвига карты, пока имя нового места в пути, берёт
    /// прежнее — как `geoCity` веба, а не координаты (Алексей, 28.09).
    @Test func spotRightAfterPanTakesLastKnownCity() async {
        let app = AppModel(snapshot: Snapshot(), store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                           locator: Locator(), geocoder: BarnaulGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
        app.moveFromMap(latitude: 53.3480, longitude: 83.7760)
        await app.place.settled()
        #expect(app.routeAddHere().spot.name == "Барнаул")
        app.moveFromMap(latitude: 53.3550, longitude: 83.7900)
        #expect(app.place.isNameStale)
        let b = app.routeAddHere().spot
        #expect(b.name == "Барнаул 2" && b.named == true)
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

    /// Точка под визиром в наборе маршрута ловит тап наравне со всеми (веб
    /// `spotAtPoint(…, all = routeMode)`), и тап снимает её с черновика. Вне
    /// набора — нет: ехать некуда. Ревью 24а, № 1: булавку, поставленную под
    /// визиром, было не снять — тап уходил мимо и ставил её же заново.
    @Test func spotUnderSightIsTappableOnlyWhileRouting() {
        let (app, ids) = threeInRoute()
        let here = app.place.coordinate
        let under = app.spots.first { $0.coordinate.isSameSpot(as: here) }
        #expect(under?.id == ids[2])

        let routing = MapSpots.tappable(app.spots, here: here, routing: true).map(\.id)
        #expect(Set(routing) == Set(ids))
        let plain = MapSpots.tappable(app.spots, here: here, routing: false).map(\.id)
        #expect(Set(plain) == Set(ids[0 ..< 2]))

        #expect(app.routeToggle(id: ids[2]) == false)
        #expect(app.mapRoute == Array(ids[0 ..< 2]))
    }

    /// Новая точка сама гасит «Вернуть» (веб: `dropRouteUndo` внутри
    /// `routeNewSpot` и `routeToggle`): иначе «Вернуть» после неё заменило бы
    /// черновик прежним и молча стёрло новую точку. Ревью 24а, № 6.
    @Test func newPointDropsRouteUndo() {
        let (app, ids) = threeInRoute()
        app.clearRoute()
        app.routeAddHere()
        #expect(app.undo == nil)
        #expect(app.mapRoute.count == 1)

        app.clearRoute()
        app.routeToggle(id: ids[0])
        #expect(app.undo == nil)
        #expect(app.mapRoute == [ids[0]])
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

    @Test func serverUrlsProfilesAndAnswer() throws {
        let pts = RoadFx.pts
        #expect(RoadRouter.key(pts) == "83.77000,53.34000;83.78000,53.35123")
        let demo = try #require(RoadServers.osrmDemo.request(mode: .car, points: pts))
        #expect(demo.url?.absoluteString
                == "https://router.project-osrm.org/route/v1/driving/83.77000,53.34000;83.78000,53.35123?overview=full&geometries=geojson")
        #expect(demo.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("LightPlan/") == true)
        // У каждого запроса свой срок = срок сервера (3 / 3 / 4 с).
        #expect(demo.timeoutInterval == 3)
        #expect(RoadServers.fossgisOSRM.request(mode: .car, points: pts)?.timeoutInterval == 3)
        #expect(RoadServers.valhalla.request(mode: .foot, points: pts)?.timeoutInterval == 4)
        // Замер 04.10: у OSRM demo пешком = машина (3705,8 м и 286,8 с), пеший профиль не его.
        #expect(RoadServers.osrmDemo.request(mode: .foot, points: pts) == nil)
        #expect(RoadServers.fossgisOSRM.request(mode: .car, points: pts)?.url?.path.hasPrefix("/routed-car/") == true)
        #expect(RoadServers.fossgisOSRM.request(mode: .foot, points: pts)?.url?.path.hasPrefix("/routed-foot/") == true)
        for mode in [RoadMode.car, .foot] {
            let v = try #require(RoadServers.valhalla.request(mode: mode, points: pts)?.url)
            let json = try #require(URLComponents(url: v, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "json" }?.value)
            let body = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            #expect(v.host == "valhalla1.openstreetmap.de")
            #expect(body["costing"] as? String == (mode == .car ? "auto" : "pedestrian") && body["format"] as? String == "osrm")
            #expect(body["shape_format"] as? String == "geojson" && body["directions_type"] as? String == "none")
        }
        let answer = RoadRouter.parseOSRM(RoadFx.osrmBody)
        #expect(answer?.line.count == 3 && answer?.line[1].latitude == 53.345)
        #expect(answer?.km == 2.45 && answer?.min == 6)
        #expect(RoadRouter.parseOSRM(Data(#"{"code":"DistanceExceeded"}"#.utf8)) == nil)
    }

    /// Первый завис дольше таймаута → ходим ко второму; сам ответ второго берём.
    @Test func clientMovesToNextServerOnTimeout() async {
        let calls = RoadFx.Calls()
        let client = RoadClient(servers: [RoadFx.server("slow"), RoadFx.server("fast")], gap: .milliseconds(1)) { req in
            calls.add(req)
            if req.url?.host == "slow.test" { try await Task.sleep(for: .seconds(30)) }
            return (RoadFx.osrmBody, 200)
        }
        // Время меряем вне главного потока: он в этом наборе занят чужими тестами.
        let (got, took) = await Task.detached {
            let t0 = ContinuousClock.now
            let a = await client.ask(mode: .car, points: RoadFx.pts)
            return (a, ContinuousClock.now - t0)
        }.value
        #expect(got?.km == 2.45)
        #expect(calls.seen.count == 2 && calls.seen[0] == "slow.test" && calls.seen[1] == "fast.test")
        #expect(took < .seconds(2))   // ждали таймаут 0,2 с, а не зависший ответ (30 с)
    }

    /// Сервер молчит и не слушает отмену (как зависшее соединение): запрос
    /// кончается только по своему `timeoutInterval`, как у URLSession. Если срок
    /// не выставлен у запроса, переход к следующему ждёт его умолчание (60 с).
    @Test func silentServerThatIgnoresCancelDelaysNextByAtMostItsTimeoutPlusOneSecond() async {
        let slow = RoadServer(id: "mute", modes: [.car, .foot], timeout: 0.5) { _, _ in URLRequest(url: URL(string: "https://mute.test/r")!) }
        let client = RoadClient(servers: [slow, RoadFx.server("next")], gap: .milliseconds(1)) { req in
            if req.url?.host == "mute.test" {
                // Не отменяемое ожидание: continuation + таймер GCD, как сокет без отклика.
                await withCheckedContinuation { c in
                    DispatchQueue.global().asyncAfter(deadline: .now() + req.timeoutInterval) { c.resume() }
                }
                throw URLError(.timedOut)
            }
            return (RoadFx.osrmBody, 200)
        }
        let (got, took) = await Task.detached {
            let t0 = ContinuousClock.now
            let a = await client.ask(mode: .car, points: RoadFx.pts)
            return (a, ContinuousClock.now - t0)
        }.value
        #expect(got?.km == 2.45)
        #expect(took < .milliseconds(1500))   // срок 0,5 с + 1 с
    }

    /// Код не 200 и мусорный ответ — тоже «не ответил»: идём дальше.
    @Test func clientSkipsBadCodeAndGarbage() async {
        let calls = RoadFx.Calls()
        let client = RoadClient(servers: [RoadFx.server("a"), RoadFx.server("b"), RoadFx.server("c")], gap: .milliseconds(1)) { req in
            calls.add(req)
            switch req.url?.host {
            case "a.test": return (RoadFx.osrmBody, 503)
            case "b.test": return (Data("{}".utf8), 200)
            default: return (RoadFx.osrmBody, 200)
            }
        }
        #expect(await client.ask(mode: .car, points: RoadFx.pts) != nil)
        #expect(calls.seen.count == 3)
    }

    /// Отказали все: `nil` — ни линии, ни километров, ни минут.
    @Test func clientAnswersNothingWhenEveryServerFails() async {
        let calls = RoadFx.Calls()
        let client = RoadClient(servers: [RoadFx.server("a"), RoadFx.server("b", timeout: 0.05), RoadFx.server("c")],
                                gap: .milliseconds(1)) { req in
            calls.add(req)
            if req.url?.host == "b.test" { try await Task.sleep(for: .seconds(30)) }
            throw URLError(.notConnectedToInternet)
        }
        #expect(await client.ask(mode: .foot, points: RoadFx.pts) == nil)
        #expect(calls.seen.count == 3)
    }

    /// Пешком OSRM demo не спрашивается совсем, машина идёт к нему первому.
    @Test func footSkipsDemoServer() async {
        let calls = RoadFx.Calls()
        let client = RoadClient(servers: [RoadFx.server("demo", modes: [.car]), RoadFx.server("foot")],
                                gap: .milliseconds(1)) { req in calls.add(req); return (RoadFx.osrmBody, 200) }
        _ = await client.ask(mode: .foot, points: RoadFx.pts)
        #expect(calls.seen.count == 1 && calls.seen[0] == "foot.test")
    }

    /// Не чаще одного запроса в секунду на сервер: три подряд встают в очередь
    /// с зазором (тут 0,6 с; пределы широкие — полный прогон грузит процессор).
    @Test func throttleSpacesRequestsPerServer() async {
        let t = RoadThrottle(gap: .milliseconds(600))
        let t0 = ContinuousClock.now
        await t.wait("s"); await t.wait("s"); await t.wait("s")
        #expect(ContinuousClock.now - t0 >= .milliseconds(1190))
        let t1 = ContinuousClock.now
        await t.wait("other")                      // другой сервер своя очередь
        #expect(ContinuousClock.now - t1 < .milliseconds(500))
    }

    /// Итог для полосы: отказ — «недоступен», а не недостающая сумма; линия
    /// отказавшего куска пуста, у спрашиваемого — прямая, у ответившего — дорога.
    @Test func totalsAndLinesForFailedRuns() async throws {
        let a = RouteRun(mode: .car, points: RoadFx.pts)
        let b = RouteRun(mode: .foot, points: Array(RoadFx.pts.reversed()))
        let ok = RoadAnswer(line: RoadFx.pts, km: 2, min: 5)
        let book = RoadBook { _, run in run.mode == .car ? ok : nil }
        #expect(book.total(.mapLibre, [a, b]) == .pending)
        #expect(book.total(.mapLibre, []) == .none)
        book.ask(.mapLibre, [a, b])
        for _ in 0 ..< 200 where book.total(.mapLibre, [a, b]) == .pending {   // дебаунс 400 мс + ответ
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(book.total(.mapLibre, [a]) == .ready(km: 2, min: 5))
        #expect(book.total(.mapLibre, [a, b]) == .unavailable)
        let roads = [book.answer(.mapLibre, a), book.answer(.mapLibre, b), nil]
        let lines = RoutePathLayer.lines(runs: [a, b, a], roads: roads)
        #expect(lines[0] == RoadFx.pts && lines[1].isEmpty && lines[2] == RoadFx.pts)
        #expect(lines[1].isEmpty)
    }

    // MARK: - Ревью 24а (шаг 1 итерации 25)

    /// № 3: у карт Apple кусок собирается из переходов, и переход кэшируется по
    /// паре точек и способу (справка 24а): точка в конце куска спрашивает один
    /// новый переход, а не все заново — 8 точек по одной стоили 28 запросов
    /// вместо 7. Сбой не кэшируется: предел частоты Apple проходит.
    @Test func appleLegsAreCachedByPairAndFailuresAreNot() async {
        var calls: [String] = [], fail = false
        let legs = RoadLegs { mode, a, b in
            calls.append("\(mode.rawValue) \(a.latitude)>\(b.latitude)")
            if fail { return nil }
            return RoadLeg(line: [a, b], meters: 1000, seconds: 60)
        }
        let p = [53.30, 53.31, 53.32, 53.33].map { MapCanvasCenter(latitude: $0, longitude: 83.7) }
        let two = await legs.run(mode: .car, points: Array(p[0 ..< 2]))
        #expect(two?.km == 1 && two?.line.count == 2)
        let three = await legs.run(mode: .car, points: Array(p[0 ..< 3]))
        #expect(three?.km == 2 && three?.min == 2 && three?.line.count == 3)
        #expect(calls.count == 2)
        // Пешком — другой вопрос.
        _ = await legs.run(mode: .foot, points: Array(p[0 ..< 2]))
        #expect(calls.count == 3)
        // Отказ перехода: куска нет, и в кэш ничего не легло.
        fail = true
        #expect(await legs.run(mode: .car, points: Array(p[2 ..< 4])) == nil)
        fail = false
        #expect(await legs.run(mode: .car, points: Array(p[2 ..< 4]))?.km == 1)
        #expect(calls.count == 5)
    }

    /// Ревью GPT к 4224ce1: два куска разом (точку добавили, пока первый ещё
    /// ждёт Apple) не спрашивают общий переход дважды — второй ждёт летящий
    /// ответ. Предел частоты Apple считает каждый запрос. Первый ответ держим,
    /// пока второй кусок не дошёл до своего первого перехода, — без опоры на
    /// время (второе ревью GPT, к d367a6a).
    @Test func concurrentRunsShareTheLegInFlight() async {
        var calls: [String] = []
        var hold: CheckedContinuation<Void, Never>?
        let legs = RoadLegs { mode, a, b in
            calls.append("\(mode.rawValue) \(a.latitude)>\(b.latitude)")
            if calls.count == 1 { await withCheckedContinuation { hold = $0 } }
            return RoadLeg(line: [a, b], meters: 1000, seconds: 60)
        }
        let p = [53.30, 53.31, 53.32].map { MapCanvasCenter(latitude: $0, longitude: 83.7) }
        let two = Task { await legs.run(mode: .car, points: Array(p[0 ..< 2])) }
        while hold == nil { await Task.yield() }
        let three = Task { await legs.run(mode: .car, points: p) }
        for _ in 0 ..< 50 { await Task.yield() }
        hold?.resume()
        let (a, b) = (await two.value, await three.value)
        #expect(a?.km == 1 && b?.km == 2)
        #expect(calls.count == 2)   // A→B и B→C — по разу
    }

    /// № 2: набранное имя пишется своей точке. Тап по другой булавке, пока
    /// поле в фокусе, сперва записывает имя прежней (у веба `blur` раньше
    /// `openSpotName`), а уход фокуса после этого не пишет новую точку и не
    /// закрывает её тихую полосу.
    @Test func typedNameGoesToItsOwnSpotWhenAnotherPinIsTapped() {
        var bar = SpotNameDraft()
        #expect(bar.open("A", focused: false, keyboard: true) == nil)
        bar.focus()
        bar.text = "Мост"
        let r = bar.open("B", focused: true, keyboard: false)
        #expect(r == .init(id: "A", name: "Мост"))
        #expect(bar.blur() == nil)
        #expect(bar.spot == "B")
        // Уход фокуса у своей полосы пишет её точке и закрывает полосу.
        bar.focus()
        bar.text = "Ресторан"
        #expect(bar.blur() == .init(id: "B", name: "Ресторан"))
        #expect(bar.spot == nil)
    }

    /// № 4: булавка садится один раз. Постановка свежа, пока идёт движение
    /// (`SpotLanding.total`); вернувшаяся на кадр позже — стоит (у веба класс
    /// `land` снимается по `animationend`).
    @Test func landedPinDoesNotLandAgainWhenItComesBack() {
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        let m = SpotLandingMark(id: "A", tick: 3, at: t0)
        #expect(m.tick(for: "A", now: t0.addingTimeInterval(0.1)) == 3)
        #expect(m.tick(for: "B", now: t0.addingTimeInterval(0.1)) == 0)
        #expect(m.tick(for: "A", now: t0.addingTimeInterval(SpotLanding.total + 0.1)) == 0)
    }
}

/// Общее для тестов маршрутизатора; вне `@MainActor`, чтобы замыкания клиента
/// читали это из любого потока.
private enum RoadFx {
    static let pts = [MapCanvasCenter(latitude: 53.34, longitude: 83.77),
                      MapCanvasCenter(latitude: 53.35123456, longitude: 83.78)]
    static let osrmBody = Data("""
        {"routes":[{"geometry":{"coordinates":[[83.77,53.34],[83.775,53.345],[83.78,53.35]]},
        "distance":2450,"duration":389}]}
        """.utf8)

    static func server(_ id: String, timeout: TimeInterval = 0.2, modes: Set<RoadMode> = [.car, .foot]) -> RoadServer {
        RoadServer(id: id, modes: modes, timeout: timeout) { _, _ in URLRequest(url: URL(string: "https://\(id).test/r")!) }
    }

    /// Кто и в каком порядке спрошен.
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var hosts: [String] = []
        var seen: [String] { lock.lock(); defer { lock.unlock() }; return hosts }
        func add(_ r: URLRequest) { lock.lock(); hosts.append(r.url?.host ?? ""); lock.unlock() }
    }
}
