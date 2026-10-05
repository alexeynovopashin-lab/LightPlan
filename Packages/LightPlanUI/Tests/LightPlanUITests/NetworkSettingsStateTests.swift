import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// 28л.6: раздел «Сеть» на состоянии приложения — режим запоминается и доходит до маршрутизаторов,
/// детектор отражается в строке состояния, Pinterest выключается режимом «Только напрямую».
@MainActor
struct NetworkSettingsStateTests {

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
    private struct NoCities: CityLookup { func cities(matching query: String) async throws -> [CityHit] { [] } }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }
    private struct NoReader: PinterestReading {
        func board(link: String) async throws -> PinterestBoard { throw PinterestFailure.boardNotFound }
        func image(at address: String) async throws -> Data { throw PinterestFailure.notFound }
        func preview(of page: String) async throws -> Data { throw PinterestFailure.notFound }
    }
    private actor Answer: ReachProbe {
        var answer: Bool
        init(_ a: Bool) { answer = a }
        func set(_ a: Bool) { answer = a }
        func probe() async -> Bool { answer }
    }

    private func model(_ snap: Snapshot = Snapshot()) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-10-05T09:00:00+03:00")!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func until(_ what: String, _ ok: () -> Bool) async {
        for _ in 0..<400 { if ok() { return }; try? await Task.sleep(for: .milliseconds(10)) }
        Issue.record("не дождались: \(what)")
    }

    @Test func byDefaultItIsAutoAndNothingIsWritten() {
        let app = model()
        #expect(app.netMode == .auto)
        #expect(app.snapshotForTests.extra["netMode"] == nil)
    }

    @Test func theChoiceIsRememberedInTheSnapshotAndReachesTheRouters() {
        let app = model()
        let hub = NetworkPolicyHub(detector: ForeignReachDetector(probe: Answer(true)))
        app.netHub = hub
        app.setNetMode(.directOnly)
        #expect(app.netMode == .directOnly)
        #expect(hub.mode == .directOnly)
        #expect(app.snapshotForTests.extra["netMode"] == .string("directOnly"))
        // Следующий запуск читает то же.
        #expect(model(app.snapshotForTests).netMode == .directOnly)
        #expect(AppModel.netMode(of: app.snapshotForTests) == .directOnly)
        app.setNetMode(.auto)
        #expect(hub.mode == .auto)
        #expect(model(app.snapshotForTests).netMode == .auto)
    }

    @Test func anUnknownStoredValueMeansAuto() {
        var snap = Snapshot()
        snap.extra["netMode"] = .string("something-else")
        #expect(model(snap).netMode == .auto)
    }

    @Test func pinterestIsOffOnlyInDirectOnlyMode() {
        let app = model()
        #expect(app.pinterestUnavailable() == .notConfigured)
        app.pinterest = NoReader()
        #expect(app.pinterestUnavailable() == nil)
        app.setNetMode(.directOnly)
        #expect(app.pinterestUnavailable() == .serverOff)
        #expect(app.pinText(.serverOff) == app.lexicon.t("pin.serverOff"))
        app.setNetMode(.auto)
        #expect(app.pinterestUnavailable() == nil)
    }

    @Test func theStatusWordFollowsTheDetector() {
        let app = model()
        let words = [ForeignReach.unknown: "проверяем", .reachable: "доступны", .unreachable: "недоступны"]
        for (state, word) in words {
            app.useShotNetwork(state)
            #expect(app.lexicon.t(app.foreignReachKey) == word)
        }
        #expect(app.lexicon.t("net.status", ["state": "недоступны"]) == "Зарубежные сервисы: недоступны")
    }

    @Test func theDetectorIsMirroredAndTheButtonRechecks() async {
        let app = model()
        let probe = Answer(false)
        let hub = NetworkPolicyHub(detector: ForeignReachDetector(probe: probe, sleep: { _ in try await Task.sleep(for: .seconds(3600)) },
                                                                  pause: { _ in try await Task.sleep(for: .seconds(3600)) }))
        app.attachNetwork(hub)
        await until("недоступно после первой пробы") { app.foreignReach == .unreachable }
        await probe.set(true)
        app.recheckNetwork()
        #expect(app.netChecking)
        #expect(app.lexicon.t(app.foreignReachKey) == "проверяем")
        await until("кнопка отработала") { !app.netChecking }
        #expect(app.foreignReach == .reachable)
        #expect(app.lexicon.t(app.foreignReachKey) == "доступны")
    }
}
