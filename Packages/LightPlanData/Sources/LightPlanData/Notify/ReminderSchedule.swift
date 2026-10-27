import Foundation
import LightPlanCore
import LightPlanDomain

/// «Напоминать о съёмке» (шаг «Напоминание-1», решение 27.10): за N минут до начала съёмки или встречи — карточка на
/// экране блокировки, как у Календаря iPhone. Один запрос на запись, `lp.remind.<запись>`.
///
/// Здесь только расчёт «кому и когда»; слова — на стороне экрана, система уведомлений — `NotificationScheduler`.
/// Момент — начало по часам **места съёмки** минус N: съёмка в Москве зовёт за 15 минут до московских 12:00, где бы
/// ни был телефон.
public enum ReminderSchedule {

    /// По ней сверка находит напоминания среди запросов и нажатие — что открыть.
    public static let idPrefix = "lp.remind."
    /// Выбор в настройках, минуты; 0 — «выкл».
    public static let choices = [0, 5, 10, 15, 30, 60]
    /// Так стоит, пока человек не выбрал сам (слова Алексея: «за 15 минут до съёмки»).
    public static let defaultMinutes = 15
    /// Мест из 64 (`NotificationScheduler.lanes`): 16 ближайших съёмок и встреч.
    public static let cap = 16

    public static func id(_ sessionId: String) -> String { idPrefix + sessionId }

    /// Одно напоминание: чья запись и когда.
    public struct Notice: Sendable, Hashable {
        public let id: String
        public let sessionId: String
        public let fire: Moment
        /// Смещение пояса места съёмки на день записи, часы: в этом поясе ложатся поля триггера.
        public let offsetHours: Double

        public init(id: String, sessionId: String, fire: Moment, offsetHours: Double) {
            self.id = id; self.sessionId = sessionId; self.fire = fire; self.offsetHours = offsetHours
        }
    }

    /// Кому напоминать: съёмке и встрече. Занятому времени (блоки — не записи), чужим событиям и черновикам из
    /// Календаря — нет: черновик сделан в Календаре руками, и напоминание у него — от самого Календаря. Завершённой
    /// кнопкой съёмке звать некого.
    public static func wants(_ s: Session) -> Bool {
        (s.kind == .shoot || s.kind == .meet) && !s.isCalendarDraft && s.doneAt == nil
    }

    /// Напоминание записи или `nil`: не та запись, выключено (`minutes` ≤ 0) или его момент уже прошёл — в том числе
    /// у начавшейся съёмки.
    public static func notice(for s: Session, minutes: Int, offsetHours: Double, now: Moment) -> Notice? {
        guard minutes > 0, wants(s) else { return nil }
        let fire = WallTime(day: s.day, minutes: s.start).moment(utcOffsetHours: offsetHours).adding(minutes: -minutes)
        guard fire > now else { return nil }
        return Notice(id: id(s.id), sessionId: s.id, fire: fire, offsetHours: offsetHours)
    }

    /// Расписание по всем записям, ближайшие первыми; равные моменты — по идентификатору.
    public static func plan(sessions: [Session], minutes: Int, now: Moment,
                            offsetHours: (Session) -> Double, limit: Int = cap) -> [Notice] {
        guard minutes > 0 else { return [] }
        let all = sessions.compactMap { notice(for: $0, minutes: minutes, offsetHours: offsetHours($0), now: now) }
            .sorted { ($0.fire, $0.id) < ($1.fire, $1.id) }
        return Array(all.prefix(limit))
    }
}
