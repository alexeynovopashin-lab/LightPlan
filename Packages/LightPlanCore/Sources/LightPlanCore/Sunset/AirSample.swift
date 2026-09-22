import Foundation

/// Аэрозоль и пыль в час заката или в окне астросъёмки (веб — второй запрос
/// Open-Meteo, `air-quality-api`). Независимы друг от друга: пыльный вынос
/// без AOD — по-прежнему пыль.
public struct AirSample: Sendable, Equatable {
    public let aod: Double?
    public let dust: Double?

    public init(aod: Double?, dust: Double?) {
        self.aod = aod
        self.dust = dust
    }
}

/// Слово о воздухе, когда есть что сказать (веб `airWord`); имя — ключ
/// словаря итерации 14 (`air.dust`, `air.smoke`, `air.haze`).
public enum AirCondition: String, Sendable, Equatable {
    case dust = "air.dust"
    case smoke = "air.smoke"
    case haze = "air.haze"
}

/// Общие приёмы погоды: ближайший час с данными и слово о воздухе. Оба
/// читают почасовые словари (`HourRecord`, `AirSample`) одной и той же
/// лесенкой — раньше она была в двух местах и на одном пропуске отвечала
/// по-разному (веб, комментарий у `nearHour`).
public enum Weather {
    /// Ближайший час с данными, допуская дыру до трёх часов: прогноз
    /// почасовой, но приходит с пропусками, а погода за три часа меняется
    /// меньше, чем стоит молчание в строке (веб `nearHour`).
    public static func nearHour<T>(_ hours: [Int: T], _ hour: Int) -> T? {
        for offset in 0...3 {
            if let value = hours[hour - offset] { return value }
            if let value = hours[hour + offset] { return value }
        }
        return nil
    }

    /// Слово о воздухе — только когда есть что сказать (веб `airWord`).
    /// Прозрачный воздух не новость, о нём молчим.
    public static func airWord(_ air: AirSample?) -> AirCondition? {
        guard let air else { return nil }
        if let dust = air.dust, dust >= 20 { return .dust }
        if let aod = air.aod, aod >= 0.6 { return .smoke }
        if let aod = air.aod, aod >= 0.35 { return .haze }
        return nil
    }
}
