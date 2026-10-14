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

    public init(id: String, sessionId: String, fire: Moment, offsetHours: Double, title: String, body: String) {
        self.id = id
        self.sessionId = sessionId
        self.fire = fire
        self.offsetHours = offsetHours
        self.title = title
        self.body = body
    }

    /// Отпечаток содержимого: лежит в запросе (`userInfo["sig"]`), по нему
    /// сверка находит устаревшие запросы без разбора триггера.
    public var signature: String { "\(fire.milliseconds)|\(offsetHours)|\(title)|\(body)" }
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
public struct NotificationScheduler: Sendable {
    public struct Report: Sendable, Equatable {
        /// Поставлены или заменены.
        public var added: [String] = []
        /// Сняты: данных под них больше нет.
        public var removed: [String] = []
        /// Уже стояли такими же — не тронуты.
        public var kept: [String] = []
        /// Не влезли под потолок системы.
        public var dropped: [String] = []
        /// Система отказала при постановке: расписание применено не целиком.
        public var failed: [String] = []
    }

    public let center: any NotificationCentering
    public let prefix: String
    public let limit: Int

    public init(center: any NotificationCentering, prefix: String = StudioSchedule.idPrefix,
                limit: Int = StudioSchedule.systemLimit) {
        self.center = center
        self.prefix = prefix
        self.limit = limit
    }

    /// Привести систему к `desired` (ближайшие первыми). Чужие запросы не
    /// трогаются, но занимают место под потолком.
    @discardableResult
    public func sync(_ desired: [ScheduledAlert]) async -> Report {
        let pending = await center.pending()
        let ours = pending.filter { $0.id.hasPrefix(prefix) }
        let foreign = pending.count - ours.count
        let room = max(0, limit - foreign)
        let wanted = Array(desired.prefix(room))
        var report = Report()
        report.dropped = desired.dropFirst(room).map(\.id)

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

    /// Снять все свои запросы (тумблер выключили).
    public func clear() async {
        let ids = await center.pending().map(\.id).filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty { await center.remove(ids: ids) }
    }
}
