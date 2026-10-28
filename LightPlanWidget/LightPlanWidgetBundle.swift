import WidgetKit
import SwiftUI

/// Расширение LightPlanWidgetExtension (30б): виджеты главного экрана и экран активности — экран блокировки и Dynamic Island (30б.3).
@main
struct LightPlanWidgetBundle: WidgetBundle {
    var body: some Widget {
        LightPlanWidget()
        ShootActivityWidget()
    }
}
