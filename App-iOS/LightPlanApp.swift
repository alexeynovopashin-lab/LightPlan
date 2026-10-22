import SwiftUI
import LightPlanUI

@main
struct LightPlanApp: App {
    init() {
        // Делегат уведомлений — до конца запуска: иначе нажатие, которым приложение открыли, теряется (30.6).
        AppModel.installNotificationDelegate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // «Прогноз переменился» при закрытом приложении (30.6): когда будить — решает iOS.
        .backgroundTask(.appRefresh(AppModel.weatherTaskIdentifier)) {
            await AppModel.backgroundWeather()
        }
    }
}
