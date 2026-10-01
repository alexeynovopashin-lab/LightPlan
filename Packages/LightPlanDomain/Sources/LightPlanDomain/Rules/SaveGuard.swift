import Foundation
import LightPlanCore

/// Когда форму съёмки сохранить нельзя (слова Алексея 01.10). Не наложения «с предупреждением», а запреты:
/// кнопка «Сохранить» не нажимается, пока причина названа на экране.
public enum SaveGuard {

    public enum Verdict: Equatable, Sendable {
        case ok
        /// «Назначить съёмку» из встречи: дату называет фотограф, за него её не ставят.
        case noDate
        /// Время съёмки пересекает занятое: «занято — это занято» (слово Алексея 01.10).
        case busy(BusyHit)
    }

    /// Чем занято: номер занятости в списке, день (у серии — день копии), часы по часам места съёмки (у «весь день» их нет).
    public struct BusyHit: Equatable, Sendable {
        public var day: CivilDate
        public var blockIndex: Int
        public var allDay: Bool
        public var from: Int?
        public var to: Int?
    }

    /// Какие занятости держат жёстко: «Занято» и «Выходной/отпуск». Дорога и перелёт — свои для съёмки (форма сама
    /// ставит «Время в пути» с утра, а съёмка встаёт после него), ими съёмку не запрещаем: остаются предупреждением.
    public static let hardKinds: Set<BlockKind> = [.off, .busy]

    /// Жёсткие занятости, которые пересекает съёмка в этот день с этими минутами; первая — самая тяжёлая.
    public static func busyHits(day: CivilDate, start: Int, end: Int, point: GeoPoint?, blocks: [Block],
                                context: ClashContext) -> [BusyHit] {
        let c = ClashCandidate(day: day, start: start, end: end, placeKey: "", skipIndex: nil, wishes: [], point: point,
                               trip: false, tripOff: false)
        return Overlaps.clashes(for: c, sessions: [], blocks: blocks, context: context).compactMap { cl in
            guard case .block(let i) = cl.subject, hardKinds.contains(blocks[i].kind) else { return nil }
            switch cl.kind {
            case .dayBusy: return BusyHit(day: day, blockIndex: i, allDay: true, from: nil, to: nil)
            case .timeBusy: return BusyHit(day: day, blockIndex: i, allDay: false, from: cl.from, to: cl.to)
            default: return nil
            }
        }
    }

    /// Можно ли сохранить форму. Съёмку нельзя ни назвать без даты, ни поставить на занятое время — ни саму, ни копию
    /// повтора. Встреча (разговор) занятого не боится. Правка записи, чьё время не тронуто, не запрещается из-за
    /// занятости, появившейся позже: нельзя дописать заметку к съёмке, которая и так стояла.
    public static func verdict(_ f: EventForm, blocks: [Block], context: ClashContext, point: GeoPoint?) -> Verdict {
        if f.dayUnset { return .noDate }
        guard f.mode == .shoot else { return .ok }
        let end = f.start + f.duration
        let touched: Bool
        if let b = f.base, f.growFrom == nil {
            // Место — тоже время: другой пояс сдвигает часы относительно занятого (ревью GPT к c9e7eea).
            touched = b.day != f.day || b.start != f.start || b.endMinute != end
                || GeoPoint(b.latitude, b.longitude) != point
        } else {
            touched = true
        }
        var days: [CivilDate] = touched ? [f.day] : []
        if f.repeatOn { days += f.repeatDates.dropFirst() }
        for d in days {
            if let hit = busyHits(day: d, start: f.start, end: end, point: point, blocks: blocks, context: context).first {
                return .busy(hit)
            }
        }
        return .ok
    }
}
