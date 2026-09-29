import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 26, шаг 5а: режим «ползунков» на карточке — вход и выход, место
/// строки при перетаскивании, тумблер, сброс, порядок после перезапуска.
@MainActor
struct CardTuneTests {

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

    /// Два портрета в разные дни: заметки и расход — чтобы у блоков были данные.
    private static func snap() -> Snapshot {
        func rec(_ id: String, _ d: Int) -> Session {
            var s = Session(id: id, kind: .shoot, day: CivilDate(year: 2026, month: 9, day: d),
                            start: 600, end: 720, duration: 120, genre: .portrait)
            s.notes = "зонт"; s.expense = 300
            return s
        }
        var snap = Snapshot()
        snap.sessions = [rec("p", 21), rec("q", 22)]
        snap.practice = "ru"
        return snap
    }

    private func model(_ snap: Snapshot = snap(), store: Store? = nil) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00+03:00")!
        return AppModel(snapshot: snap, store: store, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func rec(_ app: AppModel, _ id: String) -> Session { app.sessions.first { $0.id == id }! }
    private func rows(_ app: AppModel, _ id: String) -> [CardBlock] {
        let s = rec(app, id)
        return app.cardOrderRows(s, phase: app.phase(of: s))
    }

    // MARK: - Драг: где встанет строка

    @Test func slotFollowsStepAndIsClampedByEdges() {
        #expect(CardOrderDrag.slot(start: 2, dy: 0, count: 4) == 2)
        #expect(CardOrderDrag.slot(start: 2, dy: 31, count: 4) == 2)      // меньше полшага — на месте
        #expect(CardOrderDrag.slot(start: 2, dy: 33, count: 4) == 3)      // больше полшага — на шаг
        #expect(CardOrderDrag.slot(start: 2, dy: -70, count: 4) == 1)
        #expect(CardOrderDrag.slot(start: 2, dy: -900, count: 4) == 0)    // зажато сверху
        #expect(CardOrderDrag.slot(start: 2, dy: 900, count: 4) == 3)     // и снизу
        #expect(CardOrderDrag.slot(start: 0, dy: 10, count: 0) == 0)
    }

    @Test func previewMovesOnlyTheHeldRow() {
        let rows: [CardBlock] = [.day, .notes, .delivery, .money]
        #expect(CardOrderDrag.preview(rows, moving: .money, to: 0) == [.money, .day, .notes, .delivery])
        #expect(CardOrderDrag.preview(rows, moving: .day, to: 2) == [.notes, .delivery, .day, .money])
        #expect(CardOrderDrag.preview(rows, moving: .day, to: 0) == rows)
        #expect(CardOrderDrag.preview(rows, moving: .refs, to: 1) == rows)
    }

    // MARK: - Режим

    @Test func tuningLeavesWithCardAndWithSwitchToAnotherCard() {
        let app = model()
        #expect(!app.cardTuning)
        app.openCard(id: "p")
        app.toggleCardTuning()
        #expect(app.cardTuning)
        app.openCard(id: "p")               // та же карточка — режим держится
        #expect(app.cardTuning)
        app.openCard(id: "q")               // сосед из стопки — режим сброшен
        #expect(!app.cardTuning)
        app.toggleCardTuning()
        app.closeCard()
        #expect(!app.cardTuning)
        app.openCard(id: "q")
        #expect(!app.cardTuning)
        app.toggleCardTuning()
        app.toggleCardTuning()              // «Готово» — выход
        #expect(!app.cardTuning)
    }

    // MARK: - Порядок, тумблер, сброс

    /// Перетащили «Деньги» наверх: на месте остаются и блоки без данных в этой
    /// съёмке (их у веба уносило в конец), и порядок соседа по группе.
    @Test func dragKeepsAbsentBlocksInPlaceAndReachesGroupMates() {
        let app = model()
        let p = rec(app, "p")
        let before = CardOrder.full(genre: p.genre, saved: app.snapshotForTests.cardOrder)
        #expect(rows(app, "p") == [.day, .notes, .delivery, .money])
        let j = CardOrderDrag.slot(start: 3, dy: -200, count: 4)
        app.moveCardBlock(.money, to: j, for: p)
        #expect(rows(app, "p") == [.money, .day, .notes, .delivery])
        let after = CardOrder.full(genre: p.genre, saved: app.snapshotForTests.cardOrder)
        #expect(after.filter { $0 != .money } == before.filter { $0 != .money })
        #expect(rows(app, "q") == [.money, .day, .notes, .delivery])
    }

    @Test func switchHidesBlockFromCardButKeepsItsRow() {
        let app = model()
        let p = rec(app, "p")
        app.setCardBlock(.notes, shown: false, for: p)
        #expect(rows(app, "p").contains(.notes))
        #expect(!app.cardBlocks(p, phase: app.phase(of: p)).contains(.notes))
        #expect(app.isCardBlockOff(.notes, for: p))
        app.setCardBlock(.notes, shown: true, for: p)
        #expect(app.cardBlocks(p, phase: app.phase(of: p)).contains(.notes))
    }

    @Test func resetErasesOrderAndSwitches() {
        let app = model()
        let p = rec(app, "p")
        app.moveCardBlock(.money, to: 0, for: p)
        app.setCardBlock(.notes, shown: false, for: p)
        app.resetCardOrder(for: p)
        #expect(rows(app, "p") == [.day, .notes, .delivery, .money])
        #expect(app.cardBlocks(p, phase: app.phase(of: p)) == [.day, .notes, .delivery, .money])
        #expect(app.snapshotForTests.cardOrder[.people] == nil && app.snapshotForTests.cardOff[.people] == nil)
    }

    /// Порядок и выключенные переживают перезапуск; сброс — тоже.
    @Test func orderSwitchesAndResetSurviveRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-26-5a-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir, debounce: .milliseconds(1))
        let first = model(store: store)
        let p = rec(first, "p")
        first.moveCardBlock(.money, to: CardOrderDrag.slot(start: 3, dy: -200, count: 4), for: p)
        first.setCardBlock(.notes, shown: false, for: p)
        await first.flush()

        let second = model(try await store.load(), store: store)
        #expect(rows(second, "p") == [.money, .day, .notes, .delivery])
        #expect(second.isCardBlockOff(.notes, for: rec(second, "p")))
        #expect(second.cardBlocks(rec(second, "p"), phase: .before) == [.money, .day, .delivery])

        second.resetCardOrder(for: rec(second, "p"))
        await second.flush()
        let third = model(try await store.load(), store: store)
        #expect(rows(third, "p") == [.day, .notes, .delivery, .money])
        #expect(!third.isCardBlockOff(.notes, for: rec(third, "p")))
    }
}
