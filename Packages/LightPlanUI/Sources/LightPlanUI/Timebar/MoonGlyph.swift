import SwiftUI

/// Освещённая доля лунного диска — знак в ячейке барабана. Порт `litPath`
/// (веб): правая половина плюс-минус половина эллипса-терминатора.
///
/// Веб рисует эллиптическую дугу командой SVG `A`; `IconArt` умеет только
/// прямые и кривые Безье (дуги сведены генератором заранее, § `IconArt`),
/// поэтому фигура здесь не строка-путь, а свой `Shape`: контур считается
/// точками по параметру, без завязки на то, как конкретный фреймворк читает
/// флаг разворота у `addArc`.
///
/// Освещена по умолчанию правая половина (растущая луна, `fraction < 0.5`
/// даёт `k < 0`); зеркалит вызывающий — как в вебе, где купол разворачивает
/// диск для убывающей луны отдельным `transform`.
struct MoonGlyph: Shape {
    /// Освещённая доля диска, 0…1.
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let cx = rect.midX, cy = rect.midY
        let k = 2 * fraction - 1
        let rx = abs(k) * r
        let steps = 24

        var points: [CGPoint] = []
        // Первая дуга: правая полуокружность радиуса r, сверху вниз через +x.
        for i in 0...steps {
            let t = -90.0 + 180.0 * Double(i) / Double(steps)
            let a = t * .pi / 180
            points.append(CGPoint(x: cx + r * cos(a), y: cy + r * sin(a)))
        }
        // Вторая дуга: эллипс (rx, r). k > 0 — выпуклость влево (прибывает
        // сверх полудиска, горб); k ⩽ 0 — той же стороной, что первая дуга,
        // меньшим радиусом (серп, вырезанный из полудиска).
        let a0 = 90.0, a1 = k > 0 ? 270.0 : -90.0
        for i in 0...steps {
            let t = a0 + (a1 - a0) * Double(i) / Double(steps)
            let a = t * .pi / 180
            points.append(CGPoint(x: cx + rx * cos(a), y: cy + r * sin(a)))
        }

        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}
