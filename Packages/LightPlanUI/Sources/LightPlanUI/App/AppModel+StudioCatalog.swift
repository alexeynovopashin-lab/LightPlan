import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Общий список студий в листе «Где снимаем» → «Фотостудия» (30е.1). Правила —
/// `StudioCatalog` (Domain), чтение — `PlaceCatalogSource` (Data); здесь склейка с
/// моделью: загрузка, черновик карточки из места, поиск адреса на карте, пояс.
extension AppModel {

    /// Список читается в фоне (файл ~770 КБ); до ответа и без файла лист как до 30е.
    func attachPlaceCatalog(_ source: some PlaceCatalogSource) {
        Task { [weak self] in
            let catalog = await Task.detached { await source.load() }.value
            self?.placeCatalog = catalog
        }
    }

    /// Тесты и кадры: список сразу, без фоновой загрузки.
    public func usePlaceCatalog(_ catalog: PlaceCatalog?) { placeCatalog = catalog }

    /// Выдача поиска для листа: свои студии с тем же номером места помечены.
    func catalogHits(_ query: String, town: String) -> StudioCatalog.Hits {
        guard let c = placeCatalog else { return StudioCatalog.Hits() }
        return StudioCatalog.search(query, in: c, town: town, mine: snapshot.studios)
    }

    /// Черновик карточки по строке списка. Место уже в своих студиях — своя карточка,
    /// второй не будет; иначе новая: название, адрес, город, залы, номер места, центр
    /// города и пояс. Телефона в списке нет — поле пустое.
    func catalogDraft(_ row: StudioCatalog.Row) -> StudioDraft {
        if let id = row.mine, let st = snapshot.studios.first(where: { $0.id == id }) {
            return StudioDraft(st, fallback: place.coordinate)
        }
        let card = StudioCatalog.card(row.place)
        var d = StudioDraft(new: card.town, at: place.coordinate)
        d.name = card.name
        d.address = card.address
        d.catalogId = card.catalogId
        d.halls = card.halls.map { StudioDraft.Hall(id: $0.id, name: $0.name) }
        d.latitude = card.latitude ?? place.coordinate.latitude
        d.longitude = card.longitude ?? place.coordinate.longitude
        d.zone = card.zone
        return d
    }

    /// Дом студии на карте по адресу из списка (развилка 2, «А»): ответ дальше 60 км
    /// от центра её города — чужая улица с тем же названием, не берём. Нет сети или
    /// адреса — `nil`, студия остаётся в центре города.
    func locateCatalogPlace(_ p: CatalogPlace) async -> GeoCoordinate? {
        let addr = p.address.trimmingCharacters(in: .whitespaces)
        guard !addr.isEmpty else { return nil }
        let q = StudioCatalog.fold(addr).hasPrefix(StudioCatalog.fold(p.city)) || p.city.isEmpty ? addr : "\(p.city), \(addr)"
        guard let hit = try? await placeSearch.places(matching: q).first,
              StudioCatalog.accepts(latitude: hit.coordinate.latitude, longitude: hit.coordinate.longitude, for: p)
        else { return nil }
        return hit.coordinate
    }

    /// Пояс из списка ложится в кэш места (и в снимок, ключ веба `zones`), только если
    /// клетка его ещё не знает: офлайн на съёмке часы студии сразу верные.
    func rememberCatalogZone(_ zone: String?, latitude: Double?, longitude: Double?) {
        guard let zone, let z = ZoneID(zone), let la = latitude, let lo = longitude,
              place.rememberZone(z, at: GeoCoordinate(latitude: la, longitude: lo)) else { return }
        snapshot.extra["zones"] = .object(place.zones.entries.mapValues { .string($0) })
    }
}
