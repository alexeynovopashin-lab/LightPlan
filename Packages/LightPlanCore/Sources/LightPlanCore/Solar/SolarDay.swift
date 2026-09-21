import Foundation

/// Минуты шкалы суток. Дробные и могут выходить за 0…1440: шкала идёт от
/// солнечной полуночи, а не от полуночи по часам.
public typealias Minutes = Double
/// Градусы.
public typealias Degrees = Double

/// Солнце одних суток одного места.
///
/// Порт `computeSun`, `elevAt`, `azAt`, `tAtElev`, `shadowAt` из
/// `light_plan:Light_Plan/beta/index.html` (NOAA). Значение-тип без глобалов:
/// соседний день — второй экземпляр, приём «сохранить → посчитать → вернуть»
/// из веба здесь не нужен.
///
/// **Порядок операций тот же, что в JS, и его нельзя «упрощать».**
/// Сложение и умножение double не ассоциативны, а на границе
/// `c = ±1` в `timeAtElevation` ответ «есть событие / нет события» держится на
/// последнем бите. Единственное отступление — то, что чистые функции
/// (`sin(rad(lat))`, `cos(decl)`) посчитаны один раз, а не при каждом вызове:
/// результат тот же бит в бит, зато купол по пальцу не тратит их заново.
public struct SolarDay: Sendable, Equatable {

    /// Полярность суток: `.day` — солнце не заходит, `.night` — не восходит.
    /// Сырые значения — те же 1 / 0 / −1, что в `SUN.polar` веба.
    public enum PolarState: Int, Sendable {
        case night = -1
        case normal = 0
        case day = 1
    }

    /// Склонение солнца в **радианах**, как `decl` в вебе.
    public let declination: Double
    public let solarNoon: Minutes
    /// Начало и конец шкалы суток: солнечная полночь и следующая за ней.
    /// В вебе `MINT` и `MAXT`; названия оставлены, чтобы сверять по grep.
    public let mint: Minutes
    public let maxt: Minutes

    public let rise: Minutes?
    public let set: Minutes?
    public let goldenA: Minutes?
    public let goldenB: Minutes?
    public let blueA: Minutes?
    public let blueB: Minutes?
    public let civilA: Minutes?
    public let civilB: Minutes?
    public let nauticalA: Minutes?
    public let nauticalB: Minutes?
    public let astroA: Minutes?
    public let astroB: Minutes?

    /// Высота солнца в солнечный полдень.
    public let maxElevation: Degrees
    public let polar: PolarState
    /// Дуга светила на куполе: восход→закат, а в полярные сутки — вся шкала,
    /// чтобы солнце не превращалось в NaN, а ехало по кругу.
    public let arcA: Minutes
    public let arcB: Minutes

    private let frame: Frame

    // MARK: - Входы

    /// Ядро сверки с вебом: смещение пояса задано явно.
    ///
    /// Дробное на самом деле: Катманду 5.75, Чатем 12.75 — с `Int` эти места
    /// молча сдвигаются на четверть часа. Это то, что проверяет стенд.
    public init(date: CivilDate, latitude: Double, longitude: Double, utcOffsetHours: Double) {
        let doy = Double(date.ordinal)
        let g = 2 * Double.pi / 365 * (doy - 1 + 0.5)
        let decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g)
            - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g)
            - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
        let eq = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g)
            - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
        let noon = 720 - 4 * longitude - eq + utcOffsetHours * 60

        let frame = Frame(latitude: latitude, declination: decl, solarNoon: noon)
        self.frame = frame
        self.declination = decl
        self.solarNoon = noon
        /* Сутки всегда идут от полуночи до полуночи (веб: забраковано сдвигать
           шкалу на полдень — она обязана быть одной и той же всегда). */
        self.mint = noon - 720
        self.maxt = (noon - 720) + 1440

        let rise = frame.time(atElevation: -0.833, rising: true)
        let set = frame.time(atElevation: -0.833, rising: false)
        self.rise = rise
        self.set = set
        self.goldenA = frame.time(atElevation: 6, rising: true)
        self.goldenB = frame.time(atElevation: 6, rising: false)
        self.blueA = frame.time(atElevation: -4, rising: true)
        self.blueB = frame.time(atElevation: -4, rising: false)
        self.civilA = frame.time(atElevation: -6, rising: true)
        self.civilB = frame.time(atElevation: -6, rising: false)
        self.nauticalA = frame.time(atElevation: -12, rising: true)
        self.nauticalB = frame.time(atElevation: -12, rising: false)
        self.astroA = frame.time(atElevation: -18, rising: true)
        self.astroB = frame.time(atElevation: -18, rising: false)

        let maxElev = frame.elevation(at: noon)
        self.maxElevation = maxElev
        /* Полярные сутки: солнце не пересекает горизонт — восхода и заката нет. */
        if rise == nil && set == nil {
            self.polar = maxElev >= -0.833 ? .day : .night
        } else {
            self.polar = .normal
        }
        self.arcA = rise ?? (noon - 720)
        self.arcB = set ?? ((noon - 720) + 1440)
    }

    /// Смещение пояса берётся на дату из зоны места.
    ///
    /// Решение исполнителя, из кода: момент отсчёта — начало этого дня по часам
    /// зоны места (`ZoneID.utcOffsetHours(on:)`). Веб зовёт
    /// `tzAt(lat, lon, day)` с тем же `Date`, что и `computeSun(day)`.
    /// Подробности — DECISIONS.
    public init(date: CivilDate, place: Place) {
        self.init(
            date: date,
            latitude: place.latitude,
            longitude: place.longitude,
            utcOffsetHours: place.zone.utcOffsetHours(on: date)
        )
    }

    // MARK: - Положение солнца

    /// Высота над горизонтом, градусы.
    public func elevation(at t: Minutes) -> Degrees { frame.elevation(at: t) }

    /// Азимут, градусы от севера по часовой стрелке, в `[0, 360)`.
    public func azimuth(at t: Minutes) -> Degrees { frame.azimuth(at: t) }

    /// Длина тени в ростах предмета. `nil`, если солнце ниже 0.5° или тень
    /// длиннее сорока ростов.
    public func shadowRatio(at t: Minutes) -> Double? {
        let e = frame.elevation(at: t)
        if e <= 0.5 { return nil }
        let s = 1 / tan(rad(e))
        return s > 40 ? nil : s
    }
}

// MARK: - Тригонометрия и вспомогательное

/// В вебе `rad = d * Math.PI / 180`: сначала умножение, потом деление.
/// Замена на `d * (π / 180)` даёт другой последний бит.
private func rad(_ d: Double) -> Double { d * Double.pi / 180 }
private func deg(_ r: Double) -> Double { r * 180 / Double.pi }

/// `Math.max(a, Math.min(b, v))`. У JS NaN проходит сквозь `min` и `max`;
/// у Swift `min(1, .nan)` вернул бы 1, поэтому NaN отдан вручную.
private func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double {
    if v.isNaN { return v }
    return max(a, min(b, v))
}

/// Всё, что не зависит от минуты, посчитано один раз. Произведения связаны
/// теми же скобками, что в JS: `sin(lat)·sin(decl)` и `(cos(lat)·cos(decl))·cos(ha)`.
private struct Frame: Sendable, Equatable {
    let sinLat: Double
    let cosLat: Double
    let tanDecl: Double
    let sinLatSinDecl: Double
    let cosLatCosDecl: Double
    let solarNoon: Double

    init(latitude: Double, declination decl: Double, solarNoon: Double) {
        let latR = rad(latitude)
        sinLat = sin(latR)
        cosLat = cos(latR)
        tanDecl = tan(decl)
        sinLatSinDecl = sin(latR) * sin(decl)
        cosLatCosDecl = cos(latR) * cos(decl)
        self.solarNoon = solarNoon
    }

    func elevation(at t: Double) -> Double {
        let ha = rad((t - solarNoon) * 0.25)
        let s = sinLatSinDecl + cosLatCosDecl * cos(ha)
        return deg(asin(clamp(s, -1, 1)))
    }

    func azimuth(at t: Double) -> Double {
        let ha = rad((t - solarNoon) * 0.25)
        let a = atan2(sin(ha), cos(ha) * sinLat - tanDecl * cosLat)
        /* JS `%` — остаток с усечением, знак делимого; `remainder` округлял бы
           к ближайшему и перевернул бы знак. */
        return (deg(a) + 180 + 360).truncatingRemainder(dividingBy: 360)
    }

    func time(atElevation h: Double, rising: Bool) -> Double? {
        let c = (sin(rad(h)) - sinLatSinDecl) / cosLatCosDecl
        if c > 1 || c < -1 { return nil }
        let ha = deg(acos(c))
        return solarNoon + (rising ? -ha * 4 : ha * 4)
    }
}
