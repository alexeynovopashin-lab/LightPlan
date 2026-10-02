import Foundation
import LightPlanCore

/// «Требуют внимания» (итерация 28д, справка `docs_reference.md` § 4): съёмки, у которых по цепочке
/// сделки что-то не закрыто и время подошло. Не бумаги, а съёмки; строка несёт причины словами
/// (слова — в экране, здесь — коды).
public enum DocAttention {

    /// Порог правила 1: за сколько дней до съёмки начинать напоминать о договоре (DECISIONS 01.10).
    public static let contractDays = 7
    /// Порог правила 2: сколько дней после съёмки ждать акт.
    public static let closingDays = 3

    /// Причина, в порядке срочности (он же порядок групп списка).
    public enum Reason: Int, Sendable, Hashable, Comparable, CaseIterable {
        /// «Нет договора»: съёмка через 0…7 дней.
        case noContract
        /// «Нет акта» (`ru`) / «Нет протокола приёмки» (`eu`): съёмка была ≥ 3 дней назад.
        case noClosing
        /// «Нет оплаты»: счёт есть, оплаты нет, доход больше нуля.
        case noPay

        public static func < (a: Reason, b: Reason) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Item: Sendable, Hashable {
        public var session: Session
        /// По возрастанию срочности: первая — та, в чьей группе строка стоит.
        public var reasons: [Reason]
        /// `D − T`: дней до съёмки, отрицательное — после («через 5 дн.» / «3 дн. назад»).
        public var daysUntil: Int

        public var primary: Reason { reasons[0] }
    }

    /// Сегодняшний день в поясе телефона (как `Delivery.daysTaken(zone:)`); переворачивается ровно
    /// в 00:00 пояса. Часы машины тут не читаются — момент и пояс приходят параметрами.
    public static func today(at moment: Moment, zone: TimeZone) -> CivilDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.year, .month, .day], from: moment.date)
        return CivilDate(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Причины у одной съёмки; пусто — в порядке.
    /// - Решение Алексея 02.10: годовой договор организации закрывает «Договор» только здесь,
    ///   карточка съёмки (`DealChain`) остаётся как есть.
    /// - Закрывающая бумага — только акт (`ru`) и протокол приёмки (`eu`); у `us`/`uk` второго правила нет.
    public static func reasons(for s: Session, orgs: [Org], among sessions: [Session],
                               practice: Practice, today: CivilDate) -> [Reason] {
        guard s.kind == .shoot, DealChain.isShown(genre: s.genre, practice: practice) else { return [] }
        let links = DealChain.links(for: s, practice: practice, among: sessions)
        func closed(_ step: DealStep) -> Bool { links.first { $0.step == step }?.done ?? false }
        let ahead = s.day.days(since: today)
        var out: [Reason] = []

        if (0...contractDays).contains(ahead), !closed(.contract), !orgHasContract(s, orgs) {
            out.append(.noContract)
        }
        if -ahead >= closingDays {
            switch practice {
            case .ru where !closed(.act): out.append(.noClosing)
            case .eu where !closed(.acceptance): out.append(.noClosing)
            default: break
            }
        }
        let payStep: DealStep = (practice == .ru || practice == .eu) ? .pay : .balance
        if s.docs.contains(where: { $0.kind == .invoice }), !closed(payStep),
           Money.income(of: s, among: sessions) > 0 {
            out.append(.noPay)
        }
        return out
    }

    /// Все съёмки с причинами, порядок — как в группах списка: сначала группа по самой срочной
    /// причине, в группе — ближайшая по дню первой (для «нет договора» — меньше дней до съёмки;
    /// для «нет акта» — больше дней после; для «нет оплаты» — ближе к сегодняшнему дню).
    public static func items(sessions: [Session], orgs: [Org], practice: Practice, today: CivilDate) -> [Item] {
        let found = sessions.compactMap { s -> Item? in
            let r = reasons(for: s, orgs: orgs, among: sessions, practice: practice, today: today)
            return r.isEmpty ? nil : Item(session: s, reasons: r, daysUntil: s.day.days(since: today))
        }
        return found.enumerated().sorted { x, y in
            let a = x.element, b = y.element
            if a.primary != b.primary { return a.primary < b.primary }
            let (p, q): (Int, Int)
            switch a.primary {
            case .noContract: (p, q) = (a.daysUntil, b.daysUntil)
            case .noClosing: (p, q) = (a.daysUntil, b.daysUntil)
            case .noPay: (p, q) = (abs(a.daysUntil), abs(b.daysUntil))
            }
            return p != q ? p < q : x.offset < y.offset
        }.map(\.element)
    }

    /// Группы списка: «Нет договора» → «Нет акта» → «Нет оплаты»; съёмка с двумя причинами стоит
    /// в более срочной и несёт вторую словом. Пустые группы не возвращаются.
    public static func groups(_ items: [Item]) -> [(reason: Reason, items: [Item])] {
        Reason.allCases.compactMap { r in
            let list = items.filter { $0.primary == r }
            return list.isEmpty ? nil : (r, list)
        }
    }

    private static func orgHasContract(_ s: Session, _ orgs: [Org]) -> Bool {
        guard let id = s.orgId, let o = orgs.first(where: { $0.id == id }) else { return false }
        return o.docs.contains { $0.kind == .contract }
    }
}
