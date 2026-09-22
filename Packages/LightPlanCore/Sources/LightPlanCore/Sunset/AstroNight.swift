import Foundation

/// Есть ли астрономическая темнота этой ночью, и когда она вернётся —
/// вопрос про произвольную дату, не про выбранный день (порт `hasAstroNight`,
/// `nextAstroNight`, найдены итерацией 9а).
///
/// Порт нарочно использует ту же низкоточную формулу солнца, что и фаза луны
/// (`MoonSample.sunEquatorial`), а не модель NOAA из `SolarDay`: веб делает
/// так же (`sunEq`) — вопрос только «бывает ли −18° этой ночью», а не точное
/// время события.
public enum AstroNight {
    /// `true`, если в это солнце в эту ночь на этой широте опускается ниже
    /// −18° хотя бы на миг (веб `hasAstroNight`).
    public static func has(on date: CivilDate, latitude: Double, utcOffsetHours: Double) -> Bool {
        let d = Sky.days(date: date, minutes: 720, utcOffsetHours: utcOffsetHours)
        let dec = MoonSample.sunEquatorial(days: d).dec
        let phi = Sky.rad(latitude)
        let c = (sin(Sky.rad(-18)) - sin(phi) * sin(dec)) / (cos(phi) * cos(dec))
        return c <= 1 && c >= -1
    }

    /// Когда темнота вернётся; `nil` — не вернётся в пределах полугода (веб
    /// `nextAstroNight`: 190 суток хватает везде, где она вообще бывает).
    public static func next(after date: CivilDate, latitude: Double, utcOffsetHours: Double) -> CivilDate? {
        var d = date
        for _ in 1...190 {
            d = d.adding(days: 1)
            if has(on: d, latitude: latitude, utcOffsetHours: utcOffsetHours) { return d }
        }
        return nil
    }
}
