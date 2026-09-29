import Foundation
import LightPlanCore
import LightPlanDomain

/// Где точка относительно «сейчас» по часам места съёмки.
enum CardRouteState: Hashable { case ahead, past, now }

/// Строка ленты маршрута в карточке (веб `renderRouteFold`).
struct CardRouteLine: Hashable {
    let sign: String
    let time: String
    let name: String
    /// Место точки строкой; нет — нет и строки под именем.
    let place: String?
    /// Слово света, только тон «отлично»; утро, день и ночь молчат.
    let word: String?
    let blue: Bool
    let state: CardRouteState
}

extension AppModel {
    /// Свёрнутая строка маршрута: «7 точек · 11:00 – 23:00». Конец дня — самый
    /// поздний конец среди точек (у веба — конец последней по началу, ошибка 23:
    /// поздняя короткая точка обрезала бы день).
    func cardRouteFold(_ s: Session) -> CardRouteFold? {
        let route = s.timedRoute
        guard let first = route.first?.start else { return nil }
        let f = PlannerFacts(app: self, dark: false)
        let end = route.map { $0.end ?? $0.start ?? first }.max() ?? first
        return CardRouteFold(title: lexicon.t("card.route"),
                             sub: lexicon.count("unit.point", route.count) + " · " + f.range(Double(first), Double(end)))
    }

    /// Состояние точки (веб `renderRouteFold`): текущая — последняя с началом не
    /// позже «сейчас»; раньше «сейчас» и не текущая — прошедшая; вне суток
    /// съёмки и до первой точки все стоят без отметки.
    static func routeStates(_ route: [RoutePoint], now: Int?) -> [CardRouteState] {
        let cur = DayTileText.current(route, now)
        return route.indices.map { i in
            if i == cur { return .now }
            if let now, let t = route[i].start, t < now { return .past }
            return .ahead
        }
    }

    /// Лента точек: знак по названию, времени и месту (`PointSign`, как в плитке
    /// «Дальше»), слово света у места точки, состояние.
    func cardRouteLines(_ s: Session) -> [CardRouteLine] {
        let route = s.timedRoute
        let f = PlannerFacts(app: self, dark: false)
        let states = Self.routeStates(route, now: nowMinute(of: s))
        let sky = anchor(s)
        return route.enumerated().map { i, r in
            let stop = Stops.place(of: r, spots: snapshot.spots, studios: snapshot.studios)
            let place = r.placeText.isEmpty ? stop?.name : r.placeText
            let t = r.start ?? 0
            let code = pointLightCode(s, stop?.point ?? sky, t)
            return CardRouteLine(
                sign: PointSign.name(for: r.name, place: place, studio: !(r.studioId ?? "").isEmpty),
                time: f.fmt(Double(t)), name: r.name,
                place: r.placeText.isEmpty ? nil : r.placeText,
                word: code.map { lexicon.t("sun.\($0.rawValue).label") }, blue: code == .blue, state: states[i])
        }
    }
}
