import Foundation

/// Открываются ли зарубежные адреса, на которые ходит приложение (28л.6). Меряется одним адресом —
/// `api.open-meteo.com`: это самый частый зарубежный запрос, и если он не отвечает, остальные в той же сети
/// обычно тоже (из кода, не мерено в РФ: настоящая картина белых списков по хостам неизвестна, `docs/network_reference.md`).
public enum ForeignReach: String, Sendable, Equatable {
    /// Ещё не проверяли, идёт проверка или сети нет вовсе: решать не из чего, ведём себя как до детектора.
    case unknown
    case reachable
    case unreachable
}

/// Режим, который человек выбирает в «Настройках» → «Сеть» (слово Алексея, DECISIONS 05.10 «28л.6»).
public enum NetworkMode: String, Sendable, CaseIterable, Equatable {
    /// Зарубежное недоступно — погода и читалки идут через наш сервер сразу; доступно — напрямую.
    case auto
    /// Наш сервер для погоды и читалок не используется; при отказе честная надпись.
    case directOnly
}

/// Что известно маршрутизаторам в момент запроса.
public struct NetworkPolicy: Sendable, Equatable {
    public var mode: NetworkMode
    public var foreign: ForeignReach
    public init(mode: NetworkMode = .auto, foreign: ForeignReach = .unknown) { self.mode = mode; self.foreign = foreign }
}

/// Одна дешёвая проба: дошёл ли хоть какой-то ответ. `true` — адрес ответил (любым кодом),
/// `false` — не ответил. Сроки держит сам детектор, проба их не знает.
public protocol ReachProbe: Sendable {
    func probe() async -> Bool
}

/// Боевая проба: `HEAD` без тела (~200 байт заголовков) на `api.open-meteo.com`, срок на запрос — как у детектора.
/// Любой HTTP-ответ (даже 4xx/5xx) значит «адрес открыт»: хост ответил, а что он думает о запросе — другой вопрос.
/// Сбой соединения, сброс, DNS, срок — «не открыт».
public struct HeadProbe: ReachProbe {
    public static let defaultURL = URL(string: "https://api.open-meteo.com/v1/forecast")!

    let url: URL
    let timeout: TimeInterval
    let session: URLSession

    public init(url: URL = Self.defaultURL, timeout: TimeInterval = 4, protocolClasses: [AnyClass]? = nil) {
        self.url = url
        self.timeout = timeout
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let protocolClasses { c.protocolClasses = protocolClasses }
        self.session = URLSession(configuration: c)
    }

    public func probe() async -> Bool {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await session.data(for: request)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }
}

/// Детектор доступности зарубежного (28л.6). Результат живёт в памяти на время сеанса и пересматривается
/// - при смене сети (`NetworkReachability`: любое новое значение пути — старый ответ больше не про эту сеть;
///   пока идёт новая проба, состояние «неизвестно»),
/// - раз в несколько минут (доступно — реже, недоступно — чаще: вернувшуюся связь заметить быстро),
/// - по кнопке «Проверить снова» (`recheck()`).
/// Нет сети вовсе (путь не `satisfied`) — «неизвестно» и без пробы: зарубежное и наше недоступны одинаково.
///
/// Срок пробы (`sleep`) и паузу между проверками (`pause`) приходят снаружи — тест не ждёт настоящих секунд.
public actor ForeignReachDetector {
    public static let probeTimeout: Duration = .seconds(3)
    public static let intervalWhenReachable: Duration = .seconds(600)
    public static let intervalWhenUnreachable: Duration = .seconds(120)

    private let probe: any ReachProbe
    private let reachability: (any NetworkReachability)?
    private let timeout: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let pause: @Sendable (Duration) async throws -> Void
    private let intervals: (reachable: Duration, unreachable: Duration)

    public private(set) var state: ForeignReach = .unknown
    /// Номер «эпохи»: растёт, когда старые пробы теряют смысл (сменилась сеть). Ответ чужой эпохи выбрасывается.
    private var epoch = 0
    private var inflight: (epoch: Int, task: Task<ForeignReach, Never>)?
    private var watching: Task<Void, Never>?
    private var polling: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<ForeignReach>.Continuation] = [:]

    public init(probe: any ReachProbe, reachability: (any NetworkReachability)? = nil,
                timeout: Duration = ForeignReachDetector.probeTimeout,
                intervalWhenReachable: Duration = ForeignReachDetector.intervalWhenReachable,
                intervalWhenUnreachable: Duration = ForeignReachDetector.intervalWhenUnreachable,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.probe = probe
        self.pause = pause
        self.reachability = reachability
        self.timeout = timeout
        self.sleep = sleep
        self.intervals = (intervalWhenReachable, intervalWhenUnreachable)
    }

    /// Боевая сборка: проба на Open-Meteo, путь — системный.
    public static func live() -> ForeignReachDetector {
        ForeignReachDetector(probe: HeadProbe(), reachability: SystemReachability())
    }

    deinit {
        watching?.cancel()
        polling?.cancel()
        for c in subscribers.values { c.finish() }
    }

    // MARK: Запуск

    /// Начать слежение: смена сети и таймер. Повторный вызов ничего не делает.
    public func start() {
        guard watching == nil else { return }
        if let reachability {
            let stream = reachability.updates()
            watching = Task { [weak self] in
                for await online in stream {
                    guard let self else { return }
                    await self.pathChanged(online: online)
                }
            }
        } else {
            Task { [weak self] in _ = await self?.recheck() }
        }
        let hasPath = reachability != nil
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let wait = await self.pollDelay()
                do { try await self.pause(wait) } catch { return }
                if Task.isCancelled { return }
                // Сети нет («неизвестно» при слежении за путём) — проба зря: путь сам разбудит, когда сеть вернётся.
                if await self.state != .unknown || !hasPath { _ = await self.recheck() }
            }
        }
    }

    public func stop() {
        watching?.cancel(); watching = nil
        polling?.cancel(); polling = nil
        inflight?.task.cancel(); inflight = nil
    }

    /// Состояния по мере смены: сначала нынешнее, затем только перемены.
    public func changes() -> AsyncStream<ForeignReach> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ForeignReach>.makeStream(bufferingPolicy: .bufferingNewest(8))
        continuation.yield(state)
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.drop(id) }
        }
        return stream
    }

    private func drop(_ id: UUID) { subscribers[id] = nil }

    private func pollDelay() -> Duration {
        state == .unreachable ? intervals.unreachable : intervals.reachable
    }

    // MARK: Проверки

    /// Сменился путь: старый ответ — про другую сеть. Сети нет — «неизвестно» без пробы; сеть есть — новая проба.
    /// Пробу не ждём: следующая смена пути должна обрабатываться сразу, а не после срока зависшей пробы.
    func pathChanged(online: Bool) {
        epoch += 1
        inflight?.task.cancel(); inflight = nil
        set(.unknown)
        if online { _ = startProbeIfNeeded() }
    }

    /// Проверить сейчас (кнопка «Проверить снова», таймер). Параллельные вызовы одной эпохи делят одну пробу.
    /// Возвращает состояние после проверки; если сеть сменилась на ходу — нынешнее, а не ответ старой пробы.
    @discardableResult
    public func recheck() async -> ForeignReach {
        _ = await startProbeIfNeeded().value
        return state
    }

    private func startProbeIfNeeded() -> Task<ForeignReach, Never> {
        if let running = inflight, running.epoch == epoch { return running.task }
        let mine = epoch
        let probe = self.probe, timeout = self.timeout, sleep = self.sleep
        let task = Task<ForeignReach, Never> { [weak self] in
            let result: ForeignReach = await Self.run(probe: probe, timeout: timeout, sleep: sleep) ? .reachable : .unreachable
            await self?.finish(result, epoch: mine)
            return result
        }
        inflight = (mine, task)
        return task
    }

    /// Ответ принимается, только если сеть с тех пор не менялась.
    private func finish(_ result: ForeignReach, epoch e: Int) {
        guard e == epoch else { return }
        inflight = nil
        set(result)
    }

    /// Проба против часов: кто раньше. Опоздавшая проба отменяется (`URLSession` слышит отмену).
    private static func run(probe: any ReachProbe, timeout: Duration,
                            sleep: @escaping @Sendable (Duration) async throws -> Void) async -> Bool {
        await withTaskGroup(of: Bool?.self) { group in
            group.addTask { await probe.probe() }
            group.addTask { try? await sleep(timeout); return nil }
            defer { group.cancelAll() }
            guard let first = await group.next() else { return false }
            return first ?? false
        }
    }

    private func set(_ new: ForeignReach) {
        guard new != state else { return }
        state = new
        for c in subscribers.values { c.yield(new) }
    }
}
