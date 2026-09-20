import SwiftUI

/// Упрощённый прибор: лимб с делениями, две оси и путь солнца за сутки.
/// Полного прибора здесь нет намеренно (план, итерация 4) — нужно увидеть,
/// спорит ли холст с разметкой, а не повторить экран «Карта».
struct InstrumentOverlay: View {
    let lat: Double
    let lon: Double
    let dark: Bool
    /// Час по всемирному времени, которым ведут светило по пути.
    let hourUTC: Double

    /// Латунь взята числами из веба (`beta/index.html`): тёмная тема #E2A44C,
    /// светлая #A9721F. Светлая тема не инверсия тёмной — цвет свой.
    private var brass: Color { dark ? Color(hex: 0xE2A44C) : Color(hex: 0xA9721F) }
    private var ink: Color { dark ? Color(hex: 0x8A949A) : Color(hex: 0x3E4244) }

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) * 0.42

            // Лимб: круг и деления каждые 15°, крупные — каждые 90°.
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(brass.opacity(0.75)), lineWidth: 1.2)
            for deg in stride(from: 0, to: 360, by: 15) {
                let major = deg % 90 == 0
                let len: CGFloat = major ? 14 : 6
                let p0 = point(c, r, Double(deg)), p1 = point(c, r - len, Double(deg))
                var path = Path(); path.move(to: p0); path.addLine(to: p1)
                ctx.stroke(path, with: .color(brass.opacity(major ? 0.95 : 0.5)),
                           lineWidth: major ? 1.6 : 1)
            }

            // Две оси: север–юг и восток–запад, сквозь центр.
            for deg in [0.0, 90.0] {
                var path = Path()
                path.move(to: point(c, r, deg)); path.addLine(to: point(c, r, deg + 180))
                ctx.stroke(path, with: .color(brass.opacity(0.35)), lineWidth: 1)
            }

            // Путь солнца за сутки. Радиус несёт высоту: зенит в центре,
            // горизонт на лимбе. Под горизонтом светило не исчезает, а идёт
            // призраком за лимбом (DECISIONS, «Компас карты: полный круг суток»).
            var day = Path(), ghost = Path()
            var startedDay = false, startedGhost = false
            for step in 0...(24 * 6) {
                let h = Double(step) / 6
                let p = Sun.position(lat: lat, lon: lon, date: Date(), hourUTC: h)
                let rr = radius(for: p.alt, limb: r)
                let pt = point(c, rr, p.az)
                if p.alt >= 0 {
                    if startedDay { day.addLine(to: pt) } else { day.move(to: pt); startedDay = true }
                    startedGhost = false
                } else {
                    if startedGhost { ghost.addLine(to: pt) } else { ghost.move(to: pt); startedGhost = true }
                    startedDay = false
                }
            }
            ctx.stroke(day, with: .color(brass), lineWidth: 2)
            ctx.stroke(ghost, with: .color(ink.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.4, dash: [4, 5]))

            // Само светило.
            let now = Sun.position(lat: lat, lon: lon, date: Date(), hourUTC: hourUTC)
            let sp = point(c, radius(for: now.alt, limb: r), now.az)
            let d: CGFloat = 9
            ctx.fill(Path(ellipseIn: CGRect(x: sp.x - d/2, y: sp.y - d/2, width: d, height: d)),
                     with: .color(now.alt >= 0 ? brass : ink))

            // Точка съёмки — центр кадра, как в вебе.
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)),
                       with: .color(brass), lineWidth: 1.6)

            // Стороны света.
            for (deg, name) in [(0.0, "С"), (90.0, "В"), (180.0, "Ю"), (270.0, "З")] {
                let p = point(c, r + 14, deg)
                ctx.draw(Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(brass),
                         at: p)
            }
        }
        .allowsHitTesting(false)
    }

    /// Высота +90° — центр, 0° — лимб, −18° и ниже — полторы четверти наружу.
    private func radius(for alt: Double, limb: CGFloat) -> CGFloat {
        if alt >= 0 { return limb * CGFloat(1 - alt / 90) }
        return limb * CGFloat(1 + min(-alt, 30) / 30 * 0.22)
    }

    private func point(_ c: CGPoint, _ r: CGFloat, _ azDeg: Double) -> CGPoint {
        let a = (azDeg - 90) * .pi / 180
        return CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
