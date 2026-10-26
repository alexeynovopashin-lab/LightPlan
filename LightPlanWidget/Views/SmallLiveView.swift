import SwiftUI
import LightPlanDomain

/// Малый виджет, пока съёмка идёт (30б.2в-4): то же, что средний, но без окошка свадьбы и барабана — круг точек по центру, имена до двух строк.
/// Плашка 170 × 170 на Pro Max, 158 × 158 на iPhone 14. Вид и числа — `BraunWidget.swift`.
struct SmallLiveView: View {
    let frame: WidgetFrame
    var alpha = false

    var body: some View { BraunWidgetView(frame: frame, alpha: alpha, medium: false) }
}
