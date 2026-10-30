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

    /// Багфикс 10.10: кнопки меню часа «съёмка» и «встреча» только закрывали меню.
    /// Каждая кнопка открывает своё на выбранное время; час после полуночи — завтра.
    @Test func slotMenuActsOpenTheirSheetAtTheHour() throws {
        let app = model([])
        app.openFromSlot(.shoot, day: Self.day, at: 930)
        let shoot = try #require(app.form)
        #expect(shoot.mode == .shoot && shoot.day == Self.day && shoot.start == 930)

        let meet = model([])
        meet.openFromSlot(.meet, day: Self.day, at: 600)
        let m = try #require(meet.form)
        #expect(m.mode == .meet && m.day == Self.day && m.start == 600)

        let busy = model([])
        busy.openFromSlot(.busy, day: Self.day, at: 1470)
        let b = try #require(busy.blockSheet)
        #expect(b.block.from == Self.day.adding(days: 1) && b.block.start == 30 && !b.block.allDay && !b.editing)
        #expect(busy.form == nil)
    }

    /// Удержание пустого часа берёт час и получас, как тап; меню часа — над
    /// лентой, и касание в нём жест ленты не забирает.
    @Test func slotHoldPointAndMenuFrame() {
        let h = PlannerDayBody.hourH
        #expect(PlannerDayBody.slotAt(y: 15 * h + 2) == (15, 900))
        #expect(PlannerDayBody.slotAt(y: 15 * h + h * 0.75) == (15, 930))
        #expect(PlannerDayBody.slotAt(y: 25 * h + 40) == (24, 1470))
        #expect(PlannerDayBody.slotAt(y: -5) == (0, 0))
        // Меню едет вместе с чертой заготовки: полчаса под ней, у последних часов — над ней.
        let m = PlannerDayBody.menuFrame(at: 900, width: 440)
        #expect(m == CGRect(x: 88, y: 15 * h + h / 2, width: 328, height: 66))
        #expect(PlannerDayBody.menuFrame(at: 930, width: 440).minY == 15 * h + h)
        #expect(PlannerDayBody.menuFrame(at: 945, width: 440).minY == 15 * h + h * 0.75 + h / 2)
        // У последнего часа меню встаёт над чертой.
        #expect(PlannerDayBody.menuFrame(at: 1440, width: 440).maxY == 24 * h)
    }

    /// Заготовка (меню часа) в руке: кнопки остаются кнопками, время, щели между ними и полоса у черты берёт жест.
    @Test func draftGrabZones() {
        let w: CGFloat = 440, at = 990
        let btns = PlannerDayBody.menuButtons(at: at, width: w)
        let m = PlannerDayBody.menuFrame(at: at, width: w)
        #expect(btns.count == 3)
        for b in btns { #expect(m.insetBy(dx: -0.01, dy: -0.01).contains(b) && PlannerDayBody.draftGrab(CGPoint(x: b.midX, y: b.midY), at: at, width: w) == .button) }
        // Кнопки лежат подряд слева направо, не накрывая друг друга и время.
        #expect(btns[0].minX >= m.minX + PlannerDayBody.menuTimeW)
        #expect(btns[0].maxX < btns[1].minX && btns[1].maxX < btns[2].minX && abs(btns[2].maxX - m.maxX) < 0.01)
        // Время и щель между кнопками — заготовка.
        #expect(PlannerDayBody.draftGrab(CGPoint(x: m.minX + 10, y: m.midY), at: at, width: w) == .body)
        #expect(PlannerDayBody.draftGrab(CGPoint(x: (btns[0].maxX + btns[1].minX) / 2, y: m.midY), at: at, width: w) == .body)
        // Полоса: 14 pt над чертой и полчаса под ней, на всю ширину ленты; дальше — мимо.
        let y = PlannerDayBody.top(Double(at))
        #expect(PlannerDayBody.draftGrab(CGPoint(x: 200, y: y - 10), at: at, width: w) == .body)
        #expect(PlannerDayBody.draftGrab(CGPoint(x: 200, y: y + 5), at: at, width: w) == .body)
        #expect(PlannerDayBody.draftGrab(CGPoint(x: 200, y: y - 20), at: at, width: w) == nil)
        #expect(PlannerDayBody.draftGrab(CGPoint(x: 30, y: y), at: at, width: w) == nil)
        #expect(PlannerDayBody.draftGrab(CGPoint(x: 200, y: m.maxY + 10), at: at, width: w) == nil)
    }

    /// Заготовку ведёт тот же счёт, что запись на ленте: шаг 15 (30 при шаге 30), мёртвая зона в полшага, привязка к сетке,
    /// пределы суток. Путь — pt ленты, 38 pt на час.
    @Test func draftFollowsTheFingerLikeARecord() {
        let h = PlannerDayBody.hourH
        let d = DayGrip.Draft(a0: 990, y0: 500, step: 15)
        #expect(d.at(y: 500, hourHeight: h) == 990)
        #expect(d.at(y: 500 + 3, hourHeight: h) == 990)                  // < 7,5 мин — мёртвая зона
        #expect(d.at(y: 500 + h / 4, hourHeight: h) == 1005)             // 15 мин = 9,5 pt
        #expect(d.at(y: 500 + h * 0.3, hourHeight: h) == 1005)           // 18 мин → ближайший шаг, 15
        #expect(d.at(y: 500 + h * 0.4, hourHeight: h) == 1020)           // 24 мин → 30 от 16:30
        #expect(d.at(y: 500 + h * 0.5, hourHeight: h) == 1020)
        #expect(d.at(y: 500 - h, hourHeight: h) == 930)
        #expect(d.at(y: 500 - 99 * h, hourHeight: h) == 0)               // выше полуночи не уходит
        #expect(d.at(y: 500 + 99 * h, hourHeight: h) == 1440 - 15)       // последний шаг суток
        let coarse = DayGrip.Draft(a0: 990, y0: 0, step: 30)
        #expect(coarse.at(y: h / 4, hourHeight: h) == 1020)              // шаг 30: 15 мин — уже полшага
        #expect(coarse.at(y: h / 8, hourHeight: h) == 990)
        // Тот же ответ, что у записи (`DayDrag.track`): один счёт на двоих.
        for k in [0.05, 0.3, 0.4, 0.9, -0.3, -0.6] {
            let rec = DayDrag.track(.move, a0: 990, b0: 1050, minutes: k * 60, step: 15, nest: nil)
            #expect(rec.start == d.at(y: 500 + h * CGFloat(k), hourHeight: h))
        }
    }
}
