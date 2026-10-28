import SwiftUI
import LightPlanDomain

/// Средний виджет, пока съёмка идёт (30б.2в-4): демка Алексея 26.10 один в один — риски по периметру на всю свадьбу, шапка со знаком жанра и
/// именами, окошко Braun с обратным отсчётом свадьбы, круг точек справа от которого барабан маршрута. Вид и числа — `BraunWidget.swift`.
struct MediumLiveView: View {
    let frame: WidgetFrame
    var alpha = false

    var body: some View { BraunWidgetView(frame: frame, alpha: alpha, medium: true) }
}
