import Foundation

/// Наш сервер погоды в Yandex Cloud (28ж): адрес известен всем, ключ — нет.
/// Ключ не лежит в репозитории (он публичный): фаза сборки
/// `Tools/weather_key.sh` кладёт его в `weather_proxy.plist` рядом с
/// приложением из файла `~/.config/lightplan/weather_key`. Нет файла — нет
/// ключа — приложение ходит только напрямую в Open-Meteo, без падений.
public struct WeatherProxyConfig: Sendable, Equatable {
    public static let defaultURL = URL(string: "https://functions.yandexcloud.net/d4ed8g9iaj0to6t9dne7")!

    public let url: URL
    public let key: String

    public init(url: URL = Self.defaultURL, key: String) {
        self.url = url
        self.key = key
    }

    /// `nil` — ключа нет (файла нет, пуст, не читается).
    public static func load(bundle: Bundle = .main) -> WeatherProxyConfig? {
        guard let file = bundle.url(forResource: "weather_proxy", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: file) as? [String: Any] else { return nil }
        let key = (dict["LPWeatherProxyKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { return nil }
        let url = (dict["LPWeatherProxyURL"] as? String).flatMap(URL.init(string:)) ?? defaultURL
        return WeatherProxyConfig(url: url, key: key)
    }
}
