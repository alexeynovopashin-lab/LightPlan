import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Шаг 30б.1: приложение оставляет виджету место «Света» и переписывает файл, когда место сменилось.
@MainActor
struct WidgetShareTests {

    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
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

    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString).json")
    }

    private func read(_ url: URL) -> WidgetFeed? {
        (try? Data(contentsOf: url)).flatMap(WidgetFeed.decode)
    }

    @Test func writesOnlyWhatChanged() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let share = WidgetShare(url: url)
        let feed = WidgetFeed(place: .init(name: "Томск", latitude: 56.5, longitude: 84.97, zone: "Asia/Tomsk"))
        #expect(share.publish(feed))
        #expect(!share.publish(feed))
        #expect(read(url) == feed)
    }

    @Test func lightPlaceGoesToTheWidgetAndFollowsAMove() async throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let app = AppModel(snapshot: Snapshot(), store: nil, language: "ru", locator: NoLocator(),
                           geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
        app.widgetShare = WidgetShare(url: url)
        app.publishWidget()
        let first = try #require(read(url))
        #expect(first.place.latitude == app.place.place.latitude)
        #expect(first.place.zone == app.place.place.zone.identifier)

        app.place.move(to: GeoCoordinate(latitude: 56.4846, longitude: 84.9476))
        for _ in 0..<200 where read(url)?.place.latitude != 56.4846 { await Task.yield() }
        #expect(read(url)?.place.latitude == 56.4846)
        #expect(read(url)?.place.longitude == 84.9476)
    }
}
