import SwiftUI

/// Тренд облачности к окну съёмки — порт `sparkline(vals)` веба: ломаная по
/// шести значениям 0…100, растянутая на холст 42×14 модельных единиц.
/// Веб рисует `<polyline>` внутри `<svg viewBox="0 0 42 14">`; `Shape`
/// работает в тех же координатах и растягивается `.frame` снаружи так же,
/// как там растягивает CSS.
struct SparklineShape: Shape {
    let values: [Double]

    private static let modelWidth: CGFloat = 42
    private static let modelHeight: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let sx = rect.width / Self.modelWidth
        let sy = rect.height / Self.modelHeight
        let n = values.count
        for (i, v) in values.enumerated() {
            let x = (CGFloat(i) / CGFloat(n - 1) * Self.modelWidth) * sx
            // `H - v/100*(H-2) - 1` веба: полоса высотой 14 с отступом в
            // одну единицу сверху и снизу, чтобы линия не срезалась по краю.
            let y = (Self.modelHeight - CGFloat(v) / 100 * (Self.modelHeight - 2) - 1) * sy
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}
