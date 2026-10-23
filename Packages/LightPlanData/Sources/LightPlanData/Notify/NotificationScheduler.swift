import Foundation
import LightPlanCore

/// Один запрос к системе уведомлений: что сказать и в какой момент.
public struct ScheduledAlert: Sendable, Hashable {
    public let id: String
    public let sessionId: String
    public let fire: Moment
    /// Смещение пояса места съёмки, часы: момент ложится в календарные поля
    /// триггера именно в этом поясе, а не в поясе телефона.
    public let offsetHours: Double
    public let title: String
    public let body: String
    /// Поздравление (К6): настенные день и минута **по часам телефона**, триггер без пояса — следует за телефоном в
    /// поездке. `fire` тогда — тот же момент в поясе телефона на час расчёта, только для порядка «ближайшие первыми».
    public let wall: WallTime?
    /// Клиент, чью карточку открывает нажатие на поздравление; `nil` — праздники разных клиентов, открыть «Клиенты».
    public let clientId: String?

    public init(id: String, sessionId: String, fire: Moment, offsetHours: Double, title: String, body: String) {
        self.id = id
        self.sessionId = sessionId
        self.fire = fire
        self.offsetHours = offsetHours
        self.title = title
        self.body = body
        self.wall = nil
        self.clientId = nil
    }

    /// Поздравление: настенное время телефона, без пояса.
    public init(id: String, wall: WallTime, fire: Moment, clientId: String?, title: String, body: String) {
        self.id = id
        self.sessionId = ""
        self.fire = fire
        self.offsetHours = 0
        self.title = title
        self.body = body
        self.wall = wall
        self.clientId = clientId
    }

    /// Отпечаток содержимого: лежит в запросе (`userInfo["sig"]`), по нему
    /// сверка находит устаревшие запросы без разбора триггера. У поздравления — настенное время, не момент: переезд в
    /// другой пояс запрос не переписывает.
    public var signature: String {
        var travel = ""
        #if DEBUG
        // Переезд во времени (`-LPTravelTo`): тот же запрос при другом сдвиге встаёт на другой настоящий момент.
        if SystemNotificationCenter.debugShift != 0 { travel = "|travel \(Int(SystemNotificationCenter.debugShift))" }
        #endif
        if let wall { return "wall \(wall.day.daysSince1970) \(wall.minutes)|\(clientId ?? "")|\(title)|\(body)" + travel }
        return "\(fire.milliseconds)|\(offsetHours)|\(title)|\(body)" + travel
    }
}

/// Что система сказала о праве приложения уведомлять.
public enum NotificationAuthorization: Sendable, Equatable {
    /// Ещё не спрашивали: спросить можно один раз.
    case notDetermined
    /// Отказали (или выключили в настройках iPhone): спросить уже нельзя.
    case denied
    case allowed
}

/// Ожидающий запрос, как его видит сверка.
public struct PendingAlert: Sendable, Hashable {
    public let id: String
    /// `nil` — запрос не наш или без отпечатка.
    public let signature: String?

    public init(id: String, signature: String?) {
        self.id = id
        self.signature = signature
    }
}

/// То, что расписанию нужно от системы уведомлений. Настоящая —
/// `SystemNotificationCenter`; тесты подставляют пустышку.
public protocol NotificationCentering: Sendable {
    func authorization() async -> NotificationAuthorization
    /// Показать системный вопрос. `true` — разрешили.
    func requestAuthorization() async -> Bool
    func pending() async -> [PendingAlert]
    /// Поставить запрос; тот же идентификатор заменяет ожидающий. `false` — система отказала.
    func add(_ alert: ScheduledAlert) async -> Bool
    func remove(ids: [String]) async
}

/// Сверка расписания с системой (шаг 30а): после неё в системе лежит ровно то,
/// что вычислено, и ни одним запросом больше из наших.
///
/// Наших расписаний несколько, и 64 места iOS делятся между ними **по таблице** (`lanes`, справка
/// `docs/clients_reference.md` § 6), а не по тому, кто сверился последним: сверка всегда видит все расписания сразу.
/// Полоса с долей (поздравления, 40) берёт не больше доли; полоса без доли (студийный час) — всё, что осталось.
/// Чужие запросы (ни одной нашей приставки) не трогаются и занимают место.
public struct NotificationScheduler: Sendable {
    public struct Report: Sendable, Equatable {
        /// Поставлены или заменены.
        public var added: [String] = []
        /// Сняты: данных под них больше нет.
        public var removed: [String] = []
        /// Уже стояли такими же — не тронуты.
        public var kept: [String] = []
        /// Не влезли под потолок системы или под долю своей полосы.
        public var dropped: [String] = []
        /// Система отказала при постановке: расписание применено не целиком.
        public var failed: [String] = []
    }

    /// Одно расписание под общим потолком: свои запросы по приставке и доля мест.
    public struct Lane: Sendable, Hashable {
        public let prefix: String
        /// Не больше стольких мест; `nil` — всё, что осталось после полос с долей.
        public let cap: Int?
        public init(prefix: String, cap: Int?) {
            self.prefix = prefix
            self.cap = cap
        }
    }

    /// Студийный час: ближайшие аренды важнее — всё, что осталось (≥ 24).
    public static let studio = Lane(prefix: StudioSchedule.idPrefix, cap: nil)
    /// Поздравления: одно на день, не больше 40 дней.
    public static let greet = Lane(prefix: GreetSchedule.idPrefix, cap: GreetSchedule.cap)
    /// Таблица мест (§ 6). «Прогноз переменился» (`lp.wx.`) говорит сразу и в очереди не стоит — полосы у него нет.
    public static let lanes = [greet, studio]

    public let center: any NotificationCentering
    public let lanes: [Lane]
    public let limit: Int

    public init(center: any NotificationCentering, lanes: [Lane] = NotificationScheduler.lanes,
                limit: Int = StudioSchedule.systemLimit) {
        self.center = center
        self.lanes = lanes
        self.limit = limit
    }

    private func lane(of id: String) -> Lane? { lanes.first { id.hasPrefix($0.prefix) } }

    /// Привести систему к `desired` — запросам **всех** полос сразу (каждая полоса ближайшими первыми). Полоса, которой
    /// в `desired` нет, снимается целиком. Запрос без нашей приставки не ставится (`dropped`).
    @discardableResult
    public func sync(_ desired: [ScheduledAlert]) async -> Report {
        let pending = await center.pending()
        let ours = pending.filter { lane(of: $0.id) != nil }
        var room = max(0, limit - (pending.count - ours.count))
        var report = Report()
        var wanted: [ScheduledAlert] = []
        report.dropped = desired.filter { lane(of: $0.id) == nil }.map(\.id)
        // Сперва полосы с долей, потом «остаток»: доля не зависит от того, сколько мест держит другая полоса сейчас.
        for l in lanes.filter({ $0.cap != nil }) + lanes.filter({ $0.cap == nil }) {
            let mine = desired.filter { lane(of: $0.id) == l }
            let take = min(room, l.cap ?? room)
            wanted += mine.prefix(take)
            report.dropped += mine.dropFirst(take).map(\.id)
            room -= min(take, mine.count)
        }

        // Лишнее снимается раньше, чем ставится новое: иначе система на миг держала бы больше 64 и выбросила бы сама.
        let wantedIds = Set(wanted.map(\.id))
        let stale = ours.map(\.id).filter { !wantedIds.contains($0) }
        if !stale.isEmpty { await center.remove(ids: stale) }
        report.removed = stale

        let have = Dictionary(ours.map { ($0.id, $0.signature) }, uniquingKeysWith: { a, _ in a })
        for alert in wanted {
            if let sig = have[alert.id], sig == alert.signature {
                report.kept.append(alert.id)
            } else {
                if await center.add(alert) { report.added.append(alert.id) } else { report.failed.append(alert.id) }
            }
        }
        return report
    }

    /// Снять все свои запросы всех полос (уведомлять запретили).
    public func clear() async {
        let ids = await center.pending().map(\.id).filter { lane(of: $0) != nil }
        if !ids.isEmpty { await center.remove(ids: ids) }
    }
}
