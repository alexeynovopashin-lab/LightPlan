import Foundation

/// Млечный Путь: полоса галактического экватора и ядро на ней.
///
/// Порт «МЛЕЧНЫЙ ПУТЬ» из веба. Экваториальные координаты полосы — константы
/// неба: меняется только то, как оно повёрнуто над головой. Поэтому перевод
/// «галактика → экватор» делается один раз (`band`, `core`), а на каждый кадр
/// остаётся `Sky.horizontal` — столько же работы, сколько у луны.
public enum MilkyWay {

    /// Точка полосы. `longitude` — галактическая долгота, `halfWidth` —
    /// полуширина полосы в градусах, `ra` и `dec` — радианы.
    public struct BandPoint: Sendable, Equatable {
        public let longitude: Degrees
        public let halfWidth: Degrees
        public let center: EquatorialPoint
    }

    // Северный галактический полюс (J2000) и угол ядра — константы веба.
    private static let poleRA = Sky.rad(192.85948)
    private static let poleDec = Sky.rad(27.12825)
    private static let theta = Sky.rad(122.93192)

    /// Перевод галактических координат в экваториальные (`galToEq`).
    /// Контрольные точки: l=0 → 266.405° / −28.936°, l=180 → 86.405° / +28.936°.
    public static func equatorial(galacticLongitude l: Degrees, galacticLatitude b: Degrees) -> EquatorialPoint {
        let L = Sky.rad(l), B = Sky.rad(b), dT = theta - L
        let dec = asin(sin(poleDec) * sin(B) + cos(poleDec) * cos(B) * cos(dT))
        let ra = poleRA + atan2(cos(B) * sin(dT), cos(poleDec) * sin(B) - sin(poleDec) * cos(B) * cos(dT))
        return EquatorialPoint(ra: ra, dec: dec)
    }

    /// Полуширина полосы (`mwHalfWidth`). Полоса неоднородна, и это
    /// информация, а не украшение: у ядра балдж около 23° в поперечнике, к
    /// антицентру рукав сужается втрое. Балдж расширен на 15 % в вебе
    /// намеренно (с 10° до 11.5°); хвост не тронут.
    public static func halfWidth(galacticLongitude l: Degrees) -> Degrees {
        let dl = abs(((l + 180).truncatingRemainder(dividingBy: 360)) - 180)   // 0 у ядра, 180 у антицентра
        let k = cos(Sky.rad(dl) / 2)
        return 3 + 8.5 * k * k
    }

    /// Полоса шагом 3° — 121 точка (замыкающая совпадает с первой, поэтому
    /// её долгота `0`, а не `360`). Константа: считается один раз при первом
    /// обращении.
    public static let band: [BandPoint] = (0...120).map { i in
        let l = Double(i * 3)
        return BandPoint(
            longitude: l.truncatingRemainder(dividingBy: 360),
            halfWidth: halfWidth(galacticLongitude: l),
            center: equatorial(galacticLongitude: l, galacticLatitude: 0)
        )
    }

    /// Ядро — точка на полосе (l = 0), а не своя константа.
    public static let core: EquatorialPoint = equatorial(galacticLongitude: 0, galacticLatitude: 0)

    /// Где ядро над головой в этот момент (`milkyWayAt`).
    public static func corePosition(
        date: CivilDate, minutes: Minutes,
        latitude: Double, longitude: Double, utcOffsetHours: Double
    ) -> HorizontalPoint {
        let d = Sky.days(date: date, minutes: minutes, utcOffsetHours: utcOffsetHours)
        return Sky.horizontal(core, days: d, latitude: latitude, longitude: longitude)
    }

    public static func corePosition(date: CivilDate, minutes: Minutes, place: Place) -> HorizontalPoint {
        corePosition(
            date: date, minutes: minutes,
            latitude: place.latitude, longitude: place.longitude,
            utcOffsetHours: place.zone.utcOffsetHours(on: date)
        )
    }
}
