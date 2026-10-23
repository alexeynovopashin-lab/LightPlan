import Foundation
import LightPlanCore

/// Стопка долгов (шаг К5, `docs/clients_reference.md` § 7.2): несданные съёмки
/// одной стопкой над открытой карточкой.
///
/// Долг — съёмка, у которой «сдана» не нажата руками (Алексей, 21.10: «считаем
/// сданной только ту, где вручную нажали на смену статуса»). Срок сдачи статус
/// не меняет: просроченная и не просроченная одинаково долг. Плюс из кода:
/// только работа (встреча и чужое событие не сдаются), жанр со сдачей (пейзаж и
/// стрит — нет; без жанра — да, как у веба), и съёмка уже позади — по той же
/// фазе, что у карточки: идущая или ещё не начатая съёмка сегодня не долг.
public enum Debts {

    /// Долг ли запись сейчас.
    ///
    /// - Parameters:
    ///   - now: настенные часы места съёмки (как у `EventPhase.of`).
    ///   - manualEnd: «Завершать вручную» — съёмка позади только после «Завершить».
    public static func isDebt(_ s: Session, now: WallTime, manualEnd: Bool) -> Bool {
        guard s.kind.isWork, !s.delivered, GenreProfile(s.genre).spec.delivery else { return false }
        return EventPhase.of(s, now: now, manualEnd: manualEnd) == .after
    }

    /// Все долги в порядке стопки: самый старый первым — он ближе всех к
    /// открытой карточке (Алексей, 23.10: «самые старые долги ближе»). Старше —
    /// раньше день, в один день — раньше начало, при равном — раньше записана.
    public static func stack(_ sessions: [Session], now: (Session) -> WallTime, manualEnd: Bool) -> [Session] {
        sessions.enumerated()
            .filter { isDebt($0.element, now: now($0.element), manualEnd: manualEnd) }
            .sorted { a, b in
                if a.element.day != b.element.day { return a.element.day < b.element.day }
                if a.element.start != b.element.start { return a.element.start < b.element.start }
                return a.offset < b.offset
            }
            .map(\.element)
    }
}
