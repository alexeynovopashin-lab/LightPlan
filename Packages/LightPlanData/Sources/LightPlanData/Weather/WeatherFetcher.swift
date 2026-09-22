import Foundation
import LightPlanCore

/// Прогноз и воздух по месту — с кэшем, чтобы то же место дважды не шло в
/// сеть (веб `wxKey === key && wxLive`, `airKey === key`). Ключ — три знака
/// после запятой, как везде в продукте (`GeoCoordinate.nameKey`), но здесь
/// свой: слой Data не тянет `Place` в `LightPlanCore` ради строки.
public actor WeatherFetcher {
    private let source: any WeatherSource
    private var hourlyCache: [String: HourlyWeather] = [:]
    private var airCache: [String: [CivilDate: [Int: AirSample]]] = [:]

    public init(source: any WeatherSource) {
        self.source = source
    }

    static func key(for place: Place) -> String {
        String(format: "%.3f,%.3f", place.latitude, place.longitude)
    }

    /// Часовой прогноз; тот же адрес — из кэша, без сети.
    public func hourly(at place: Place) async throws -> HourlyWeather {
        let key = Self.key(for: place)
        if let hit = hourlyCache[key] { return hit }
        let got = try await source.fetchHourly(at: place)
        try Task.checkCancellation()
        hourlyCache[key] = got
        return got
    }

    /// Воздух; тот же адрес — из кэша, без сети.
    public func air(at place: Place) async throws -> [CivilDate: [Int: AirSample]] {
        let key = Self.key(for: place)
        if let hit = airCache[key] { return hit }
        let got = try await source.fetchAir(at: place)
        try Task.checkCancellation()
        airCache[key] = got
        return got
    }
}
