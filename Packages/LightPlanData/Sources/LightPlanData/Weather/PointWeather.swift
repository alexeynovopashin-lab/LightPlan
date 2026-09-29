import Foundation
import Observation
import LightPlanCore

/// Прогноз по точкам съёмки для карточки (веб `ptFetch`, итерация 26, шаг 3):
/// свой, отдельный от прогноза места приложения. Без него погода, свет «плохое
/// небо» и тревоги карточки говорили бы про город, где стоит «Свет», а не про
/// место съёмки (ошибка 6 веба в справке).
///
/// Ключ — координаты с тремя знаками (~100 м), как у `WeatherFetcher`. Пока
/// ответ летит — `.flying` (у колонок прочерки); пришёл пустой — `.empty` и в
/// сеть по кругу не ходим; сеть оборвалась — ключ освобождается, спросит
/// следующее открытие карточки. Веб спрашивает все точки одним запросом
/// (Open-Meteo принимает список координат); здесь — запрос на точку через тот
/// же `WeatherSource`, что у «Света»: точек не больше семи, а протокол и
/// сценарии тестов остаются одни (DECISIONS 29.09, шаг 3). Воздух (дым в балле
/// заката) точкам не спрашивается — у веба он только у якоря и на 5 суток.
@MainActor
@Observable
public final class PointWeather {

    public enum State: Sendable, Equatable {
        case flying
        case empty
        case ready(days: [CivilDate: WeatherDay], hourly: [CivilDate: [Int: HourRecord]])
    }

    public private(set) var states: [String: State] = [:]
    private let fetcher: WeatherFetcher
    private var inFlight: [Task<Void, Never>] = []

    public init(source: any WeatherSource) {
        self.fetcher = WeatherFetcher(source: source)
    }

    public static func key(_ p: Place) -> String { WeatherFetcher.key(for: p) }

    public func state(at p: Place) -> State? { states[Self.key(p)] }

    /// Спросить прогноз точки, если о ней ещё не спрашивали.
    public func ask(_ p: Place) {
        let k = Self.key(p)
        guard states[k] == nil else { return }
        states[k] = .flying
        inFlight.append(Task { [weak self, fetcher] in
            do {
                let h = try await fetcher.hourly(at: p)
                let built = WeatherDay.buildDays(from: h, place: p)
                self?.states[k] = built.days.isEmpty ? .empty : .ready(days: built.days, hourly: built.hourly)
            } catch {
                self?.states[k] = nil
            }
        })
    }

    /// Дождаться ответов, что уже в пути (для тестов и съёмки пар).
    public func settled() async {
        let now = inFlight
        inFlight = []
        for t in now { await t.value }
    }
}
