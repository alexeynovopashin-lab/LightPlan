import SwiftUI
import LightPlanCore

/// Дорожка света ползунка: цвет неба по высоте светила вдоль суток, как в
/// вебе красится рельс слайдера (`drawRail`, `stopAt`).
///
/// Веб красит рельс своей отдельной таблицей `PATH_STOPS` — она же кормит
/// путь солнца на куполе и карте (итерации 18 и 20, ещё не перенесены).
/// Здесь взята уже готовая, измеренная модель `LightPalette.skyColor` того же
/// смысла («высота светила → цвет неба», итерация 8) — заводить вторую
/// таблицу ради этой итерации незачем; если `PATH_STOPS` придёт вместе с
/// куполом, две дорожки можно свести к одной тогда.
enum LightTrack {
    /// Остановки градиента, каждые 10 минут окна суток — тот же шаг, что у
    /// веба (`drawRail`, счётчик не на каждый кадр движения ручки).
    static func gradient(day: SolarDay) -> Gradient {
        var stops: [Gradient.Stop] = []
        let span = day.maxt - day.mint
        guard span > 0 else { return Gradient(colors: [.black]) }
        var t = day.mint
        while t <= day.maxt {
            let c = LightPalette.skyColor(elevation: day.elevation(at: t))
            let location = (t - day.mint) / span
            stops.append(Gradient.Stop(color: Color(c), location: location))
            t += 10
        }
        if stops.last?.location ?? 0 < 1 {
            let c = LightPalette.skyColor(elevation: day.elevation(at: day.maxt))
            stops.append(Gradient.Stop(color: Color(c), location: 1))
        }
        return Gradient(stops: stops)
    }
}

extension Color {
    init(_ c: SkyColor) {
        self.init(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }
}
