import Foundation

/// Солнце для слоя AR (шаг 29.8в): где оно в данный момент и по какой дуге пройдёт за день.
///
/// Считает тот же `SolarDay`, что «Свет» и «Карта»: тот же день места, то же смещение пояса. Поэтому дуга в AR
/// и высоты на других экранах не расходятся ни на долю градуса, а стенд паритета держит `SolarDay` против беты.
/// Новая здесь только рефракция — для камеры нужна видимая высота, а не геометрическая.
public struct SunSample: Sendable, Equatable {
    /// Минуты от полуночи по часам места, `0 … 1440`.
    public let minutes: Minutes
    /// Градусы от истинного севера по часовой, `0 ..< 360`.
    public let azimuth: Degrees
    /// Геометрическая высота центра диска, как в остальном приложении (без рефракции).
    public let altitude: Degrees

    public init(minutes: Minutes, azimuth: Degrees, altitude: Degrees) {
        self.minutes = minutes
        self.azimuth = azimuth
        self.altitude = altitude
    }

    /// Высота, как её видит камера.
    public var apparentAltitude: Degrees { SunTrack.apparent(altitude: altitude) }
}

public enum SunTrack {
    /// Ниже этой высоты дуга не рисуется — порог гражданских сумерек из «Солнечного компаса»
    /// (`MIN_ALTITUDE` в `findSolarPassage`). Сам маркер ниже порога не исчезает, а идёт призраком.
    public static let visibleFrom: Degrees = -6

    /// Ниже этой высоты дуга не продолжается вовсе: конец астрономических сумерек, где «Свет» красит шкалу
    /// последним цветом. От −6° до сюда дуга идёт пунктиром (шаг 29.8в.3) — сумерки видны до самой ночи.
    public static let arcFrom: Degrees = -18

    /// Шаг точек дуги, минуты.
    public static let arcStep: Minutes = 10

    /// Высоты (геометрические), на которых свет меняет характер для съёмки: начало золотого часа (+6,05°,
    /// порог `LightState`), закат (−0,833°), начало синего часа (−4°) и его конец (−6°). Ручка, пересёкшая
    /// порог, отдаёт тем же щелчком, что и час на таймбаре (шаг 29.8в.3).
    public static let lightThresholds: [Degrees] = [6.05, -0.833, -4, -6]

    /// Сколько порогов лежит между двумя высотами (в любую сторону).
    public static func thresholdsCrossed(from a: Degrees, to b: Degrees) -> Int {
        // Сторона порога — «ниже него» (`< t`): отсчёт ровно на пороге лежит выше, значит щелчок будет на одном шаге.
        lightThresholds.reduce(0) { n, t in (a < t) != (b < t) ? n + 1 : n }
    }

    /// Строка «до заката …» под временем: что ближайшее и сколько минут до него или после него.
    public enum EventNote: Sendable, Equatable {
        case untilSunrise(Minutes)
        case untilSunset(Minutes)
        case afterSunset(Minutes)
        /// Солнце весь день над горизонтом / весь день под ним: события нет.
        case polarDay
        case polarNight
    }

    /// Ближайшее к `minutes` событие дня: рассвет, закат, или время после заката.
    public static func note(at minutes: Minutes, solar: SolarDay) -> EventNote {
        switch solar.polar {
        case .day: return .polarDay
        case .night: return .polarNight
        case .normal: break
        }
        if let r = solar.rise, minutes < r { return .untilSunrise(r - minutes) }
        if let s = solar.set {
            return minutes < s ? .untilSunset(s - minutes) : .afterSunset(minutes - s)
        }
        // Восход был, а заката в этих сутках нет: до конца суток солнце над горизонтом.
        return .polarDay
    }

    /// День и минуты по часам места для момента: тот же приём, что у `TimebarState.wallNow` — грубая дата
    /// из UTC берёт смещение пояса, дальше `WallTime`-арифметика. Минуты дробные: ползунок идёт плавно.
    public static func wallClock(of moment: Moment, in place: Place) -> (day: CivilDate, minutes: Minutes) {
        let approx = CivilDate(daysSince1970: Int((Double(moment.milliseconds) / 86_400_000).rounded(.down)))
        let offset = place.zone.utcOffsetHours(on: approx)
        let local = moment.milliseconds + Int64((offset * 3_600_000).rounded())
        let days = WallTime.floorDiv(local, 86_400_000)
        let rest = local - days * 86_400_000
        return (CivilDate(daysSince1970: Int(days)), Double(rest) / 60_000)
    }

    /// Момент по дню и минутам часов места — обратное к `wallClock`.
    public static func moment(day: CivilDate, minutes: Minutes, in place: Place) -> Moment {
        let offset = place.zone.utcOffsetHours(on: day)
        let base = Int64(day.daysSince1970) * 86_400_000 + Int64((minutes * 60_000).rounded())
        return Moment(milliseconds: base - Int64((offset * 3_600_000).rounded()))
    }

    /// Положение солнца в этот момент.
    public static func sample(at moment: Moment, in place: Place) -> SunSample {
        let wall = wallClock(of: moment, in: place)
        return sample(day: wall.day, minutes: wall.minutes, in: place)
    }

    public static func sample(day: CivilDate, minutes: Minutes, in place: Place) -> SunSample {
        sample(solar: SolarDay(date: day, place: place), minutes: minutes)
    }

    private static func sample(solar: SolarDay, minutes: Minutes) -> SunSample {
        SunSample(minutes: minutes, azimuth: solar.azimuth(at: minutes), altitude: solar.elevation(at: minutes))
    }

    /// Дуга суток: точки через `arcStep` минут от полуночи до полуночи по часам места, все, не только видимые —
    /// отбор по порогу делает рисующий (так же ломаная рвётся там, где солнце ушло за камеру).
    public static func arc(day: CivilDate, in place: Place, step: Minutes = arcStep) -> [SunSample] {
        let solar = SolarDay(date: day, place: place)
        var out: [SunSample] = []
        var t = 0.0
        while t <= 1440 + 1e-9 {
            out.append(sample(solar: solar, minutes: t))
            t += step
        }
        return out
    }

    /// Точки дуги, где солнце не ниже порога; подряд идущие образуют отрезок, перерыв разрывает ломаную.
    public static func visible(_ arc: [SunSample]) -> [SunSample] {
        arc.filter { $0.altitude >= visibleFrom }
    }

    /// Видимая высота по геометрической: добавка рефракции по Сэмундссону (из геометрической высоты в видимую),
    /// `R = 1,02′ / tan(h + 10,3 / (h + 5,11))`. На горизонте добавка ≈ 0,48°, на 10° — 0,09°, на 45° — 0,02°.
    /// Ниже −1° формула расходится, поэтому добавка держится на значении при −1°.
    public static func apparent(altitude h: Degrees) -> Degrees {
        let g = max(h, -1)
        let arg = (g + 10.3 / (g + 5.11)) * Double.pi / 180
        let arcminutes = 1.02 / tan(arg)
        return h + arcminutes / 60
    }
}
