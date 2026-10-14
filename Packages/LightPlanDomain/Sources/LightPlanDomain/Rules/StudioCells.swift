import Foundation

/// Все ячейки дня со студией (шаг 30а). Веб `rentWindow` отвечает одним
/// окном — тем, что идёт сейчас; расписанию уведомлений нужны все разом: у
/// каждой ячейки свой дедлайн выхода, и сигнал ставится заранее на каждую.
extension RentWindow {

    /// Ячейка дня: окно аренды и её номер в `route` записи (`nil` — запись
    /// старого вида, студия лежит полями самой записи).
    public struct Cell: Sendable, Hashable {
        public let index: Int?
        public let window: RentWindow
    }

    /// Те же отборы, что у `RentWindow.of`: ячейка со студией, найденной в
    /// каталоге, и с часом начала и конца. По часам начала; равные — в порядке
    /// списка. Нет ни одной — окно записи старого вида, если оно есть.
    public static func cells(of s: Session, studios: [Studio]) -> [Cell] {
        let found = s.route.enumerated().compactMap { i, r -> (Int, RoutePoint, Studio)? in
            guard let st = Stops.studio(r.studioId, in: studios), r.start != nil, r.end != nil else { return nil }
            return (i, r, st)
        }
        .sorted { ($0.1.start!, $0.0) < ($1.1.start!, $1.0) }
        if !found.isEmpty {
            return found.map {
                Cell(index: $0.0, window: RentWindow(studio: $0.2, hallId: $0.1.hallId, from: $0.1.start!, to: $0.1.end!))
            }
        }
        guard let legacy = RentWindow.of(s, studios: studios, now: nil) else { return [] }
        return [Cell(index: nil, window: legacy)]
    }
}
