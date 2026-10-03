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
        // Часы, которых у службы нет, приходят `null` (замер 23 сентября 2026:
        // 4 из 120). `[Double]` ронял весь ответ, и дым выпадал из балла.
        let aerosol_optical_depth: [Double?]?
        let dust: [Double?]?
    }
    let hourly: Hourly
}

extension OpenMeteoAirResponse.Hourly {
    func byDay() -> [CivilDate: [Int: AirSample]] {
        var out: [CivilDate: [Int: AirSample]] = [:]
        for i in 0..<time.count {
            guard let (date, hour) = WeatherDay.parse(time[i]) else { continue }
            out[date, default: [:]][hour] = AirSample(aod: aerosol_optical_depth?[i] ?? nil, dust: dust?[i] ?? nil)
        }
        return out
    }
}

/// Загрузка байтов по запросу — за протоколом, чтобы вид запроса (адрес,
/// заголовок ключа) проверялся без сети.
public protocol HTTPLoading: Sendable {
    func load(_ request: URLRequest) async throws -> Data
}

public enum WeatherHTTPError: Error, Equatable { case status(Int) }

/// Живая сеть. Ответ не из 2xx — сбой: тело ошибки (`403`, `502`, `429` прокси
/// или `400` Open-Meteo) прогнозом не является и разбираться не должно.
public struct URLSessionLoader: HTTPLoading {
    public init() {}
    public func load(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WeatherHTTPError.status(http.statusCode)
        }
        return data
    }
}

/// Open-Meteo — прогноз остаётся основным (docs/17 § 11, план § 4.6): ярусы
/// облаков и влажность по часам, 16 суток вперёд и 5 назад, без ключа и квоты,
/// одинаково на всех платформах. WeatherKit заводится за тем же протоколом,
/// но проверка на бесплатной команде невозможна (docs/17 §12, измерено
/// 19 сентября 2026: «Personal development teams … do not support the …
/// capability» — тот же отказ, что и у iCloud и Push).
///
/// Путь (28ж): `.direct` — сам Open-Meteo; `.proxy` — наша функция в Yandex
/// Cloud (`kind=forecast|air&lat=&lon=`, ключ в `X-LP-Key`). Форма ответа у
/// обоих одна, разбор общий. Какой путь пробовать и когда — решает
/// `RoutedWeatherSource`, не этот тип.
public struct OpenMeteoSource: WeatherSource {
    public enum Endpoint: Sendable, Equatable {
        case direct
        case proxy(URL, key: String)
    }

    /// Сколько ждать один ответ; дольше — сбой этого пути.
    static let requestTimeout: TimeInterval = 20

    private let hourlyVariables = "cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,"
        + "relative_humidity_2m,temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,"
        + "precipitation,weather_code"
    private let endpoint: Endpoint
    private let loader: any HTTPLoading

    public init(endpoint: Endpoint = .direct, loader: any HTTPLoading = URLSessionLoader()) {
        self.endpoint = endpoint
        self.loader = loader
    }

    func hourlyRequest(at place: Place) -> URLRequest {
        switch endpoint {
        case .direct:
            return Self.get("https://api.open-meteo.com/v1/forecast", [
                URLQueryItem(name: "latitude", value: String(place.latitude)),
                URLQueryItem(name: "longitude", value: String(place.longitude)),
                URLQueryItem(name: "hourly", value: hourlyVariables),
                URLQueryItem(name: "forecast_days", value: "16"),
                URLQueryItem(name: "past_days", value: "5"),
                URLQueryItem(name: "timezone", value: "auto"),
                URLQueryItem(name: "windspeed_unit", value: "ms"),
            ])
        case .proxy(let url, let key):
            return Self.proxy(url, key: key, kind: "forecast", place: place)
        }
    }

    func airRequest(at place: Place) -> URLRequest {
        switch endpoint {
        case .direct:
            return Self.get("https://air-quality-api.open-meteo.com/v1/air-quality", [
                URLQueryItem(name: "latitude", value: String(place.latitude)),
                URLQueryItem(name: "longitude", value: String(place.longitude)),
                URLQueryItem(name: "hourly", value: "aerosol_optical_depth,dust"),
                URLQueryItem(name: "forecast_days", value: "5"),
                URLQueryItem(name: "timezone", value: "auto"),
            ])
        case .proxy(let url, let key):
            return Self.proxy(url, key: key, kind: "air", place: place)
        }
    }

    public func fetchHourly(at place: Place) async throws -> HourlyWeather {
        let data = try await loader.load(hourlyRequest(at: place))
        return try JSONDecoder().decode(OpenMeteoHourlyResponse.self, from: data).hourly.toHourlyWeather()
    }

    public func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] {
        let data = try await loader.load(airRequest(at: place))
        return try JSONDecoder().decode(OpenMeteoAirResponse.self, from: data).hourly.byDay()
    }

    private static func get(_ base: String, _ items: [URLQueryItem]) -> URLRequest {
        var comps = URLComponents(string: base)!
        comps.queryItems = items
        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = requestTimeout
        return request
    }

    /// Точка уходит на наш сервер с двумя знаками (~1 км): функция всё равно
    /// округляет до двух, а лишнее ей знать незачем.
    private static func proxy(_ url: URL, key: String, kind: String, place: Place) -> URLRequest {
        var request = get(url.absoluteString, [
            URLQueryItem(name: "kind", value: kind),
            URLQueryItem(name: "lat", value: String(format: "%.2f", place.latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.2f", place.longitude)),
        ])
        request.setValue(key, forHTTPHeaderField: "X-LP-Key")
        return request
    }
}
