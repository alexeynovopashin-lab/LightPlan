import Foundation
import LightPlanCore

/// Прогноз из файлов — сырые ответы Open-Meteo, сохранённые один раз. Нужен
/// снимку против веба (итерация 19б): веб получает те же два файла вместо
/// сети, и небо на обеих половинах пары одно и то же. Разбор — тот же, что у
/// живого `OpenMeteoSource`, поэтому файл проверяет и его.
public struct FileWeatherSource: WeatherSource {
    private let forecast: URL
    private let air: URL?

    public init(forecast: URL, air: URL?) {
        self.forecast = forecast
        self.air = air
    }

    public func fetchHourly(at place: Place) async throws -> HourlyWeather {
        let data = try Data(contentsOf: forecast)
        return try JSONDecoder().decode(OpenMeteoHourlyResponse.self, from: data).hourly.toHourlyWeather()
    }

    public func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] {
        guard let air else { return [:] }
        let data = try Data(contentsOf: air)
        return try JSONDecoder().decode(OpenMeteoAirResponse.self, from: data).hourly.byDay()
    }
}
