import Foundation

/// Положение и блеск пяти планет, видимых глазом (шаг 29.8в.15). Без каталога: орбиты считаются по формулам.
///
/// **Источник формул.** Paul Schlyter, «How to compute planetary positions»
/// (https://stjarnhimlen.se/comp/ppcomp.html): элементы орбит с линейным дрейфом от дня 1999-12-31 0:00 UT,
/// возмущения Юпитера и Сатурна друг от друга, формулы видимой величины. Это общедоступная публикация автора:
/// лицензии на неё нет, а сами формулы — наблюдательные константы и математика, которые авторским правом не
/// защищены. Код написан здесь заново, текст страницы не копировался. Орбитальные элементы там сняты с общедоступных
/// таблиц Standish (JPL), возмущения — из Meeus, «Astronomical Algorithms» (используется только их числовой вид).
///
/// **Точность** (по автору — около 1–2 угловых минут для 1990–2100): положения даны на равноденствие даты, как
/// склонение и восхождение для часового угла, — прецессию вводить не нужно. Не учтены: параллакс (у планет меньше
/// 0,01°), аберрация и время света (≈ 0,005°). Допуск шага — 0,5° (Венера, Марс, Юпитер, Сатурн) и 1° (Меркурий);
/// измеренные расхождения записаны в тестах и в DECISIONS.
///
/// **Блеск.** Меркурий и Сатурн — формулы Schlyter. Венера, Марс и Юпитер — полиномы по фазовому углу из
/// A. Mallama, J. L. Hilton, «Computing Apparent Planetary Magnitudes for The Astronomical Almanac»,
/// Astronomy and Computing 25 (2018), arXiv:1808.02992 (общедоступная статья; взяты числа формул, без добавок
/// на широту и долготу центрального меридиана Марса и без кольца Сатурна — он по Schlyter). Причина замены:
/// у Schlyter Юпитер стабильно на 0,2 слабее Horizons, Венера вблизи верхнего соединения на 0,46.
///
/// Уран и Нептун не нужны: глазом не видны (слово Алексея 18.10: планеты — отдельным слоем).
public enum Planet: String, CaseIterable, Sendable {
    case mercury, venus, mars, jupiter, saturn

    /// Ключ слова в словаре (`planet.venus`).
    public var nameKey: String { "planet." + rawValue }
}

/// Планета на небе на момент: восхождение и склонение в **радианах** (как `EquatorialPoint`), видимая величина и
/// удаление от Солнца.
public struct PlanetPosition: Sendable, Equatable {
    public let planet: Planet
    /// Экваториальные координаты на равноденствие даты.
    public let point: EquatorialPoint
    /// Видимая величина (меньше — ярче).
    public let magnitude: Double
    /// Угол между планетой и Солнцем на небе, градусы `0 … 180`.
    public let elongation: Degrees
    /// Расстояние от Земли, а.е.
    public let distance: Double

    public init(planet: Planet, point: EquatorialPoint, magnitude: Double, elongation: Degrees, distance: Double) {
        self.planet = planet; self.point = point; self.magnitude = magnitude
        self.elongation = elongation; self.distance = distance
    }
}

public enum PlanetEphemeris {

    /// Все пять планет на момент `days` (дни от J2000, как у `Sky.days`).
    public static func all(days: Double) -> [PlanetPosition] {
        Planet.allCases.map { position($0, days: days) }
    }

    // MARK: - Элементы

    /// Орбитальные элементы на день `d`: линейный дрейф `начало + скорость · d`. Углы — градусы.
    private struct Elements {
        let n: (Double, Double), i: (Double, Double), w: (Double, Double)
        let a: Double
        let e: (Double, Double)
        let m: (Double, Double)

        func at(_ d: Double) -> (n: Double, i: Double, w: Double, a: Double, e: Double, m: Double) {
            (n.0 + n.1 * d, i.0 + i.1 * d, w.0 + w.1 * d, a, e.0 + e.1 * d, m.0 + m.1 * d)
        }
    }

    private static func elements(_ p: Planet) -> Elements {
        switch p {
        case .mercury:
            return Elements(n: (48.3313, 3.24587e-5), i: (7.0047, 5.00e-8), w: (29.1241, 1.01444e-5), a: 0.387098,
                            e: (0.205635, 5.59e-10), m: (168.6562, 4.0923344368))
        case .venus:
            return Elements(n: (76.6799, 2.46590e-5), i: (3.3946, 2.75e-8), w: (54.8910, 1.38374e-5), a: 0.723330,
                            e: (0.006773, -1.302e-9), m: (48.0052, 1.6021302244))
        case .mars:
            return Elements(n: (49.5574, 2.11081e-5), i: (1.8497, -1.78e-8), w: (286.5016, 2.92961e-5), a: 1.523688,
                            e: (0.093405, 2.516e-9), m: (18.6021, 0.5240207766))
        case .jupiter:
            return Elements(n: (100.4542, 2.76854e-5), i: (1.3030, -1.557e-7), w: (273.8777, 1.64505e-5), a: 5.20256,
                            e: (0.048498, 4.469e-9), m: (19.8950, 0.0830853001))
        case .saturn:
            return Elements(n: (113.6634, 2.38980e-5), i: (2.4886, -1.081e-7), w: (339.3939, 2.97661e-5), a: 9.55475,
                            e: (0.055546, -9.499e-9), m: (316.9670, 0.0334442282))
        }
    }

    // MARK: - Расчёт

    private static func rad(_ d: Double) -> Double { Sky.rad(d) }

    /// Эксцентрическая аномалия из средней: первое приближение и поправки Ньютона до 1e-12 рад (для эксцентриситетов
    /// планет — три-четыре шага).
    private static func eccentricAnomaly(mean m: Double, e: Double) -> Double {
        var ea = m + e * sin(m) * (1 + e * cos(m))
        for _ in 0..<20 {
            let step = (ea - e * sin(ea) - m) / (1 - e * cos(ea))
            ea -= step
            if abs(step) < 1e-12 { break }
        }
        return ea
    }

    /// Истинная аномалия и расстояние до Солнца в а.е. по орбите: `(v, r)`.
    private static func orbit(mean m: Double, e: Double, a: Double) -> (v: Double, r: Double) {
        let ea = eccentricAnomaly(mean: m, e: e)
        let x = a * (cos(ea) - e), y = a * (1 - e * e).squareRoot() * sin(ea)
        return (atan2(y, x), (x * x + y * y).squareRoot())
    }

    /// Средняя аномалия, градусы приведены к `0 … 360`.
    private static func norm(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Положение Солнца с Земли в эклиптических координатах (плоскость z = 0): `(x, y, расстояние)`, а.е.
    private static func sun(d: Double) -> (x: Double, y: Double, r: Double) {
        let m = rad(norm(356.0470 + 0.9856002585 * d))
        let w = 282.9404 + 4.70935e-5 * d
        let e = 0.016709 - 1.151e-9 * d
        let o = orbit(mean: m, e: e, a: 1)
        let lon = o.v + rad(w)
        return (o.r * cos(lon), o.r * sin(lon), o.r)
    }

    /// Возмущения долготы и широты Юпитера и Сатурна друг от друга, градусы. `mj`, `ms` — средние аномалии
    /// (градусы).
    private static func perturbation(_ p: Planet, mj: Double, ms: Double) -> (lon: Double, lat: Double) {
        func sd(_ x: Double) -> Double { sin(rad(x)) }
        func cd(_ x: Double) -> Double { cos(rad(x)) }
        switch p {
        case .jupiter:
            let lon = -0.332 * sd(2 * mj - 5 * ms - 67.6) - 0.056 * sd(2 * mj - 2 * ms + 21)
                + 0.042 * sd(3 * mj - 5 * ms + 21) - 0.036 * sd(mj - 2 * ms) + 0.022 * cd(mj - ms)
                + 0.023 * sd(2 * mj - 3 * ms + 52) - 0.016 * sd(mj - 5 * ms - 69)
            return (lon, 0)
        case .saturn:
            let lon = 0.812 * sd(2 * mj - 5 * ms - 67.6) - 0.229 * cd(2 * mj - 4 * ms - 2)
                + 0.119 * sd(mj - 2 * ms - 3) + 0.046 * sd(2 * mj - 6 * ms - 69) + 0.014 * sd(mj - 3 * ms + 32)
            let lat = -0.020 * cd(2 * mj - 4 * ms - 2) + 0.018 * sd(2 * mj - 6 * ms - 49)
            return (lon, lat)
        default:
            return (0, 0)
        }
    }

    /// Азимут и высота планеты для места: звёздное время IAU через `SkyFrame`, как у всех слоёв AR (шаг 29.8в.21).
    /// `Sky.horizontal` держит константу веба 280,16 и скорость 360,9856235: звёздное время у неё отстаёт на 0,30° в
    /// J2000 и ещё на 2,4·10⁻⁵ градуса в сутки (к 2026 году 0,53°, к 2030-му 0,57° — измерено против Horizons).
    /// Координаты планет уже на равноденствие даты, поэтому прецессия не нужна.
    public static func horizontal(_ p: PlanetPosition, days: Double, latitude: Double, longitude: Double) -> HorizontalPoint {
        SkyFrame(days: days, latitude: latitude, longitude: longitude).horizontal(ofDate: p.point)
    }

    /// Планета на момент `days` (дни от J2000).
    public static func position(_ planet: Planet, days: Double) -> PlanetPosition {
        // Schlyter считает дни от 1999-12-31 0:00 UT: на 1,5 суток позже J2000.
        let d = days + 1.5
        let el = elements(planet).at(d)
        let s = sun(d: d)

        // Гелиоцентрическая эклиптическая позиция по невозмущённой орбите.
        let o = orbit(mean: rad(norm(el.m)), e: el.e, a: el.a)
        let n = rad(el.n), inc = rad(el.i), vw = o.v + rad(el.w)
        var xh = o.r * (cos(n) * cos(vw) - sin(n) * sin(vw) * cos(inc))
        var yh = o.r * (sin(n) * cos(vw) + cos(n) * sin(vw) * cos(inc))
        var zh = o.r * sin(vw) * sin(inc)

        // Возмущения Юпитера и Сатурна: правятся долгота и широта, потом вектор собирается заново.
        if planet == .jupiter || planet == .saturn {
            let mj = norm(elements(.jupiter).at(d).m), ms = norm(elements(.saturn).at(d).m)
            let pert = perturbation(planet, mj: mj, ms: ms)
            let lon = atan2(yh, xh) + rad(pert.lon)
            let lat = atan2(zh, (xh * xh + yh * yh).squareRoot()) + rad(pert.lat)
            let r = (xh * xh + yh * yh + zh * zh).squareRoot()
            xh = r * cos(lon) * cos(lat); yh = r * sin(lon) * cos(lat); zh = r * sin(lat)
        }
        let rSun = (xh * xh + yh * yh + zh * zh).squareRoot()

        // Геоцентрический эклиптический вектор: положение планеты относительно Солнца плюс Солнца относительно Земли.
        let xg = xh + s.x, yg = yh + s.y, zg = zh
        let dist = (xg * xg + yg * yg + zg * zg).squareRoot()

        // Наклон эклиптики на дату, потом экваториальные координаты.
        let ecl = rad(23.4393 - 3.563e-7 * d)
        let xe = xg, ye = yg * cos(ecl) - zg * sin(ecl), ze = yg * sin(ecl) + zg * cos(ecl)
        let ra = atan2(ye, xe), dec = atan2(ze, (xe * xe + ye * ye).squareRoot())

        // Удаление от Солнца: угол между планетой и Солнцем, виденными с Земли (Солнце лежит в плоскости эклиптики).
        let cosElong = (xg * s.x + yg * s.y) / (dist * s.r)
        let elongation = Sky.deg(acos(min(1, max(-1, cosElong))))

        // Фазовый угол — при планете между Солнцем и Землёй.
        let cosPhase = (rSun * rSun + dist * dist - s.r * s.r) / (2 * rSun * dist)
        let phase = Sky.deg(acos(min(1, max(-1, cosPhase))))
        let base = 5 * log10(rSun * dist)
        let magnitude: Double
        switch planet {
        case .mercury: magnitude = -0.36 + base + 0.027 * phase + 2.2e-13 * pow(phase, 6)
        case .venus:
            // Mallama & Hilton 2018: два куска по фазовому углу; у Schlyter Венера у верхнего соединения ошибалась на 0,46.
            let f = phase
            magnitude = base + (f <= 163.7
                ? -4.384 - 1.044e-3 * f + 3.687e-4 * f * f - 2.814e-6 * pow(f, 3) + 8.938e-9 * pow(f, 4)
                : 236.05828 - 2.81914 * f + 8.39034e-3 * f * f)
        case .mars: magnitude = -1.601 + base + 0.02267 * phase - 0.0001302 * phase * phase
        case .jupiter: magnitude = -9.395 + base - 3.7e-4 * phase + 6.16e-4 * phase * phase
        case .saturn:
            // Кольца: наклон к лучу зрения по геоцентрической долготе и широте.
            let lon = atan2(yg, xg), lat = atan2(zg, (xg * xg + yg * yg).squareRoot())
            let ring = rad(28.06), node = rad(169.51 + 3.82e-5 * d)
            let b = asin(sin(lat) * cos(ring) - cos(lat) * sin(ring) * sin(lon - node))
            magnitude = -9.0 + base + 0.044 * phase + (-2.6 * sin(abs(b)) + 1.2 * sin(b) * sin(b))
        }
        return PlanetPosition(planet: planet, point: EquatorialPoint(ra: ra, dec: dec), magnitude: magnitude,
                              elongation: elongation, distance: dist)
    }
}
