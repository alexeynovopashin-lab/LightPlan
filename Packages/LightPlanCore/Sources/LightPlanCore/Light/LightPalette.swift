import Foundation

/// Цвет неба в целых каналах 0…255, как массив `[r, g, b]` в вебе.
public struct SkyColor: Sendable, Equatable {
    public let r: Int
    public let g: Int
    public let b: Int

    public init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// Палитра модели света и лестница «высота солнца → цвет неба».
///
/// Порт `GOLD…NIGHT`, `lerp`, `skyColor` из `light_plan:Light_Plan/beta/index.html`.
/// Это цвета **модели света** — зарева и дуги, — а не цвета интерфейса: те
/// живут в UI и темах. Пороги и цвета — физика продукта, их не «причёсывают»;
/// правка идёт сначала в вебе, потом здесь, и стенд паритета упадёт, если
/// разойдутся.
public enum LightPalette {
    public static let gold = SkyColor(226, 164, 76)
    public static let amber = SkyColor(217, 172, 107)
    public static let silver = SkyColor(239, 234, 224)
    public static let scarlet = SkyColor(216, 80, 47)
    public static let pink = SkyColor(201, 105, 143)
    public static let blue = SkyColor(91, 119, 160)
    public static let deep = SkyColor(61, 88, 120)
    public static let night = SkyColor(104, 126, 168)

    /// `lerp(a, b, k)` веба: `k` зажат в 0…1, канал округлён `Math.round`.
    /// Каналы неотрицательны, поэтому `Math.round` (половина вверх) и
    /// `.rounded()` (половина от нуля) дают одно и то же.
    public static func lerp(_ a: SkyColor, _ b: SkyColor, _ k: Double) -> SkyColor {
        let k = clamp01(k)
        func channel(_ x: Int, _ y: Int) -> Int {
            Int((Double(x) + (Double(y) - Double(x)) * k).rounded())
        }
        return SkyColor(channel(a.r, b.r), channel(a.g, b.g), channel(a.b, b.b))
    }

    /// Цвет неба по высоте светила. Одна лестница на два неба: своё и
    /// «призрак» солнца на другой стороне планеты, где высота ровно `−e`.
    public static func skyColor(elevation e: Degrees) -> SkyColor {
        if e >= -0.833 {
            if e > 40 { return silver }
            if e > 20 { return lerp(amber, silver, 0.6) }
            if e > 6.05 { return amber }
            return gold
        }
        let d = -e
        if d < 1.8 { return lerp(gold, scarlet, d / 1.8) }
        if d < 4 { return lerp(scarlet, pink, (d - 1.8) / 2.2) }
        if d < 6 { return lerp(pink, blue, (d - 4) / 2) }
        if d < 12 { return lerp(blue, deep, (d - 6) / 6) }
        if d < 18 { return lerp(deep, night, (d - 12) / 6) }
        return night
    }

    /// `Math.max(0, Math.min(1, k))` с NaN сквозь: у JS NaN проходит через
    /// `min` и `max`, у Swift `min(1, .nan)` вернул бы 1.
    private static func clamp01(_ k: Double) -> Double {
        if k.isNaN { return k }
        return max(0, min(1, k))
    }
}
