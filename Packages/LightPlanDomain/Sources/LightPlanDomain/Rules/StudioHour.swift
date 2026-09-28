import Foundation

/// Окно аренды студии в карточке (веб `rentWindow`): часы той точки дня, где
/// стоит студия. Минуты — шкала съёмки, от полуночи её первого дня.
public struct RentWindow: Hashable, Sendable {
    public let studio: Studio
    /// Зал точки, давшей окно (у двух залов одной студии часы разные).
    public let hallId: String?
    public let from: Int
    public let to: Int

    /// Точек со студией за день бывает две; отвечает та, что идёт, иначе
    /// ближайшая впереди, иначе последняя. `now` — минута шкалы съёмки
    /// (`nil` — не сегодня): тогда первая. Запись старого вида держит студию
    /// своими полями (`studioId`, `rentFrom`, `rentTo`, `hallId`).
    public static func of(_ s: Session, studios: [Studio], now: Int?) -> RentWindow? {
        let stops = s.route.compactMap { r -> (RoutePoint, Studio)? in
            guard let st = Stops.studio(r.studioId, in: studios), r.start != nil, r.end != nil else { return nil }
            return (r, st)
        }
        .enumerated().sorted { ($0.element.0.start!, $0.offset) < ($1.element.0.start!, $1.offset) }
        .map(\.element)
        if !stops.isEmpty {
            var pick = stops[0]
            if let now {
                pick = stops.first { now >= $0.0.start! && now <= $0.0.end! }
                    ?? stops.first { $0.0.start! > now }
                    ?? stops[stops.count - 1]
            }
            return RentWindow(studio: pick.1, hallId: pick.0.hallId, from: pick.0.start!, to: pick.0.end!)
        }
        guard let st = Stops.studio(s.studioId, in: studios) else { return nil }
        return RentWindow(studio: st, hallId: s.hallId, from: s.rentFrom ?? s.start, to: s.rentTo ?? s.endMinute)
    }

    /// Дедлайн выхода (веб `studioDeadline`): час студии — 55 минут, выходить
    /// на пять минут раньше конца оплаченного.
    public var deadline: Int { to - (60 - (studio.hourMinutes ?? StudioHour.hourMinutes)) }

    /// Имя зала точки, если он назван.
    public var hallName: String? {
        guard let hallId, let h = studio.halls.first(where: { $0.id == hallId }), !h.name.isEmpty else { return nil }
        return h.name
    }
}

/// Студийный час — кольцо обратного отсчёта до выхода из зала (веб
/// `paintStudio`, `studioClock`).
public enum StudioHour {
    /// Минут в рабочем часе студии, если своё число не записано (`STUDIO_HOUR_MIN`).
    public static let hourMinutes = 55
    /// С этой минуты до дедлайна счёт идёт по секундам (`STUDIO_FINE`).
    public static let fine = 15
    /// Последние минуты: обод сбрасывается и сходит по секундам (`STUDIO_RESET`).
    public static let reset = 5

    /// Ступень тревоги: подпись и цвет.
    public enum Stage: Sendable { case calm, wrap, leave }

    /// Секунды до дедлайна. `minute` — минута шкалы съёмки по часам места,
    /// `second` — секунды этой минуты. Веб вычитает секунды **суток** и после
    /// полуночи прибавляет сутки («25:25» вместо «1:25») — ошибку не переносим.
    public static func secondsLeft(deadline: Int, minute: Int, second: Int) -> Int {
        (deadline - minute) * 60 - second
    }

    /// `Ч:ММ`, пока до дедлайна не меньше четверти часа, дальше `ММ:СС`.
    public static func clock(_ sec: Int) -> String {
        let a = abs(sec), m = a / 60
        if a >= fine * 60 { return "\(m / 60):" + two(m % 60) }
        return two(m) + ":" + two(a % 60)
    }

    public static func stage(_ sec: Int) -> Stage {
        let mins = Int((Double(sec) / 60).rounded(.up))
        return mins <= reset ? .leave : mins <= fine ? .wrap : .calm
    }

    /// Доля обода: две шкалы — до последних пяти минут путь от начала аренды,
    /// последние пять минут обод снова полный и сходит по секундам.
    public static func fraction(_ sec: Int, window w: RentWindow) -> Double {
        let last = reset * 60
        if sec <= last { return Double(sec) / Double(last) }
        let span = max(1, (w.deadline - w.from) * 60 - last)
        return min(1, max(0, Double(sec - last) / Double(span)))
    }

    private static func two(_ n: Int) -> String { (n < 10 ? "0" : "") + String(n) }
}
