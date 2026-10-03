import Testing
import Foundation
@testable import LightPlanData
@testable import LightPlanCore

/// Источник, у которого прогноз и воздух включаются и выключаются по ходу
/// теста, а вопросы считаются; прогноз можно придержать (ответ «в пути»).
private actor Switchable: WeatherSource {
    struct Down: Error {}
    private(set) var hourlyUp: Bool
    private(set) var airUp: Bool
    private(set) var hourlyCalls = 0
    private(set) var airCalls = 0
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(hourly: Bool, air: Bool) { hourlyUp = hourly; airUp = air }
    func set(hourly: Bool? = nil, air: Bool? = nil) {
        if let hourly { hourlyUp = hourly }
        if let air { airUp = air }
    }
    func hold() { held = true }
    func release() { held = false; waiters.forEach { $0.resume() }; waiters = [] }

    func fetchHourly(at place: Place) async throws -> HourlyWeather {
        hourlyCalls += 1
        if held { await withCheckedContinuation { waiters.append($0) } }   // глух к отмене, как сеть без вести
        guard hourlyUp else { throw Down() }
        return day(cloud: place.latitude)
    }

    func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] {
        airCalls += 1
        guard airUp else { throw Down() }
        let d = CivilDate(year: 2026, month: 6, day: 10)
        return [d: Dictionary(uniqueKeysWithValues: (0..<24).map { ($0, AirSample(aod: 0.5, dust: 0)) })]
    }
}

private func day(cloud: Double) -> HourlyWeather {
    let time = (0..<24).map { "2026-06-10T" + String(format: "%02d", $0) + ":00" }
    return HourlyWeather(time: time, cloud: Array(repeating: cloud, count: 24), temperature: Array(repeating: 10, count: 24),
                         windSpeed: Array(repeating: 2, count: 24), precipitation: Array(repeating: 0, count: 24),
                         weatherCode: Array(repeating: 0, count: 24))
}

private let june10 = CivilDate(year: 2026, month: 6, day: 10)
private let a = Place(latitude: 20, longitude: 30, zone: ZoneID(fixedOffsetHours: 3))
private let b = Place(latitude: 40, longitude: 50, zone: ZoneID(fixedOffsetHours: 3))

/// Ждёт условия, не дольше двух секунд.
@MainActor private func until(_ what: String = "", _ cond: () async -> Bool) async -> Bool {
    for _ in 0..<200 { if await cond() { return true }; try? await Task.sleep(for: .milliseconds(10)) }
    return false
}

@MainActor
struct WeatherRetryTests {

    @Test("Паузы между повторами — 3, 4, 5 минут, дальше по пять")
    func theDelaysAreThreeToFiveMinutes() {
        #expect(WeatherStore.retryDelays == [.seconds(180), .seconds(240), .seconds(300)])
    }

    @Test("Сбой не вечный: по таймеру спрашивает снова и находит прогноз")
    func afterAFailureTheTimerAsksAgain() async {
        let source = Switchable(hourly: false, air: true)
        let store = WeatherStore(place: a, source: source, debounce: .zero, retryDelays: [.milliseconds(40)])
        await store.settled()
        #expect(store.status == .unavailable)
        await source.set(hourly: true)
        let came = await until { store.isLive }
        #expect(came, "повтор по таймеру не пришёл")
        #expect(store.day(for: june10)?.cloud == 20)
    }

    @Test("Повтор идёт, пока не удастся, и после успеха замолкает")
    func retriesStopOnceItWorks() async {
        let source = Switchable(hourly: false, air: true)
        let store = WeatherStore(place: a, source: source, debounce: .zero, retryDelays: [.milliseconds(30)])
        await store.settled()
        _ = await until { await source.hourlyCalls >= 3 }          // ещё не удаётся — спрашивает снова и снова
        await source.set(hourly: true)
        _ = await until { store.isLive }
        let callsAtSuccess = await source.hourlyCalls
        try? await Task.sleep(for: .milliseconds(200))
        #expect(await source.hourlyCalls == callsAtSuccess, "после успеха вопросов больше нет")
    }

    @Test("Возврат на экран спрашивает сразу, не дожидаясь таймера")
    func returningToTheScreenAsksAtOnce() async {
        let source = Switchable(hourly: false, air: true)
        let store = WeatherStore(place: a, source: source, debounce: .zero, retryDelays: [.seconds(600)])
        await store.settled()
        #expect(await source.hourlyCalls == 1)
        await source.set(hourly: true)
        store.resume()
        await store.settled()
        #expect(store.isLive)
        #expect(await source.hourlyCalls == 2)
    }

    @Test("Возврат во время идущего запроса второго запроса не начинает")
    func returningDuringAnOngoingRequestDoesNotDouble() async {
        let source = Switchable(hourly: true, air: true)
        await source.hold()
        let store = WeatherStore(place: a, source: source, debounce: .zero, retryDelays: [.seconds(600)])
        _ = await until { await source.hourlyCalls == 1 }
        store.resume(); store.resume()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await source.hourlyCalls == 1, "запрос уже идёт — возврат не плодит второй")
        await source.release()
        await store.settled()
        #expect(store.isLive)
        #expect(await source.hourlyCalls == 1)
    }

    @Test("Уже получено всё — возврат на экран ничего не спрашивает")
    func returningWhenEverythingIsLoadedAsksNothing() async {
        let source = Switchable(hourly: true, air: true)
        let store = WeatherStore(place: a, source: source, debounce: .zero, retryDelays: [.seconds(600)])
        await store.settled()
        store.resume()
        await store.settled()
        #expect(await source.hourlyCalls == 1 && store.isLive)
    }

    @Test("Воздух не ждёт прогноза: прогноз упал, воздух всё равно загружен")
    func airIsNotBlockedByAFailedForecast() async {
        let source = Switchable(hourly: false, air: true)
        let store = WeatherStore(place: a, source: source, debounce: .zero, retryDelays: [.seconds(600)])
        await store.settled()
        #expect(!store.isLive)
        #expect(await source.airCalls == 1, "воздух спрошен, хотя прогноза нет")
        #expect(store.airSample(for: june10, hour: 19)?.aod == 0.5)
    }

    @Test("Воздух упал, прогноз пришёл — прогноз показан; повтор берёт только воздух")
    func aFailedAirDoesNotHideTheForecastAndIsRetriedAlone() async {
        let source = Switchable(hourly: true, air: false)
        let store = WeatherStore(place: a, source: source, debounce: .zero, retryDelays: [.milliseconds(40)])
        await store.settled()
        #expect(store.isLive)
        #expect(store.airSample(for: june10, hour: 19) == nil)
        await source.set(air: true)
        let came = await until { store.airSample(for: june10, hour: 19) != nil }
        #expect(came)
        #expect(await source.hourlyCalls == 1, "прогноз в кэше — второй раз в сеть не шёл")
    }

    @Test("Смена места во время запроса: ответ про старое место выброшен, повтор — про новое")
    func movingDuringARequestDropsTheOldAnswer() async {
        let source = Switchable(hourly: true, air: true)
        await source.hold()
        let store = WeatherStore(place: a, source: source, debounce: .zero, retryDelays: [.seconds(600)])
        _ = await until { await source.hourlyCalls == 1 }          // про A уже летит
        store.move(to: b)
        #expect(store.status == .loading, "прогноз прежнего места не остаётся")
        await source.release()
        await store.settled()
        _ = await until { store.isLive }
        #expect(store.place == b)
        #expect(store.day(for: june10)?.cloud == 40, "облачность из ответа про B (в тесте = широта), не про A")
    }

    @Test("Смена места стирает прогноз прежнего: он не про это место")
    func movingClearsTheOldPlacesForecast() async {
        let source = Switchable(hourly: true, air: true)
        let store = WeatherStore(place: a, source: source, debounce: .zero, retryDelays: [.seconds(600)])
        await store.settled()
        #expect(store.day(for: june10)?.cloud == 20)
        await source.hold()
        store.move(to: b)
        #expect(store.day(for: june10) == nil)
        #expect(store.status == .loading)
        await source.release()
    }

    @Test("Сдвиг в пределах тысячной градуса — тот же адрес: прогноз на месте, сети нет")
    func theSameKeyMoveKeepsTheForecast() async {
        let source = Switchable(hourly: true, air: true)
        let store = WeatherStore(place: a, source: source, debounce: .zero, retryDelays: [.seconds(600)])
        await store.settled()
        store.move(to: Place(latitude: 20.0001, longitude: 30.0001, zone: a.zone))
        #expect(store.day(for: june10)?.cloud == 20, "тот же адрес — прогноз на месте, не «грузится»")
        #expect(store.status == .live(.direct))
        #expect(await source.hourlyCalls == 1)
    }

    @Test("Источник, знающий пути, называет путь: сервер → .live(.proxy)")
    func theOriginReachesTheStatus() async {
        struct Dead: WeatherSource {
            func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Switchable.Down() }
            func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Switchable.Down() }
        }
        let routed = RoutedWeatherSource(direct: Dead(), proxy: Switchable(hourly: true, air: true), sleep: { _ in })
        let store = WeatherStore(place: a, source: routed, debounce: .zero, retryDelays: [.seconds(600)])
        await store.settled()
        #expect(store.status == .live(.proxy))
    }

    @Test("Оба пути упали — «недоступно», выдумки нет, повтор назначен")
    func bothPathsDownIsUnavailable() async {
        struct Dead: WeatherSource {
            func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Switchable.Down() }
            func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Switchable.Down() }
        }
        let routed = RoutedWeatherSource(direct: Dead(), proxy: Dead(), sleep: { _ in })
        let store = WeatherStore(place: a, source: routed, debounce: .zero, retryDelays: [.seconds(600)])
        await store.settled()
        #expect(store.status == .unavailable)
        #expect(store.day(for: june10) == nil)
    }
}
