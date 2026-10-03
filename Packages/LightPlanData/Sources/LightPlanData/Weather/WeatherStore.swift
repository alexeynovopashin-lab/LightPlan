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
/// - прогноз живёт час, воздух три (как у сервера): по истечении срока
///   спрашиваем заново по таймеру и при возврате на экран; старый прогноз не
///   стирается, пока новый не пришёл, а при сбое держится до шести часов,
///   потом — «недоступно»;
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
    /// Когда получены показанные прогноз и воздух; `nil` — ничего нет.
    private var hourlyAt: Date?
    private var airAt: Date?

    private let fetcher: WeatherFetcher
    private let lifetime: WeatherLifetime
    private let now: @Sendable () -> Date
    private let debounce: Duration
    private let retryDelays: [Duration]
    private var refreshTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var failures = 0
    /// Номер идущей попытки; `nil` — никто сейчас не спрашивает.
    private var activeAttempt: Int?
    private var attemptCounter = 0

    public init(place: Place, source: any WeatherSource, debounce: Duration = .milliseconds(500),
                retryDelays: [Duration] = WeatherStore.retryDelays,
                lifetime: WeatherLifetime = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.place = place
        self.lifetime = lifetime
        self.now = now
        self.fetcher = WeatherFetcher(source: source, lifetime: lifetime, now: now)
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
        hourlyAt = nil
        airAt = nil
        status = .loading
        failures = 0
        start(debounced: true)
    }

    /// Приложение вернулось на экран: если прогноза или воздуха всё ещё нет либо
    /// их срок прошёл и никто сейчас не спрашивает — спросить сразу, не дожидаясь
    /// таймера.
    public func resume() {
        guard needsHourly || needsAir, activeAttempt == nil else { return }
        failures = 0
        start(debounced: false)
    }

    // MARK: - Вопрос и повторы

    private func age(of stamp: Date) -> TimeInterval { now().timeIntervalSince(stamp) }
    /// Ровно срок — уже старый (кэш `WeatherFetcher` считает так же).
    private var needsHourly: Bool { hourlyAt.map { age(of: $0) >= lifetime.hourly } ?? true }
    private var needsAir: Bool { airAt.map { age(of: $0) >= lifetime.air } ?? true }

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
        dropIfTooStale()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadHourly(for: requested) }
            group.addTask { await self.loadAir(for: requested) }
        }
        guard !Task.isCancelled, sameSpot(requested) else { return }
        if needsHourly || needsAir {
            scheduleRetry(for: requested)
        } else {
            failures = 0
            scheduleRefresh(for: requested)
        }
    }

    /// Всё свежо — следующий вопрос, когда истечёт ближайший срок.
    private func scheduleRefresh(for requested: Place) {
        let left = [hourlyAt.map { lifetime.hourly - age(of: $0) }, airAt.map { lifetime.air - age(of: $0) }]
            .compactMap { $0 }.min() ?? 0
        let delay = Duration.seconds(max(left, 0.001))
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            await self?.attempt(for: requested)
        }
    }

    /// Старому прогнозу, которому давно за предел, не место на экране, пока
    /// спрашиваем: он уже не про «сейчас».
    private func dropIfTooStale() {
        if let at = hourlyAt, age(of: at) >= lifetime.staleLimit {
            dropHourly()
            status = .loading
        }
        if let at = airAt, age(of: at) >= lifetime.staleLimit { dropAir() }
    }

    private func dropHourly() {
        rawHourly = nil
        real = [:]
        hourlyByDay = [:]
        hourlyAt = nil
    }

    private func dropAir() {
        air = [:]
        airAt = nil
        rebuild()
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
        guard needsHourly else { return }
        do {
            let got = try await fetcher.hourlyStamped(at: requested)
            guard !Task.isCancelled, sameSpot(requested) else { return }   // место уже другое — ответ не актуален
            rawHourly = got.value
            hourlyAt = got.at
            status = .live(got.origin)
            rebuild()
        } catch {
            guard !Task.isCancelled, sameSpot(requested) else { return }
            // Новый не пришёл: старый, если ему нет шести часов, остаётся.
            if let at = hourlyAt, age(of: at) < lifetime.staleLimit { return }
            dropHourly()
            status = .unavailable
        }
    }

    private func loadAir(for requested: Place) async {
        guard needsAir else { return }
        do {
            let got = try await fetcher.airStamped(at: requested)
            guard !Task.isCancelled, sameSpot(requested) else { return }
            air = got.value
            airAt = got.at
            rebuild()
        } catch {
            guard !Task.isCancelled, sameSpot(requested) else { return }
            // воздух необязателен: без него оценка прежняя; старый держим до шести часов
            if let at = airAt, age(of: at) >= lifetime.staleLimit { dropAir() }
        }
    }

    private func rebuild() {
        guard let hourly = rawHourly else { return }
        let built = WeatherDay.buildDays(from: hourly, place: place, air: air)
        real = built.days
        hourlyByDay = built.hourly
    }
}
