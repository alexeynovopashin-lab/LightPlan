import Foundation
import LightPlanCore

/// Прогноз погоды за протоколом: приложение говорит с Open-Meteo, тесты — со
/// сценарием (§ 4.6 плана; тот же приём, что `ReverseGeocoding`).
public protocol WeatherSource: Sendable {
    /// Часовой прогноз на 16 суток вперёд и 5 назад.
    func fetchHourly(at place: Place) async throws -> HourlyWeather
    /// Аэрозоль и пыль на 5 суток вперёд, разложенные по суткам и часам
    /// (веб `fetchAir` + сборка `airDay`).
    func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]]
}

/// Сырой ответ Open-Meteo `/v1/forecast` — только имена полей, порт JSON без
/// перевода: перевод в `HourlyWeather` — прямое переложение полей, значения
/// не трогаются.
struct OpenMeteoHourlyResponse: Decodable {
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
}

extension OpenMeteoHourlyResponse.Hourly {
    func toHourlyWeather() -> HourlyWeather {
        HourlyWeather(time: time, cloud: cloud_cover, cloudLow: cloud_cover_low, cloudMid: cloud_cover_mid,
                      cloudHigh: cloud_cover_high, humidity: relative_humidity_2m, temperature: temperature_2m,
                      windSpeed: wind_speed_10m, windDirection: wind_direction_10m, windGusts: wind_gusts_10m,
                      precipitation: precipitation, weatherCode: weather_code)
    }
}

/// Сырой ответ `air-quality-api` — та же логика, разложенная по суткам и часам.
struct OpenMeteoAirResponse: Decodable {
    struct Hourly: Decodable {
        let time: [String]
        let aerosol_optical_depth: [Double]?
        let dust: [Double]?
    }
    let hourly: Hourly
}

extension OpenMeteoAirResponse.Hourly {
    func byDay() -> [CivilDate: [Int: AirSample]] {
        var out: [CivilDate: [Int: AirSample]] = [:]
        for i in 0..<time.count {
            guard let (date, hour) = WeatherDay.parse(time[i]) else { continue }
            out[date, default: [:]][hour] = AirSample(aod: aerosol_optical_depth?[i], dust: dust?[i])
        }
        return out
    }
}

/// Open-Meteo — прогноз остаётся основным (docs/17 § 11, план § 4.6): ярусы
/// облаков и влажность по часам, 16 суток вперёд и 5 назад, без ключа и квоты,
/// одинаково на всех платформах. WeatherKit заводится за тем же протоколом,
/// но проверка на бесплатной команде невозможна (docs/17 §12, измерено
/// 19 сентября 2026: «Personal development teams … do not support the …
/// capability» — тот же отказ, что и у iCloud и Push).
public struct OpenMeteoSource: WeatherSource {
    private let hourlyVariables = "cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,"
        + "relative_humidity_2m,temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,"
        + "precipitation,weather_code"

    public init() {}

    public func fetchHourly(at place: Place) async throws -> HourlyWeather {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "hourly", value: hourlyVariables),
            URLQueryItem(name: "forecast_days", value: "16"),
            URLQueryItem(name: "past_days", value: "5"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "windspeed_unit", value: "ms"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        return try JSONDecoder().decode(OpenMeteoHourlyResponse.self, from: data).hourly.toHourlyWeather()
    }

    public func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] {
        var comps = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "hourly", value: "aerosol_optical_depth,dust"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        return try JSONDecoder().decode(OpenMeteoAirResponse.self, from: data).hourly.byDay()
    }
}
