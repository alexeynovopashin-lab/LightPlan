import Testing
import Foundation
@testable import LightPlanData
@testable import LightPlanCore

/// Open-Meteo для центра России и Крыма отдаёт два последних часа окна
/// (индексы 502 и 503 из 504) пустыми по всем полям (замер 16 октября 2026).
/// Разбор с `[Double]` падал на первом `null` — «Прогноз недоступен». Пустой
/// час в ряд не попадает и числом не подменяется (слово Алексея 02.10, «без
/// имитации»): ряды обрезаются по этим часам разом.
private struct Stub: HTTPLoading {
    let data: Data
    func load(_ request: URLRequest) async throws -> Data { data }
}

private func fixture(_ name: String) throws -> Data {
    var u = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { u.deleteLastPathComponent() }
    return try Data(contentsOf: u.appendingPathComponent("Fixtures/\(name).json"))
}

private let moscow = Place(latitude: 55.75, longitude: 37.62, zone: ZoneID(fixedOffsetHours: 3))
private let tomsk = Place(latitude: 56.5, longitude: 84.97, zone: ZoneID(fixedOffsetHours: 7))

/// Разбор «как до правки»: строгие ряды без `null`. На ответе без пустых часов
/// новый разбор обязан дать то же самое, что дал бы этот.
private struct Legacy: Decodable {
    struct Hourly: Decodable {
        let time: [String]
        let cloud_cover: [Double]
        let cloud_cover_low, cloud_cover_mid, cloud_cover_high: [Double]?
        let relative_humidity_2m: [Double]?
        let temperature_2m: [Double]
        let wind_speed_10m: [Double]
        let wind_direction_10m, wind_gusts_10m: [Double]?
        let precipitation: [Double]
        let weather_code: [Int]
    }
    let hourly: Hourly
    var weather: HourlyWeather {
        HourlyWeather(time: hourly.time, cloud: hourly.cloud_cover, cloudLow: hourly.cloud_cover_low,
                      cloudMid: hourly.cloud_cover_mid, cloudHigh: hourly.cloud_cover_high,
                      humidity: hourly.relative_humidity_2m, temperature: hourly.temperature_2m,
                      windSpeed: hourly.wind_speed_10m, windDirection: hourly.wind_direction_10m,
                      windGusts: hourly.wind_gusts_10m, precipitation: hourly.precipitation,
                      weatherCode: hourly.weather_code)
    }
}

private func rowsAligned(_ w: HourlyWeather) -> Bool {
    let n = w.time.count
    let required = [w.cloud.count, w.temperature.count, w.windSpeed.count, w.precipitation.count, w.weatherCode.count]
    let optional = [w.cloudLow, w.cloudMid, w.cloudHigh, w.humidity, w.windDirection, w.windGusts].compactMap { $0?.count }
    return (required + optional).allSatisfy { $0 == n }
}

/// Ответ из двух часов с пустотами, какие нужны тесту: имя поля → значения.
private func json(_ fields: [String: String], times: [String] = ["2026-10-31T20:00", "2026-10-31T21:00", "2026-10-31T22:00"]) -> Data {
    let t = times.map { "\"\($0)\"" }.joined(separator: ",")
    let rest = fields.map { "\"\($0.key)\":[\($0.value)]" }.joined(separator: ",")
    return Data("{\"hourly\":{\"time\":[\(t)],\(rest)}}".utf8)
}

private let full: [String: String] = [
    "cloud_cover": "10,20,30", "temperature_2m": "5,4,3", "wind_speed_10m": "1,2,3",
    "precipitation": "0,0,0", "weather_code": "0,1,2",
]

@Suite struct WeatherNullHoursTests {
    @Test func moscowTailOfNullsGivesForecastUpToLastFullHour() async throws {
        let source = OpenMeteoSource(loader: Stub(data: try fixture("open_meteo_moscow_tail")))
        let w = try await source.fetchHourly(at: moscow)
        #expect(w.time.count == 28)
        #expect(w.time.last == "2026-10-31T21:00")
        #expect(rowsAligned(w))
        #expect(w.cloud.last == 100 && w.cloud.count == 28)
    }

    @Test func proxyAndDirectGiveTheSameShape() async throws {
        let data = try fixture("open_meteo_moscow_tail")
        let direct = try await OpenMeteoSource(endpoint: .direct, loader: Stub(data: data)).fetchHourly(at: moscow)
        let proxy = try await OpenMeteoSource(endpoint: .proxy(URL(string: "https://example.test/f")!, key: "k"),
                                              loader: Stub(data: data)).fetchHourly(at: moscow)
        #expect(direct == proxy)
        #expect(direct.time.last == "2026-10-31T21:00")
    }

    @Test func tomskWithoutNullsIsUnchanged() async throws {
        let data = try fixture("open_meteo_tomsk_tail")
        let now = try await OpenMeteoSource(loader: Stub(data: data)).fetchHourly(at: tomsk)
        let before = try JSONDecoder().decode(Legacy.self, from: data).weather
        #expect(now == before)
        #expect(now.time.count == 30)
    }

    @Test func allFieldsNullAtOnceDoNotBreakTheResponse() async throws {
        let data = json([
            "cloud_cover": "10,20,null", "temperature_2m": "5,4,null", "wind_speed_10m": "1,2,null",
            "precipitation": "0,0,null", "weather_code": "0,1,null",
            "cloud_cover_low": "1,2,null", "wind_gusts_10m": "3,4,null",
        ])
        let w = try await OpenMeteoSource(loader: Stub(data: data)).fetchHourly(at: moscow)
        #expect(w.time == ["2026-10-31T20:00", "2026-10-31T21:00"])
        #expect(rowsAligned(w))
        #expect(w.cloudLow == [1, 2] && w.windGusts == [3, 4])
    }

    @Test func onlySomeFieldsNullDropsThatHourWithoutInventingNumbers() async throws {
        // Пусто только облако (хвост), только ветер (середина), только ярус (середина): час уходит из всех рядов.
        var f = full
        f["cloud_cover"] = "10,20,null"
        var w = try await OpenMeteoSource(loader: Stub(data: json(f))).fetchHourly(at: moscow)
        #expect(w.time.count == 2 && w.temperature == [5, 4] && rowsAligned(w))

        f = full
        f["wind_speed_10m"] = "1,null,3"
        w = try await OpenMeteoSource(loader: Stub(data: json(f))).fetchHourly(at: moscow)
        #expect(w.time == ["2026-10-31T20:00", "2026-10-31T22:00"])
        #expect(w.windSpeed == [1, 3] && w.cloud == [10, 30] && w.weatherCode == [0, 2] && rowsAligned(w))

        f = full
        f["cloud_cover_low"] = "1,null,3"
        w = try await OpenMeteoSource(loader: Stub(data: json(f))).fetchHourly(at: moscow)
        #expect(w.time.count == 2 && w.cloudLow == [1, 3] && rowsAligned(w))
    }

    @Test func screensSurviveShortenedRow() async throws {
        let source = OpenMeteoSource(loader: Stub(data: try fixture("open_meteo_moscow_tail")))
        let w = try await source.fetchHourly(at: moscow)
        let (days, hourly) = WeatherDay.buildDays(from: w, place: moscow)
        let last = CivilDate(year: 2026, month: 10, day: 31)
        let day = try #require(days[last])
        // Пустой час не стал нулём: его нет в почасовых записях.
        #expect(hourly[last]?[21] != nil)
        #expect(hourly[last]?[22] == nil && hourly[last]?[23] == nil)
        #expect(day.real && day.cloud >= 0 && day.cloud <= 100)
    }

    @Test func rowOfOnlyNullsIsEmptyNotACrash() async throws {
        let data = json([
            "cloud_cover": "null,null,null", "temperature_2m": "null,null,null", "wind_speed_10m": "null,null,null",
            "precipitation": "null,null,null", "weather_code": "null,null,null",
        ])
        let w = try await OpenMeteoSource(loader: Stub(data: data)).fetchHourly(at: moscow)
        #expect(w.time.isEmpty && rowsAligned(w))
        let (days, hourly) = WeatherDay.buildDays(from: w, place: moscow)
        #expect(days.isEmpty && hourly.isEmpty)
    }
}
