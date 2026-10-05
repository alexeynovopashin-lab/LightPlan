import Testing
import Foundation
@testable import LightPlanData
@testable import LightPlanCore

// MARK: - Подставные пути

private actor Path: WeatherSource {
    struct Boom: Error {}
    enum Mode: Sendable { case ok(Double), fail, hang }
    var mode: Mode
    private(set) var calls = 0
    init(_ mode: Mode) { self.mode = mode }
    func set(_ m: Mode) { mode = m }

    func fetchHourly(at place: Place) async throws -> HourlyWeather {
        calls += 1
        switch mode {
        case .ok(let c): return forecast(cloud: c)
        case .fail: throw Boom()
        case .hang: try await Task.sleep(for: .seconds(3600)); throw Boom()
        }
    }

    func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] {
        _ = try await fetchHourly(at: place)
        return [:]
    }
}

private func forecast(cloud: Double) -> HourlyWeather {
    let time = (0..<24).map { "2026-06-10T" + String(format: "%02d", $0) + ":00" }
    return HourlyWeather(time: time, cloud: Array(repeating: cloud, count: 24), temperature: Array(repeating: 10, count: 24),
                         windSpeed: Array(repeating: 2, count: 24), precipitation: Array(repeating: 0, count: 24),
                         weatherCode: Array(repeating: 0, count: 24))
}

private actor Waits {
    private(set) var asked: [Duration] = []
    func note(_ d: Duration) { asked.append(d) }
}

private let spot = Place(latitude: 56.011, longitude: 37.483, zone: ZoneID(fixedOffsetHours: 3))

/// Режим и состояние детектора, которыми тест переставляет решение на лету.
private final class Policy: @unchecked Sendable {
    private let lock = NSLock()
    private var p: NetworkPolicy
    init(_ p: NetworkPolicy) { self.p = p }
    func set(_ m: NetworkMode? = nil, _ f: ForeignReach? = nil) {
        lock.lock(); if let m { p.mode = m }; if let f { p.foreign = f }; lock.unlock()
    }
    var value: NetworkPolicy { lock.lock(); defer { lock.unlock() }; return p }
}

private func routed(direct: Path, proxy: Path, policy: Policy, waits: Waits? = nil,
                    sleep: (@Sendable (Duration) async throws -> Void)? = nil) -> RoutedWeatherSource {
    let wait: @Sendable (Duration) async throws -> Void = sleep ?? { d in
        await waits?.note(d)
        try await Task.sleep(for: .seconds(3600))
    }
    return RoutedWeatherSource(direct: direct, proxy: proxy, sleep: wait, policy: { policy.value })
}

// MARK: - Авто выбирает путь по состоянию детектора

struct NetworkPolicyRoutingTests {

    @Test("Авто, зарубежное недоступно: сразу наш сервер, прямой не спрашивается и срока не ждём")
    func autoUnreachableGoesStraightToOurServer() async throws {
        let direct = Path(.hang), proxy = Path(.ok(7))
        let waits = Waits()
        let s = routed(direct: direct, proxy: proxy, policy: Policy(.init(mode: .auto, foreign: .unreachable)), waits: waits)
        let (_, origin) = try await s.fetchHourlyWithOrigin(at: spot)
        #expect(origin == .proxy)
        #expect(await direct.calls == 0)
        #expect(await proxy.calls == 1)
        #expect(await waits.asked.isEmpty)
    }

    @Test("Авто, зарубежное доступно: прямой; прежняя отметка «ходим через сервер» забыта")
    func autoReachableGoesDirectAndForgetsTheOldMark() async throws {
        let direct = Path(.fail), proxy = Path(.ok(7))
        let policy = Policy(.init(mode: .auto, foreign: .unknown))
        let s = routed(direct: direct, proxy: proxy, policy: policy, sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        // Прямой отказал при неизвестном состоянии → отметка «через сервер».
        _ = try await s.fetchHourlyWithOrigin(at: spot)
        #expect(await s.preferred == .proxy)
        let proxyBefore = await proxy.calls
        // Детектор увидел, что зарубежное открыто, и прямой ожил.
        await direct.set(.ok(3))
        policy.set(nil, .reachable)
        let (w, origin) = try await s.fetchHourlyWithOrigin(at: spot)
        #expect(origin == .direct)
        #expect(w.cloud.first == 3)
        #expect(await proxy.calls == proxyBefore)
        #expect(await s.preferred == .direct)
    }

    @Test("Авто, зарубежное недоступно, но наш сервер молчит: остаётся прямой — со сроком")
    func autoUnreachableFallsBackToDirect() async throws {
        let direct = Path(.ok(3)), proxy = Path(.fail)
        let s = routed(direct: direct, proxy: proxy, policy: Policy(.init(mode: .auto, foreign: .unreachable)))
        let (_, origin) = try await s.fetchHourlyWithOrigin(at: spot)
        #expect(origin == .direct)
        #expect(await proxy.calls == 1)
    }

    @Test("Авто, неизвестно: как до детектора — прямой со сроком 4 с, не ответил — наш сервер")
    func autoUnknownKeepsTheOldBehaviour() async throws {
        let direct = Path(.hang), proxy = Path(.ok(7))
        let waits = Waits()
        let s = routed(direct: direct, proxy: proxy, policy: Policy(.init(mode: .auto, foreign: .unknown)),
                       sleep: { d in await waits.note(d) })
        let (_, origin) = try await s.fetchHourlyWithOrigin(at: spot)
        #expect(origin == .proxy)
        #expect(await direct.calls == 1)
        #expect(await waits.asked == [.seconds(4)])
    }

    // MARK: Только напрямую

    @Test("Только напрямую: наш сервер не спрашивается ни при каком состоянии; ответ прямого — как есть")
    func directOnlyNeverCallsOurServer() async throws {
        for foreign in [ForeignReach.unknown, .reachable, .unreachable] {
            let direct = Path(.ok(3)), proxy = Path(.ok(7))
            let s = routed(direct: direct, proxy: proxy, policy: Policy(.init(mode: .directOnly, foreign: foreign)))
            let (w, origin) = try await s.fetchHourlyWithOrigin(at: spot)
            #expect(origin == .direct)
            #expect(w.cloud.first == 3)
            #expect(await proxy.calls == 0)
        }
    }

    @Test("Только напрямую: прямой отказал — отказ уходит наверх, наш сервер молчит (без имитации)")
    func directOnlyFailureIsHonest() async throws {
        let direct = Path(.fail), proxy = Path(.ok(7))
        let s = routed(direct: direct, proxy: proxy, policy: Policy(.init(mode: .directOnly, foreign: .unreachable)))
        await #expect(throws: Path.Boom.self) { _ = try await s.fetchHourlyWithOrigin(at: spot) }
        await #expect(throws: Path.Boom.self) { _ = try await s.fetchAirWithOrigin(at: spot) }
        #expect(await proxy.calls == 0)
        #expect(await s.preferred == .direct)
    }

    @Test("Режим переставляется на лету: следующий запрос уже идёт по новому")
    func modeChangesBetweenRequests() async throws {
        let direct = Path(.fail), proxy = Path(.ok(7))
        let policy = Policy(.init(mode: .auto, foreign: .unreachable))
        let s = routed(direct: direct, proxy: proxy, policy: policy)
        #expect(try await s.fetchHourlyWithOrigin(at: spot).1 == .proxy)
        policy.set(.directOnly)
        await #expect(throws: Path.Boom.self) { _ = try await s.fetchHourlyWithOrigin(at: spot) }
        #expect(await proxy.calls == 1)
    }

    @Test("Источник без политики ведёт себя как «Авто, неизвестно» — прежние пути не сломаны")
    func defaultPolicyIsAutoUnknown() async {
        #expect(NetworkPolicy() == NetworkPolicy(mode: .auto, foreign: .unknown))
    }
}

// MARK: - Читалка

struct PolicyPinterestReaderTests {

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        func hit() { lock.lock(); n += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    private func reader(_ mode: NetworkMode, calls: Calls) -> PolicyPinterestReader {
        let client = PinterestClient(config: PinterestConfig(url: URL(string: "https://example.test/fn")!, key: "K")) { req in
            calls.hit()
            let body = req.url!.absoluteString.contains("board=") ? "{\"pins\":[]}" : "x"
            return (Data(body.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        return PolicyPinterestReader(client) { NetworkPolicy(mode: mode, foreign: .unreachable) }
    }

    @Test("Только напрямую: ни доска, ни картинка, ни превью не уходят на наш сервер")
    func directOnlyNeverTouchesTheServer() async {
        let calls = Calls()
        let r = reader(.directOnly, calls: calls)
        await #expect(throws: PinterestFailure.serverOff) { _ = try await r.board(link: "https://pin.it/a") }
        await #expect(throws: PinterestFailure.serverOff) { _ = try await r.image(at: "https://i.pinimg.com/a.jpg") }
        await #expect(throws: PinterestFailure.serverOff) { _ = try await r.preview(of: "https://pin.it/a") }
        #expect(calls.count == 0)
    }

    @Test("Авто: читалка ходит через наш сервер при любом состоянии зарубежного — другого пути у неё нет")
    func autoUsesTheServer() async throws {
        let calls = Calls()
        let r = reader(.auto, calls: calls)
        _ = try await r.board(link: "https://pin.it/a")
        _ = try await r.image(at: "https://i.pinimg.com/a.jpg")
        _ = try await r.preview(of: "https://pin.it/a")
        #expect(calls.count == 3)
    }

    @Test("Отказ режима — системный: очередь закачки не мучает сервер повторами")
    func serverOffIsSystemic() {
        #expect(PinterestFailure.serverOff.isSystemic)
        #expect(!PinterestFailure.serverOff.isTransient)
    }
}
