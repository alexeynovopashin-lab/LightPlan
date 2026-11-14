import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain

extension AppModel {
    /// Нажатие на ответ быстрого поля листа «Где снимаем» (30и.1, слово Алексея 14.11: «сразу переносит»):
    /// место переехало, лист закрыт, «Готово» не нужно.
    ///
    /// Место приложения встаёт на точку ответа под городом, который нашёл поиск (`PlaceHit.city`: «Токио», не
    /// район обратного геокодера). У точки маршрута формы место — всегда запись «Моих мест» (точка на неё
    /// ссылается, как у «Готово» пути «Место»).
    func takeQuickHit(_ hit: PlaceHit) {
        if let i = placeSheetStop {
            let sp = saveSpot(at: hit.coordinate, name: hit.name, address: "", fromHit: true)
            setFormStopPlace(i, spot: sp)
        } else {
            movePlace(to: hit.coordinate, chosenName: hit.city)
        }
        placeSheetOpen = false
        placeSheetStop = nil
    }
}
