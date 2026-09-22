import Testing
import Foundation
@testable import LightPlanData
@testable import LightPlanCore

private actor ScriptedSource: WeatherSource {
    enum Step {
        case hourly(HourlyWeather)
        case fail
        case slow(HourlyWeather, Duration)
    }
    private var hourlySteps: [String: [Step]]
    private var airAnswers: [String: [CivilDate: [Int: AirSample]]]
    private(set) var hourlyCalls: [String] = []
    private(set) var airCalls: [String] = []
    struct Boom: Error {}

    init(hourly: [String: [Step]], air: [String: [CivilDate: [Int: AirSample]]] = [:]) {
        self.hourlySteps = hourly
        self.airAnswers = air
    }

    func fetchHourly(at place: Place) async throws -> HourlyWeather {
        let key = String(format: "%.3f,%.3f", place.latitude, place.longitude)
        hourlyCalls.append(key)
        var steps = hourlySteps[key] ?? []
        let step = steps.isEmpty ? Step.fail : steps.removeFirst()
        if !steps.isEmpty { hourlySteps[key] = steps }
        switch step {
        case .hourly(let h): return h
        case .fail: throw Boom()
        case .slow(let h, let d):
            try? await Task.sleep(for: d)   // намеренно глухо к отмене: как сеть, которой не сказали
            return h
        }
    }

    func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] {
        let key = String(format: "%.3f,%.3f", place.latitude, place.longitude)
        airCalls.append(key)
        return airAnswers[key] ?? [:]
    }
}

private func hour(cloud: Double, date: String, days: Int = 1) -> HourlyWeather {
    var time: [String] = [], c: [Double] = [], temp: [Double] = [], wind: [Double] = [],
        precip: [Double] = []
    var code: [Int] = []
    let base = date
    for dd in 0..<days {
        for hh in 0..<24 {
            time.append(base + "T" + String(format: "%02d", hh) + ":00")
            c.append(cloud); temp.append(10); wind.append(2); precip.append(0); code.append(0)
        }
        _ = dd
    }
    return HourlyWeather(time: time, cloud: c, temperature: temp, windSpeed: wind, precipitation: precip, weatherCode: code)
}

private let lobnya = Place(latitude: 56.011, longitude: 37.483, zone: ZoneID(fixedOffsetHours: 3))
private let tomsk = Place(latitude: 56.489, longitude: 84.952, zone: ZoneID(fixedOffsetHours: 7))

@MainActor
struct WeatherStoreTests {

    @Test("Пока идёт дебаунс, сеть не спрашивают")
    func debounceDelaysTheFirstRequest() async {
        let source = ScriptedSource(hourly: [:])
        let store = WeatherStore(place: lobnya, source: source, debounce: .milliseconds(60))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await source.hourlyCalls.isEmpty)
        await store.settled()
        #expect(await source.hourlyCalls.count == 1)
    }

    @Test("Тот же адрес — без сети: вопрос ушёл, а второй раз не идёт")
    func secondRequestForTheSamePlaceDoesNotGoToTheNetwork() async {
        let key = String(format: "%.3f,%.3f", lobnya.latitude, lobnya.longitude)
        let source = ScriptedSource(hourly: [key: [.hourly(hour(cloud: 20, date: "2026-06-10"))]])
        let store = WeatherStore(place: lobnya, source: source, debounce: .zero)
        await store.settled()
        #expect(store.isLive)
        // Тот же адрес до тысячной градуса — карту слегка подвинули назад.
        store.move(to: Place(latitude: 56.0111, longitude: 37.4829, zone: lobnya.zone))
        await store.settled()
        #expect(await source.hourlyCalls.count == 1)
    }

    @Test("Офлайн — молча остаётся выдумка, isLive не включается")
    func offlineFallsBackToMockSilently() async {
        let source = ScriptedSource(hourly: [:])
        let store = WeatherStore(place: lobnya, source: source, debounce: .zero)
        await store.settled()
        #expect(!store.isLive)
        let date = CivilDate(year: 2026, month: 6, day: 10)
        let day = store.day(for: date)
        #expect(!day.real)
        // То же самое, что вернул бы MockWeather напрямую — выдумка не своя, общая.
        #expect(day.quality == MockWeather.day(for: date).quality)
    }

    @Test("Настоящий прогноз перекрывает выдумку по тому же дню")
    func realWeatherOverridesMockForTheSameDay() async {
        let key = String(format: "%.3f,%.3f", lobnya.latitude, lobnya.longitude)
        let hourly = hour(cloud: 5, date: "2026-06-10")
        let source = ScriptedSource(hourly: [key: [.hourly(hourly)]])
        let store = WeatherStore(place: lobnya, source: source, debounce: .zero)
        await store.settled()
        let date = CivilDate(year: 2026, month: 6, day: 10)
        #expect(store.day(for: date).real)
        #expect(store.day(for: date).cloud == 5)
    }

    @Test("Ответ про место, откуда карту уже увели, ничего не меняет")
    func lateAnswerForAnOldPlaceNeverOverridesTheNewOne() async {
        let lobnyaKey = String(format: "%.3f,%.3f", lobnya.latitude, lobnya.longitude)
        let tomskKey = String(format: "%.3f,%.3f", tomsk.latitude, tomsk.longitude)
        let source = ScriptedSource(hourly: [
            lobnyaKey: [.slow(hour(cloud: 90, date: "2026-06-10"), .milliseconds(120))],
            tomskKey: [.hourly(hour(cloud: 5, date: "2026-06-10"))],
        ])
        let store = WeatherStore(place: Place(latitude: 0, longitude: 0, zone: ZoneID(fixedOffsetHours: 0)),
                                  source: source, debounce: .zero)
        await store.settled()
        store.move(to: lobnya)
        try? await Task.sleep(for: .milliseconds(30))   // вопрос про Лобню уже в пути
        store.move(to: tomsk)
        await store.settled()
        try? await Task.sleep(for: .milliseconds(200))  // ждём, пока медленный ответ придёт и будет выброшен
        let date = CivilDate(year: 2026, month: 6, day: 10)
        #expect(store.place == tomsk)
        #expect(store.day(for: date).cloud == 5)
    }

    @Test("Воздух приходит вторым и поправляет уже построенный день")
    func airArrivesSecondAndCorrectsTheAlreadyBuiltDay() async {
        let key = String(format: "%.3f,%.3f", lobnya.latitude, lobnya.longitude)
        let hourly = hour(cloud: 5, date: "2026-06-10")
        let date = CivilDate(year: 2026, month: 6, day: 10)
        var airByHour: [Int: AirSample] = [:]
        for h in 0..<24 { airByHour[h] = AirSample(aod: 0.7, dust: 0) }
        let source = ScriptedSource(hourly: [key: [.hourly(hourly)]], air: [key: [date: airByHour]])
        let store = WeatherStore(place: lobnya, source: source, debounce: .zero)
        await store.settled()
        #expect(await source.airCalls.count == 1)
        // Балл посчитан с поправкой на дым, а не как «чистое небо»: без ярусов
        // mid/high (`hour()` не задаёт их) закладка та же, что у buildWx —
        // low = облачность, mid и high — ноль.
        let bare = SunsetScore.score(low: 5, mid: 0, high: 0, humidity: 50)
        #expect(store.day(for: date).sunset != nil)
        #expect(store.day(for: date).sunset! < bare)
    }
}
