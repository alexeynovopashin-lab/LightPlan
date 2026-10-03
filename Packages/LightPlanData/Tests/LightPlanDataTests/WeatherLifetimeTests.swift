import Testing
import Foundation
@testable import LightPlanData
@testable import LightPlanCore

/// Часы, которыми тест двигает «сейчас» сам; сеть не нужна.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: Date
    init() { t = Date(timeIntervalSince1970: 1_000_000_000) }
    var date: Date { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ seconds: TimeInterval) { lock.lock(); t = t.addingTimeInterval(seconds); lock.unlock() }
    var now: @Sendable () -> Date { { [self] in date } }
}

/// Источник с выключателем, счётчиками вопросов и «ответом в пути».
/// Облачность = широта + `bump`: по ней видно, какой ответ показан.
private actor Source: WeatherSource {
    struct Down: Error {}
    private(set) var hourlyCalls = 0
    private(set) var airCalls = 0
    private var hourlyUp = true
    private var airUp = true
    private var bump = 0.0
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func set(hourly: Bool? = nil, air: Bool? = nil, bump: Double? = nil) {
        if let hourly { hourlyUp = hourly }
        if let air { airUp = air }
        if let bump { self.bump = bump }
    }
    func hold() { held = true }
    func release() { held = false; waiters.forEach { $0.resume() }; waiters = [] }

    func fetchHourly(at place: Place) async throws -> HourlyWeather {
        hourlyCalls += 1
        if held { await withCheckedContinuation { waiters.append($0) } }
        guard hourlyUp else { throw Down() }
        let time = (0..<24).map { "2026-06-10T" + String(format: "%02d", $0) + ":00" }
        return HourlyWeather(time: time, cloud: Array(repeating: place.latitude + bump, count: 24),
                             temperature: Array(repeating: 10, count: 24), windSpeed: Array(repeating: 2, count: 24),
                             precipitation: Array(repeating: 0, count: 24), weatherCode: Array(repeating: 0, count: 24))
    }

    func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] {
        airCalls += 1
        guard airUp else { throw Down() }
        let d = CivilDate(year: 2026, month: 6, day: 10)
        return [d: Dictionary(uniqueKeysWithValues: (0..<24).map { ($0, AirSample(aod: 0.5, dust: 0)) })]
    }
}

private let june10 = CivilDate(year: 2026, month: 6, day: 10)
private let a = Place(latitude: 20, longitude: 30, zone: ZoneID(fixedOffsetHours: 3))
private let b = Place(latitude: 40, longitude: 50, zone: ZoneID(fixedOffsetHours: 3))
private let hour = 3600.0

@MainActor private func until(_ cond: () async -> Bool) async -> Bool {
    for _ in 0..<200 { if await cond() { return true }; try? await Task.sleep(for: .milliseconds(10)) }
    return false
}

@MainActor private func makeStore(_ source: Source, _ clock: Clock, place: Place = a) -> WeatherStore {
    WeatherStore(place: place, source: source, debounce: .zero, retryDelays: [.seconds(600)], now: clock.now)
}

struct WeatherFetcherLifetimeTests {

    @Test("Прогноз: за секунду до срока — из кэша, ровно в срок — заново")
    func hourlyExpiresExactlyAtTheLifetime() async throws {
        let source = Source(), clock = Clock()
        let fetcher = WeatherFetcher(source: source, now: clock.now)
        _ = try await fetcher.hourly(at: a)
        clock.advance(hour - 1)
        _ = try await fetcher.hourly(at: a)
        #expect(await source.hourlyCalls == 1, "за секунду до срока — кэш")
        clock.advance(1)
        _ = try await fetcher.hourly(at: a)
        #expect(await source.hourlyCalls == 2, "ровно срок — уже старый")
    }

    @Test("Воздух живёт три часа: на часе ещё кэш, за секунду до трёх — кэш, ровно три — заново")
    func airExpiresExactlyAtThreeHours() async throws {
        let source = Source(), clock = Clock()
        let fetcher = WeatherFetcher(source: source, now: clock.now)
        _ = try await fetcher.air(at: a)
        clock.advance(hour)
        _ = try await fetcher.air(at: a)
        clock.advance(2 * hour - 1)
        _ = try await fetcher.air(at: a)
        #expect(await source.airCalls == 1)
        clock.advance(1)
        _ = try await fetcher.air(at: a)
        #expect(await source.airCalls == 2)
    }

    @Test("Сбой при обновлении просроченного: кэш старого не отдаётся")
    func anExpiredEntryIsNotServedWhenTheRefreshFails() async throws {
        let source = Source(), clock = Clock()
        let fetcher = WeatherFetcher(source: source, now: clock.now)
        _ = try await fetcher.hourly(at: a)
        clock.advance(hour)
        await source.set(hourly: false)
        await #expect(throws: Source.Down.self) { _ = try await fetcher.hourly(at: a) }
    }
}

@MainActor
struct WeatherStoreLifetimeTests {

    @Test("Возврат на экран за секунду до срока ничего не спрашивает, ровно в срок — спрашивает и показывает новое")
    func returningBeforeAndAtTheLifetime() async {
        let source = Source(), clock = Clock()
        let store = makeStore(source, clock)
        await store.settled()
        #expect(store.day(for: june10)?.cloud == 20)
        clock.advance(hour - 1)
        store.resume(); await store.settled()
        #expect(await source.hourlyCalls == 1, "срок не прошёл — вопроса нет")
        await source.set(bump: 5)
        clock.advance(1)
        store.resume(); await store.settled()
        #expect(await source.hourlyCalls == 2)
        #expect(store.day(for: june10)?.cloud == 25)
        #expect(await source.airCalls == 1, "воздух живёт три часа — на часе его не трогаем")
    }

    @Test("Пока новый прогноз в пути, старый на экране, статус «есть»")
    func theOldForecastStaysWhileTheNewOneIsOnItsWay() async {
        let source = Source(), clock = Clock()
        let store = makeStore(source, clock)
        await store.settled()
        clock.advance(hour)
        await source.hold()
        store.resume()
        _ = await until { await source.hourlyCalls == 2 }
        #expect(store.day(for: june10)?.cloud == 20, "старый не стёрт")
        #expect(store.status == .live(.direct))
        await source.release(); await store.settled()
    }

    @Test("Сбой при обновлении: старый остаётся до шести часов, ровно шесть — «недоступно»")
    func aFailedRefreshKeepsTheOldOneUntilSixHours() async {
        let source = Source(), clock = Clock()
        let store = makeStore(source, clock)
        await store.settled()
        await source.set(hourly: false)
        clock.advance(hour)
        store.resume(); await store.settled()
        #expect(store.day(for: june10)?.cloud == 20, "час: сбой — старый на месте")
        #expect(store.status == .live(.direct))
        clock.advance(5 * hour - 1)
        store.resume(); await store.settled()
        #expect(store.day(for: june10)?.cloud == 20, "за секунду до шести часов — старый ещё на месте")
        #expect(store.status == .live(.direct))
        clock.advance(1)
        store.resume(); await store.settled()
        #expect(store.day(for: june10) == nil, "ровно шесть часов — прогноза нет")
        #expect(store.status == .unavailable)
    }

    @Test("Шесть часов исполняются во время запроса: за секунду до — старый остаётся, ровно в срок — «недоступно»")
    func theSixHourLimitReachedDuringTheRequest() async {
        for (extra, stays) in [(0.0, true), (1.0, false)] {
            let source = Source(), clock = Clock()
            let store = makeStore(source, clock)
            await store.settled()
            clock.advance(6 * hour - 1 - 0)
            await source.set(hourly: false)
            await source.hold()
            store.resume()
            _ = await until { await source.hourlyCalls == 2 }
            clock.advance(extra)                       // запрос в пути, часы идут
            await source.release(); await store.settled()
            if stays {
                #expect(store.day(for: june10)?.cloud == 20, "5:59:59 на момент сбоя — старый на месте")
                #expect(store.status == .live(.direct))
            } else {
                #expect(store.day(for: june10) == nil, "ровно 6:00:00 на момент сбоя — прогноза нет")
                #expect(store.status == .unavailable)
            }
        }
    }

    @Test("После «недоступно» следующий успех возвращает прогноз")
    func recoveryAfterUnavailable() async {
        let source = Source(), clock = Clock()
        let store = makeStore(source, clock)
        await store.settled()
        await source.set(hourly: false)
        clock.advance(6 * hour)
        store.resume(); await store.settled()
        #expect(store.status == .unavailable)
        await source.set(hourly: true, bump: 3)
        store.resume(); await store.settled()
        #expect(store.status == .live(.direct))
        #expect(store.day(for: june10)?.cloud == 23)
    }

    @Test("Вернулись через шесть часов и больше: пока спрашиваем, старого на экране нет")
    func aVeryOldForecastIsNotShownWhileAsking() async {
        let source = Source(), clock = Clock()
        let store = makeStore(source, clock)
        await store.settled()
        clock.advance(10 * hour)
        await source.hold()
        store.resume()
        _ = await until { await source.hourlyCalls == 2 }
        #expect(store.day(for: june10) == nil)
        #expect(store.status == .loading)
        await source.release(); await store.settled()
        #expect(store.status == .live(.direct))
    }

    @Test("Воздух упал при обновлении: старый держится до шести часов, потом убран, прогноз цел")
    func staleAirIsDroppedAtSixHours() async {
        let source = Source(), clock = Clock()
        let store = makeStore(source, clock)
        await store.settled()
        await source.set(hourly: true, air: false)
        clock.advance(3 * hour)
        store.resume(); await store.settled()
        #expect(store.airSample(for: june10, hour: 19)?.aod == 0.5, "три часа: воздух просрочен, но моложе шести — на месте")
        clock.advance(3 * hour)
        store.resume(); await store.settled()
        #expect(store.airSample(for: june10, hour: 19) == nil, "шесть часов — воздух убран")
        #expect(store.isLive)
    }

    @Test("Смена места во время обновления: ответ про прежнее место не просачивается")
    func movingDuringARefreshShowsTheNewPlace() async {
        let source = Source(), clock = Clock()
        let store = makeStore(source, clock)
        await store.settled()
        clock.advance(hour)
        await source.set(bump: 5)
        await source.hold()
        store.resume()
        _ = await until { await source.hourlyCalls == 2 }
        store.move(to: b)
        #expect(store.day(for: june10) == nil)
        await source.release()
        let came = await until { store.isLive }
        #expect(came)
        #expect(store.place == b)
        #expect(store.day(for: june10)?.cloud == 45, "ответ про B (40 + 5), не про A (25)")
    }

    @Test("Таймер: без возврата на экран прогноз обновляется сам, когда истёк срок")
    func theTimerRefreshesWithoutReturning() async {
        let source = Source()
        let store = WeatherStore(place: a, source: source, debounce: .zero, retryDelays: [.seconds(600)],
                                 lifetime: WeatherLifetime(hourly: 0.1, air: 0.1, staleLimit: 60))
        await store.settled()
        await source.set(bump: 5)
        let came = await until { store.day(for: june10)?.cloud == 25 }
        #expect(came, "таймер не обновил прогноз")
        #expect(await source.hourlyCalls >= 2)
    }

    @Test("Таймер не плодит вопросов, пока срок не истёк")
    func theTimerStaysQuietBeforeExpiry() async {
        let source = Source()
        let store = WeatherStore(place: a, source: source, debounce: .zero, retryDelays: [.seconds(600)])
        await store.settled()
        try? await Task.sleep(for: .milliseconds(200))
        let (h, air) = (await source.hourlyCalls, await source.airCalls)
        #expect(h == 1 && air == 1)
        _ = store
    }
}
