import Foundation

/// Точное Солнце одних суток одного места — вторая модель `SolarDay` (`.iau`, шаг 29.8в.25).
///
/// Положение берётся из `SunMoonTheory.sun` (Меёс, гл. 25), звёздное время — из `SiderealTime` (IAU), перевод в азимут и
/// высоту — та же формула, что у `SkyFrame.horizontal(ofDate:)`: это то самое Солнце, которое рисует AR (`SunTrack`),
/// поэтому «Свет» и AR показывают один закат. Против JPL Horizons: ≤ 0,01° по положению, ≤ 0,12 минуты по времени
/// событий (до 0,55 у Тромсё, где Солнце скользит вдоль горизонта и время события плохо определено).
///
/// Теория считается **три раза за сутки**, а не на каждую минуту: прямое восхождение и склонение в узлах
/// «местный полдень ± сутки» и парабола через них. Ошибка параболы на сутках ≤ 1·10⁻⁵° (третья производная
/// склонения и уравнения времени мала), ниже ошибки самой теории; зато `elevation(at:)` стоит как у веба, а не в
/// десять раз дороже — ленте, куполу и планировщику это важно (`SolarDay` строится на каждый день барабана).
struct ExactSun: Sendable, Equatable {
    private let sinLat: Double
    private let cosLat: Double
    private let lon: Double
    /// Дни от J2000 в местном полдне суток (минута 720): центр параболы, `u = 0`.
    private let dc: Double
    // Парабола по u = дни от центра: f(u) = f0 + f1·u + f2·u².
    private let ra0: Double, ra1: Double, ra2: Double
    private let dec0: Double, dec1: Double, dec2: Double
    /// Точное время прохождения Солнца через меридиан, минуты шкалы суток.
    let noon: Double

    init(date: CivilDate, latitude: Double, longitude: Double, utcOffsetHours: Double) {
        sinLat = sin(Sky.rad(latitude))
        cosLat = cos(Sky.rad(latitude))
        lon = longitude
        let center = Sky.days(date: date, minutes: 720, utcOffsetHours: utcOffsetHours)
        dc = center
        let before = SunMoonTheory.sun(days: center - 1)
        let at = SunMoonTheory.sun(days: center)
        let after = SunMoonTheory.sun(days: center + 1)
        /* Прямое восхождение приходит из atan2 и прыгает на 2π: узлы считаем относительно среднего. */
        func wrap(_ x: Double) -> Double { x - 2 * Double.pi * (x / (2 * Double.pi)).rounded() }
        let a = wrap(before.ra - at.ra), b = wrap(after.ra - at.ra)
        ra0 = at.ra; ra1 = (b - a) / 2; ra2 = (a + b) / 2
        let c = before.dec - at.dec, d = after.dec - at.dec
        dec0 = at.dec; dec1 = (d - c) / 2; dec2 = (c + d) / 2

        /* Прохождение через меридиан: часовой угол Солнца равен нулю. Два шага Ньютона от среднего полдня. */
        var t = 720 - 4 * longitude + utcOffsetHours * 60
        for _ in 0..<3 {
            let u = (t - 720) / 1440
            let ra = ra0 + ra1 * u + ra2 * u * u
            let lst = Sky.rad(SiderealTime.localMean(days: center + u, longitude: longitude))
            var h = (lst - ra).truncatingRemainder(dividingBy: 2 * Double.pi)
            if h > Double.pi { h -= 2 * Double.pi } else if h < -Double.pi { h += 2 * Double.pi }
            // Часовой угол растёт на 360,9856°/сутки за вычетом хода прямого восхождения.
            let rate = (Sky.rad(360.98564736629) - (ra1 + 2 * ra2 * u)) / 1440
            t -= h / rate
        }
        noon = t
    }

    /// Склонение Солнца в минуту `t`, радианы.
    func declination(at t: Double) -> Double {
        let u = (t - 720) / 1440
        return dec0 + dec1 * u + dec2 * u * u
    }

    /// Часовой угол и склонение в минуту `t` (радианы).
    private func hourAngleAndDeclination(at t: Double) -> (h: Double, dec: Double) {
        let u = (t - 720) / 1440
        let ra = ra0 + ra1 * u + ra2 * u * u
        let lst = Sky.rad(SiderealTime.localMean(days: dc + u, longitude: lon))
        return (lst - ra, dec0 + dec1 * u + dec2 * u * u)
    }

    func elevation(at t: Double) -> Double {
        let (h, dec) = hourAngleAndDeclination(at: t)
        let s = sinLat * sin(dec) + cosLat * cos(dec) * cos(h)
        return Sky.deg(asin(max(-1, min(1, s))))
    }

    func azimuth(at t: Double) -> Double {
        let (h, dec) = hourAngleAndDeclination(at: t)
        let a = atan2(sin(h), cos(h) * sinLat - tan(dec) * cosLat)
        return (Sky.deg(a) + 180 + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Минута, когда центр Солнца пересекает высоту `h`: утром (`rising`) или вечером. До полудня высота растёт от
    /// полуночи, после — падает, поэтому событие ищется делением пополам на половине суток; `nil`, если за сутки
    /// Солнце до этой высоты не доходит или не опускается ниже неё.
    func time(atElevation h: Double, rising: Bool) -> Double? {
        let top = elevation(at: noon) - h
        if top < 0 { return nil }
        var lo: Double, hi: Double, fLo: Double, fHi: Double
        if rising {
            lo = noon - 720; hi = noon
            fLo = elevation(at: lo) - h; fHi = top
            if fLo >= 0 { return nil }
        } else {
            lo = noon; hi = noon + 720
            fLo = top; fHi = elevation(at: hi) - h
            if fHi >= 0 { return nil }
        }
        /* Метод Иллинойса: деление пополам, но с шагом по секущей — 8–10 вычислений вместо двадцати пяти. */
        var side = 0
        for _ in 0..<60 {
            let mid = (lo * fHi - hi * fLo) / (fHi - fLo)
            let fMid = elevation(at: mid) - h
            if abs(hi - lo) < 1e-6 || abs(fMid) < 1e-10 { return mid }
            if (fMid > 0) == (fHi > 0) {
                hi = mid; fHi = fMid
                if side == -1 { fLo /= 2 }
                side = -1
            } else {
                lo = mid; fLo = fMid
                if side == 1 { fHi /= 2 }
                side = 1
            }
        }
        return (lo + hi) / 2
    }
}
