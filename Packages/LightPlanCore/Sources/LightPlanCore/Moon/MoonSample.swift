import Foundation

/// Луна в один момент в одном месте: высота, азимут, расстояние, фаза.
///
/// Порт `moonEq`, `moonAt` и `moonPhase` из веба — приближение Меёса низкой
/// точности. **Точность не улучшается при переносе.** Веб сам записал, что до
/// минуты на восходе не претендует; «починить» её значило бы изменить
/// поведение продукта (план, итерация 9). Затмения этим приближением не
/// считаются вовсе — они в `EclipseTable`.
///
/// Значение-тип без глобалов. Пояс — явный параметр, как у `SolarDay`.
public struct MoonSample: Sendable, Equatable {

    /// Высота над горизонтом, градусы. Ноль — математический горизонт: край
    /// диска (`MOON_H0` веба) поднимается только в поиске восхода.
    public let altitude: Degrees
    /// Азимут от севера по часовой, градусы, `0 ..< 360`.
    public let azimuth: Degrees
    /// Расстояние до луны, километры.
    public let distance: Double

    /// Дни от J2000: фаза считается из них на месте, а не хранится — лента
    /// луны зовёт `altitude` сотни раз, и фаза нужна ей не каждый раз.
    private let days: Double

    // MARK: - Входы

    /// Ядро сверки: смещение пояса задано явно (дробное: Катманду 5.75).
    public init(
        date: CivilDate, minutes: Minutes,
        latitude: Double, longitude: Double, utcOffsetHours: Double
    ) {
        let d = Sky.days(date: date, minutes: minutes, utcOffsetHours: utcOffsetHours)
        let m = Self.equatorial(days: d)
        let p = Sky.horizontal(ra: m.ra, dec: m.dec, days: d, latitude: latitude, longitude: longitude)
        self.altitude = p.altitude
        self.azimuth = p.azimuth
        self.distance = m.dist
        self.days = d
    }

    /// Смещение зоны места берётся на эту дату, как у `SolarDay(date:place:)`.
    public init(date: CivilDate, minutes: Minutes, place: Place) {
        self.init(
            date: date, minutes: minutes,
            latitude: place.latitude, longitude: place.longitude,
            utcOffsetHours: place.zone.utcOffsetHours(on: date)
        )
    }

    /// Доля освещённого диска и фаза этого же момента.
    public var phase: MoonPhase { MoonPhase(days: days) }

    // MARK: - Модель

    /// Положение луны на небе (`moonEq`): средние долгота, аномалия и аргумент
    /// широты плюс по одному члену возмущения. Радианы и километры.
    static func equatorial(days d: Double) -> (ra: Double, dec: Double, dist: Double) {
        let eps = Sky.obliquity
        let L = Sky.rad(218.316 + 13.176396 * d)   // средняя долгота
        let M = Sky.rad(134.963 + 13.064993 * d)   // средняя аномалия
        let F = Sky.rad(93.272 + 13.229350 * d)    // аргумент широты
        let l = L + Sky.rad(6.289) * sin(M)
        let b = Sky.rad(5.128) * sin(F)
        return (
            ra: atan2(sin(l) * cos(eps) - tan(b) * sin(eps), cos(l)),
            dec: asin(sin(b) * cos(eps) + cos(b) * sin(eps) * sin(l)),
            dist: 385_001 - 20_905 * cos(M)
        )
    }

    /// Положение солнца на небе (`sunEq`) — нужно только для фазы луны.
    static func sunEquatorial(days d: Double) -> (ra: Double, dec: Double) {
        let eps = Sky.obliquity
        let M = Sky.rad(357.5291 + 0.98560028 * d)
        let C = Sky.rad(1.9148 * sin(M) + 0.02 * sin(2 * M) + 0.0003 * sin(3 * M))
        let L = M + C + Sky.rad(102.9372) + Double.pi
        return (
            ra: atan2(sin(L) * cos(eps), cos(L)),
            dec: asin(sin(eps) * sin(L))
        )
    }
}
