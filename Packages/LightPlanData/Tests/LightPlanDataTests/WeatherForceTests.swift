import Testing
import Foundation
@testable import LightPlanData
@testable import LightPlanCore

/// Источник с переключателями: прогноз вкл/выкл, облачность задаётся, ответ
/// можно придержать («в пути»), вопросы считаются.
private actor ForceSource: WeatherSource {
    struct Down: Error {}
    private(set) var hourlyUp: Bool
    private(set) var hourlyCalls = 0
    private(set) var airCalls = 0
    private var cloud: Double = 10
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(hourly: Bool) { hourlyUp = hourly }
    func set(hourly: Bool? = nil, cloud: Double? = nil) {
        if let hourly { hourlyUp = hourly }
        if let cloud { self.cloud = cloud }
    }
    func hold() { held = true }
    func release() { held = false; waiters.forEach { $0.resume() }; waiters = [] }

    func fetchHourly(at place: Place) async throws -> HourlyWeather {
        hourlyCalls += 1
        let c = cloud + place.latitude
        if held { await withCheckedContinuation { waiters.append($0) } }
        guard hourlyUp else { throw Down() }
        return forceDay(cloud: c)
    }

    func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] {
        airCalls += 1
        let d = CivilDate(year: 2026, month: 6, day: 10)
        return [d: Dictionary(uniqueKeysWithValues: (0..<24).map { ($0, AirSample(aod: 0.5, dust: 0)) })]
    }
}

private func forceDay(cloud: Double) -> HourlyWeather {
    let time = (0..<24).map { "2026-06-10T" + String(format: "%02d", $0) + ":00" }
    return HourlyWeather(time: time, cloud: Array(repeating: cloud, count: 24), temperature: Array(repeating: 10, count: 24),
                         windSpeed: Array(repeating: 2, count: 24), precipitation: Array(repeating: 0, count: 24),
                         weatherCode: Array(repeating: 0, count: 24))
}

/// Часы, которые двигает тест: 10 секунд между запросами меряются ими.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_780_000_000)
    var date: Date { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ s: TimeInterval) { lock.lock(); t += s; lock.unlock() }
}

/// Сеть, которой управляет тест.
private final class FakeNet: NetworkReachability, @unchecked Sendable {
    private var continuation: AsyncStream<Bool>.Continuation?
    func updates() -> AsyncStream<Bool> { AsyncStream { continuation = $0 } }
    func send(_ up: Bool) { continuation?.yield(up) }
}

private let june10 = CivilDate(year: 2026, month: 6, day: 10)
private let a = Place(latitude: 20, longitude: 30, zone: ZoneID(fixedOffsetHours: 3))
private let b = Place(latitude: 40, longitude: 50, zone: ZoneID(fixedOffsetHours: 3))

@MainActor private func until(_ cond: () async -> Bool) async -> Bool {
    for _ in 0..<200 { if await cond() { return true }; try? await Task.sleep(for: .milliseconds(10)) }
    return false
}

@MainActor private func quiet() async { try? await Task.sleep(for: .milliseconds(80)) }

@MainActor
struct WeatherForceTests {
    private func make(_ source: ForceSource, net: FakeNet? = nil, clock: TestClock = TestClock()) -> (WeatherStore, TestClock) {
        let store = WeatherStore(place: a, source: source, debounce: .zero, retryDelays: [.seconds(600)],
                                 now: { clock.date }, reachability: net)
        return (store, clock)
    }

    // MARK: - Сеть вернулась

    @Test("Сеть вернулась, прогноза нет — запрос сразу, мимо таймера")
    func networkReturnAsksAtOnce() async {
        let source = ForceSource(hourly: false)
        let net = FakeNet()
        let (store, _) = make(source, net: net)
        await store.settled()
        net.send(false)                       // самолётный режим
        #expect(store.status == .unavailable)
        await source.set(hourly: true)
        net.send(true)                        // выключили
        #expect(await until { store.isLive })
        #expect(await source.hourlyCalls == 2)
    }

    @Test("Первое значение потока — точка отсчёта: сеть «есть» с самого начала запроса не вызывает")
    func firstValueIsOnlyABaseline() async {
        let source = ForceSource(hourly: false)
        let net = FakeNet()
        let (store, _) = make(source, net: net)
        await store.settled()
        net.send(true)
        await quiet()
        #expect(await source.hourlyCalls == 1)
        #expect(store.status == .unavailable)
    }

    @Test("Прогноз свежий — возврат сети ничего не спрашивает")
    func networkReturnWithFreshForecastIsQuiet() async {
        let source = ForceSource(hourly: true)
        let net = FakeNet()
        let (store, _) = make(source, net: net)
        await store.settled()
        net.send(false); net.send(true)
        await quiet()
        #expect(await source.hourlyCalls == 1)
    }

    @Test("Прогноз просрочен — возврат сети спрашивает сразу, старый держится до ответа")
    func networkReturnWithExpiredForecastAsks() async {
        let source = ForceSource(hourly: true)
        let net = FakeNet()
        let (store, clock) = make(source, net: net)
        await store.settled()
        clock.advance(3601)
        await source.set(cloud: 50); await source.hold()
        net.send(false); net.send(true)
        #expect(await until { await source.hourlyCalls == 2 })
        #expect(store.day(for: june10)?.cloud == 30, "пока новый в пути, на экране старый")
        await source.release()
        #expect(await until { store.day(for: june10)?.cloud == 70 })
    }

    @Test("Сеть появилась при идущем запросе — второй не начинается")
    func networkReturnDuringARequestDoesNotDouble() async {
        let source = ForceSource(hourly: true)
        await source.hold()
        let net = FakeNet()
        let (store, clock) = make(source, net: net)
        #expect(await until { await source.hourlyCalls == 1 })
        net.send(false)
        clock.advance(30)                     // окно 10 с не мешает: мешает только идущий запрос
        net.send(true)
        await quiet()
        #expect(await source.hourlyCalls == 1)
        await source.release()
        #expect(await until { store.isLive })
    }

    @Test("Сеть мигает быстрее 10 секунд — один запрос")
    func flappingNetworkMakesOneRequest() async {
        let source = ForceSource(hourly: false)
        let net = FakeNet()
        let (store, _) = make(source, net: net)
        await store.settled()
        for _ in 0..<4 {
            net.send(false); net.send(true)
            await quiet()
        }
        #expect(await source.hourlyCalls == 2, "первый + один на всё мигание")
        #expect(store.status == .unavailable)
    }

    @Test("Мигание через 10 секунд и позже — снова запрос")
    func networkAfterTheWindowAsksAgain() async {
        let source = ForceSource(hourly: false)
        let net = FakeNet()
        let (store, clock) = make(source, net: net)
        await store.settled()
        net.send(false); net.send(true)
        #expect(await until { await source.hourlyCalls == 2 })
        await store.settled()
        clock.advance(10)
        net.send(false); net.send(true)
        #expect(await until { await source.hourlyCalls == 3 })
    }

    // MARK: - Принудительная загрузка

    @Test("Тап при «недоступно»: «загружается», затем прогноз")
    func tapWhenUnavailable() async {
        let source = ForceSource(hourly: false)
        let (store, _) = make(source)
        await store.settled()
        #expect(store.status == .unavailable)
        await source.set(hourly: true); await source.hold()
        #expect(store.refreshNow())
        #expect(store.status == .loading)
        await source.release()
        #expect(await until { store.isLive })
        #expect(store.day(for: june10) != nil)
    }

    @Test("Тап при свежем прогнозе: запрос идёт, старый на экране до нового")
    func tapWithFreshForecastStillAsks() async {
        let source = ForceSource(hourly: true)
        let (store, _) = make(source)
        await store.settled()
        #expect(store.day(for: june10)?.cloud == 30)
        await source.set(cloud: 50); await source.hold()
        #expect(store.refreshNow())
        #expect(await until { await source.hourlyCalls == 2 })
        #expect(store.isLive)
        #expect(store.day(for: june10)?.cloud == 30, "старый остаётся, пока новый в пути")
        await source.release()
        #expect(await until { store.day(for: june10)?.cloud == 70 })
        #expect(await source.airCalls == 2, "воздух тоже спрошен заново")
    }

    @Test("Тап во время запроса — второго запроса нет")
    func tapDuringARequestIsIgnored() async {
        let source = ForceSource(hourly: true)
        await source.hold()
        let (store, clock) = make(source)
        #expect(await until { await source.hourlyCalls == 1 })
        clock.advance(60)
        #expect(!store.refreshNow())
        await quiet()
        #expect(await source.hourlyCalls == 1)
        await source.release()
    }

    @Test("Тап дважды за 10 секунд — второй не уходит; через 10 — уходит")
    func tapTwiceWithinTheWindow() async {
        let source = ForceSource(hourly: true)
        let (store, clock) = make(source)
        await store.settled()
        #expect(store.refreshNow())
        await store.settled()
        #expect(await until { await source.hourlyCalls == 2 })
        clock.advance(9)
        #expect(!store.refreshNow())
        await quiet()
        #expect(await source.hourlyCalls == 2)
        clock.advance(1)
        #expect(store.refreshNow())
        #expect(await until { await source.hourlyCalls == 3 })
    }

    @Test("Нет сети — тап не стирает старый прогноз")
    func tapWithoutNetworkKeepsTheOldForecast() async {
        let source = ForceSource(hourly: true)
        let (store, _) = make(source)
        await store.settled()
        await source.set(hourly: false)
        #expect(store.refreshNow())
        #expect(await until { await source.hourlyCalls == 2 })
        await store.settled()
        await quiet()
        #expect(store.isLive)
        #expect(store.day(for: june10)?.cloud == 30)
    }

    @Test("Смена места во время запроса: ответ прежнего места не ложится, новое место загружается")
    func moveDuringAForcedRequest() async {
        let source = ForceSource(hourly: true)
        let (store, _) = make(source)
        await store.settled()
        await source.set(cloud: 50); await source.hold()
        #expect(store.refreshNow())
        #expect(await until { await source.hourlyCalls == 2 })
        store.move(to: b)
        await source.set(cloud: 5)
        await source.release()
        #expect(await until { store.day(for: june10)?.cloud == 45 })   // 5 + широта b (40)
        #expect(store.place == b)
        await quiet()
        #expect(store.day(for: june10)?.cloud == 45, "запоздавший ответ места a не перекрыл")
    }
}
