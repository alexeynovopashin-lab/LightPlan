import SwiftUI
import LightPlanCore

/// Цвет пути светила по его высоте — `PATH_STOPS`/`stopAt` веба. Им веб
/// красит рельс слайдера (`drawRail`) и путь солнца на карте. Цвет идёт с
/// прозрачностью поверх `--rail`: днём рельс едва тонирован, в золотой час
/// горит латунью, в синий — синим, ночью почти гаснет.
///
/// Итерация 17 красила рельс `LightPalette.skyColor` — цветом неба, а не
/// пути, — и без прозрачности; в светлой теме полоса выходила тёмной
/// (найдено снимком пары в 19б). Таблица перенесена буквально.
enum PathStops {
    struct Stop: Equatable {
        let rgb: (Int, Int, Int)
        let a: Double
        let w: Double

        static func == (l: Stop, r: Stop) -> Bool {
            l.rgb == r.rgb && l.a == r.a && l.w == r.w
        }

        var color: Color {
            Color(.sRGB, red: Double(rgb.0) / 255, green: Double(rgb.1) / 255, blue: Double(rgb.2) / 255, opacity: a)
        }
    }

    private static let table: [(alt: Double, rgb: (Int, Int, Int), a: Double, w: Double)] = [
        (90, (138, 132, 120), 0.40, 1.3),
        (20, (176, 160, 132), 0.50, 1.7),
        (6, (226, 164, 76), 0.95, 3.4),     // золотой час сверху
        (0, (226, 164, 76), 0.95, 3.4),     // горизонт
        (-4, (150, 110, 170), 0.88, 3.0),   // перелом к синему
        (-6, (124, 156, 196), 0.85, 3.0),   // синий час
        (-12, (64, 92, 140), 0.48, 2.0),
        (-18, (40, 54, 92), 0.28, 1.4),
    ]

    /// `stopAt(alt)`: линейно между соседними остановками, каналы цвета
    /// округляются, как `Math.round` веба (половина — вверх).
    static func at(_ alt: Double) -> Stop {
        let s = table
        if alt >= s[0].alt { return Stop(rgb: s[0].rgb, a: s[0].a, w: s[0].w) }
        let last = s[s.count - 1]
        if alt <= last.alt { return Stop(rgb: last.rgb, a: last.a, w: last.w) }
        for i in 0..<(s.count - 1) {
            let hi = s[i], lo = s[i + 1]
            if alt <= hi.alt, alt >= lo.alt {
                let k = (alt - lo.alt) / (hi.alt - lo.alt)
                let mix = { (l: Int, h: Int) in Int((Double(l) + Double(h - l) * k + 0.5).rounded(.down)) }
                return Stop(rgb: (mix(lo.rgb.0, hi.rgb.0), mix(lo.rgb.1, hi.rgb.1), mix(lo.rgb.2, hi.rgb.2)),
                            a: lo.a + (hi.a - lo.a) * k, w: lo.w + (hi.w - lo.w) * k)
            }
        }
        return Stop(rgb: last.rgb, a: last.a, w: last.w)
    }

    /// Остановки рельса: каждые 10 минут окна `mint…maxt`, место — доля окна
    /// (`drawRail`). Прозрачность округляется до сотых, как `toFixed(2)`.
    static func railGradient(day: SolarDay) -> Gradient {
        let span = day.maxt - day.mint
        guard span > 0 else { return Gradient(colors: [.clear]) }
        var stops: [Gradient.Stop] = []
        var t = day.mint
        while t <= day.maxt {
            let c = at(day.elevation(at: t))
            let color = Color(.sRGB, red: Double(c.rgb.0) / 255, green: Double(c.rgb.1) / 255,
                              blue: Double(c.rgb.2) / 255, opacity: (c.a * 100).rounded() / 100)
            stops.append(Gradient.Stop(color: color, location: (t - day.mint) / span))
            t += 10
        }
        return Gradient(stops: stops)
    }
}
