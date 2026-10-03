import Foundation
import Observation
import LightPlanCore

/// Прогноз для места: настоящий или никакого. Выдумки нет (слово Алексея
/// 02.10, 28ж): пока прогноза нет, экраны пишут об этом и показывают одну
/// астрономию.
///
/// Правила веба (`fetchWeather`, `fetchAir`, `wxTimer`), перенесённые как есть:
/// - место меняется — сеть спрашивается не на каждом кадре карты, а после
///   паузы (веб 500 мс: `clearTimeout` + `setTimeout`);
/// - тот же адрес уже настоящий — второй раз в сеть не идём (`WeatherFetcher`);
/// - ответ про место, откуда карту уже увели, не должен ничего менять — как у
///   `CurrentPlace`, сверка места, а не только отмена задачи.
///
/// Отличия от веба:
/// - погода и воздух там — два независимых глобальных кэша с ручной сверкой
///   ключа; здесь оба идут через `WeatherFetcher`, сверка одна;
/// - сбой не вечный (веб и первый натив молчали и больше не спрашивали): повтор
///   при возврате приложения на экран (`resume`) и по таймеру 3, 4, 5, 5… минут,
///   пока не удастся и прогноз, и воздух;
/// - воздух не ждёт прогноза: оба вопроса уходят вместе, сбой одного не мешает
///   другому;
/// - ушли в другое место — прогноз прежнего места не остаётся: он не про это
///   место.
@MainActor
@Observable
public final class WeatherStore {
    /// Паузы между повторами: 3, 4, 5 минут, дальше — по пять (слово ТЗ 28ж).
    public static let retryDelays: [Duration] = [.seconds(180), .seconds(240), .seconds(300)]

    public private(set) var place: Place
    public private(set) var status: WeatherStatus = .loading
    /// Настоящий прогноз загружен и относится к текущему месту.
    public var isLive: Bool { if case .live = status { true } else { false } }

    private var real: [CivilDate: WeatherDay] = [:]
    private var hourlyByDay: [CivilDate: [Int: HourRecord]] = [:]
    private var air: [CivilDate: [Int: AirSample]] = [:]
    private var rawHourly: HourlyWeather?
    private var hourlyLoaded = false
    private var airLoaded = false

    private let fetcher: WeatherFetcher
    private let debounce: Duration
    private let retryDelays: [Duration]
    private var refreshTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var failures = 0
    /// Номер идущей попытки; `nil` — никто сейчас не спрашивает.
    private var activeAttempt: Int?
    private var attemptCounter = 0

    public init(place: Place, source: any WeatherSource, debounce: Duration = .milliseconds(500),
                retryDelays: [Duration] = WeatherStore.retryDelays) {
        self.place = place
        self.fetcher = WeatherFetcher(source: source)
        self.debounce = debounce
        self.retryDelays = retryDelays.isEmpty ? Self.retryDelays : retryDelays
        start(debounced: true)
    }

    /// Прогноз этого дня; `nil` — настоящего нет (ещё грузится, не удалось, день
    /// за окном 16 суток вперёд и 5 назад). Выдумка не подставляется.
    public func day(for date: CivilDate) -> WeatherDay? {
        real[date]
    }

    /// Погода над окном Млечного Пути этой ночи; `nil` — нет ни прогноза на
    /// эти часы, ни окна вовсе (веб `mwSkyAt`).
    public func milkyWaySky(for date: CivilDate, window: MilkyWayWindow) -> MilkyWaySky? {
        MilkyWaySky.over(date: date, window: window, hourly: hourlyByDay, air: air)
    }

    /// Аэрозоль и пыль в час `hour` этих суток; `nil` — на этот час данных
    /// нет (веб `airAt`). Экран «Свет» (итерация 19) зовёт это для строки
    /// «Воздух» — единственный, кроме `milkyWaySky`, читатель воздуха снаружи.
    public func airSample(for date: CivilDate, hour: Int) -> AirSample? {
        Weather.nearHour(air[date] ?? [:], hour)
    }

    /// Дождаться, пока первый вопрос о погоде решится (для тестов и для
    /// экранов, которым нужно закрыть спиннер). Повторы не ждёт.
    public func settled() async { await refreshTask?.value }

    /// Место сменилось: карту отпустили, выбрали закладку, набрали координаты.
    /// Тот же адрес до тысячной градуса — тот же прогноз, ничего не трогаем.
    public func move(to newPlace: Place) {
        let same = WeatherFetcher.key(for: newPlace) == WeatherFetcher.key(for: place)
        place = newPlace
        if same { return }
        rawHourly = nil
        real = [:]
        hourlyByDay = [:]
        air = [:]
        hourlyLoaded = false
        airLoaded = false
        status = .loading
        failures = 0
        start(debounced: true)
    }

    /// Приложение вернулось на экран: если прогноза или воздуха всё ещё нет и
    /// никто сейчас не спрашивает — спросить сразу, не дожидаясь таймера.
    public func resume() {
        guard !(hourlyLoaded && airLoaded), activeAttempt == nil else { return }
        failures = 0
        start(debounced: false)
    }

    // MARK: - Вопрос и повторы

    private func start(debounced: Bool) {
        refreshTask?.cancel()
        retryTask?.cancel()
        retryTask = nil
        let requested = place
        refreshTask = Task { [weak self, debounce] in
            if debounced {
                do { try await Task.sleep(for: debounce) } catch { return }   // отменено следующим move — новый вопрос уже назначен
            }
            await self?.attempt(for: requested)
        }
    }

    private func attempt(for requested: Place) async {
        attemptCounter += 1
        let mine = attemptCounter
        activeAttempt = mine
        defer { if activeAttempt == mine { activeAttempt = nil } }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadHourly(for: requested) }
            group.addTask { await self.loadAir(for: requested) }
        }
        guard !Task.isCancelled, sameSpot(requested) else { return }
        if !(hourlyLoaded && airLoaded) { scheduleRetry(for: requested) }
    }

    private func scheduleRetry(for requested: Place) {
        let delay = retryDelays[min(failures, retryDelays.count - 1)]
        failures += 1
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            await self?.attempt(for: requested)
        }
    }

    private func sameSpot(_ requested: Place) -> Bool {
        WeatherFetcher.key(for: requested) == WeatherFetcher.key(for: place)
    }

    private func loadHourly(for requested: Place) async {
        guard !hourlyLoaded else { return }
        do {
            let (hourly, origin) = try await fetcher.hourlyWithOrigin(at: requested)
            guard !Task.isCancelled, sameSpot(requested) else { return }   // место уже другое — ответ не актуален
            rawHourly = hourly
            hourlyLoaded = true
            status = .live(origin)
            rebuild()
        } catch {
            guard !Task.isCancelled, sameSpot(requested) else { return }
            status = .unavailable
        }
    }

    private func loadAir(for requested: Place) async {
        guard !airLoaded else { return }
        do {
            let got = try await fetcher.air(at: requested)
            guard !Task.isCancelled, sameSpot(requested) else { return }
            air = got
            airLoaded = true
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
