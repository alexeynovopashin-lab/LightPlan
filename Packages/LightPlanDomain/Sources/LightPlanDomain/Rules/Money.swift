import Foundation
import LightPlanCore

/// Доход, расход и суммы по валютам (веб «Деньги: доход, расходы, прибыль»).
///
/// Деньги — `Decimal`, а не двоичное число веба (корзина 2 плана): почасовая
/// «1234 ₽ × 50 минут» здесь ровно 1028,(3), а не 1028,3333333333335. Отличия с
/// вебом — в последних знаках дробной части, которую экран всё равно
/// округляет до целых (`NumberText`, итерация 14).
public enum Money {

    /// Доход записи (веб `sessionIncome`). Встреча и чужое событие — не работа,
    /// дохода у них нет; нет способа оплаты — нет и дохода.
    ///
    /// `sessions` — все живые записи: доля месяца у помесячной карточки
    /// делится между соседями по группе.
    public static func income(of s: Session, among sessions: [Session]) -> Decimal {
        guard s.kind.isWork, let pay = s.pay else { return 0 }
        let r = s.rate ?? 0
        switch pay.mechanic {
        case .hourly: return r * Decimal(s.duration ?? 0) / 60
        case .unit: return r * s.units
        case .monthly: return s.rate == nil ? monthShare(of: s, among: sessions) : r
        case .flat: return r
        }
    }

    /// Доход минус расход (веб `sessionNet`). Предоплата не вычитается: она
    /// отвечает, сколько привезут в день съёмки, а не сколько заработано.
    public static func net(of s: Session, among sessions: [Session]) -> Decimal {
        income(of: s, among: sessions) - s.expense
    }

    /// Валюта сделки (веб `sessionCurrency`): своя у записи, иначе из настроек.
    public static func currency(of s: Session, home: Currency) -> Currency {
        s.currency ?? home
    }

    /// Суммы по валютам без пересчёта курса (веб `sumByCurrency`): домашняя
    /// валюта первой, остальные по убыванию, равные — в порядке появления.
    /// Валюта с нулевой суммой не показывается.
    public static func sumByCurrency(_ list: [Session], home: Currency,
                                     amount: (Session) -> Decimal) -> [(currency: Currency, sum: Decimal)] {
        var order: [Currency] = []
        var by: [Currency: Decimal] = [:]
        for s in list {
            let c = currency(of: s, home: home)
            if by[c] == nil { order.append(c) }
            by[c, default: 0] += amount(s)
        }
        let codes = order.filter { by[$0]! != 0 }
        let others = codes.enumerated()
            .filter { $0.element != home }
            .sorted { a, b in by[a.element]! != by[b.element]! ? by[a.element]! > by[b.element]! : a.offset < b.offset }
            .map(\.element)
        let head: [Currency] = codes.contains(home) ? [home] : []
        return (head + others).map { ($0, by[$0]!) }
    }

    // MARK: - Повтор с помесячной оплатой

    /// Номер месяца группы от её первого дня (веб `repPeriodIndex`): абонемент с
    /// 14-го по 13-е. Месяц без такого числа кончается своим последним днём:
    /// от 31 января первый — по 28 февраля.
    public static func monthIndex(start: CivilDate, day: CivilDate) -> Int {
        let k = (day.year - start.year) * 12 + day.month - start.month
        return day.day < start.day ? k - 1 : k
    }

    /// Сумма месяца `k` у группы (веб `repSumAt`): действует самая поздняя из
    /// смен, начатых не позже этого месяца. Смены читаются со всех живых
    /// карточек группы — слияние облака могло оставить у карточки версию, где
    /// смены ещё нет, и её донесут соседи.
    public static func monthSum(_ rep: Repeat, month k: Int, among sessions: [Session]) -> Decimal {
        var best = (sum: rep.monthly ?? 0, at: Int64(0))
        func see(_ e: MonthSum) { if e.month <= k && e.at > best.at { best = (e.sum, e.at) } }
        for x in sessions where x.repeatInfo?.group == rep.group { x.repeatInfo!.sums.forEach(see) }
        rep.sums.forEach(see)
        return best.sum
    }

    /// Доля месяца (веб `repShare`): сумма группы поровну между живыми
    /// помесячными карточками этого месяца. Удалённая выпадает — доли растут.
    /// Карточка со своим гонораром в счёт идёт: её число — доплата или скидка.
    public static func monthShare(of s: Session, among sessions: [Session]) -> Decimal {
        guard let rep = s.repeatInfo, let start = rep.start else { return 0 }
        let k = monthIndex(start: start, day: s.day)
        let sum = monthSum(rep, month: k, among: sessions)
        if sum == 0 { return 0 }
        var n = 1
        for x in sessions where x.id != s.id && x.repeatInfo?.group == rep.group && x.pay == .monthly
            && monthIndex(start: start, day: x.day) == k {
            n += 1
        }
        return sum / Decimal(n)
    }
}
