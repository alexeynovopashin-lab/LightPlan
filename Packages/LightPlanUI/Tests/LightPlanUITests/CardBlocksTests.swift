import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 26, шаг 2: порядок блоков карточки хранится по группе жанров, у
/// заказа после съёмки бумаги и деньги впереди, свёртки держатся, пока
/// карточка открыта.
@MainActor
struct CardBlocksTests {

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

    /// Съёмки 21–24.09 10:00–12:00, по одной в день (без наложений):
    /// портрет, второй портрет, свадьба, предметка.
    private static func snap() -> Snapshot {
        func rec(_ id: String, _ g: Genre, _ d: Int) -> Session {
            var s = Session(id: id, kind: .shoot, day: CivilDate(year: 2026, month: 9, day: d),
                            start: 600, end: 720, duration: 120, genre: g)
            s.notes = "зонт"; s.expense = 300
            return s
        }
        var p2 = rec("p2", .portrait, 22)
        p2.route = [RoutePoint(start: 610, name: "Парк")]
        var c = rec("c", .product, 24)
        c.brief = "каталог"
        c.docs = [Attachment(source: .link, path: nil, name: "Договор", size: nil, url: "https://disk", kind: .contract)]
        var snap = Snapshot()
        snap.sessions = [rec("p", .portrait, 21), p2, rec("w", .wedding, 23), c]
        snap.practice = "ru"
        return snap
    }

    private func model(_ snap: Snapshot = snap(), store: Store? = nil,
                       at iso: String = "2026-09-20T12:00:00+03:00") -> AppModel {
        let now = ISO8601DateFormatter().date(from: iso)!
        return AppModel(snapshot: snap, store: store, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func rec(_ app: AppModel, _ id: String) -> Session { app.sessions.first { $0.id == id }! }
    private func blocks(_ app: AppModel, _ id: String) -> [CardBlock] {
        let s = rec(app, id)
        return app.cardBlocks(s, phase: app.phase(of: s))
    }

    @Test func defaultOrderShowsOnlyBlocksWithData() {
        let app = model()
        #expect(blocks(app, "p") == [.day, .notes, .delivery, .money])
        // Маршрут с названной точкой — у дня есть место (плитка «Место и дальше»).
        #expect(blocks(app, "p2") == [.day, .place, .route, .notes, .delivery, .money])
        #expect(blocks(app, "c") == [.deal, .day, .brief, .docs, .notes, .delivery, .money])
    }

    @Test func orderSurvivesRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-26-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir, debounce: .milliseconds(1))
        let first = model(store: store)
        first.moveCardBlock(.money, to: 0, for: rec(first, "p"))
        first.setCardBlock(.notes, shown: false, for: rec(first, "p"))
        await first.flush()
        let second = model(try await store.load(), store: store)
        #expect(blocks(second, "p") == [.money, .day, .delivery])
    }

    /// Порядок — группы, не съёмки: второй портрет (с маршрутом) получает его,
    /// маршрут стоит, где стоял; свадьба и заказ не тронуты.
    @Test func groupOrderDoesNotTouchOtherGroup() {
        let app = model()
        app.moveCardBlock(.money, to: 0, for: rec(app, "p"))
        #expect(blocks(app, "p2") == [.money, .day, .place, .route, .notes, .delivery])
        #expect(blocks(app, "w") == [.day, .notes, .delivery, .money])
        #expect(blocks(app, "c") == [.deal, .day, .brief, .docs, .notes, .delivery, .money])
        #expect(Set(app.snapshotForTests.cardOrder.keys) == [.people])
    }

    /// `AFTER_FIRST`: после съёмки у заказа сделка, документы, гонорар, сдача
    /// выходят вперёд поверх порядка; у портрета — нет.
    @Test func afterFirstLiftsPapersAndMoneyForClient() {
        let app = model(at: "2026-09-25T12:00:00+03:00")
        #expect(app.phase(of: rec(app, "c")) == .after)
        #expect(blocks(app, "c") == [.deal, .docs, .money, .delivery, .day, .brief, .notes])
        #expect(blocks(app, "p") == [.day, .notes, .delivery, .money])
        // Список перестановки стоит так же, как карточка (решение Алексея 29.09: как в бете).
        #expect(app.cardOrderRows(rec(app, "c"), phase: .after) == [.deal, .docs, .money, .delivery, .day, .brief, .notes])
    }

    @Test func offBlockStaysInRowsAndResetClearsGroup() {
        let app = model()
        let p = rec(app, "p")
        app.setCardBlock(.notes, shown: false, for: p)
        #expect(!blocks(app, "p").contains(.notes))
        #expect(app.cardOrderRows(p, phase: .before).contains(.notes))
        app.moveCardBlock(.money, to: 0, for: p)
        app.resetCardOrder(for: p)
        #expect(blocks(app, "p") == [.day, .notes, .delivery, .money])
        #expect(app.snapshotForTests.cardOff[.people] == nil)
    }

    /// Открытая свёртка остаётся открытой, пока карточка открыта (у веба
    /// закрывалась при любой перерисовке — ошибка 5); другая карточка — заново.
    @Test func foldStaysOpenUntilCardCloses() {
        let app = model()
        app.openCard(id: "c")
        app.toggleCardFold(.docs)
        #expect(app.isCardFoldOpen(.docs))
        app.openCard(id: "p")
        #expect(!app.isCardFoldOpen(.docs))
        app.toggleCardFold(.docs)
        app.closeCard()
        #expect(!app.isCardFoldOpen(.docs))
    }
}
