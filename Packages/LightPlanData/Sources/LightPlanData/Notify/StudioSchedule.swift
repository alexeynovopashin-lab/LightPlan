import Foundation
import LightPlanCore
import LightPlanDomain

/// Студийный час зовёт дважды (шаг 30а; веб `studioAnnounce`, `STUDIO_SAY`).
///
/// Здесь только расчёт: ячейка дня → список «что, когда, о чём». Ни
/// `UNUserNotificationCenter`, ни UIKit; система уведомлений — в
/// `NotificationScheduler`, поверх этого списка.
///
/// Числа не свои. Обе ступени привязаны к дедлайну выхода
/// (`RentWindow.deadline` = `to − (60 − hourMin)`, веб `studioDeadline`) и
/// стоят за 10 и за 5 минут до него: при часе в 55 минут это конец − 15 и
/// конец − 10. Двухчасовая аренда зовёт на 1 ч 45 мин и на 1 ч 50 мин.
public enum StudioSchedule {

    /// Минут до дедлайна: первая ступень и вторая (веб `STUDIO_SAY`).
    public static let say = [10, 5]

    /// Потолок iOS: не больше 64 ожидающих запросов на приложение. В очередь
    /// идут ближайшие по времени; остальные встанут, когда приложение откроют.
    public static let systemLimit = 64

    /// Общее начало идентификаторов: по нему расписание находит свои запросы
    /// среди чужих и снимает лишние.
    public static let idPrefix = "lp.studio."

    /// Один сигнал: ячейка, ступень, момент.
    public struct Notice: Sendable, Hashable {
        /// `lp.studio.<запись>.<ячейка>.<ступень>`; ячейка — номер в
        /// маршруте записи, `r` — запись старого вида. Не зависит от часов:
        /// правка часов и продление переписывают тот же запрос, а не множат.
        public let id: String
        public let sessionId: String
        /// 0 — начало аренды (30б.3), 1 — за десять минут, 2 — за пять.
        public let stage: Int
        public let fire: Moment
        /// Минут до дедлайна в момент сигнала: 10, 5 или меньше, если аренда
        /// началась позже, чем наступила ступень (веб говорит «через N» по
        /// остатку, а не по номеру ступени).
        public let minutesLeft: Int
        /// Дедлайн выхода, минута шкалы съёмки.
        public let deadline: Int
        /// Смещение пояса места съёмки на день записи, часы: по нему момент
        /// превращается в календарные поля триггера (см. `NotificationTrigger`).
        public let offsetHours: Double
        public let studioName: String
        public let hallName: String?

        public init(id: String, sessionId: String, stage: Int, fire: Moment, minutesLeft: Int, deadline: Int,
                    offsetHours: Double, studioName: String, hallName: String?) {
            self.id = id; self.sessionId = sessionId; self.stage = stage; self.fire = fire
            self.minutesLeft = minutesLeft; self.deadline = deadline; self.offsetHours = offsetHours
            self.studioName = studioName; self.hallName = hallName
        }
    }

    /// Сигналы одной записи — по всем её ячейкам со студией. Прошедшие не
    /// возвращаются.
    ///
    /// - Parameters:
    ///   - offsetHours: смещение пояса места съёмки на день записи.
    ///   - finished: съёмка уже завершена (фаза «после») — звать некого.
    public static func notices(for s: Session, studios: [Studio], offsetHours: Double,
                               now: Moment, finished: Bool) -> [Notice] {
        guard s.kind.isWork, !finished else { return [] }
        var out: [Notice] = []
        for cell in RentWindow.cells(of: s, studios: studios) {
            let w = cell.window
            let deadline = w.deadline
            // Дедлайн раньше начала аренды: человек его уже не застанет —
            // веб молчит (`left < 0`).
            guard deadline >= w.from else { continue }
            let key = cell.index.map(String.init) ?? "r"
            // Ступень приходит на `deadline − 10` / `− 5`. Веб молчит, пока аренда не началась (`nm < rw.from`),
            // и в момент начала говорит одну ступень — ту, что уже наступила. Поэтому обе ступени, раньше
            // начала, схлопываются в начало, а две на одной минуте — в одну, вторую.
            let m2 = max(deadline - say[1], w.from)
            let m1 = max(deadline - say[0], w.from)
            let slots: [(stage: Int, minute: Int)] = m1 < m2 ? [(1, m1), (2, m2)] : [(2, m2)]
            for slot in slots {
                let wall = WallTime(day: s.day, minutes: slot.minute)
                let fire = wall.moment(utcOffsetHours: offsetHours)
                guard fire > now else { continue }
                out.append(Notice(
                    id: "\(idPrefix)\(s.id).\(key).\(slot.stage)", sessionId: s.id, stage: slot.stage,
                    fire: fire, minutesLeft: deadline - slot.minute, deadline: deadline,
                    offsetHours: offsetHours, studioName: w.studio.name, hallName: w.hallName))
            }
        }
        return out
    }

    /// Начало аренды (30б.3, слова Алексея 25.10: «в начале аренды уведомление «Студийный час», нажатие на него включает полный
    /// режим студии»): ступень `0`, на минуте `from`. Нажатие переводит экран активности в студийный режим (`NotificationPresenter.Tap.studio`).
    /// Молчит, если в ту же минуту и так зовёт ступень выхода (аренда короче десяти минут): два сигнала подряд — лишнее.
    public static func starts(for s: Session, studios: [Studio], offsetHours: Double,
                              now: Moment, finished: Bool) -> [Notice] {
        guard s.kind.isWork, !finished else { return [] }
        var out: [Notice] = []
        for cell in RentWindow.cells(of: s, studios: studios) {
            let w = cell.window
            guard w.deadline >= w.from, max(w.deadline - say[0], w.from) > w.from, max(w.deadline - say[1], w.from) > w.from else { continue }
            let fire = WallTime(day: s.day, minutes: w.from).moment(utcOffsetHours: offsetHours)
            guard fire > now else { continue }
            let key = cell.index.map(String.init) ?? "r"
            out.append(Notice(id: "\(idPrefix)\(s.id).\(key).0", sessionId: s.id, stage: 0, fire: fire,
                              minutesLeft: w.deadline - w.from, deadline: w.deadline, offsetHours: offsetHours,
                              studioName: w.studio.name, hallName: w.hallName))
        }
        return out
    }

    /// Расписание по всем записям: ближайшие `limit`, по времени. Равные
    /// моменты — по идентификатору, чтобы порядок не зависел от обхода.
    public static func plan(sessions: [Session], studios: [Studio], now: Moment,
                            offsetHours: (Session) -> Double, finished: (Session) -> Bool,
                            limit: Int = systemLimit) -> [Notice] {
        var all: [Notice] = []
        for s in sessions {
            all += notices(for: s, studios: studios, offsetHours: offsetHours(s), now: now, finished: finished(s))
            all += starts(for: s, studios: studios, offsetHours: offsetHours(s), now: now, finished: finished(s))
        }
        all.sort { ($0.fire, $0.id) < ($1.fire, $1.id) }
        return Array(all.prefix(limit))
    }
}
