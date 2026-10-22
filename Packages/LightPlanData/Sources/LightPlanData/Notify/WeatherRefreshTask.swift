import Foundation
#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks
#endif

/// Фоновая сверка прогноза (шаг 30.6, `BGAppRefreshTask`): когда будить — решает iOS, не мы. Сервера нет, гарантий
/// нет: «при закрытом приложении — по возможности, при открытии — всегда» (SWIFT_MIGRATION_PLAN, итерация 30).
/// Идентификатор — в `BGTaskSchedulerPermittedIdentifiers` (`Config/Info-iOS.plist`), режим — `fetch`.
public enum WeatherRefreshTask {
    public static let identifier = "Novopashin.LightPlan.wx"
    /// Не раньше часа: модель прогноза чаще не обновляется, и ответ у нас живёт час (`WeatherLifetime.hourly`).
    public static let gap: TimeInterval = 3600

    /// Попросить следующее пробуждение (заменяет прежнюю просьбу). `false` — система не приняла (симулятор,
    /// фоновое обновление выключено в настройках iPhone).
    @discardableResult
    public static func schedule(after: TimeInterval = gap, now: Date = Date()) -> Bool {
        #if canImport(BackgroundTasks) && os(iOS)
        let r = BGAppRefreshTaskRequest(identifier: identifier)
        r.earliestBeginDate = now.addingTimeInterval(after)
        do { try BGTaskScheduler.shared.submit(r); return true } catch { return false }
        #else
        return false
        #endif
    }

    /// Следить не за чем или говорить запрещено — будить незачем.
    public static func cancel() {
        #if canImport(BackgroundTasks) && os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        #endif
    }
}
