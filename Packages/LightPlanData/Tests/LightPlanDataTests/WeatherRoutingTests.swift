import Testing
import Foundation
@testable import LightPlanData
@testable import LightPlanCore

// MARK: - Подставные пути

/// Что делает путь на очередной вопрос.
private enum Mode: Sendable {
    case ok(Double)            // ответ с такой облачностью — по ней видно, чей он
    case fail
    case hang                  // не отвечает вовсе, но отмену слышит (как `URLSession`)
    case deafLate(Double, Duration) // ответит позже, отмену не слышит
}

private actor Path: WeatherSource {
    struct Boom: Error {}
    var mode: Mode
    private(set) var hourlyCalls = 0
    private(set) var airCalls = 0

    init(_ mode: Mode) { self.mode = mode }
    func set(_ m: Mode) { mode = m }

    func fetchHourly(at place: Place) async throws -> HourlyWeather {
        hourlyCalls += 1
        return try await run(mode)
    }

    func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] {
        airCalls += 1
        _ = try await run(mode)
        return [:]
    }

    private func run(_ m: Mode) async throws -> HourlyWeather {
        switch m {
        case .ok(let c): return forecast(cloud: c)
        case .fail: throw Boom()
        case .hang: try await Task.sleep(for: .seconds(3600)); throw Boom()
        case .deafLate(let c, let d): try? await Task.sleep(for: d); return forecast(cloud: c)
        }
    }
}

private func forecast(cloud: Double) -> HourlyWeather {
    let time = (0..<24).map { "2026-06-10T" + String(format: "%02d", $0) + ":00" }
    return HourlyWeather(time: time, cloud: Array(repeating: cloud, count: 24), temperature: Array(repeating: 10, count: 24),
                         windSpeed: Array(repeating: 2, count: 24), precipitation: Array(repeating: 0, count: 24),
                         weatherCode: Array(repeating: 0, count: 24))
}

/// Записывает, сколько просили ждать, и ждёт «вечно» или не ждёт вовсе.
private actor Waits {
    private(set) var asked: [Duration] = []
    func note(_ d: Duration) { asked.append(d) }
}

private final class Clock3h: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_800_000_000)
    var date: Date { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ s: TimeInterval) { lock.lock(); t = t.addingTimeInterval(s); lock.unlock() }
}

private let spot = Place(latitude: 56.011, longitude: 37.483, zone: ZoneID(fixedOffsetHours: 3))

/// «Таймаут вышел сразу» / «таймаут не выйдет никогда».
private let timeoutNow: @Sendable (Duration) async throws -> Void = { _ in }
private let timeoutNever: @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .seconds(3600)) }

private func routed(direct: Path, proxy: Path, clock: Clock3h = Clock3h(),
                    sleep: @escaping @Sendable (Duration) async throws -> Void) -> RoutedWeatherSource {
    RoutedWeatherSource(direct: direct, proxy: proxy, now: { clock.date }, sleep: sleep)
}

// MARK: - Выбор пути

struct WeatherRoutingTests {

    @Test("Ожидание прямого пути — ровно 4 с; перепроверка — ровно 3 часа")
    func theConstantsAreTheOnesTheDecisionNamed() async throws {
        #expect(RoutedWeatherSource.directTimeout == .seconds(4))
        #expect(RoutedWeatherSource.recheckInterval == 3 * 3600)
        // И что именно эта цифра, не другая, уходит в часы при обычной сборке.
        let waits = Waits()
        let source = RoutedWeatherSource(direct: Path(.hang), proxy: Path(.ok(7)),
                                          sleep: { d in await waits.note(d) })
        _ = try await source.fetchHourlyWithOrigin(at: spot)
        #expect(await waits.asked == [.seconds(4)])
    }

    @Test("Прямой ответил в срок — сервер не трогаем")
    func directAnswersInTimeAndTheProxyIsNeverAsked() async throws {
        let direct = Path(.ok(11)), proxy = Path(.ok(77))
        let source = routed(direct: direct, proxy: proxy, sleep: timeoutNever)
        let (got, origin) = try await source.fetchHourlyWithOrigin(at: spot)
        #expect(origin == .direct)
        #expect(got.cloud.first == 11)
        #expect(await proxy.hourlyCalls == 0)
    }

    @Test("Прямой молчит до таймаута — отвечает сервер, путь запомнен")
    func directTimesOutAndTheProxyAnswers() async throws {
        let direct = Path(.hang), proxy = Path(.ok(77))
        let source = routed(direct: direct, proxy: proxy, sleep: timeoutNow)
        let (got, origin) = try await source.fetchHourlyWithOrigin(at: spot)
        #expect(origin == .proxy)
        #expect(got.cloud.first == 77)
        #expect(await source.preferred == .proxy)
    }

    @Test("Прямой ответил ПОСЛЕ таймаута — его ответ не берётся")
    func aLateDirectAnswerIsThrownAway() async throws {
        let direct = Path(.deafLate(11, .milliseconds(120))), proxy = Path(.ok(77))
        let source = routed(direct: direct, proxy: proxy, sleep: timeoutNow)
        let (got, origin) = try await source.fetchHourlyWithOrigin(at: spot)
        try await Task.sleep(for: .milliseconds(200))        // опоздавший давно «пришёл»
        #expect(origin == .proxy)
        #expect(got.cloud.first == 77, "взят ответ сервера, не опоздавший прямой")
        #expect(await source.preferred == .proxy)
    }

    @Test("Оба пути упали — сбой, а запомненный путь не меняется")
    func bothFailThrowsAndKeepsThePath() async throws {
        let direct = Path(.fail), proxy = Path(.fail)
        let source = routed(direct: direct, proxy: proxy, sleep: timeoutNever)
        await #expect(throws: Path.Boom.self) { _ = try await source.fetchHourlyWithOrigin(at: spot) }
        #expect(await direct.hourlyCalls == 1)
        #expect(await proxy.hourlyCalls == 1)
        #expect(await source.preferred == .direct)
    }

    @Test("Прямой упал, сервер ответил — следующий запрос идёт сразу на сервер")
    func theRememberedProxyStartsTheNextRequest() async throws {
        let direct = Path(.fail), proxy = Path(.ok(77))
        let source = routed(direct: direct, proxy: proxy, sleep: timeoutNever)
        _ = try await source.fetchHourlyWithOrigin(at: spot)
        let (_, origin) = try await source.fetchHourlyWithOrigin(at: spot)
        #expect(origin == .proxy)
        #expect(await direct.hourlyCalls == 1, "второй раз прямой не спрашивали")
        #expect(await proxy.hourlyCalls == 2)
    }

    @Test("Воздух начинает с пути, что запомнил прогноз")
    func airStartsWhereTheForecastLeftOff() async throws {
        let direct = Path(.fail), proxy = Path(.ok(77))
        let source = routed(direct: direct, proxy: proxy, sleep: timeoutNever)
        _ = try await source.fetchHourlyWithOrigin(at: spot)
        let (_, origin) = try await source.fetchAirWithOrigin(at: spot)
        #expect(origin == .proxy)
        #expect(await direct.airCalls == 0)
    }

    @Test("Через 3 часа прямой пробуется снова: ответил — путь возвращается")
    func afterThreeHoursTheDirectPathIsTriedAgain() async throws {
        let clock = Clock3h()
        let direct = Path(.fail), proxy = Path(.ok(77))
        let source = routed(direct: direct, proxy: proxy, clock: clock, sleep: timeoutNever)
        _ = try await source.fetchHourlyWithOrigin(at: spot)           // прямой упал, сервер
        clock.advance(3 * 3600 - 1)
        _ = try await source.fetchHourlyWithOrigin(at: spot)
        #expect(await direct.hourlyCalls == 1, "за секунду до срока прямой не пробуют")
        clock.advance(1)
        await direct.set(.ok(11))                                       // VPN выключили
        let (got, origin) = try await source.fetchHourlyWithOrigin(at: spot)
        #expect(await direct.hourlyCalls == 2, "ровно в срок — пробуют")
        #expect(origin == .direct && got.cloud.first == 11)
        #expect(await source.preferred == .direct)
    }

    @Test("Перепроверка не помогла — сервер, и три часа считаются заново")
    func aFailedRecheckStartsANewWindow() async throws {
        let clock = Clock3h()
        let direct = Path(.fail), proxy = Path(.ok(77))
        let source = routed(direct: direct, proxy: proxy, clock: clock, sleep: timeoutNever)
        _ = try await source.fetchHourlyWithOrigin(at: spot)
        clock.advance(3 * 3600)
        let (_, origin) = try await source.fetchHourlyWithOrigin(at: spot)   // перепроверка: прямой упал снова
        #expect(origin == .proxy)
        #expect(await direct.hourlyCalls == 2)
        clock.advance(3600)
        _ = try await source.fetchHourlyWithOrigin(at: spot)
        #expect(await direct.hourlyCalls == 2, "окно началось заново: через час прямой не трогают")
    }

    @Test("Запомненный сервер замолчал — остаётся прямой, и путь возвращается к нему")
    func aSilentRememberedProxyFallsBackToDirect() async throws {
        let direct = Path(.fail), proxy = Path(.ok(77))
        let source = routed(direct: direct, proxy: proxy, sleep: timeoutNever)
        _ = try await source.fetchHourlyWithOrigin(at: spot)
        await direct.set(.ok(11)); await proxy.set(.fail)
        let (got, origin) = try await source.fetchHourlyWithOrigin(at: spot)
        #expect(origin == .direct && got.cloud.first == 11)
        #expect(await source.preferred == .direct)
    }

    @Test("Задачу отменили — на сервер не переходим")
    func cancellationIsNotAFailureOfTheDirectPath() async throws {
        let direct = Path(.hang), proxy = Path(.ok(77))
        let source = routed(direct: direct, proxy: proxy, sleep: timeoutNever)
        let task = Task { try await source.fetchHourlyWithOrigin(at: spot) }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        _ = await task.result
        #expect(await proxy.hourlyCalls == 0)
        #expect(await source.preferred == .direct)
    }
}

// MARK: - Вид запроса

private struct CapturingLoader: HTTPLoading {
    final class Box: @unchecked Sendable { var requests: [URLRequest] = []; var body = Data(); var failWith: Error? }
    let box = Box()
    func load(_ request: URLRequest) async throws -> Data {
        box.requests.append(request)
        if let e = box.failWith { throw e }
        return box.body
    }
}

private func queryItems(_ r: URLRequest) -> [String: String] {
    let items = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
}

struct OpenMeteoRequestTests {
    private let proxyURL = URL(string: "https://functions.example/abc")!

    @Test("Прямой путь: адреса Open-Meteo, все переменные на месте, ключа нет")
    func directRequestsGoToOpenMeteo() async throws {
        let loader = CapturingLoader()
        let source = OpenMeteoSource(endpoint: .direct, loader: loader)
        let h = source.hourlyRequest(at: spot), a = source.airRequest(at: spot)
        #expect(h.url?.host == "api.open-meteo.com" && h.url?.path == "/v1/forecast")
        #expect(a.url?.host == "air-quality-api.open-meteo.com")
        #expect(queryItems(h)["past_days"] == "5" && queryItems(h)["forecast_days"] == "16")
        #expect(h.value(forHTTPHeaderField: "X-LP-Key") == nil)
    }

    @Test("Путь через сервер: адрес функции, kind/lat/lon, ключ — в заголовке, не в адресе")
    func proxyRequestsCarryTheKeyInTheHeaderOnly() async throws {
        let source = OpenMeteoSource(endpoint: .proxy(proxyURL, key: "SECRET-VALUE"), loader: CapturingLoader())
        let h = source.hourlyRequest(at: spot), a = source.airRequest(at: spot)
        #expect(h.url?.host == "functions.example" && h.url?.path == "/abc")
        #expect(queryItems(h) == ["kind": "forecast", "lat": "56.01", "lon": "37.48"])
        #expect(queryItems(a) == ["kind": "air", "lat": "56.01", "lon": "37.48"])
        #expect(h.value(forHTTPHeaderField: "X-LP-Key") == "SECRET-VALUE")
        #expect(!h.url!.absoluteString.contains("SECRET-VALUE"), "ключ не должен попасть в адрес")
    }

    @Test("Форма ответа одна: через сервер разбор тот же")
    func theSameBodyDecodesThroughBothPaths() async throws {
        let body = """
        {"hourly":{"time":["2026-06-10T12:00"],"cloud_cover":[40],"temperature_2m":[18],"wind_speed_10m":[3],
        "precipitation":[0],"weather_code":[1]}}
        """
        for endpoint in [OpenMeteoSource.Endpoint.direct, .proxy(proxyURL, key: "k")] {
            let loader = CapturingLoader()
            loader.box.body = Data(body.utf8)
            let got = try await OpenMeteoSource(endpoint: endpoint, loader: loader).fetchHourly(at: spot)
            #expect(got.cloud == [40] && got.temperature == [18])
        }
    }

    @Test("Ответ не из 2xx — сбой, тело не разбирается как прогноз")
    func nonSuccessStatusIsAFailure() async {
        let loader = CapturingLoader()
        loader.box.failWith = WeatherHTTPError.status(403)
        let source = OpenMeteoSource(endpoint: .proxy(proxyURL, key: "k"), loader: loader)
        await #expect(throws: WeatherHTTPError.self) { _ = try await source.fetchHourly(at: spot) }
    }
}

// MARK: - Ключ из пакета

struct WeatherProxyConfigTests {
    private func bundle(plist: [String: Any]?) throws -> (Bundle, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-wx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let plist { (plist as NSDictionary).write(to: dir.appendingPathComponent("weather_proxy.plist"), atomically: true) }
        return (try #require(Bundle(path: dir.path)), dir)
    }

    @Test("Нет файла, пустой ключ, ключ из пробелов — ключа нет, без падений")
    func noKeyMeansNoConfig() throws {
        for plist: [String: Any]? in [nil, ["LPWeatherProxyKey": ""], ["LPWeatherProxyKey": "  \n"], ["other": 1]] {
            let (b, dir) = try bundle(plist: plist)
            defer { try? FileManager.default.removeItem(at: dir) }
            #expect(WeatherProxyConfig.load(bundle: b) == nil)
        }
    }

    @Test("Ключ есть — адрес по умолчанию наш, из файла можно подменить")
    func aKeyGivesAConfig() throws {
        let (b, dir) = try bundle(plist: ["LPWeatherProxyKey": "abc\n"])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(WeatherProxyConfig.load(bundle: b) == WeatherProxyConfig(key: "abc"))
        let (b2, dir2) = try bundle(plist: ["LPWeatherProxyKey": "abc", "LPWeatherProxyURL": "https://example.com/x"])
        defer { try? FileManager.default.removeItem(at: dir2) }
        #expect(WeatherProxyConfig.load(bundle: b2)?.url.absoluteString == "https://example.com/x")
    }

    @Test("Без ключа боевая сборка — один прямой Open-Meteo, без ожидания")
    func withoutAKeyTheLiveSourceIsPlainDirect() {
        #expect(RoutedWeatherSource.live(config: nil) is OpenMeteoSource)
        #expect(RoutedWeatherSource.live(config: WeatherProxyConfig(key: "k")) is RoutedWeatherSource)
    }
}
