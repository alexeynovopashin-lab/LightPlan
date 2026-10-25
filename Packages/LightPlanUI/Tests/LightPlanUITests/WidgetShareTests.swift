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

    // MARK: 30б.2 — съёмки в файле

    private func model(now: Date) -> AppModel {
        AppModel(snapshot: Snapshot(), store: nil, language: "ru", locator: NoLocator(),
                 geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather(), now: { now })
    }

    /// 24.10.2026 06:00 UTC — в месте приложения («ru» → столица) уже день 24-го.
    private let morning = Date(timeIntervalSince1970: 1_792_821_600)

    @Test func shootsGoToTheWidgetByGenreNotByClient() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let app = model(now: morning)
        app.widgetShare = WidgetShare(url: url)
        var shoot = Session(id: "w1", day: app.today, start: 15 * 60, end: 19 * 60, genre: .wedding)
        shoot.contact = "Иванова Мария +7 913 000-00-00"
        shoot.wishes = [.sunset]
        app.snapshot.sessions = [shoot]
        app.publishWidget()

        let feed = try #require(read(url))
        let w = try #require(feed.shoots.first)
        #expect(feed.shoots.count == 1 && w.id == "w1" && w.wantsSunset)
        #expect(w.title == app.lexicon.t("genre.wedding"), "название жанра на языке приложения: \(w.title)")
        #expect(!(try Data(contentsOf: url)).contains(Data("Иванова".utf8)), "имя клиента в файл не идёт")
        #expect(feed.words[.sunset] == app.lexicon.t("tele.sunset") && feed.words[.next] == app.lexicon.t("pane.next"))
        #expect(feed.lang == "ru" && !feed.clock12)
    }

    @Test func savingTheDataRewritesTheFile() async throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let app = model(now: morning)
        app.widgetShare = WidgetShare(url: url)
        app.snapshot.sessions = [Session(id: "p1", day: app.today, start: 16 * 60, end: 17 * 60, genre: .portrait)]
        app.persist()
        #expect(read(url)?.shoots.map(\.id) == ["p1"])
        app.snapshot.sessions = []
        app.persist()
        #expect(read(url)?.shoots.isEmpty == true)
    }

    @Test func aDayLinkOpensThatDayInThePlanner() throws {
        let app = model(now: morning)
        #expect(!app.openDayLink(URL(string: "lightplan://shoot/abc")!))
        #expect(app.openDayLink(WidgetFeed.dayURL(CivilDate(year: 2026, month: 10, day: 27))))
        #expect(app.tab == .planner && app.planner.selected == CivilDate(year: 2026, month: 10, day: 27))
        #expect(app.planner.scope == .day)
    }
}
