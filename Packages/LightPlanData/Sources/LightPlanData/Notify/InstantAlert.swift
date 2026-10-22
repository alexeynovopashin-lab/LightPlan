import Foundation

/// Уведомление «сейчас», без расписания (шаг 30.6): фон узнал новость — говорит сразу.
public struct InstantAlert: Sendable, Hashable {
    /// Один идентификатор на запись: новое уведомление о той же съёмке заменяет старое в центре уведомлений.
    public let id: String
    public let sessionId: String
    public let title: String
    public let body: String

    public init(id: String, sessionId: String, title: String, body: String) {
        self.id = id
        self.sessionId = sessionId
        self.title = title
        self.body = body
    }

    /// Приставка уведомлений о погоде: по ней нажатие находит запись и открывает её карточку.
    public static let weatherPrefix = "lp.wx."
    public static func weatherId(_ sessionId: String) -> String { weatherPrefix + sessionId }
}

/// Сказать сейчас. Настоящая — `SystemNotificationCenter`; тесты подставляют пустышку.
public protocol InstantNotifying: Sendable {
    /// `false` — система не приняла: о такой новости не сказано, и память этого не запишет.
    func deliver(_ alert: InstantAlert) async -> Bool
}
