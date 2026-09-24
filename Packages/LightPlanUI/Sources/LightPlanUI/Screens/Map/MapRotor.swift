import Foundation
import Observation
import LightPlanData

/// Ротор карты (итерация 20б): карта, вуаль, точки и прибор — один слой,
/// живой компас крутит его вокруг наблюдателя (`.map-rotor` веба,
/// `transform-origin: 50% --optic-cy`).
enum MapRotor {
    /// Сторона квадрата под картой — `measureMapOptic` веба: круг, который
    /// кадр заметает вокруг наблюдателя, радиусом до дальнего угла (`R`), и
    /// сдвиг середины кадра от наблюдателя (`off`). Диагонали кадра хватало,
    /// пока ось стояла в середине; на оси наблюдателя она оставляла клин
    /// (веб, 17 сентября: 390 × 844, сторона 930 — угол выходит на 109 px при 158°).
    static func side(width w: Double, height h: Double, cy: Double) -> Double {
        let r = hypot(w / 2, max(cy, h - cy))
        let off = abs(h / 2 - cy)
        return (2 * (r + off)).rounded(.up)
    }

    /// Угол кадра, не накрытый квадратом при повороте на `deg` вокруг
    /// наблюдателя, — на сколько точек он выходит (0 — клина нет). Квадрат
    /// со стороной `side` стоит серединой в середине кадра.
    static func gap(width w: Double, height h: Double, cy: Double, side: Double, deg: Double) -> Double {
        let a = -deg * .pi / 180
        let ox = w / 2, oy = cy
        var worst = 0.0
        for (x, y) in [(0.0, 0.0), (w, 0), (0, h), (w, h)] {
            // Угол кадра в системе квадрата — повёрнутый назад вокруг оси.
            let dx = x - ox, dy = y - oy
            let qx = ox + dx * cos(a) - dy * sin(a), qy = oy + dx * sin(a) + dy * cos(a)
            let out = max(abs(qx - w / 2), abs(qy - h / 2)) - side / 2
            worst = max(worst, out)
        }
        return worst
    }

    /// `smoothHeading` веба: шаг кадра — 0,15 пути коротким концом.
    static func smooth(_ target: Double, _ current: Double) -> Double {
        var diff = target - current
        while diff > 180 { diff -= 360 }
        while diff < -180 { diff += 360 }
        return current + diff * 0.15
    }
}

/// Живой компас. По умолчанию карта смотрит на север; включённый крутит
/// ротор за телефоном. Угол между запусками не хранится — веб так же.
@MainActor
@Observable
final class CompassRotor {
    private(set) var live = false
    /// Видимый угол, непрерывный (без скачка 359 → 0), градусы.
    var angle: Double = 0
    @ObservationIgnored private var real: Double = 0
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let source: (any HeadingSource)?

    init(source: (any HeadingSource)?) { self.source = source }

    var available: Bool { source?.isAvailable ?? false }

    func setLive(_ on: Bool) {
        guard on != live else { return }
        if on {
            guard let source, source.isAvailable else { return }
            live = true
            source.start { [weak self] deg in self?.real = deg }
            loop = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.angle = MapRotor.smooth(self.real, self.angle)
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
        } else {
            live = false
            source?.stop()
            loop?.cancel()
            loop = nil
            real = 0
            // Возврат на север — коротким концом: угол сводится к ±180
            // без анимации, а до нуля едет уже вид (0,3 с, как у веба).
            angle = angle - 360 * (angle / 360).rounded()
        }
    }
}
