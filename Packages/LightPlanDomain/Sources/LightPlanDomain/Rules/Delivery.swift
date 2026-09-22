import Foundation
import LightPlanCore

/// Как считать срок сдачи (веб `delivery.mode`): по жанру, один на всё или без срока.
public enum DeliveryMode: String, Sendable {
    case genre, single, none
}

/// Настройка сдачи (веб `delivery`: `mode`, `days`).
public struct DeliverySetting: Sendable, Hashable {
    public var mode: DeliveryMode
    /// Срок при «один на всё».
    public var days: Int

    public init(mode: DeliveryMode, days: Int) {
        self.mode = mode
        self.days = days
    }

    /// Умолчание веба: по жанру, «один на всё» — неделя.
    public static let standard = DeliverySetting(mode: .genre, days: 7)
}

/// Своё у жанра, правленое в шестерёнках (веб `genrePrefs[жанр]`). Пусто —
/// «как заведено»: общая ставка, доли нет, срок из жанровой таблицы.
public struct GenrePrefs: Sendable, Hashable {
    /// `pay` — способ оплаты, выбранный последним.
    public var pay: PayKind?
    /// `dur` — своя длительность; `.some(nil)` — «по свету», `nil` — своей нет.
    public var duration: Int??
    /// `delv` — срок, который форма ставит новой съёмке.
    public var deadline: DeadlineChoice?
    /// `rate` — своя ставка часа.
    public var rate: Decimal?
    /// `pre` — доля предоплаты.
    public var prepayShare: Double?
    /// `delvDays` — свой срок сдачи в днях.
    public var deliveryDays: Int?

    public init(pay: PayKind? = nil, duration: Int?? = nil, deadline: DeadlineChoice? = nil,
                rate: Decimal? = nil, prepayShare: Double? = nil, deliveryDays: Int? = nil) {
        self.pay = pay
        self.duration = duration
        self.deadline = deadline
        self.rate = rate
        self.prepayShare = prepayShare
        self.deliveryDays = deliveryDays
    }
}

/// Где съёмка по сдаче материала (веб `deliveryState`). Цвет шкалы срочности —
/// дело экрана, здесь — ступень и числа.
public enum DeliveryStatus: Hashable, Sendable {
    /// Встреча или чужое событие: сдавать нечего.
    case notWork
    /// Материал сдан.
    case done
    /// Съёмка ещё впереди.
    case ahead
    /// Прошла, а срока нет.
    case noTerm
    /// Срок идёт: доля прошедшего срока и дней до конца.
    case due(progress: Double, daysLeft: Int)
    /// Срок прошёл: на сколько дней.
    case overdue(days: Int)

    /// Тяжесть для дня календаря (веб `rank`): день показывает самую тяжёлую.
    public var rank: Int {
        switch self {
        case .notWork, .done: 0
        case .ahead, .noTerm: 1
        case .due: 2
        case .overdue: 3
        }
    }
}

/// Сроки сдачи материала.
public enum Delivery {

    /// Варианты срока в форме, дни (веб `DELV_DAYS`).
    public static let dayChoices = [3, 7, 14, 30, 90]

    /// Срок жанра с поправкой фотографа (веб `genreDeadline`).
    public static func genreDays(_ genre: Genre?, prefs: [Genre: GenrePrefs]) -> Int {
        if let genre, let own = prefs[genre]?.deliveryDays { return own }
        return GenreProfile(genre).deliveryDays
    }

    /// Сколько дней на сдачу, `nil` — без срока (веб `resolveDeadlineDays`).
    /// Свой срок записи сильнее всего; у стрита и пейзажа сдачи нет вовсе, и
    /// срока тоже — даже если настройка говорит «по жанру».
    public static func days(for s: Session, setting: DeliverySetting, prefs: [Genre: GenrePrefs]) -> Int? {
        switch s.deadline {
        case .none: return nil
        case .days(let d): return d
        case .auto: break
        }
        if let g = s.genre, !g.spec.delivery { return nil }
        switch setting.mode {
        case .none: return nil
        case .single: return setting.days
        case .genre: return genreDays(s.genre, prefs: prefs)
        }
    }

    /// День, к которому сдать (веб `deadlineDate`).
    public static func deadline(for s: Session, setting: DeliverySetting, prefs: [Genre: GenrePrefs]) -> CivilDate? {
        days(for: s, setting: setting, prefs: prefs).map { s.day.adding(days: $0) }
    }

    /// За сколько дней сдан материал (веб `deliveryDays`): от дня съёмки до дня
    /// передачи, днями календаря в поясе телефона. Сданный до дня съёмки — ноль.
    public static func daysTaken(_ s: Session, zone: TimeZone) -> Int? {
        guard s.delivered, let at = s.deliveredAt else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.year, .month, .day], from: at)
        let day = CivilDate(year: c.year!, month: c.month!, day: c.day!)
        return max(0, day.days(since: s.day))
    }

    /// Ступень сдачи на момент `now` (веб `deliveryState`). Сутки считаются от
    /// полуночи дня съёмки в поясе телефона, как в вебе.
    public static func status(_ s: Session, now: Moment, zone: TimeZone,
                              setting: DeliverySetting, prefs: [Genre: GenrePrefs]) -> DeliveryStatus {
        guard s.kind.isWork else { return .notWork }
        if s.delivered { return .done }
        let shot = midnight(s.day, zone)
        let nowMs = Double(now.milliseconds)
        if shot > nowMs { return .ahead }
        guard let due = deadline(for: s, setting: setting, prefs: prefs) else { return .noTerm }
        let dd = midnight(due, zone)
        let p = (nowMs - shot) / (dd - shot)
        let left = Int(((dd - nowMs) / 86_400_000).rounded(.up))
        return p >= 1 ? .overdue(days: abs(left)) : .due(progress: p, daysLeft: left)
    }

    /// Полночь дня в поясе, миллисекунды (веб `new Date(y, m, d).getTime()`).
    static func midnight(_ day: CivilDate, _ zone: TimeZone) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))!
        return (date.timeIntervalSince1970 * 1000).rounded()
    }
}
