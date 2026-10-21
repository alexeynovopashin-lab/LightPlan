import Foundation

/// Каким звёздным временем считать положение на небе. `.web` — константа беты (паритет «Света», «Карты», купола),
/// `.iau` — слои AR (`SkyFrame`). По умолчанию везде `.web`: паритет с вебом не двигается сам.
public enum SkyTime: Sendable { case web, iau }

/// Звёздное время и перевод точки неба в азимут и высоту — **одно на все слои AR** (шаг 29.8в.21).
///
/// Веб считает звёздное время по `280,16 + 360,9856235 · d` (`Sky.horizontal`): константа и скорость округлены, и к
/// 2026 году время отстаёт от IAU на 0,53° (измерено против JPL Horizons). Луна, звёзды, Млечный Путь и планеты
/// стояли на небе в разных местах одного кадра. Слои AR теперь идут через `SkyFrame`: звёздное время по IAU,
/// прецессия на дату для каталожных точек J2000. `Sky.horizontal` остался как был — на нём держится паритет с вебом
/// («Свет», «Карта», созвездия-купол).
public enum SiderealTime {

    /// Среднее гринвичское звёздное время, градусы `0 ..< 360`. `days` — дни от J2000 по UTC; разница UT1 − UTC
    /// (< 0,9 с = 0,004°) не учитывается. Формула Меёса 12.4 (IAU 1982), на 2026 год совпадает с IAU 2006 до 0,0001°.
    public static func greenwichMean(days: Double) -> Double {
        let t = days / 36_525
        let g = 280.46061837 + 360.98564736629 * days + 0.000387933 * t * t - t * t * t / 38_710_000
        let r = g.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Местное среднее звёздное время, градусы; долгота — к востоку положительная.
    public static func localMean(days: Double, longitude: Double) -> Double {
        let r = (greenwichMean(days: days) + longitude).truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}

/// Небо одного момента и одного места: звёздное время и прецессия считаются один раз, потом сколько угодно точек.
public struct SkyFrame: Sendable {
    private let lat: Double
    private let sinLat: Double
    private let cosLat: Double
    /// Местное звёздное время, радианы.
    private let lst: Double
    /// Матрица прецессии J2000 → средний экватор и равноденствие даты (по строкам).
    private let p: (Double, Double, Double, Double, Double, Double, Double, Double, Double)

    public init(days: Double, latitude: Double, longitude: Double) {
        lat = Sky.rad(latitude)
        sinLat = sin(Sky.rad(latitude))
        cosLat = cos(Sky.rad(latitude))
        lst = Sky.rad(SiderealTime.localMean(days: days, longitude: longitude))
        p = Self.precession(centuries: days / 36_525)
    }

    /// Точка в координатах **даты** (Солнце, Луна, планеты): считаются уже на равноденствие даты.
    public func horizontal(ofDate point: EquatorialPoint) -> HorizontalPoint {
        horizontal(ra: point.ra, dec: point.dec)
    }

    /// Точка каталога в координатах **J2000** (звёзды, Млечный Путь): сначала прецессия на дату.
    public func horizontal(j2000 point: EquatorialPoint) -> HorizontalPoint {
        let cd = cos(point.dec)
        let x = cd * cos(point.ra), y = cd * sin(point.ra), z = sin(point.dec)
        let u = p.0 * x + p.1 * y + p.2 * z
        let v = p.3 * x + p.4 * y + p.5 * z
        let w = p.6 * x + p.7 * y + p.8 * z
        return horizontal(ra: atan2(v, u), dec: asin(max(-1, min(1, w))))
    }

    /// Точка в координатах даты, **как её видит наблюдатель на поверхности Земли**, а не из центра: суточный параллакс
    /// (Меё, гл. 40). `distanceKm` — расстояние до тела от центра Земли. Годится для Луны (до 0,95° у горизонта, ноль в
    /// зените); для Солнца и планет сдвиг меньше 9″ и не нужен. Высота наблюдателя над уровнем моря — `heightMeters`
    /// (`Place` её не хранит, AR считает от уровня моря: 1 км высоты сдвигают Луну на 0,00015°).
    public func horizontal(ofDate point: EquatorialPoint, distanceKm: Double, heightMeters: Double = 0) -> HorizontalPoint {
        let (rhoSin, rhoCos) = Self.observer(latitude: lat, heightMeters: heightMeters)
        let sinPi = Self.earthEquatorialRadiusKm / distanceKm
        let h = lst - point.ra
        // Меё 40.2 – 40.3: сдвиг прямого восхождения и новое склонение.
        let dRa = atan2(-rhoCos * sinPi * sin(h), cos(point.dec) - rhoCos * sinPi * cos(h))
        let dec = atan2((sin(point.dec) - rhoSin * sinPi) * cos(dRa), cos(point.dec) - rhoCos * sinPi * cos(h))
        return horizontal(ra: point.ra + dRa, dec: dec)
    }

    /// Экваториальный радиус Земли (WGS-84 / IAU), км: единица, в которой Меё меряет параллакс.
    static let earthEquatorialRadiusKm = 6_378.14

    /// ρ·sin φ′ и ρ·cos φ′ (Меё гл. 11): геоцентрическая широта наблюдателя на эллипсоиде, ρ — в экваториальных радиусах.
    static func observer(latitude lat: Double, heightMeters h: Double) -> (sin: Double, cos: Double) {
        let u = atan(0.99664719 * tan(lat))
        return (0.99664719 * sin(u) + h / 6_378_140 * sin(lat), cos(u) + h / 6_378_140 * cos(lat))
    }

    private func horizontal(ra: Double, dec: Double) -> HorizontalPoint {
        let h = lst - ra
        let alt = asin(sinLat * sin(dec) + cosLat * cos(dec) * cos(h))
        let az = atan2(sin(h), cos(h) * sinLat - tan(dec) * cosLat)
        return HorizontalPoint(altitude: Sky.deg(alt), azimuth: (Sky.deg(az) + 180 + 360).truncatingRemainder(dividingBy: 360))
    }

    /// Прецессия J2000 → средний экватор и равноденствие даты: углы ζ, z, θ (IAU 1976, Lieske), `t` — юлианские века
    /// от J2000. Без массивов и замыканий: `SkyFrame` строится на каждую точку дуги, и на 2026 год углы расходятся с
    /// IAU 2006 на сотые доли угловой секунды (`SkyTimeTests` сверяет Сириус с прецессией 2006).
    static func precession(centuries t: Double)
        -> (Double, Double, Double, Double, Double, Double, Double, Double, Double) {
        let as_ = Double.pi / 648_000
        let zeta = (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) * as_
        let z = (2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) * as_
        let theta = (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) * as_
        let cz = cos(zeta), sz = sin(zeta), cZ = cos(z), sZ = sin(z), ct = cos(theta), st = sin(theta)
        return (cz * ct * cZ - sz * sZ, -sz * ct * cZ - cz * sZ, -st * cZ,
                cz * ct * sZ + sz * cZ, -sz * ct * sZ + cz * cZ, -st * sZ,
                cz * st, -sz * st, ct)
    }
}
