import Foundation
import LightPlanCore

/// Фаза события: до, во время, после. Одна ось карточки: вычисляется по
/// часам и переключается сама (`docs/12`, «Состояние: одна ось, а не две»).
public enum EventPhase: String, Sendable {
    case before, during, after

    /// Фаза записи по часам **места съёмки** (веб `eventPhase`): в поездке они
    /// расходятся с часами телефона, и карточка иначе объявляла бы съёмку
    /// прошедшей, пока она идёт.
    ///
    /// Границы — записанные рамки съёмки, а не маршрут: от рамок считается
    /// стоимость работы (решено 29 августа 2026). Затянувшуюся съёмку
    /// закрывает человек кнопкой (`doneAt`), а при ручном завершении
    /// (`manualEnd`) фаза держится, пока не нажмут.
    ///
    /// - Parameter now: настенные часы места — день и минута суток.
    public static func of(_ s: Session, now: WallTime, manualEnd: Bool) -> EventPhase {
        guard let m = s.minute(at: now) else {
            return now.day.days(since: s.day) < 0 ? .before : .after
        }
        if m < s.start { return .before }
        if let done = s.doneAt { return m < done ? .during : .after }
        if manualEnd { return .during }
        return m <= s.endMinute ? .during : .after
    }
}

extension Session {
    /// «Сейчас» в минутах шкалы съёмки (веб `shootMin`): 00:31 второго дня — это
    /// 1471, а не 31. Пока идут календарные дни съёмки — число, вне их — `nil`.
    ///
    /// - Parameter now: настенные часы места — день и минута суток.
    public func minute(at now: WallTime) -> Int? {
        let d = now.day.days(since: day)
        if d < 0 || d > Session.floorDiv(endMinute, 1440) { return nil }
        return d * 1440 + now.minutes
    }

    /// Какая часть этих суток занята записью (веб `partOfDay`): свадьба с 19:10
    /// до 03:10 принадлежит обоим своим дням. Смотрит на двое суток назад —
    /// столько длится потолок длительности.
    public func part(on date: CivilDate) -> DayPart? {
        for k in 0...2 where day == date.adding(days: -k) {
            let a = start - k * 1440, b = endMinute - k * 1440
            if b <= 0 || a >= 1440 { return nil }
            return DayPart(start: max(0, a), end: min(1440, b), fromYesterday: a < 0, intoTomorrow: b > 1440)
        }
        return nil
    }

    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }
}

/// Часть суток, занятая записью.
public struct DayPart: Hashable, Sendable {
    /// Начало в этих сутках, минуты.
    public let start: Int
    /// Конец в этих сутках, не дальше полуночи.
    public let end: Int
    /// Продолжение из вчера (веб `tail`): блоку нельзя показывать «19:10 – 03:10»,
    /// в этих сутках он начинается в полночь.
    public let fromYesterday: Bool
    /// Уходит в завтра (веб `cut`).
    public let intoTomorrow: Bool
}

/// «Событие — матрёшка» (DECISIONS, 18 сентября 2026; `docs/16`): съёмка —
/// оболочка, точки маршрута со временем и часы студии — подсущности, и стоят
/// они на своём времени. Оболочка их не двигает — ни переносом, ни растяжкой.
public enum Nest {

    /// Промежуток, который оболочка обязана накрывать (веб `nestSpan`): от начала
    /// первой подсущности до конца последней. Держат его только якорные точки —
    /// с часом; точка без часа не привязана к времени. `nil` — съёмка пустая и
    /// двигается целиком, как встреча.
    public static func span(route: [RoutePoint], studioId: String?, rentFrom: Int?, rentTo: Int?) -> NestSpan? {
        var lo: Int?, hi: Int?
        func take(_ a: Int?, _ b: Int?) {
            guard let a else { return }
            let b = (b == nil || b! < a) ? a : b!
            if lo == nil || a < lo! { lo = a }
            if hi == nil || b > hi! { hi = b }
        }
        for r in route { take(r.start, r.end) }
        /// Запись старого вида держит часы студии своими полями, без ячейки.
        if !(studioId ?? "").isEmpty, rentFrom != nil { take(rentFrom, rentTo) }
        guard let lo, let hi else { return nil }
        return NestSpan(start: lo, end: hi)
    }

    /// Промежуток подсущностей записи.
    public static func span(of s: Session) -> NestSpan? {
        span(route: s.route, studioId: s.studioId, rentFrom: s.rentFrom, rentTo: s.rentTo)
    }
}

/// Промежуток подсущностей оболочки, минуты от полуночи первого дня.
public struct NestSpan: Hashable, Sendable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    /// Накрывает ли оболочка содержимое. Шире — можно, уже — нельзя: форма
    /// такую съёмку не сохраняет и показывает ошибку (веб `formNestBad`).
    public func fits(start s: Int, end e: Int) -> Bool {
        !(start < s || end > e)
    }

    /// Ручка начала встаёт ровно на начало первой точки, не заходя внутрь
    /// содержимого, даже вне шага ленты.
    public func clampStart(_ proposed: Int) -> Int { min(proposed, start) }

    /// Ручка конца — на конец последней.
    public func clampEnd(_ proposed: Int) -> Int { max(proposed, end) }
}

extension Session {
    /// Переносить целиком можно только пустую оболочку.
    public var movesWhole: Bool { Nest.span(of: self) == nil }
}
