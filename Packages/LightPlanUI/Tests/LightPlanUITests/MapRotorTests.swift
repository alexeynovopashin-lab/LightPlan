import Foundation
import Testing
@testable import LightPlanUI

/// Ротор живого компаса (20б): квадрат под картой не открывает клина
/// пустоты ни на одном угле (план: «восемь углов», DECISIONS 9504).
struct MapRotorTests {
    /// Кадры iPhone 14 … 17 Pro Max в точках; наблюдатель — от трети до
    /// середины высоты (окно прибора между шапкой и доком).
    static let frames: [(Double, Double)] = [(390, 844), (428, 926), (393, 852), (402, 874), (440, 956)]

    @Test("Восемь углов и 158° веба — клина нет на всех кадрах и осях")
    func noWedge() {
        for (w, h) in Self.frames {
            for k in stride(from: 0.33, through: 0.5, by: 0.01) {
                let cy = (h * k).rounded()
                let side = MapRotor.side(width: w, height: h, cy: cy)
                for deg in [0.0, 45, 90, 135, 180, 225, 270, 315, 158] {
                    #expect(MapRotor.gap(width: w, height: h, cy: cy, side: side, deg: deg) <= 0.5,
                            "\(w)×\(h) cy \(cy) \(deg)°")
                }
            }
        }
    }

    /// Порча: сторона-диагональ (прежнее правило веба) на оси наблюдателя
    /// клин даёт — значит, проверка выше что-то ловит.
    @Test("Диагональ кадра при оси не в середине — клин есть")
    func diagonalLeaks() {
        let w = 390.0, h = 844.0, cy = 330.0
        let diag = hypot(w, h).rounded(.up)
        let worst = [45.0, 135, 158, 225, 315].map { MapRotor.gap(width: w, height: h, cy: cy, side: diag, deg: $0) }.max()!
        #expect(worst > 50)
        #expect(MapRotor.gap(width: w, height: h, cy: h / 2, side: diag, deg: 158) <= 0.5)
    }

    @Test("Сглаживание идёт коротким концом через север")
    func smoothShortWay() {
        #expect(abs(MapRotor.smooth(10, 350) - 353) < 1e-9)
        #expect(abs(MapRotor.smooth(350, 10) - 7) < 1e-9)
        #expect(abs(MapRotor.smooth(90, 0) - 13.5) < 1e-9)
    }
}
