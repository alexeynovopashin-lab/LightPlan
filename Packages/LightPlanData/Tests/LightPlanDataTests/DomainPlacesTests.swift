import Foundation
import Testing
import LightPlanCore
import LightPlanDomain
@testable import LightPlanData

/// Связка с доменом (итерация 11): место из «Моих мест» ищется тем же допуском,
/// что закладка, а кэш зон отвечает правилам домена тем же поясом, что солнцу.
struct DomainPlacesTests {
    @Test func spotIsLocated() {
        let spots = [Spot(id: "a", name: "Парк", latitude: 55.76, longitude: 37.64),
                     Spot(id: "b", name: "Без точки", latitude: nil, longitude: nil)]
        #expect(SavedPoints.firstIndex(near: GeoCoordinate(latitude: 55.7603, longitude: 37.6404), in: spots) == 0)
        #expect(SavedPoints.firstIndex(near: GeoCoordinate(latitude: 55.7610, longitude: 37.64), in: spots) == nil)
        #expect(SavedPoints.firstIndex(near: GeoCoordinate(latitude: 0.0001, longitude: 0.0001), in: spots) == 1,
                "место без координат — нуль, как в вебе")
    }

    @Test func zoneCacheResolvesDomainZones() {
        var cache = ZoneCache()
        let day = CivilDate(year: 2026, month: 9, day: 10)
        #expect(cache.utcOffsetHours(latitude: 56.4846, longitude: 84.9482, on: day) == 6, "без зоны — оценка по долготе")
        cache.remember(ZoneID("Asia/Tomsk")!, at: GeoCoordinate(latitude: 56.4846, longitude: 84.9482))
        #expect(cache.utcOffsetHours(latitude: 56.4846, longitude: 84.9482, on: day) == 7, "известная зона сильнее оценки")
        let moment = Moment.of(day: day, minutes: 600, at: GeoPoint(latitude: 56.4846, longitude: 84.9482),
                               zones: cache, appOffsetHours: 3)
        #expect(WallTime(moment: moment, utcOffsetHours: 3) == WallTime(day: day, minutes: 360), "10:00 в Томске — 06:00 в Москве")
    }
}
