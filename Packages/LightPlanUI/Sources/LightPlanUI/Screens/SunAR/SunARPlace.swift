import Foundation
import LightPlanCore
import LightPlanData

/// Для какого места AR считает солнце (шаг 29.8в.3). Слово Алексея 14.10: у окна наш +13° против +10,3° у
/// Sun Surveyor — AR брал место, выбранное в приложении (засев «Барнаул»), а не то, где стоит телефон.
enum SunARPlaceChoice: Equatable {
    /// Место телефона. `chosenFarKm` — расстояние до места, выбранного в приложении, если оно дальше `farKm`:
    /// тогда на плашке сказано, что экран считает не для него.
    case phone(Place, chosenFarKm: Double?)
    /// Телефон положения не дал: берётся выбранное в приложении место, и плашка говорит об этом.
    case chosen(Place)

    /// Дальше этого расстояния от телефона выбранное место называется на плашке отдельно.
    static let farKm = 50.0

    var place: Place {
        switch self {
        case .phone(let p, _), .chosen(let p): return p
        }
    }

    static func resolve(phone: Place?, chosen: Place) -> SunARPlaceChoice {
        guard let phone else { return .chosen(chosen) }
        let km = kmBetween(GeoCoordinate(latitude: phone.latitude, longitude: phone.longitude),
                           GeoCoordinate(latitude: chosen.latitude, longitude: chosen.longitude))
        return .phone(phone, chosenFarKm: km > farKm ? km : nil)
    }
}
