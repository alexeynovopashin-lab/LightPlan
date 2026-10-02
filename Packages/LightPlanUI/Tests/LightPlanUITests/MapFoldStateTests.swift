import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Шаг 28с: сводка «Карты» в хозяине приложения — по умолчанию свёрнута, разворот и сворот
/// ложатся в снимок (его и пишет хранилище, так выбор переживает перезапуск).
@MainActor
struct MapFoldStateTests {

    private struct NoWeather: WeatherSource {
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            HourlyWeather(time: [], cloud: [], temperature: [], windSpeed: [], precipitation: [], weatherCode: [])
        }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { [:] }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    private func model(_ snap: Snapshot = Snapshot()) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-09-30T09:00:00+03:00")!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    @Test func startsShut() {
        #expect(model().mapFoldShut == true)
    }

    @Test func openThenShutIsRecordedInSnapshot() {
        let m = model()
        m.setMapFold(shut: false)
        #expect(m.mapFoldShut == false)
        #expect(m.snapshot.mapFold == false)
        m.setMapFold(shut: true)
        #expect(m.mapFoldShut == true)
        #expect(m.snapshot.mapFold == true)
    }

    @Test func savedOpenChoiceIsKeptOnNextLaunch() {
        var snap = Snapshot()
        snap.mapFold = false
        #expect(model(snap).mapFoldShut == false)
    }
}
