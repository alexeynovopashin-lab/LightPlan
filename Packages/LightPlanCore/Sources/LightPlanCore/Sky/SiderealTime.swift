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
    private let sinLat: Double
    private let cosLat: Double
    /// Местное звёздное время, радианы.
    private let lst: Double
    /// Матрица прецессии J2000 → средний экватор и равноденствие даты (по строкам).
    private let p: (Double, Double, Double, Double, Double, Double, Double, Double, Double)

    public init(days: Double, latitude: Double, longitude: Double) {
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

    private func horizontal(ra: Double, dec: Double) -> HorizontalPoint {
        let h = lst - ra
        let alt = asin(sinLat * sin(dec) + cosLat * cos(dec) * cos(h))
        let az = atan2(sin(h), cos(h) * sinLat - tan(dec) * cosLat)
        return HorizontalPoint(altitude: Sky.deg(alt), azimuth: (Sky.deg(az) + 180 + 360).truncatingRemainder(dividingBy: 360))
    }

    /// Прецессия IAU 2006 (углы Фукушимы — Вильямс, Capitaine и др. 2003) без нутации: средний экватор даты.
    /// Матрица `R1(−εA) · R3(−ψ̄) · R1(φ̄) · R3(−γ̄)`.
    static func precession(centuries t: Double)
        -> (Double, Double, Double, Double, Double, Double, Double, Double, Double) {
        func poly(_ c: [Double]) -> Double { c.enumerated().reduce(0) { $0 + $1.element * pow(t, Double($1.offset)) } * Double.pi / 648_000 }
        let gam = poly([-0.052928, 10.556378, 0.4932044, -0.00031238, -0.000002788, 0.0000000260])
        let phi = poly([84381.412819, -46.811016, 0.0511268, 0.00053289, -0.000000440, -0.0000000176])
        let psi = poly([-0.041775, 5038.481484, 1.5584175, -0.00018522, -0.000026452, -0.0000000148])
        let eps = poly([84381.406, -46.836769, -0.0001831, 0.00200340, -0.000000576, -0.0000000434])
        typealias M = [[Double]]
        func r1(_ a: Double) -> M { [[1, 0, 0], [0, cos(a), sin(a)], [0, -sin(a), cos(a)]] }
        func r3(_ a: Double) -> M { [[cos(a), sin(a), 0], [-sin(a), cos(a), 0], [0, 0, 1]] }
        func mul(_ a: M, _ b: M) -> M { (0..<3).map { i in (0..<3).map { j in (0..<3).reduce(0) { $0 + a[i][$1] * b[$1][j] } } } }
        let m = mul(r1(-eps), mul(r3(-psi), mul(r1(phi), r3(-gam))))
        return (m[0][0], m[0][1], m[0][2], m[1][0], m[1][1], m[1][2], m[2][0], m[2][1], m[2][2])
    }
}
