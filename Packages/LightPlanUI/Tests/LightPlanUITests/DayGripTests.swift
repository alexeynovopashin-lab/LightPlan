import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Итерация 29а: время события рукой на ленте дня — что видит запись и
/// карточка после сдвига (строка заметки, алерт `#cdMoved`), что берёт палец
/// и когда свайп дней молчит. Палец и прокрутка — замером на симуляторе
/// (`-LPDayGripLog`), числа сетки — `DayDragTests` домена.
@MainActor
struct DayGripTests {

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

    static let day = CivilDate(year: 2026, month: 9, day: 23)
    /// 14:00–16:00 — как замер беты.
    static func shoot(_ id: String = "a", start: Int = 840, end: Int = 960, kind: RecordKind = .shoot) -> Session {
        var s = Session(id: id, kind: kind, day: day, start: start, end: end, duration: end - start, genre: .portrait)
        s.notes = "Заметка фотографа"
        return s
    }

    private func model(_ sessions: [Session], blocks: [Block] = []) -> AppModel {
        var snap = Snapshot()
        snap.sessions = sessions
        snap.blocks = blocks
        let now = ISO8601DateFormatter().date(from: "2026-09-18T13:35:00+07:00")!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func rec(_ app: AppModel, _ id: String = "a") -> Session { app.sessions.first { $0.id == id }! }
    private let nb = "\u{00A0}"

    /// Сдвиг с ленты: строка в заметке словами беты, алерт «было … стало …»;
    /// серия — одна строка; вернули как было — ни строки, ни алерта.
    @Test func moveWritesNoteAndAlertAndReturnClearsBoth() throws {
        let app = model([Self.shoot()])
        #expect(app.moveOnDay(id: "a", start: 900, end: 1020))
        var s = rec(app)
        let line = try #require(s.dayMoved?.line)
        #expect(line.hasSuffix(" · время сдвинуто в календаре: 14:00\(nb)–\(nb)16:00 → 15:00\(nb)–\(nb)17:00"))
        #expect(s.notes == "Заметка фотографа\n" + line)
        let m = try #require(app.cardMoved(s))
        #expect(m.from == "14:00\(nb)–\(nb)16:00" && m.to == "15:00\(nb)–\(nb)17:00")

        // Второй сдвиг — строка та же одна, «было» прежнее.
        #expect(app.moveOnDay(id: "a", start: 930, end: 1050))
        s = rec(app)
        #expect(s.notes.components(separatedBy: "время сдвинуто").count == 2)
        #expect(app.cardMoved(s)?.from == "14:00\(nb)–\(nb)16:00" && app.cardMoved(s)?.to == "15:30\(nb)–\(nb)17:30")

        // Вернули на 14:00–16:00 — сдвига не было.
        #expect(app.moveOnDay(id: "a", start: 840, end: 960))
        s = rec(app)
        #expect(s.dayMoved == nil && s.notes == "Заметка фотографа" && app.cardMoved(s) == nil)
        // На то же время — записывать нечего.
        #expect(!app.moveOnDay(id: "a", start: 840, end: 960))
        #expect(!app.moveOnDay(id: "нет", start: 900, end: 1020))
    }

    /// Правка формой алерт не зажигает и не гасит: время меняют нарочно.
    @Test func formEditNeitherLightsNorClearsTheAlert() throws {
        let app = model([Self.shoot(), Self.shoot("b", start: 600, end: 690)])
        app.openForm(editing: "b")
        app.form?.start = 660
        _ = try #require(app.saveForm())
        #expect(rec(app, "b").start == 660 && rec(app, "b").dayMoved == nil)

        app.moveOnDay(id: "a", start: 900, end: 1020)
        app.openForm(editing: "a")
        app.form?.start = 960
        _ = try #require(app.saveForm())
        let s = rec(app)
        #expect(s.dayMoved?.start == 840 && s.dayMoved?.end == 960)
        #expect(app.cardMoved(s)?.from == "14:00\(nb)–\(nb)16:00")
        // Крестик гасит — и только он.
        app.clearDayMoved(id: "a")
        #expect(app.cardMoved(rec(app)) == nil)
    }

    /// Палец берёт съёмку, встречу и событие этих суток; не берёт занятость
    /// (замок) и продолжение ночной съёмки из вчера.
    @Test func lockAndYesterdayTailAreNotGrabbed() {
        let night = Self.shoot("n", start: 1320, end: 1500)
        var block = Block(id: "z", kind: .busy, from: Self.day)
        block.start = 540
        block.duration = 60
        let sessions = [Self.shoot(), Self.shoot("m", start: 1140, end: 1200, kind: .meet),
                        Self.shoot("e", start: 600, end: 660, kind: .event), night]
        let today = DayItem.items(on: Self.day, sessions: sessions, blocks: [block], eventsLayer: true)
        let tomorrow = DayItem.items(on: Self.day.adding(days: 1), sessions: sessions, blocks: [block], eventsLayer: true)
        func grab(_ items: [DayItem], _ id: String) -> Bool? {
            items.first { ($0.session?.id ?? $0.block?.id) == id }.map(PlannerDayBody.grabbable)
        }
        #expect(grab(today, "a") == true && grab(today, "m") == true && grab(today, "e") == true)
        #expect(grab(today, "n") == true)
        #expect(grab(today, "z") == false)
        #expect(grab(tomorrow, "n") == false)
        // Съёмка через полночь: в своих сутках уходит в завтра — нижней ручки нет.
        #expect(today.first { $0.session?.id == "n" }?.intoTomorrow == true)
    }

    /// Свайп дней молчит, пока жест поднят, и ещё 0,4 с после; тап — 0,45 с.
    @Test func swipeAndTapsWaitForTheGesture() {
        let g = DayGrip()
        #expect(!g.blocksSwipe && !g.swallows)
        g.armed = true
        g.swallowTill = .infinity
        #expect(g.blocksSwipe && g.swallows)
        g.armed = false
        g.armedEnd = DayGrip.clock - 0.1
        g.swallowTill = DayGrip.clock + 0.3
        #expect(g.blocksSwipe && g.swallows)
        g.armedEnd = DayGrip.clock - 0.5
        g.swallowTill = DayGrip.clock - 0.01
        #expect(!g.blocksSwipe && !g.swallows)
    }

    /// Рамка блока на ленте — та же, что рисуется: 38 pt на час, не ниже 34,
    /// колонки от черты 70.
    @Test func laneRectMatchesDrawing() {
        let one = PlannerDayBody.rect(start: 840, end: 960, slot: nil, width: 440)
        #expect(one == CGRect(x: 70, y: 532, width: 370, height: 76))
        let short = PlannerDayBody.rect(start: 840, end: 850, slot: nil, width: 440)
        #expect(short.height == 34)
        let half = PlannerDayBody.rect(start: 840, end: 960,
                                       slot: DayLanes.Slot(top: 532, bottom: 608, column: 1, columns: 2), width: 440)
        #expect(half == CGRect(x: 255, y: 532, width: 181, height: 76))
    }
}
