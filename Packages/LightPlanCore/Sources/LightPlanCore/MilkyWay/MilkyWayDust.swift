import Foundation

/// Облако точек Млечного Пути на приборе карты (`MW_DUST`, `MW_HAZE` веба).
///
/// Не рисунок, а данные: какие точки неба стоят на холсте и какого они калибра,
/// должно совпадать с вебом точка в точку, иначе пара снимков веб / натив
/// расходится на каждой точке (итерация 20а). Поэтому генератор перенесён
/// дословно — свой LCG с зашитым зерном, а не `random`: поле одинаковое при
/// каждом запуске и на каждом устройстве.
public enum MilkyWayDust {

    /// Точка облака. `tier` — калибр (0 крупнейший … 4 мельчайший), `fade` —
    /// свой порог угасания у горизонта: точки гаснут по одной и всегда одни и
    /// те же, без мерцания при движении ползунка.
    public struct Point: Sendable, Equatable {
        public let equatorial: EquatorialPoint
        public let tier: Int
        public let fade: Double
    }

    /// Между нулём и `haze` градусами облако тает (`MW_HAZE`).
    public static let haze: Degrees = 8

    /// Около семисот точек; считается один раз при первом обращении.
    public static let points: [Point] = build()

    /// Видна ли точка на этой высоте: под горизонтом точек нет, в дымке у
    /// горизонта гаснут те, чей порог выше доли пройденной дымки.
    public static func visible(_ p: Point, altitude: Degrees) -> Bool {
        if altitude < 0 { return false }
        if altitude < haze && altitude / haze < p.fade { return false }
        return true
    }

    /// `MW_DUST` веба. Порядок вызовов `rnd()` — часть данных: каждая точка
    /// берёт долготу, три слагаемых колокола, ярус и порог — ровно в этом
    /// порядке.
    static func build() -> [Point] {
        var rng = WebLCG(seed: 20260817)
        let step = 3.0, total = 700.0
        var weights: [Double] = []
        var sum = 0.0
        var l = 0.0
        while l < 360 {
            let w = MilkyWay.halfWidth(galacticLongitude: l)
            weights.append(w); sum += w
            l += step
        }
        var out: [Point] = []
        out.reserveCapacity(720)
        for (i, w) in weights.enumerated() {
            let l0 = Double(i) * step
            let n = max(1, Int((total * w / sum).rounded(.toNearestOrAwayFromZero)))
            for _ in 0..<n {
                let lp = l0 + rng.next() * step
                let bell = (rng.next() + rng.next() + rng.next()) / 1.5 - 1
                let wl = MilkyWay.halfWidth(galacticLongitude: lp)
                let dl = abs(((lp + 180).truncatingRemainder(dividingBy: 360)) - 180)
                let bright = (0.35 + 0.65 * cos(Sky.rad(dl) / 2)) * (1 - 0.55 * abs(bell))
                let r = rng.next()
                let tier = r < bright * 0.14 ? 0
                    : r < bright * 0.34 ? 1
                    : r < bright * 0.62 ? 2
                    : r < bright * 0.86 ? 3 : 4
                out.append(Point(equatorial: MilkyWay.equatorial(galacticLongitude: lp, galacticLatitude: bell * wl),
                                 tier: tier, fade: rng.next()))
            }
        }
        return out
    }
}

/// Генератор веба: `seed = (seed * 1103515245 + 12345) & 0x7fffffff`.
/// В JS произведение — двойная точность, и при зерне около 2³¹ оно
/// перерастает 2⁵³: младшие биты округляются до маски. Повторяем ту же
/// арифметику, а не честное 64-битное умножение, — иначе поле разошлось бы
/// с вебом с первой же точки.
struct WebLCG {
    private var seed: Double

    init(seed: Int) { self.seed = Double(seed) }

    mutating func next() -> Double {
        // Два шага раздельно, как в JS: произведение округляется, потом сумма.
        let product = seed * 1103515245
        let sum = product + 12345
        // ToInt32 и маска: у целого double младшие 31 бит берутся из Int64.
        let wide = Int64(sum.truncatingRemainder(dividingBy: 4_294_967_296))
        seed = Double(wide & 0x7fff_ffff)
        return seed / 2_147_483_647
    }
}
