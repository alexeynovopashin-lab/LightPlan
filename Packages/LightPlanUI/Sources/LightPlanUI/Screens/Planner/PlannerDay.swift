import Foundation
import LightPlanCore
import LightPlanDomain

/// Что стоит в сутках ленты дня (веб `items` в `renderDayPanel`): съёмки,
/// встречи, события календаря и занятость — одной хронологической лентой.
public struct DayItem: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case shoot, meet, event, busy }

    public let kind: Kind
    /// Минуты этих суток, 0…1440.
    public let start: Int
    public let end: Int
    /// Продолжение из вчера / уходит в завтра (веб `tail`/`cut`).
    public let fromYesterday: Bool
    public let intoTomorrow: Bool
    public let session: Session?
    public let block: Block?

    public var id: String { (session?.id ?? block?.id ?? "") + "@" + kind.rawValue }
    /// Занятость на весь день — фон, а не сосед: в колонки не встаёт.
    public var isAllDayBusy: Bool { kind == .busy && block?.allDay == true }

    /// Сутки `day`: записи, у которых есть часть в этих сутках (съёмка через
    /// полночь даёт кусок каждому дню), и занятость дня. Порядок — по началу,
    /// потом по концу; равные — в порядке записей, как стабильная сортировка
    /// веба.
    public static func items(on day: CivilDate, sessions: [Session], blocks: [Block],
                             eventsLayer: Bool) -> [DayItem] {
        var out: [DayItem] = []
        for s in sessions {
            guard let p = s.part(on: day), s.isShown(eventsLayer: eventsLayer) else { continue }
            let k: Kind = s.kind == .meet ? .meet : s.kind == .event ? .event : .shoot
            out.append(DayItem(kind: k, start: p.start, end: p.end, fromYesterday: p.fromYesterday,
                               intoTomorrow: p.intoTomorrow, session: s, block: nil))
        }
        for b in blocks where b.covers(day) {
            // У занятости по часам начало и длительность есть всегда; `?? 0` —
            // только от битой записи (веб дал бы NaN и не нарисовал её).
            let a = b.allDay ? 0 : (b.start ?? 0)
            let e = b.allDay ? 1440 : a + (b.duration ?? 0)
            out.append(DayItem(kind: .busy, start: a, end: e, fromYesterday: false, intoTomorrow: false,
                               session: nil, block: b))
        }
        return out.enumerated()
            .sorted { ($0.element.start, $0.element.end, $0.offset) < ($1.element.start, $1.element.end, $1.offset) }
            .map(\.element)
    }
}

/// Колонки ленты дня (веб, `LANE_GAP` и раскладка в `renderDayPanel`).
public enum DayLanes {
    /// Высота часа в сетке, pt (веб `HOUR_H`).
    public static let hourHeight: Double = 38
    /// Меньше блок не бывает: две короткие съёмки с разницей в десять минут
    /// иначе легли бы друг на друга.
    public static let minHeight: Double = 34
    /// Зазор между колонками.
    public static let gap: Double = 4

    public struct Slot: Hashable, Sendable {
        public let top: Double
        public let bottom: Double
        /// Колонка блока и сколько колонок у его сцепки.
        public let column: Int
        public let columns: Int
    }

    public static func top(_ minute: Int) -> Double { Double(minute) / 60 * hourHeight }

    /// Места блоков по порядку `items` (уже отсортированы). Весь день занятости
    /// получает `nil`: он фон и за ширину не спорит. Сцепка — цепочка блоков,
    /// связанных перекрытием хотя бы через соседа; блок, начавшийся после конца
    /// последнего в колонке, занимает эту колонку, а не открывает новую.
    public static func layout(_ items: [DayItem]) -> [Slot?] {
        var out = [Slot?](repeating: nil, count: items.count)
        let lay = items.indices.filter { !items[$0].isAllDayBusy }
        let top = lay.map { self.top(items[$0].start) }
        let bot = lay.indices.map { top[$0] + max(minHeight, self.top(items[lay[$0]].end) - top[$0]) }
        var i = 0
        while i < lay.count {
            var end = bot[i], j = i + 1
            while j < lay.count, top[j] < end { end = max(end, bot[j]); j += 1 }
            var ends: [Double] = [], col = [Int](repeating: 0, count: j - i)
            for k in i..<j {
                var c = 0
                while c < ends.count, ends[c] > top[k] { c += 1 }
                if c == ends.count { ends.append(0) }
                ends[c] = bot[k]
                col[k - i] = c
            }
            for k in i..<j {
                out[lay[k]] = Slot(top: top[k], bottom: bot[k], column: col[k - i], columns: ends.count)
            }
            i = j
        }
        return out
    }
}

/// Срочность сдачи — цвет (веб `urgencyRGB`, `deliveryState`, `dayMark`).
public enum Urgency {
    public typealias RGB = (r: Double, g: Double, b: Double)

    /// Серый сданного и не рабочего (веб `GREY`).
    public static let grey: RGB = (107, 101, 91)

    /// Непрерывная шкала по доле прошедшего срока: 0 — чернила, 0,5 — жёлтый,
    /// 0,8 — латунь, 1 — терракота.
    public static func rgb(_ p: Double, dark: Bool) -> RGB {
        let stops: [(Double, RGB)] = dark
            ? [(0, (239, 234, 224)), (0.5, (232, 208, 122)), (0.8, (226, 164, 76)), (1, (201, 102, 61))]
            : [(0, (23, 21, 15)), (0.5, (122, 90, 34)), (0.8, (166, 86, 45)), (1, (138, 63, 34))]
        let x = min(1, max(0, p))
        for k in 1..<stops.count where x <= stops[k].0 {
            let (a, ca) = stops[k - 1], (b, cb) = stops[k]
            // Веб `lerp` округляет каналы до целых.
            let t = (x - a) / (b - a)
            func mix(_ u: Double, _ v: Double) -> Double { (u + (v - u) * t).rounded() }
            return (mix(ca.r, cb.r), mix(ca.g, cb.g), mix(ca.b, cb.b))
        }
        return stops.last!.1
    }

    /// Спокойный цвет съёмки, которая ещё впереди (веб `urgencyCalm`) — начало шкалы.
    public static func calm(dark: Bool) -> RGB { dark ? (239, 234, 224) : (23, 21, 15) }

    /// Цвет ступени сдачи (веб `deliveryState().c`).
    public static func color(_ st: DeliveryStatus, dark: Bool) -> RGB {
        switch st {
        case .notWork, .done, .noTerm: grey
        case .ahead: calm(dark: dark)
        case .due(let p, _): rgb(p, dark: dark)
        case .overdue: dark ? (201, 102, 61) : (138, 63, 34)
        }
    }

    /// Самая тяжёлая ступень сдачи среди рабочих записей дня (веб `dayMark`).
    public static func dayMark(_ day: CivilDate, sessions: [Session],
                               status: (Session) -> DeliveryStatus) -> DeliveryStatus? {
        var best: DeliveryStatus?
        for s in sessions where s.kind.isWork && s.part(on: day) != nil {
            let st = status(s)
            if best == nil || st.rank > best!.rank { best = st }
        }
        return best
    }
}
