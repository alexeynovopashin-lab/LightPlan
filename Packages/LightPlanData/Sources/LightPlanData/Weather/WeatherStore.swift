import Foundation
import Observation
import LightPlanCore

/// Прогноз для места: настоящий, если загружен, иначе выдумка офлайн — и то,
/// как он обновляется, когда место меняется.
///
/// Правила веба (`fetchWeather`, `fetchAir`, `wxTimer`), перенесённые как есть:
/// - место меняется — сеть спрашивается не на каждом кадре карты, а после
///   паузы (веб 500 мс: `clearTimeout` + `setTimeout`);
/// - тот же адрес уже настоящий — второй раз в сеть не идём (`WeatherFetcher`);
/// - офлайн или отказ — молча остаётся выдумка, на экране ни одной ошибки;
/// - ответ про место, откуда карту уже увели, не должен ничего менять — как у
///   `CurrentPlace`, сверка места, а не только отмена задачи.
///
/// Отличие от веба: погода и воздух там — два независимых глобальных кэша с
/// ручной сверкой ключа в каждом; здесь оба идут через `WeatherFetcher`,
/// сверка одна.
@MainActor
@Observable
public final class WeatherStore {
    public private(set) var place: Place
    /// Настоящий прогноз загружен и относится к текущему месту.
    public private(set) var isLive = false

    private var real: [CivilDate: WeatherDay] = [:]
    private var hourlyByDay: [CivilDate: [Int: HourRecord]] = [:]
    private var air: [CivilDate: [Int: AirSample]] = [:]
    private var rawHourly: HourlyWeather?

    private let fetcher: WeatherFetcher
    private let debounce: Duration
    private var refreshTask: Task<Void, Never>?

    public init(place: Place, source: any WeatherSource, debounce: Duration = .milliseconds(500)) {
        self.place = place
        self.fetcher = WeatherFetcher(source: source)
        self.debounce = debounce
        scheduleRefresh()
    }

    /// Прогноз этого дня: настоящий, если есть, иначе выдумка (веб
    /// `wxReal[key] || qualityOf/dayWeather`).
    public func day(for date: CivilDate) -> WeatherDay {
        real[date] ?? MockWeather.day(for: date)
    }

    /// Погода над окном Млечного Пути этой ночи; `nil` — нет ни прогноза на
    /// эти часы, ни окна вовсе (веб `mwSkyAt`).
    public func milkyWaySky(for date: CivilDate, window: MilkyWayWindow) -> MilkyWaySky? {
        MilkyWaySky.over(date: date, window: window, hourly: hourlyByDay, air: air)
    }

    /// Дождаться, пока текущий вопрос о погоде решится (для тестов и для
    /// экранов, которым нужно закрыть спиннер).
    public func settled() async { await refreshTask?.value }

    /// Место сменилось: карту отпустили, выбрали закладку, набрали координаты.
    public func move(to newPlace: Place) {
        place = newPlace
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        let requested = place
        refreshTask = Task { [weak self, debounce, fetcher] in
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return                                    // отменено следующим move — новый вопрос уже назначен
            }
            guard let self else { return }
            await self.refreshHourly(for: requested, fetcher: fetcher)
        }
    }

    private func refreshHourly(for requested: Place, fetcher: WeatherFetcher) async {
        do {
            let hourly = try await fetcher.hourly(at: requested)
            guard !Task.isCancelled, requested == place else { return }   // место уже другое — ответ не актуален
            rawHourly = hourly
            isLive = true
            rebuild()
        } catch {
            return                                        // офлайн или сбой — молча остаётся выдумка
        }
        await refreshAir(for: requested, fetcher: fetcher)
    }

    private func refreshAir(for requested: Place, fetcher: WeatherFetcher) async {
        do {
            let got = try await fetcher.air(at: requested)
            guard !Task.isCancelled, requested == place else { return }
            air = got
            rebuild()
        } catch {
            return                                        // воздух необязателен: без него оценка прежняя
        }
    }

    private func rebuild() {
        guard let hourly = rawHourly else { return }
        let built = WeatherDay.buildDays(from: hourly, place: place, air: air)
        real = built.days
        hourlyByDay = built.hourly
    }
}
