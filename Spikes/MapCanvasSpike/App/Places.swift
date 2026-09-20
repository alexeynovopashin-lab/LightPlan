import Foundation

/// Положение светила — не продуктовая модель, а ровно столько, сколько нужно
/// прибору песочницы, чтобы путь солнца отличался между городом и природой и
/// между летом и зимой. В продукт это не едет: там `Solar Engine` (итерация 7).
/// Формула — упрощённый NOAA: склонение и уравнение времени по дню года.
struct Sun {
    /// Азимут в градусах от севера по часовой и высота в градусах.
    static func position(lat: Double, lon: Double, date: Date, hourUTC: Double) -> (az: Double, alt: Double) {
        let cal = Calendar(identifier: .gregorian)
        let n = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let g = 2 * .pi / 365 * (n - 1 + (hourUTC - 12) / 24)
        let decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g)
            - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g)
            - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
        let eqt = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g)
            - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
        let trueSolarMin = hourUTC * 60 + eqt + 4 * lon
        let ha = (trueSolarMin / 4 - 180) * .pi / 180
        let latR = lat * .pi / 180
        let sinAlt = sin(latR) * sin(decl) + cos(latR) * cos(decl) * cos(ha)
        let alt = asin(max(-1, min(1, sinAlt)))
        let cosAz = (sin(decl) - sin(alt) * sin(latR)) / (cos(alt) * cos(latR))
        var az = acos(max(-1, min(1, cosAz)))
        if ha > 0 { az = 2 * .pi - az }
        return (az * 180 / .pi, alt * 180 / .pi)
    }
}
