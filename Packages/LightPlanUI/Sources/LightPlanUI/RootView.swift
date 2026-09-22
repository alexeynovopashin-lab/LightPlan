import SwiftUI
import LightPlanCore
import LightPlanData

/// Хозяин приложения: заводит место, дату и погоду один раз, дальше отдаёт
/// их экрану «Свет» (итерация 19). Место — фиксированный демо-адрес, не
/// устройство: `CurrentPlace`/`CoreLocationProvider` заведёт экран «Свет»
/// вместе с разрешением на геолокацию, когда придёт итерация 12; до тех пор
/// это тот же Барнаул, что был здесь и раньше.
public struct RootView: View {
    @State private var model: LightScreenModel

    public init() {
        // Барнаул — рабочий город Алексея, тот же ориентир, что и в сетке
        // стенда паритета (план, § 5.2).
        let place = Place(latitude: 53.3481, longitude: 83.7798, zone: ZoneID("Asia/Barnaul")!)
        let today = RootView.today(in: place)
        let weather = WeatherStore(place: place, source: OpenMeteoSource())
        let timebar = TimebarState(place: place, date: today, weather: weather)
        _model = State(wrappedValue: LightScreenModel(timebar: timebar, weather: weather))
    }

    public var body: some View {
        LightScreenView(model)
    }

    private static func today(in place: Place) -> CivilDate {
        let zone = TimeZone(identifier: place.zone.identifier) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.year, .month, .day], from: Date())
        return CivilDate(year: c.year!, month: c.month!, day: c.day!)
    }
}

#Preview {
    RootView()
}
