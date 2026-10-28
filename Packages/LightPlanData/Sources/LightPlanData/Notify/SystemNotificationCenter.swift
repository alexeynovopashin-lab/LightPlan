import Foundation
import Synchronization
import UserNotifications
import LightPlanCore

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

    /// Поздравление (К6): поля без пояса и без календаря — система читает их по часам телефона в момент срабатывания,
    /// так 10:00 остаётся 10:00 и после перелёта (из документации Apple, на телефоне не мерено).
    public static func trigger(wall: WallTime) -> UNCalendarNotificationTrigger {
        var c = DateComponents()
        c.year = wall.day.year
        c.month = wall.day.month
        c.day = wall.day.day
        c.hour = wall.minutes / 60
        c.minute = wall.minutes % 60
        return UNCalendarNotificationTrigger(dateMatching: c, repeats: false)
    }

    #if DEBUG
    /// Сдвиг часов приложения при переезде во времени (`-LPTravelTo`, только Debug), секунды: запрос встаёт на настоящий
    /// момент `fire − сдвиг`, триггером «через N секунд».
    nonisolated(unsafe) public static var debugShift: TimeInterval = 0
    #endif

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

    public func add(_ alert: ScheduledAlert) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        var info: [String: String] = ["sig": alert.signature, "session": alert.sessionId]
        var trigger: UNNotificationTrigger
        if let wall = alert.wall {
            content.threadIdentifier = "lp.greet"
            if let cid = alert.clientId { info["client"] = cid }
            trigger = Self.trigger(wall: wall)
        } else {
            content.threadIdentifier = alert.id.hasPrefix(ReminderSchedule.idPrefix) ? "lp.remind" : "lp.studio"
            trigger = Self.trigger(fire: alert.fire.date, offsetHours: alert.offsetHours)
        }
        // Неотложное решено до постановки (`timeSensitiveAllowed`) и лежит в отпечатке запроса.
        if alert.urgent { content.interruptionLevel = .timeSensitive }
        content.userInfo = info
        #if DEBUG
        if Self.debugShift != 0 {
            let left = alert.fire.date.timeIntervalSinceNow - Self.debugShift
            guard left > 0 else { return false }
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, left), repeats: false)
        }
        #endif
        do {
            try await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
            return true
        } catch {
            return false
        }
    }

    /// Что система на самом деле держит (не наша таблица, а её): по строке на запрос — идентификатор, момент
    /// срабатывания по её же расчёту (`nextTriggerDate`, UTC), поля триггера, заголовок и текст. Для замеров.
    public func dump() async -> [String] {
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        let requests = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications().map { n in
            "delivered \(n.request.identifier) | \(iso.string(from: n.date)) | \(n.request.content.title) | \(n.request.content.body)"
                + Self.level(n.request.content)
        }
        return delivered.sorted() + requests.map { r in
            let t = r.trigger as? UNCalendarNotificationTrigger
            let next = (t?.nextTriggerDate() ?? (r.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate())
                .map { iso.string(from: $0) } ?? "—"
            let c = t?.dateComponents
            let fields = c.map { "\($0.year ?? 0)-\($0.month ?? 0)-\($0.day ?? 0) \($0.hour ?? 0):\($0.minute ?? 0) tz=\($0.timeZone?.secondsFromGMT() ?? 0)" } ?? "—"
            return "\(r.identifier) | \(next) | \(fields) | \(r.content.title) | \(r.content.body)" + Self.level(r.content)
        }.sorted()
    }

    /// Уровень, с которым система держит запрос, — только не обычный: ` | level=timeSensitive`.
    private static func level(_ c: UNNotificationContent) -> String {
        switch c.interruptionLevel {
        case .active: return ""
        case .timeSensitive: return " | level=timeSensitive"
        case .passive: return " | level=passive"
        case .critical: return " | level=critical"
        @unknown default: return " | level=\(c.interruptionLevel.rawValue)"
        }
    }

    public func remove(ids: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Бесплатная подпись права не даёт (замер 27.10: «Personal development teams … do not support the Time Sensitive
    /// Notifications capability»), и напоминание идёт обычным. Появится право в `Config/LightPlan-iOS.entitlements` —
    /// здесь станет `true`, и сверка перепишет стоящие напоминания неотложными.
    public func timeSensitiveAllowed() async -> Bool {
        await center.notificationSettings().timeSensitiveSetting == .enabled
    }
}

extension SystemNotificationCenter: InstantNotifying {
    /// Без триггера — система показывает сразу (шаг 30.6). Право уведомлять не спрашивается здесь никогда: нет его —
    /// система отказывает, и это `false`.
    public func deliver(_ alert: InstantAlert) async -> Bool {
        guard await authorization() == .allowed else { return false }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.threadIdentifier = "lp.wx"
        content.userInfo = ["session": alert.sessionId]
        do {
            try await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: nil))
            return true
        } catch {
            return false
        }
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

    /// Куда ведёт нажатие на уведомление.
    public enum Tap: Sendable, Equatable {
        /// Прогноз переменился (30.6) или напоминание о съёмке: карточка этой записи.
        case card(String)
        /// Поздравление (К6): карточка клиента, если праздники дня у одного клиента; `nil` — список «Клиенты».
        case client(String?)
        /// Студийный час (30б.3): экран активности переходит в студийный режим; сама карточка не открывается (как было).
        case studio(String)
    }

    /// Что делать с нажатием. Вызывается на главном потоке.
    public typealias Open = @MainActor @Sendable (Tap) -> Void
    private let open = Mutex<Open?>(nil)
    /// Нажатие пришло раньше, чем приложение собрало себя (холодный запуск из уведомления): ждёт хозяина.
    private let waiting = Mutex<Tap?>(nil)

    public override init() { super.init() }

    /// Один на живое приложение: ставится делегатом на запуске, до того как система передаст нажатие, с которым
    /// приложение открыли (иначе нажатие на уведомление при холодном запуске теряется).
    public static let shared = NotificationPresenter()

    public func setCardCheck(_ check: @escaping CardCheck) {
        cardOpen.withLock { $0 = check }
    }

    /// Хозяин готов открывать; нажатие, что ждало его, исполняется сразу.
    public func setOpen(_ handler: @escaping Open) {
        open.withLock { $0 = handler }
        if let tap = waiting.withLock({ w -> Tap? in defer { w = nil }; return w }) {
            Task { @MainActor in handler(tap) }
        }
    }

    /// Нажатие по идентификатору запроса и его `userInfo`: чужое и не наше — `nil`. Отдельно от системы, чтобы читалось тестом.
    public static func tap(id: String, info: [AnyHashable: Any]) -> Tap? {
        if id.hasPrefix(InstantAlert.weatherPrefix), let sid = info["session"] as? String { return .card(sid) }
        if id.hasPrefix(GreetSchedule.idPrefix) { return .client(info["client"] as? String) }
        if id.hasPrefix(StudioSchedule.idPrefix), let sid = info["session"] as? String { return .studio(sid) }
        // Напоминание о съёмке: её карточка.
        if id.hasPrefix(ReminderSchedule.idPrefix), let sid = info["session"] as? String { return .card(sid) }
        return nil
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse) async {
        let r = response.notification.request
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let tap = Self.tap(id: r.identifier, info: r.content.userInfo) else { return }
        guard let handler = open.withLock({ $0 }) else { waiting.withLock { $0 = tap }; return }
        await MainActor.run { handler(tap) }
    }

    /// Правило показа — отдельно от системы, чтобы читалось тестом.
    public static func options(cardOpen: Bool) -> UNNotificationPresentationOptions {
        cardOpen ? [] : [.banner, .list, .sound]
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Студийный час и напоминание молчат над открытой карточкой своей записи: она и так перед глазами.
        let id = notification.request.identifier
        guard id.hasPrefix(StudioSchedule.idPrefix) || id.hasPrefix(ReminderSchedule.idPrefix),
              let sid = notification.request.content.userInfo["session"] as? String else {
            return [.banner, .list, .sound]
        }
        let check = cardOpen.withLock { $0 }
        let open = await MainActor.run { check(sid) }
        return Self.options(cardOpen: open)
    }
}
