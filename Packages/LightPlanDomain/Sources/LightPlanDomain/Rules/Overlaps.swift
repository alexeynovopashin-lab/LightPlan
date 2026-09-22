import Foundation
import LightPlanCore

/// Пояс места по координатам (веб `tzAt(lat, lon, day)`): настоящая зона, если
/// известна, иначе оценка по долготе. В нативе отвечает кэш зон слоя Data
/// (итерация 13); домен о сети и кэше не знает.
public protocol ZoneResolving {
    /// Смещение от UTC в часах на этот день.
    func utcOffsetHours(latitude: Double, longitude: Double, on day: CivilDate) -> Double
}

extension Moment {
    /// Момент настенного времени записи (веб `momentOf`): по поясу её места, а
    /// у записи без точки — по поясу приложения, как всё приложение вело себя
    /// до появления зон.
    public static func of(day: CivilDate, minutes: Int, at point: GeoPoint?,
                          zones: any ZoneResolving, appOffsetHours: Double) -> Moment {
        let off: Double
        if let point, point.latitude.isFinite, point.longitude.isFinite {
            off = zones.utcOffsetHours(latitude: point.latitude, longitude: point.longitude, on: day)
        } else {
            off = appOffsetHours
        }
        return WallTime(day: day, minutes: minutes).moment(utcOffsetHours: off)
    }
}

/// Ответ о дороге между двумя точками (веб `travelMinutes`).
public enum TravelTime: Hashable, Sendable {
    /// Ответа ещё нет — спросили, ждём.
    case pending
    /// Сеть не ответила — в этом сеансе не спрашиваем снова.
    case unavailable
    /// Минуты за рулём.
    case minutes(Int)
}

/// Род наложения, по убыванию тяжести (`docs/12`, «Наложения»).
public enum ClashKind: String, CaseIterable, Sendable {
    /// День занят целиком: отпуск, выходной.
    case dayBusy
    /// Занятость по часам пересекается со съёмкой.
    case timeBusy
    /// Пересечение времени: быть в двух местах разом нельзя.
    case overlap
    /// Выезд забирает день целиком, а соседняя съёмка в другом месте.
    case tripDay
    /// Дорога длиннее рабочего дня: не «впритык», а «нельзя».
    case tripFar
    /// Дорога известна, и запаса не хватает.
    case tripShort
    /// Дорога неизвестна, запас меньше порога фотографа.
    case tripTight
    /// Две съёмки одного дня заказали закат, а золотой час один.
    case bothSunset

    /// Вес: 3 — нельзя, 2 — впритык, 1 — спор за свет.
    public var weight: Int {
        switch self {
        case .dayBusy, .timeBusy, .overlap, .tripDay, .tripFar: 3
        case .tripShort, .tripTight: 2
        case .bothSunset: 1
        }
    }
}

/// Наложение: что и с кем. Слова собирает экран (`clash.*` в словаре).
public struct Clash: Hashable, Sendable {
    public enum Subject: Hashable, Sendable {
        /// Номер в списке занятости.
        case block(Int)
        /// Номер в списке записей.
        case session(Int)
    }

    public let kind: ClashKind
    public let subject: Subject
    /// Часы соседа на экране: у занятости — в часах места съёмки, у записи — её рамки.
    public let from: Int?
    public let to: Int?
    /// Минуты дороги (дальняя дорога и нехватка запаса).
    public let travel: Int?
    /// Запас между съёмками, минуты.
    public let gap: Int?

    public var weight: Int { kind.weight }
}

/// Съёмка, которую проверяют: та, что в форме, или сохранённая.
public struct ClashCandidate: Sendable {
    public var day: CivilDate
    public var start: Int
    public var end: Int
    /// Ключ места (`Session.placeKey`).
    public var placeKey: String
    /// Номер самой себя в списке, чтобы не спорить с собой.
    public var skipIndex: Int?
    public var wishes: [Wish]
    public var point: GeoPoint?
    /// С выездом: день уходит на дорогу целиком.
    public var trip: Bool
    /// Выезд снят руками — ответ «успею».
    public var tripOff: Bool

    public init(day: CivilDate, start: Int, end: Int, placeKey: String, skipIndex: Int?,
                wishes: [Wish], point: GeoPoint?, trip: Bool, tripOff: Bool) {
        self.day = day
        self.start = start
        self.end = end
        self.placeKey = placeKey
        self.skipIndex = skipIndex
        self.wishes = wishes
        self.point = point
        self.trip = trip
        self.tripOff = tripOff
    }

    /// Сохранённая запись как кандидат (веб `clashesOf`).
    public init(session s: Session, index: Int) {
        self.init(day: s.day, start: s.start, end: s.endMinute, placeKey: s.placeKey, skipIndex: index,
                  wishes: s.wishes, point: GeoPoint(s.latitude, s.longitude),
                  trip: s.trip, tripOff: s.tripManual && !s.trip)
    }
}

/// Всё, что проверка берёт снаружи: пояса, дорогу, настройки.
public struct ClashContext {
    public var zones: any ZoneResolving
    /// Пояс приложения (веб `TZ`): у записи без точки.
    public var appOffsetHours: Double
    /// Дорога между двумя точками.
    public var travel: (GeoPoint, GeoPoint) -> TravelTime
    /// Порог на дорогу, когда её не знаем (веб `travelMin`): в городе хватает
    /// двадцати минут, в пригороде и полутора часов бывает мало.
    public var travelThreshold: Int
    /// Слой событий из чужого календаря включён.
    public var eventsLayer: Bool

    public init(zones: any ZoneResolving, appOffsetHours: Double, travel: @escaping (GeoPoint, GeoPoint) -> TravelTime,
                travelThreshold: Int, eventsLayer: Bool) {
        self.zones = zones
        self.appOffsetHours = appOffsetHours
        self.travel = travel
        self.travelThreshold = travelThreshold
        self.eventsLayer = eventsLayer
    }
}

/// Наложения в дне (веб `clashesFor`): не ошибка ввода, а факт, о котором
/// фотограф должен узнать раньше, чем окажется в двух местах сразу.
/// Предупреждаем, но никогда не запрещаем сохранить.
public enum Overlaps {

    /// Дальняя дорога, которую фотограф взял на себя (веб `FAR_MIN`): со снятым
    /// руками выездом её больше не считают.
    public static let farTrip = 180
    /// Дорога длиннее рабочего дня (веб `FLY_MIN`): туда летят, а не едут.
    public static let flight = 480

    /// Наложения кандидата, тяжёлые первыми. Сравниваются моменты, а не
    /// настенные минуты: 10:00 в Томске и 12:00 в Москве — шесть часов зазора, а
    /// не два.
    public static func clashes(for c: ClashCandidate, sessions: [Session], blocks: [Block],
                               context ctx: ClashContext) -> [Clash] {
        var out: [Clash] = []
        let myFrom = Moment.of(day: c.day, minutes: c.start, at: c.point, zones: ctx.zones, appOffsetHours: ctx.appOffsetHours)
        let myTo = Moment.of(day: c.day, minutes: c.end, at: c.point, zones: ctx.zones, appOffsetHours: ctx.appOffsetHours)

        /* Занятость спорит наравне с другой съёмкой. Соседние сутки считаются
           наравне со своими: перелёт в 23:00 садится назавтра. «Весь день»
           остаётся у своего дня — иначе вечерний заказ спорил бы с завтрашним
           выходным (DECISIONS, «Хвосты, заход А2»). */
        for k in -1...1 {
            let d = c.day.adding(days: k)
            for (bi, b) in blocks.enumerated() where b.covers(d) && (k == 0 || !b.allDay) {
                if b.allDay {
                    out.append(Clash(kind: .dayBusy, subject: .block(bi), from: nil, to: nil, travel: nil, gap: nil))
                    continue
                }
                let dur = b.duration ?? 0
                var bMin = (b.start ?? 0) + k * 1440, bEnd = bMin + dur
                let busy: Bool
                if let tz = b.zoneFrom {
                    /* Дорога из формы помнит пояс вылета: её минуты — часы билета,
                       длительность — настоящее время в пути. На экране — часы
                       места съёмки. */
                    let bFrom = WallTime(day: d, minutes: b.start ?? 0).moment(utcOffsetHours: tz)
                    busy = myFrom < bFrom.adding(minutes: dur) && bFrom < myTo
                    bMin = c.start + bFrom.minutes(since: myFrom)
                    bEnd = bMin + dur
                } else {
                    /* Занятость, записанная руками, поясов не знает: её часы —
                       часы места, где снимают в тот день. */
                    busy = c.start < bEnd && bMin < c.end
                }
                if busy {
                    out.append(Clash(kind: .timeBusy, subject: .block(bi), from: bMin, to: bEnd, travel: nil, gap: nil))
                }
            }
        }

        for (i, s) in sessions.enumerated() {
            if i == c.skipIndex || s.day != c.day || !s.isShown(eventsLayer: ctx.eventsLayer) { continue }
            let sEnd = s.endMinute
            let point = GeoPoint(s.latitude, s.longitude)
            let oFrom = Moment.of(day: s.day, minutes: s.start, at: point, zones: ctx.zones, appOffsetHours: ctx.appOffsetHours)
            let oTo = Moment.of(day: s.day, minutes: sEnd, at: point, zones: ctx.zones, appOffsetHours: ctx.appOffsetHours)
            func clash(_ kind: ClashKind, travel: Int? = nil, gap: Int? = nil) -> Clash {
                Clash(kind: kind, subject: .session(i), from: s.start, to: sEnd, travel: travel, gap: gap)
            }
            if myFrom < oTo && oFrom < myTo {
                out.append(clash(.overlap))
                continue
            }
            let gap = myFrom >= oTo ? myFrom.minutes(since: oTo) : oFrom.minutes(since: myTo)
            let other = s.placeKey
            let differ = !other.isEmpty && !c.placeKey.isEmpty && other != c.placeKey
            /* Выезд отвечает сам, до всякой дороги, и весом наравне с пересечением:
               туда летят, а не едут. */
            if (c.trip || s.trip) && differ {
                out.append(clash(.tripDay))
                continue
            }
            if differ {
                var known: Int?
                if let a = c.point, let b = point, case .minutes(let m) = ctx.travel(a, b) { known = m }
                /* Кто-то из двоих снял отметку выезда руками — про дальнюю дорогу
                   уже сказано, второй раз её не считаем. */
                if c.tripOff || (s.tripManual && !s.trip), let m = known, m > farTrip { continue }
                if let m = known, m > flight {
                    out.append(clash(.tripFar, travel: m))
                    continue
                }
                if let m = known, gap < m {
                    out.append(clash(.tripShort, travel: m, gap: gap))
                    continue
                }
                if known == nil && gap < ctx.travelThreshold {
                    out.append(clash(.tripTight, gap: gap))
                    continue
                }
            }
            /* Спор за свет — единственное предупреждение из световой модели. */
            if c.wishes.contains(.sunset) && s.wishes.contains(.sunset) {
                out.append(clash(.bothSunset))
            }
        }
        return out.enumerated()
            .sorted { $0.element.weight != $1.element.weight ? $0.element.weight > $1.element.weight : $0.offset < $1.offset }
            .map(\.element)
    }

    /// Наложения записи из списка (веб `clashesOf`): для карточки и списка дня.
    public static func clashes(ofSessionAt index: Int, sessions: [Session], blocks: [Block],
                               context: ClashContext) -> [Clash] {
        guard sessions.indices.contains(index) else { return [] }
        return clashes(for: ClashCandidate(session: sessions[index], index: index),
                       sessions: sessions, blocks: blocks, context: context)
    }
}
