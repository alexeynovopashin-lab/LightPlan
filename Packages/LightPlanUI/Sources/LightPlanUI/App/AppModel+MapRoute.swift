import Foundation
import LightPlanDomain
import LightPlanData
import LightPlanCore
import LightPlanMapCanvas
import Observation

/// Черновик маршрута «Карты» (итерация 24а): `mapRoute` веба — id «Моих мест»
/// по порядку, один на приложение. Ключ веба лежит в снимке среди чужих
/// (`extra`), как `graves`: веб читает и пишет тот же массив, файл переезжает
/// между ними без перевода. Переживает перезапуск; режим набора — нет.
extension AppModel {
    /// Id черновика как записаны — и удалённых мест тоже: черновик их
    /// переживает, пропуск — при чтении (`routeSpots`).
    public var mapRoute: [String] {
        guard case .array(let a)? = snapshot.extra["mapRoute"] else { return [] }
        return a.compactMap { if case .string(let id) = $0 { id } else { nil } }
    }

    func setMapRoute(_ ids: [String]) {
        snapshot.extra["mapRoute"] = .array(ids.map { .string($0) })
        persist()
    }

    /// `routeSpots()` веба: места черновика по порядку, у которых есть координаты.
    public var routeSpots: [Spot] {
        let byId = Dictionary(snapshot.spots.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return mapRoute.compactMap { byId[$0] }.filter { $0.latitude != nil && $0.longitude != nil }
    }

    /// Номер места в черновике с единицы — или `nil`, если его там нет.
    /// Считается по живым местам: удалённое номер не занимает.
    public func routeNumber(of id: String) -> Int? {
        routeSpots.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    /// Тап мимо булавки в режиме набора (`routeNewSpot`): точка — в центре
    /// кадра, то есть под головкой. Там уже сохранённое место — оно идёт в
    /// черновик; нет — заводится новое, как у закладки. `isNew` — открыть
    /// полосу имени. Одно место дважды в черновик не встаёт. «Вернуть»
    /// черновика гаснет здесь же, как у веба, а не у каждого, кто зовёт.
    @discardableResult
    public func routeAddHere(now: Date = Date()) -> (spot: Spot, isNew: Bool) {
        dropRouteUndo()
        let old = spotHere
        let sp = old ?? insertSpotHere(now: now)
        var ids = mapRoute
        if !ids.contains(sp.id) { ids.append(sp.id) }
        setMapRoute(ids)
        return (sp, old == nil)
    }

    /// Тап по булавке в режиме набора (`routeToggle`): в черновик в конец или
    /// из черновика. `true` — положили (у постановки есть движение, у снятия нет).
    @discardableResult
    public func routeToggle(id: String) -> Bool {
        dropRouteUndo()
        var ids = mapRoute
        if let i = ids.firstIndex(of: id) {
            ids.remove(at: i)
            setMapRoute(ids)
            return false
        }
        ids.append(id)
        setMapRoute(ids)
        return true
    }
}

// MARK: - Полоса черновика (шаг 2)

extension AppModel {
    /// `walkKey` веба: переход от A к B — ключ пары, не номер.
    static func walkKey(_ a: String, _ b: String) -> String { a + ">" + b }

    /// `mapWalk` веба — `{ "<a>><b>": 1 }`, тоже ключом веба в `extra`.
    public var mapWalk: Set<String> {
        guard case .object(let o)? = snapshot.extra["mapWalk"] else { return [] }
        return Set(o.keys)
    }

    public func isWalk(from a: String, to b: String) -> Bool { mapWalk.contains(Self.walkKey(a, b)) }

    /// Знак способа в строке: «едут» ↔ «пешком» от A к B.
    public func toggleWalk(from a: String, to b: String) {
        var o: [String: JSONValue] = [:]
        if case .object(let old)? = snapshot.extra["mapWalk"] { o = old }
        let k = Self.walkKey(a, b)
        if o[k] != nil { o[k] = nil } else { o[k] = .number(1) }
        snapshot.extra["mapWalk"] = .object(o)
        persist()
    }

    /// «✕» полосы: черновик снят, «Вернуть» 6 с (`offerRouteUndo`). Места целы.
    public func clearRoute() {
        let was = mapRoute
        guard !was.isEmpty else { return }
        setMapRoute([])
        undo = UndoOffer(what: .route(ids: was),
                         text: lexicon.t("map.routeCleared", ["n": lexicon.count("unit.point", was.count)]))
    }

    /// Новая точка и выход из режима убирают «Вернуть» черновика (`dropRouteUndo`).
    public func dropRouteUndo() {
        if case .route? = undo?.what { undo = nil }
    }

    /// Жанр для «Сделать съёмкой» (`routeGenre`): последний выбранный, если у
    /// него бывают точки дня, иначе первый включённый такой; нет — `nil`.
    public var routeGenre: Genre? {
        if GenreProfile(lastFormGenre).hasRoute { return lastFormGenre }
        return enabledGenres.first { GenreProfile($0).hasRoute }
    }

    /// «Сделать съёмкой» (`makeRouteShoot`): форма на день `day`, начало —
    /// начало золотого часа или `minute`; точки дня — места черновика по
    /// порядку без часов, ссылками на места, способ — из `mapWalk`. Первая
    /// точка — место съёмки. Черновик остаётся. `false` — не из чего.
    @discardableResult
    public func makeRouteShoot(day: CivilDate, minute: Double) -> Bool {
        let pts = routeSpots
        guard !pts.isEmpty, let g = routeGenre else { return false }
        lastFormGenre = g
        let sun = SolarDay(date: day, place: place.place)
        openForm(day: day, start: Int((sun.goldenB ?? minute).rounded()))
        guard var f = form else { return false }
        f.route = pts.enumerated().map { i, sp in
            let nx = i + 1 < pts.count ? pts[i + 1] : nil
            return RoutePoint(start: nil, name: "", placeText: sp.name, spotId: sp.id,
                              walk: nx.map { isWalk(from: sp.id, to: $0.id) } ?? false)
        }
        f.routeSeeded = false
        f.syncHeadPlace(spots: snapshot.spots, studios: snapshot.studios, home: repeatHome)
        form = f
        formChanged()
        return true
    }
}

/// Расстояние по прямой, км (`kmBetween` веба, R 6371).
func kmBetween(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
    let rad = Double.pi / 180
    let dLat = (b.latitude - a.latitude) * rad, dLon = (b.longitude - a.longitude) * rad
    let h = sin(dLat / 2) * sin(dLat / 2)
        + cos(a.latitude * rad) * cos(b.latitude * rad) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * 6371 * asin(min(1, sqrt(h)))
}

// MARK: - Дорога (шаг 3)

/// Кусок черновика, который спрашивают у маршрутизатора одним запросом
/// (`chainRuns` веба): подряд идущие точки одного способа.
public struct RouteRun: Equatable, Sendable {
    public var mode: RoadMode
    public var points: [MapCanvasCenter]
}

extension AppModel {
    /// Одно место (`sameSpot` веба): ближе 0,0006° по обеим осям.
    static func sameSpot(_ a: MapCanvasCenter, _ b: MapCanvasCenter) -> Bool {
        abs(a.latitude - b.latitude) < 0.0006 && abs(a.longitude - b.longitude) < 0.0006
    }

    /// `chainRuns(routeChain())` веба для черновика. Два места подряд в одной
    /// точке — не переезд; смена способа рвёт кусок: машину и пешком считают
    /// разные сервисы.
    public var routeRuns: [RouteRun] {
        let pts = routeSpots
        var runs: [RouteRun] = []
        var cur: Int?
        for i in 0 ..< max(0, pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            guard let ala = a.latitude, let alo = a.longitude,
                  let bla = b.latitude, let blo = b.longitude else { cur = nil; continue }
            let pa = MapCanvasCenter(latitude: ala, longitude: alo)
            let pb = MapCanvasCenter(latitude: bla, longitude: blo)
            if Self.sameSpot(pa, pb) { continue }
            let mode: RoadMode = isWalk(from: a.id, to: b.id) ? .foot : .car
            if let c = cur, runs[c].mode == mode, let last = runs[c].points.last, Self.sameSpot(last, pa) {
                runs[c].points.append(pb)
            } else {
                runs.append(RouteRun(mode: mode, points: [pa, pb]))
                cur = runs.count - 1
            }
        }
        return runs
    }

    /// Перестановка удержанием номера (`rbDragEnd`): строка `from` встаёт на `to`
    /// в порядке живых точек. Удалённые места в черновике остаются, где были.
    public func moveRoute(from: Int, to: Int) {
        let live = routeSpots.map(\.id)
        guard from != to, live.indices.contains(from), live.indices.contains(to) else { return }
        var order = live
        order.insert(order.remove(at: from), at: to)
        // Живые id встают на свои прежние места в полном списке по новому порядку.
        var next = order.makeIterator()
        let liveSet = Set(live)
        setMapRoute(mapRoute.map { liveSet.contains($0) ? next.next()! : $0 })
    }
}

/// Кэш и очередь маршрутизатора (`roadCache`, `roadFly`, `roadAsk` веба).
/// Ключ — источник, способ и точки: те же точки пешком — другой вопрос, и
/// карты Apple — другой ответ. Сбой кладёт `nil`: в этом сеансе кусок не
/// спрашивают снова и он остаётся прямой.
@MainActor
@Observable
final class RoadBook {
    private(set) var cache: [String: RoadAnswer?] = [:]
    @ObservationIgnored private var flying: Set<String> = []
    @ObservationIgnored private var pending = ""
    @ObservationIgnored private var wait: Task<Void, Never>?

    static func key(_ source: MapCanvasSource, _ run: RouteRun) -> String {
        source.rawValue + "|" + run.mode.rawValue + "|" + RoadRouter.key(run.points)
    }

    /// Ответ на кусок: `nil` — ещё не спрашивали или летит; `.some(nil)` — сбой.
    func answer(_ source: MapCanvasSource, _ run: RouteRun) -> RoadAnswer?? {
        cache[Self.key(source, run)]
    }

    /// Спросить разом всё, что нужно кадру, через 400 мс тишины. Ждём руку, а
    /// не кусок: тот же набор кусков повторно не перезапускает ожидание.
    func ask(_ source: MapCanvasSource, _ runs: [RouteRun]) {
        let keys = runs.map { Self.key(source, $0) }
        let id = keys.joined(separator: "‖")
        guard !id.isEmpty, id != pending else { return }
        pending = id
        wait?.cancel()
        wait = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            for (k, run) in zip(keys, runs) where self.cache[k] == nil && !self.flying.contains(k) {
                self.flying.insert(k)
                Task {
                    let a = await RoadRouter.ask(source: source, mode: run.mode, points: run.points)
                    self.flying.remove(k)
                    self.cache[k] = .some(a)
                }
            }
        }
    }
}
