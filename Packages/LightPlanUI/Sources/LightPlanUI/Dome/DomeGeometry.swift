import Foundation
import CoreGraphics
import LightPlanCore

/// Геометрия купола: положение светила на дуге дня и ночи, портал полярных
/// суток, глубина просвечивающего пятна, нужда в тени под диском.
///
/// Порт `posOn`, `nightAmp`, `polarAt`, `posAt`, `deepOf`, `shadeNeed` из
/// `light_plan:Light_Plan/beta/index.html`. Холст 390×240, та же сетка, что у
/// веба (`cx=195, cy=196, rx=163, ry=148`) — числа связывают дугу с горизонтом
/// и с размером `viewBox`, менять их значит менять картинку, не порт.
enum DomeGeometry {
    static let cx: Double = 195
    static let cy: Double = 196
    static let rx: Double = 163
    static let ry: Double = 148
    static let viewWidth: Double = 390
    static let viewHeight: Double = 240
    /// Горизонт — тот же `cy`: дуга дня стоит на нём обоими концами.
    static let horizonY: Double = cy

    /// Ширина портального перехода полярных суток, в долях высоты купола.
    static let portal: Double = 0.12
    /// Пол непрозрачности призрака солнца — ниже него пятно не гаснет всю ночь.
    static let ghostFloor: Double = 2.0 / 3.0
    /// Толщина стеклянной подложки в градусах купола — диск гаснет, уходя под
    /// неё, а не на самом краю дуги.
    static let glass: Double = 3

    /// `Math.max(a, Math.min(b, v))` с проходом NaN, как в вебе.
    static func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double {
        if v.isNaN { return v }
        return max(a, min(b, v))
    }

    private static func rad(_ d: Double) -> Double { d * Double.pi / 180 }

    /// `CGPoint` из модельных координат `Double`: единственное место, где
    /// геометрия переходит в валюту `CoreGraphics` — CGFloat и Double не
    /// конвертируются друг в друга неявно.
    private static func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }

    /// Точка на дуге между `rise` и `set` (или их полярными заменами):
    /// верхняя половина эллипса при `set > rise`.
    static func posOn(_ t: Minutes, _ rise: Minutes, _ set: Minutes) -> CGPoint {
        let th = rad(180 - (t - rise) / (set - rise) * 180)
        return pt(cx + rx * cos(th), cy - ry * sin(th))
    }

    /// Размах ночного нырка: высота светила в нижней кульминации (полдень ±
    /// 12 ч) той ночи, что видна в момент `t`, приведённая к долям купола.
    static func nightAmp(_ t: Minutes, sun: SolarDay) -> Double {
        let at = sun.solarNoon + (t > sun.arcB ? 720 : -720)
        return clamp((-sun.elevation(at: at) - 0.833) / 18, 0, 1)
    }

    struct PolarPoint {
        let p: CGPoint
        let twin: CGPoint
        /// Вес тела в портальном перетекании; `1 − k` достаётся двойнику.
        let k: Double
    }

    /// Полярные сутки: своя половина купола и портал на обоих концах дуги.
    static func polarAt(_ t: Minutes, sun: SolarDay) -> PolarPoint {
        let a = sun.arcA, b = sun.arcB
        let day = sun.polar != .night
        let th = rad(180 - (t - a) / (b - a) * 180)
        let s = sin(th)
        let h = day ? s : -nightAmp(a, sun: sun) * s
        let x = cx + rx * cos(th)
        let p = pt(x, cy - ry * h)
        let twin = pt(2 * cx - x, cy - ry * (day ? -h : h))
        let k = clamp(0.5 + s / (2 * portal), 0, 1)
        return PolarPoint(p: p, twin: twin, k: k)
    }

    /// Положение светила в любую минуту: дуга дня, ночной ход по нижней
    /// половине того же эллипса, или портал полярных суток.
    static func posAt(_ t: Minutes, sun: SolarDay) -> CGPoint {
        let a = sun.arcA, b = sun.arcB
        let night = 1440 - (b - a)
        if night <= 0 { return polarAt(t, sun: sun).p }
        if t >= a && t <= b { return posOn(t, a, b) }
        let frac = t > b ? (t - b) / night : (a - t) / night
        if frac > 1 { return posOn(t > b ? t - 1440 : t + 1440, a, b) }
        let th = rad(t > b ? -frac * 180 : 180 + frac * 180)
        return pt(cx + rx * cos(th), cy + ry * nightAmp(t, sun: sun) * abs(sin(th)))
    }

    /// Высота купола в градусах у точки `pos`, минус толщина подложки —
    /// решает, диск это ещё или уже просвечивающее пятно.
    static func geoDegrees(_ pos: CGPoint) -> Double {
        (cy - Double(pos.y)) / ry * 90 - glass
    }

    /// Плотность просвечивающего пятна ушедшего светила по его высоте.
    static func deepOf(_ e: Degrees) -> Double {
        clamp(-e / 3, 0, 1) * max(ghostFloor, clamp((12 + e) / 9, 0, 1))
    }

    /// Относительная светлота по WCAG, нужна для `shadeNeed`.
    private static func relativeLuminance(_ c: SkyColor) -> Double {
        func f(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(Double(c.r) / 255) + 0.7152 * f(Double(c.g) / 255) + 0.0722 * f(Double(c.b) / 255)
    }

    /// `--surface` светлой темы, `#FAF8F3` — светило сливается с ним ровно
    /// настолько, насколько ему нужна тень.
    private static let litSurfaceLuminance = relativeLuminance(SkyColor(250, 248, 243))

    /// Сколько тени нужно под диском на светлой теме: тень отделяет светлое
    /// от светлого и не больше — в золотой час диск держит свой цвет и
    /// отделяется сам.
    static func shadeNeed(_ c: SkyColor) -> Double {
        clamp((0.42 - (litSurfaceLuminance - relativeLuminance(c))) / 0.30, 0, 1)
    }
}
