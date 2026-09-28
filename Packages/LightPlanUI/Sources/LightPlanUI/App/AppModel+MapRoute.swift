import Foundation
import LightPlanDomain
import LightPlanData

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
    /// полосу имени. Одно место дважды в черновик не встаёт.
    @discardableResult
    public func routeAddHere(now: Date = Date()) -> (spot: Spot, isNew: Bool) {
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
