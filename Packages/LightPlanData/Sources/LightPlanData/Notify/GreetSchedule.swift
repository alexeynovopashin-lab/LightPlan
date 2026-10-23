import Foundation
import LightPlanCore
import LightPlanDomain

/// Поздравления по расписанию (шаг К6, справка `docs/clients_reference.md` § 6): один запрос на день с праздниками,
/// `lp.greet.<ГГГГ-ММ-ДД>`, в 10:00 по часам телефона. Здесь только идентификаторы и места; праздники —
/// `Greetings.days` (Domain), слова — на стороне экрана.
public enum GreetSchedule {
    /// По ней сверка находит поздравления среди запросов и нажатие — что открыть.
    public static let idPrefix = "lp.greet."
    /// Мест из 64 (§ 6): 40 ближайших дней с праздниками.
    public static let cap = Greetings.cap

    public static func id(_ d: CivilDate) -> String { idPrefix + d.snapshotString }
}
