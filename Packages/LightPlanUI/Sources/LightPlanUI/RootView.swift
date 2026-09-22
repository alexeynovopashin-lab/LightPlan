import SwiftUI
import LightPlanCore
import LightPlanData

/// Хозяин экрана на время итерации 17: показывает таймбар на настоящих
/// данных, пока «Свет» (итерация 19) не завёл собственную модель момента и
/// хранилище настроек места (итерация 12). Место — фиксированный демо-адрес,
/// не устройство: `CurrentPlace`/`CoreLocationProvider` заведёт экран «Свет»
/// вместе с разрешением на геолокацию, здесь этого спрашивать не у чего.
public struct RootView: View {
    @State private var state: TimebarState

    public init() {
        // Барнаул — рабочий город Алексея, тот же ориентир, что и в сетке
        // стенда паритета (план, § 5.2).
        let place = Place(latitude: 53.3481, longitude: 83.7798, zone: ZoneID("Asia/Barnaul")!)
        let today = RootView.today(in: place)
        let weather = WeatherStore(place: place, source: OpenMeteoSource())
        _state = State(wrappedValue: TimebarState(place: place, date: today, weather: weather))
    }

    public var body: some View {
        VStack {
            Spacer()
            DomeView(sun: state.solarDay, place: state.place, date: state.machine.selectedDate,
                      t: state.machine.viewMinute, nowMinute: state.nowMinute, mode: skyMode)
                .padding(.horizontal, 16)
            TimebarView(state)
                .padding(.horizontal, 16)
            Spacer(minLength: 24)
        }
        .background(.black.opacity(0.92))
        .preferredColorScheme(.dark)
    }

    /// Купол (итерация 18) и таймбар (итерация 17) делят один тумблер:
    /// вебовский `showMoon` барабана — то же самое «солнце или луна» куполом.
    private var skyMode: Binding<DomeSkyMode> {
        Binding(get: { state.showMoon ? .moon : .sun },
                set: { state.showMoon = $0 == .moon })
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
