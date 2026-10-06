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
        // Ровно половина шага: как `Math.round` веба — вниз на шаг, вверх остаётся на месте.
        #expect(CardOrderDrag.slot(start: 2, dy: 32, count: 4) == 3)
        #expect(CardOrderDrag.slot(start: 2, dy: -32, count: 4) == 2)
        #expect(CardOrderDrag.slot(start: 2, dy: -32.5, count: 4) == 1)
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

    /// 27а.2: при «Уменьшении движения» вход мгновенный, хода нет; с движением ход идёт
    /// счётчиком, и по окончании анимации он ровно ноль (в том числе после повторного тапа посреди хода).
    @Test func reducedMotionToggleIsInstantAndLeavesNoMove() {
        let app = model()
        app.openCard(id: "p")
        app.toggleCardTuning(still: true)
        #expect(app.cardTuning && !app.cardTuneMoving)
        app.toggleCardTuning(still: true)
        #expect(!app.cardTuning && !app.cardTuneMoving)
    }

    @Test func moveCounterReturnsToZeroWhenAnimationEnds() async {
        let app = model()
        app.openCard(id: "p")
        app.toggleCardTuning(still: false)
        #expect(app.cardTuning)
        // Повторный тап посреди хода: оба хода должны закрыться.
        app.toggleCardTuning(still: false)
        #expect(!app.cardTuning)
        for _ in 0..<100 where app.cardTuneMoves != 0 { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(app.cardTuneMoves == 0 && !app.cardTuneMoving)
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

    // MARK: - 27а.3: порядок после драга за пальцем

    /// Палец ведёт блок `b` на `dy` (по осям экрана), `scroll` — на сколько уехал лист; отпустили — запись.
    /// `lift` рука делает с места в списке, как жест на ручке.
    private func dragBlock(_ app: AppModel, _ id: String, _ b: CardBlock, dy: CGFloat, scroll: CGFloat = 0, interrupt: Bool = false) {
        let p = rec(app, id)
        let list = rows(app, id)
        var hand = CardHand()
        hand.lift(b, from: list.firstIndex(of: b)!, count: list.count, startY: 500, startScroll: 0)
        hand.follow(finger: 500 + dy, scroll: scroll)
        if interrupt { hand.interrupt() }
        if let m = hand.release(finger: 500 + dy, scroll: scroll) { app.moveCardBlock(m.block, to: m.to, for: p) }
    }

    @Test func dragDownUpAndToTheSamePlace() {
        let app = model()
        dragBlock(app, "p", .notes, dy: 70)                         // вниз на строку
        #expect(rows(app, "p") == [.day, .delivery, .notes, .money])
        dragBlock(app, "p", .money, dy: -130)                       // вверх на две
        #expect(rows(app, "p") == [.day, .money, .delivery, .notes])
        let saved = app.snapshotForTests.cardOrder
        dragBlock(app, "p", .delivery, dy: 20)                      // меньше полшага — то же место
        dragBlock(app, "p", .delivery, dy: -31)
        #expect(rows(app, "p") == [.day, .money, .delivery, .notes])
        #expect(app.snapshotForTests.cardOrder == saved)            // и записи нет
    }

    @Test func dragToTheEdgesAndBeyond() {
        let app = model()
        dragBlock(app, "p", .day, dy: 5000)                         // первый — в самый низ, дальше края не уйти
        #expect(rows(app, "p") == [.notes, .delivery, .money, .day])
        dragBlock(app, "p", .day, dy: -5000)                        // и обратно в самый верх
        #expect(rows(app, "p") == [.day, .notes, .delivery, .money])
        dragBlock(app, "p", .money, dy: 5000)                       // последний ниже последнего — на месте
        dragBlock(app, "p", .day, dy: -5000)                        // первый выше первого — на месте
        #expect(rows(app, "p") == [.day, .notes, .delivery, .money])
    }

    @Test func dragWithTheSheetScrollingUnderAStillFinger() {
        let app = model()
        dragBlock(app, "p", .day, dy: 0, scroll: 128)               // палец стоит, лист проехал две строки
        #expect(rows(app, "p") == [.notes, .delivery, .day, .money])
    }

    /// Звонок посреди драга: строки остаются, как были, и следующий драг идёт обычно.
    @Test func interruptedDragChangesNothingAndDoesNotStick() {
        let app = model()
        dragBlock(app, "p", .money, dy: -500, interrupt: true)
        #expect(rows(app, "p") == [.day, .notes, .delivery, .money])
        #expect(app.snapshotForTests.cardOrder[.people] == nil)
        dragBlock(app, "p", .money, dy: -500)
        #expect(rows(app, "p") == [.money, .day, .notes, .delivery])
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
