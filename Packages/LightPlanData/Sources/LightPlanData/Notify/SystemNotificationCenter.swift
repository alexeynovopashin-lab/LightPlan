import Foundation
import Synchronization
import UserNotifications

/// Настоящая система уведомлений iOS: `UNUserNotificationCenter` и
/// `UNCalendarNotificationTrigger` (шаг 30а).
public struct SystemNotificationCenter: NotificationCentering {

    public init() {}

    private var center: UNUserNotificationCenter { .current() }

    /// Правило показа при открытом приложении. Система держит делегата слабо — хозяин держит его сам.
    public static func install(delegate: NotificationPresenter) {
        UNUserNotificationCenter.current().delegate = delegate
    }

    /// Календарный триггер на момент `fire` в поясе места съёмки.
    ///
    /// Поля ложатся в **фиксированном** поясе (смещение места на день
    /// записи, как у веба `momentOf`), а не в поясе телефона: «плавающие»
    /// поля без пояса система читает по часам телефона на момент срабатывания,
    /// и вылет в другой пояс сдвинул бы сигнал. Так момент абсолютный.
    public static func trigger(fire: Date, offsetHours: Double) -> UNCalendarNotificationTrigger {
        let zone = TimeZone(secondsFromGMT: Int((offsetHours * 3600).rounded())) ?? .gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        c.calendar = calendar
        c.timeZone = zone
        return UNCalendarNotificationTrigger(dateMatching: c, repeats: false)
    }

    public func authorization() async -> NotificationAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }

    public func requestAuthorization() async -> Bool {
        var options: UNAuthorizationOptions = [.alert, .sound]
        #if DEBUG
        // Замеры на симуляторе без руки на системном окне (`-LPAlertProvisional 1`): временное разрешение
        // выдаётся без вопроса и доставляет тихо. Путь запроса тот же, меняется только набор опций.
        if UserDefaults.standard.bool(forKey: "LPAlertProvisional") { options.insert(.provisional) }
        #endif
        return (try? await center.requestAuthorization(options: options)) ?? false
    }

    public func pending() async -> [PendingAlert] {
        await center.pendingNotificationRequests().map {
            PendingAlert(id: $0.identifier, signature: $0.content.userInfo["sig"] as? String)
        }
    }

    public func add(_ alert: ScheduledAlert) async {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.threadIdentifier = "lp.studio"
        content.userInfo = ["sig": alert.signature, "session": alert.sessionId]
        let trigger = Self.trigger(fire: alert.fire.date, offsetHours: alert.offsetHours)
        try? await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
    }

    /// Что система на самом деле держит (не наша таблица, а её): по строке на запрос — идентификатор, момент
    /// срабатывания по её же расчёту (`nextTriggerDate`, UTC), поля триггера, заголовок и текст. Для замеров.
    public func dump() async -> [String] {
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        let requests = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications().map { n in
            "delivered \(n.request.identifier) | \(iso.string(from: n.date)) | \(n.request.content.title) | \(n.request.content.body)"
        }
        return delivered.sorted() + requests.map { r in
            let t = r.trigger as? UNCalendarNotificationTrigger
            let next = t?.nextTriggerDate().map { iso.string(from: $0) } ?? "—"
            let c = t?.dateComponents
            let fields = c.map { "\($0.year ?? 0)-\($0.month ?? 0)-\($0.day ?? 0) \($0.hour ?? 0):\($0.minute ?? 0) tz=\($0.timeZone?.secondsFromGMT() ?? 0)" } ?? "—"
            return "\(r.identifier) | \(next) | \(fields) | \(r.content.title) | \(r.content.body)"
        }.sorted()
    }

    public func remove(ids: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}

/// Приложение открыто, а сигнал пришёл (шаг 30а). Правило беты: открытой
/// карточке баннер не нужен — там стоит кольцо с отсчётом, и оно честнее
/// любого баннера; всё прочее, пока телефон в руке, говорится как обычно.
public final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {

    /// Решение при показе в открытом приложении: открыта ли сейчас карточка
    /// этой записи. Вызывается на главном потоке.
    public typealias CardCheck = @MainActor @Sendable (_ sessionId: String) -> Bool

    private let cardOpen = Mutex<CardCheck>({ _ in false })

    public override init() { super.init() }

    public func setCardCheck(_ check: @escaping CardCheck) {
        cardOpen.withLock { $0 = check }
    }

    /// Правило показа — отдельно от системы, чтобы читалось тестом.
    public static func options(cardOpen: Bool) -> UNNotificationPresentationOptions {
        cardOpen ? [] : [.banner, .list, .sound]
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard notification.request.identifier.hasPrefix(StudioSchedule.idPrefix),
              let sid = notification.request.content.userInfo["session"] as? String else {
            return [.banner, .list, .sound]
        }
        let check = cardOpen.withLock { $0 }
        let open = await MainActor.run { check(sid) }
        return Self.options(cardOpen: open)
    }
}
