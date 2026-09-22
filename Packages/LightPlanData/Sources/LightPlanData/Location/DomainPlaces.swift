import Foundation
import LightPlanCore
import LightPlanDomain

/// Сохранённое место — такая же точка на карте, как закладка: поиск по допуску
/// 60 м не знает, чья это запись (итерация 13 ждала этого от итерации 11).
extension Spot: Located {
    /// Место без координат читается нулём — как `Math.abs(null − lat)` в вебе
    /// (`sameSpot`): с настоящей точкой оно совпадает, только если та стоит у
    /// нулевого меридиана на экваторе. Форма таких мест не заводит.
    public var coordinate: GeoCoordinate {
        GeoCoordinate(latitude: latitude ?? 0, longitude: longitude ?? 0)
    }
}

/// Пояс места для правил домена — наложений, фаз, света (веб `tzAt`):
/// настоящая зона из кэша, иначе оценка по долготе. Смещение — на начало дня
/// в этой зоне, как у солнца итерации 7.
extension ZoneCache: ZoneResolving {
    public func utcOffsetHours(latitude: Double, longitude: Double, on day: CivilDate) -> Double {
        zoneOrEstimate(at: GeoCoordinate(latitude: latitude, longitude: longitude)).utcOffsetHours(on: day)
    }
}
