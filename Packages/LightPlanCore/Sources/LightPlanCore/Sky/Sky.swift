import Foundation

/// Точка неба в экваториальных координатах. **Радианы**, как в вебе: ни `ra`,
/// ни `dec` не нормализуются, потому что фикстуры хранят их сырыми.
public struct EquatorialPoint: Sendable, Equatable {
    public let ra: Double
    public let dec: Double

    public init(ra: Double, dec: Double) {
        self.ra = ra
        self.dec = dec
    }
}

/// Точка неба над головой: высота над горизонтом и азимут от севера по часовой.
public struct HorizontalPoint: Sendable, Equatable {
    /// Градусы, от −90 до +90.
    public let altitude: Degrees
    /// Градусы, `0 ..< 360`.
    public let azimuth: Degrees

    public init(altitude: Degrees, azimuth: Degrees) {
        self.altitude = altitude
        self.azimuth = azimuth
    }
}

/// Общий аппарат луны и Млечного Пути: момент, дни от эпохи J2000 и перевод
/// «точка неба → над головой». В вебе луна и Млечный Путь держат по копии
/// одной и той же формулы (`moonAt` и `eqToAltAz`); здесь она одна.
///
/// Порядок операций тот же, что в JS (`light_plan:Light_Plan/beta/index.html`,
/// «ЛУННАЯ МОДЕЛЬ»). Его нельзя «упрощать»: параметры обкатаны на вебе, а
/// сверка идёт по фикстурам стенда.
public enum Sky {

    static func rad(_ d: Double) -> Double { d * Double.pi / 180 }
    static func deg(_ r: Double) -> Double { r * 180 / Double.pi }

    /// Наклон эклиптики, `EPS` веба.
    static let obliquity = rad(23.4397)

    /// Дни от 2000-01-01 12:00 UTC (J2000) на момент «день плюс минуты шкалы».
    ///
    /// Момент собирается так же, как `instant` + `toDays` в вебе: UTC-полночь
    /// дня плюс `(минуты − пояс·60)` минут, и **дробные миллисекунды
    /// отбрасываются** — `new Date(мс)` в JS обрезает их к нулю. Ползунок
    /// таймбара даёт дробные минуты, а луна уходит на 4·10⁻⁶° за миллисекунду,
    /// что больше допуска сверки (1·10⁻⁷). Поэтому обрезка здесь не деталь, а
    /// часть паритета.
    public static func days(date: CivilDate, minutes: Minutes, utcOffsetHours: Double) -> Double {
        let midnight = Double(CivilDate.daysFromCivil(date.year, date.month, date.day)) * 86_400_000
        let ms = (midnight + (minutes - utcOffsetHours * 60) * 60_000).rounded(.towardZero)
        return ms / 86_400_000 - 0.5 + 2_440_588 - 2_451_545
    }

    /// Точка неба, неподвижная относительно звёзд (`eqToAltAz`), для места на
    /// широте и долготе. `days` — из `days(date:minutes:utcOffsetHours:)`.
    public static func horizontal(
        _ point: EquatorialPoint, days: Double, latitude: Double, longitude: Double
    ) -> HorizontalPoint {
        horizontal(ra: point.ra, dec: point.dec, days: days, latitude: latitude, longitude: longitude)
    }

    static func horizontal(
        ra: Double, dec: Double, days d: Double, latitude: Double, longitude: Double
    ) -> HorizontalPoint {
        let phi = rad(latitude)
        let h = rad(280.16 + 360.9856235 * d) - rad(-longitude) - ra
        let alt = asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(h))
        let az = atan2(sin(h), cos(h) * sin(phi) - tan(dec) * cos(phi))
        return HorizontalPoint(altitude: deg(alt), azimuth: (deg(az) + 180 + 360).truncatingRemainder(dividingBy: 360))
    }
}
