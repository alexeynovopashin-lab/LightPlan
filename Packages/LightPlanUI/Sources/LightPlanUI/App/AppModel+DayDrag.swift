import Foundation
import LightPlanCore
import LightPlanDomain

// MARK: - Время события рукой на ленте дня (29а)

extension AppModel {
    /// Шаг пальца на ленте (веб `dlStep`): 15 минут, 30 — при шаге настроек 30.
    var dayDragStep: Int { DayDrag.step(timeStep: settings.timeStep) }

    /// Сдвиг с ленты дня (веб `dlCommit`): новое время в запись, строка в
    /// заметку («18 сен 13:35 · время сдвинуто в календаре: 14:00 – 16:00 →
    /// 15:00 – 17:00»), след для строки карточки `#cdMoved`. `false` — время
    /// то же или записи нет.
    @discardableResult
    public func moveOnDay(id: String, start: Int, end: Int) -> Bool {
        guard let i = snapshot.sessions.firstIndex(where: { $0.id == id }) else { return false }
        let f = PlannerFacts(app: self, dark: false)
        let when = f.dates.dMonShort(f.date(today)) + " " + f.fmt(Double(nowMinute))
        var s = snapshot.sessions[i]
        let moved = DayDrag.commit(&s, start: start, end: end) { was, now in
            lexicon.t("day.movedNote", ["when": when,
                                        "from": f.range(Double(was.0), Double(was.1)),
                                        "to": f.range(Double(now.0), Double(now.1))])
        }
        guard moved else { return false }
        s.modifiedAt = nowMs
        snapshot.sessions[i] = s
        persist()
        return true
    }
}
