import Foundation
import LightPlanCore

/// Когда форму съёмки сохранить нельзя (слова Алексея 01.10). Не наложения «с предупреждением», а запреты:
/// кнопка «Сохранить» не нажимается, пока причина названа на экране.
public enum SaveGuard {

    public enum Verdict: Equatable, Sendable {
        case ok
        /// «Назначить съёмку» из встречи: дату называет фотограф, за него её не ставят.
        case noDate
    }

    public static func verdict(_ f: EventForm) -> Verdict {
        f.dayUnset ? .noDate : .ok
    }
}
