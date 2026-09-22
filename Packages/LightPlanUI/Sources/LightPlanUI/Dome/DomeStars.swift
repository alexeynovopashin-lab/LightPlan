import Foundation
import CoreGraphics

/// `mulberry32` веба: генератор с посевом, побитово тот же ряд что в JS.
///
/// JS держит аккумулятор в 32-битном знаковом (`|0`) и умножает `Math.imul`
/// (тоже 32-битное, с переполнением), а под конец читает результат как
/// беззнаковый (`>>>0`) перед делением. В Swift то же самое даёт `UInt32` с
/// операциями через `&+`/`&*` — переполнение по модулю 2^32 у знакового и
/// беззнакового совпадает бит в бит, а финальное значение уже беззнаковое.
struct Mulberry32 {
    private var a: UInt32

    init(seed: UInt32) { self.a = seed }

    mutating func next() -> Double {
        a = a &+ 0x6D2B79F5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296.0
    }
}

/// Звёздное поле купола: 280 точек, посев `20260715` (день переноса) —
/// тот же посев и тот же порядок вызовов `rnd()`, что в вебе (`buildStars`),
/// так что поле не «похожее», а то же самое.
enum DomeStars {
    struct Star {
        let x: Double
        let y: Double
        let radius: Double
        let opacity: Double
    }

    static let points: [Star] = {
        var rnd = Mulberry32(seed: 20_260_715)
        var stars: [Star] = []
        stars.reserveCapacity(280)
        for _ in 0..<280 {
            let ang = rnd.next() * 2 * Double.pi
            let r = 18 + (rnd.next()).squareRoot() * 262
            let mag = rnd.next()
            stars.append(Star(
                x: DomeGeometry.cx + r * cos(ang),
                y: DomeGeometry.cy + r * sin(ang),
                radius: 0.35 + mag * mag * 0.75,
                opacity: 0.12 + mag * 0.3
            ))
        }
        return stars
    }()
}
