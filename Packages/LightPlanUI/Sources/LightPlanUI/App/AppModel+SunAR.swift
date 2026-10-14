import Foundation
import LightPlanCore

/// Слой AR (шаг 29.8в): вход и выход. Экран получает только место и момент.
extension AppModel {
    /// Открыть AR на этом месте и в этот момент. Момент по умолчанию — «сейчас».
    func openSunAR(place: Place, moment: Moment = Moment(Date())) {
        sunAR = SunARTarget(place: place, moment: moment)
    }

    func closeSunAR() {
        sunAR = nil
    }

    #if DEBUG
    /// Снимок и проверка в симуляторе: `-LPSunAR 1` открывает экран сразу на месте приложения; момент —
    /// `-LPSunARMoment 2026-06-21T15:30:00Z`, по умолчанию «сейчас».
    func debugOpenSunAR() {
        let d = UserDefaults.standard
        guard d.string(forKey: "LPSunAR") != nil else { return }
        var moment = Moment(Date())
        if let s = d.string(forKey: "LPSunARMoment"), let date = ISO8601DateFormatter().date(from: s) {
            moment = Moment(date)
        }
        openSunAR(place: light.timebar.place, moment: moment)
    }
    #endif
}
