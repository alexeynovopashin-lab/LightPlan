import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Итерация 22: год, статистика, поиск, корзина. Прибыль года и основа слова
/// поиска сверяются с кодом веба (`Fixtures/year.json`, `make year`);
/// остальное — правила веба из справки `docs/native_22_planner_web_spec.md`.
@Suite struct PlannerYearParityTests {

    struct Ref: Decodable {
        struct Year: Decodable {
            struct Other: Decodable { let code: String; let sum: Double }
            let year: Int; let amount: Double; let cumulative: [Double]; let others: [Other]
        }
        struct Stem: Decodable { let q: String; let stem: String }
        let home: String
        let sessions: [Session]
        let years: [Year]
        let stems: [Stem]
    }

    static let ref: Ref = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        u.appendPathComponent("Fixtures/year.json")
        do { return try JSONDecoder().decode(Ref.self, from: Data(contentsOf: u)) }
        catch { fatalError("нет или не читается \(u.path): \(error). Собрать: make year") }
    }()

    private static func d(_ v: Decimal) -> Double { NSDecimalNumber(decimal: v).doubleValue }

    @Test func profitByCurrencyMatchesWeb() {
        let r = Self.ref
        #expect(r.sessions.count == 92)
        let home = Currency(rawValue: r.home)!
        for y in r.years {
            let p = YearMath.profit(r.sessions, year: y.year, home: home)
            #expect(abs(Self.d(p.amount) - y.amount) < 1e-6, "\(y.year): \(p.amount) ≠ \(y.amount)")
            #expect(p.cumulative.map(Self.d).enumerated().allSatisfy { abs($0.element - y.cumulative[$0.offset]) < 1e-6 },
                    "\(y.year): нарастающий итог разошёлся")
            #expect(p.others.map(\.currency.rawValue) == y.others.map(\.code), "\(y.year): порядок валют")
            for (a, b) in zip(p.others, y.others) {
                #expect(abs(Self.d(a.sum) - b.sum) < 1e-6, "\(y.year) \(b.code): \(a.sum) ≠ \(b.sum)")
            }
        }
        // В эталоне есть и минус, и несколько чужих валют — иначе сверка слабая.
        #expect(r.years.contains { $0.amount < 0 })
        #expect(r.years.allSatisfy { $0.others.count >= 3 })
    }

    @Test func searchStemMatchesWeb() {
        for s in Self.ref.stems { #expect(YearMath.stem(s.q) == s.stem, "«\(s.q)»") }
    }
}

@Suite struct PlannerYearMathTests {
    private func shoot(_ id: String, _ y: Int, _ m: Int, _ d: Int, kind: RecordKind = .shoot,
                       genre: Genre = .portrait) -> Session {
        Session(id: id, kind: kind, day: CivilDate(year: y, month: m, day: d), start: 600, duration: 60, genre: genre)
    }

    @Test func monthShapeIsMondayFirstWithoutTail() {
        // Сентябрь 2026 начинается во вторник: одна пустая клетка, 30 дней.
        #expect(YearMath.monthShape(year: 2026, month: 9) == (1, 30))
        // Февраль 2027 — с понедельника, 28 дней.
        #expect(YearMath.monthShape(year: 2027, month: 2) == (0, 28))
    }

    @Test func year12DotsCountWorkByStartDay() {
        let s = [shoot("a", 2026, 9, 5), shoot("b", 2026, 9, 5), shoot("c", 2026, 9, 6, kind: .meet),
                 shoot("d", 2026, 9, 7, kind: .event), shoot("e", 2026, 10, 5)]
        #expect(YearMath.dayCounts(s, year: 2026, month: 9) == [5: 2])
    }

    @Test func yearSumCountsWorkAndTodayIsAhead() {
        let today = CivilDate(year: 2026, month: 9, day: 23)
        let s = [shoot("a", 2026, 9, 1), shoot("b", 2026, 9, 23), shoot("c", 2026, 12, 1),
                 shoot("m", 2026, 9, 24, kind: .meet), shoot("x", 2027, 1, 1)]
        let r = YearMath.summary(s, year: 2026, today: today)
        #expect(r.count == 3)
        #expect(r.next == today)
        #expect(YearMath.summary([], year: 2026, today: today).count == 0)
    }

    @Test func monthBarsCountMeetingsAndKeepFirstWorst() {
        let s = [shoot("a", 2026, 3, 1), shoot("b", 2026, 3, 2), shoot("m", 2026, 3, 3, kind: .meet),
                 shoot("c", 2026, 7, 1), shoot("d", 2026, 7, 2)]
        let st: [String: DeliveryStatus] = ["a": .due(progress: 0.2, daysLeft: 5), "b": .due(progress: 0.9, daysLeft: 1),
                                            "m": .notWork, "c": .overdue(days: 2), "d": .ahead]
        let bars = YearMath.monthBars(s, year: 2026) { st[$0.id]! }
        #expect(bars[2].count == 3)       // встреча в счёт, как у веба
        #expect(bars[2].percent == 100)
        #expect(bars[6].percent == 67)    // round(2/3·100)
        #expect(bars[0].percent == 0)
        // Равные ступени — первая запись (веб `>`), а не самая срочная.
        #expect(bars[2].worst == .due(progress: 0.2, daysLeft: 5))
        #expect(bars[6].worst == .overdue(days: 2))
        let one = YearMath.monthBars([shoot("a", 2026, 1, 1)] + (1...30).map { shoot("f\($0)", 2026, 2, $0 % 28 + 1) },
                                     year: 2026) { _ in .ahead }
        #expect(one[0].percent == 8)      // короче 8 % полоса не бывает
    }

    @Test func genresSortByCountThenFirstSeen() {
        let s = [shoot("a", 2026, 1, 1, genre: .family), shoot("b", 2026, 1, 2, genre: .wedding),
                 shoot("c", 2026, 1, 3, genre: .wedding), shoot("d", 2026, 1, 4, genre: .portrait)]
        let g = YearMath.genreCounts(s)
        #expect(g.map(\.genre) == [.wedding, .family, .portrait])
        #expect(g.map(\.count) == [2, 1, 1])
    }

    @Test func overloadNeedsThreeAndThreeAndTodayIsNotUpcoming() {
        let zone = TimeZone(identifier: "Asia/Barnaul")!
        let now = Date(timeIntervalSince1970: 1_790_157_600) // 23.09.2026 17:00 по Барнаулу
        let today = CivilDate(year: 2026, month: 9, day: 23)
        var s = (0..<3).map { shoot("o\($0)", 2026, 8, 1 + $0) }
        s += (1...3).map { shoot("u\($0)", 2026, 9, 23 + $0) }
        let dl: (Session) -> CivilDate? = { $0.day < today ? $0.day.adding(days: 7) : nil }
        let r = YearMath.overload(s, now: now, zone: zone, deadline: dl)
        #expect(r?.overdue == 3 && r?.upcoming == 3)
        // Сегодняшняя вместо завтрашней — впереди уже две: сигнала нет.
        var t = s
        t[3] = shoot("u1", 2026, 9, 23)
        #expect(YearMath.overload(t, now: now, zone: zone, deadline: dl) == nil)
    }

    @Test func lateGenresNeedFiveAndHalfADay() {
        let zone = TimeZone(identifier: "Asia/Barnaul")!
        func delivered(_ id: String, genre: Genre, lateHours: Double) -> Session {
            var s = shoot(id, 2026, 5, 1, genre: genre)
            s.delivered = true
            s.deliveredAt = Date(timeIntervalSince1970: YearMath.midnight(CivilDate(year: 2026, month: 5, day: 8), zone) / 1000
                                 + lateHours * 3600)
            return s
        }
        var s: [Session] = []
        s += (0..<5).map { delivered("w\($0)", genre: .wedding, lateHours: 72) }      // 3 дня
        s += (0..<5).map { delivered("p\($0)", genre: .portrait, lateHours: 11) }     // меньше полудня — вовремя
        s += (0..<4).map { delivered("f\($0)", genre: .family, lateHours: 240) }      // четыре — мало
        s += (0..<5).map { delivered("r\($0)", genre: .report, lateHours: 13) }       // 0,54 → 1 день
        let rows = YearMath.lateGenres(s, zone: zone) { $0.day.adding(days: 7) }
        #expect(rows.map(\.genre) == [.wedding, .report])
        #expect(rows.map(\.days) == [3, 1])
    }

    @Test func searchFindsByStemNewestFirstAndHidesEvents() {
        var a = shoot("a", 2026, 3, 1); a.contact = "Ольга и Марк"
        var b = shoot("b", 2026, 9, 1); b.place = "Свадебный салон"
        var c = shoot("c", 2027, 1, 1, kind: .event); c.contact = "Ольга"
        var m = shoot("m", 2026, 5, 1, kind: .meet); m.contact = "ольга"
        let name: (Session) -> String = { _ in "Портрет" }
        #expect(YearMath.search("ольга", in: [a, b, c, m], eventsLayer: false, typeName: name).map(\.id) == ["m", "a"])
        #expect(YearMath.search("ольга", in: [a, b, c, m], eventsLayer: true, typeName: name).map(\.id) == ["c", "m", "a"])
        #expect(YearMath.search("  ", in: [a], eventsLayer: true, typeName: name).isEmpty)
        #expect(YearMath.search("портреты", in: [a], eventsLayer: true, typeName: name).map(\.id) == ["a"])
    }

    @Test func sparkKeepsZeroInScale() {
        let p = YearMath.sparkPoints([100, 200, 300])
        #expect(p.first == CGPoint(x: 4, y: 26.7))
        #expect(p.last == CGPoint(x: 316, y: 4))
    }
}

/// Корзина: удаление обратимо (инвариант 17), «Вернуть» держит запись, а не
/// номер в корзине, стирание — только «Очистить корзину».
@MainActor
@Suite struct PlannerBinTests {
    private func rec(_ id: String) -> Session {
        Session(id: id, day: CivilDate(year: 2026, month: 9, day: 1), start: 600, duration: 60, genre: .portrait)
    }

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

    private func model(_ snap: Snapshot) -> AppModel {
        AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                 locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
    }

    @Test func trashAndRestoreKeepPlaceAndStamp() {
        var s = Snapshot()
        s.sessions = [rec("a"), rec("b"), rec("c")]
        #expect(Bin.trash("b", in: &s, now: 1000)?.id == "b")
        #expect(s.sessions.map(\.id) == ["a", "c"])
        #expect(s.trashed.first?.index == 1 && s.trashed.first?.deletedAt == 1000)
        #expect(Bin.restore("b", in: &s, now: 2000))
        #expect(s.sessions.map(\.id) == ["a", "b", "c"])
        #expect(s.sessions[1].modifiedAt == 2000)
        #expect(s.trashed.isEmpty)
    }

    @Test func clearBuriesAndRestoreUnburies() {
        var s = Snapshot()
        s.sessions = [rec("a"), rec("b")]
        Bin.trash("a", in: &s, now: 1)
        Bin.trash("b", in: &s, now: 2)
        #expect(s.trashed.map(\.record.id) == ["b", "a"])      // новые первыми
        Bin.clear(&s, now: 3)
        #expect(s.trashed.isEmpty)
        guard case .array(let g)? = s.extra["graves"] else { Issue.record("теней нет"); return }
        #expect(g.count == 2)
    }

    @Test func undoBarReturnsItsOwnRecordNotTheNewest() {
        var s = Snapshot()
        s.sessions = [rec("a"), rec("b")]
        let app = model(s)
        app.trashSession(id: "a")
        let barForA = app.undo
        app.trashSession(id: "b")
        #expect(app.undo?.what == .session(id: "b"))
        #expect(app.undo?.token != barForA?.token)
        // Вернули «b» из листа — полоса гаснет: у веба она подняла бы «a».
        app.restoreSession(id: "b")
        #expect(app.undo == nil)
        #expect(app.sessions.map(\.id) == ["b"])
        app.takeUndo()
        #expect(app.sessions.map(\.id) == ["b"])
        #expect(app.trashed.map(\.record.id) == ["a"])
    }

    @Test func undoRestoresAndClearSilencesTheBar() {
        var s = Snapshot()
        s.sessions = [rec("a")]
        let app = model(s)
        app.trashSession(id: "a")
        app.takeUndo()
        #expect(app.sessions.map(\.id) == ["a"] && app.trashed.isEmpty && app.undo == nil)
        app.trashSession(id: "a")
        app.clearBin()
        #expect(app.undo == nil && app.trashed.isEmpty && app.sessions.isEmpty)
    }

    @Test func expiredTokenDoesNotHideANewerBar() {
        var s = Snapshot()
        s.sessions = [rec("a"), rec("b")]
        let app = model(s)
        app.trashSession(id: "a")
        let old = app.undo!.token
        app.trashSession(id: "b")
        app.expireUndo(old)
        #expect(app.undo?.what == .session(id: "b"))
    }

    @Test func blockRemovalCanBeUndoneInPlace() {
        var s = Snapshot()
        let day = CivilDate(year: 2026, month: 9, day: 1)
        s.blocks = [Block(id: "x", kind: .off, from: day), Block(id: "y", kind: .road, from: day)]
        let app = model(s)
        app.removeBlock(id: "x")
        #expect(app.blocks.map(\.id) == ["y"])
        // Слова «Выходной · убрано» — из каталога, его собирает только Xcode.
        if case .block(let b, let i)? = app.undo?.what { #expect(b.id == "x" && i == 0) }
        else { Issue.record("полоса «Вернуть» не про занятость") }
        app.takeUndo()
        #expect(app.blocks.map(\.id) == ["x", "y"])
    }

    @Test func blockSheetKeepsMidnightStart() {
        var s = Snapshot()
        var b = Block(id: "x", kind: .busy, from: CivilDate(year: 2026, month: 9, day: 1))
        b.start = 0; b.duration = 60
        s.blocks = [b]
        let app = model(s)
        app.openBlockSheet(editing: "x")
        // Веб `b.min || 600` открывал занятость с полуночи как 10:00.
        #expect(app.blockSheet?.block.start == 0)
        app.openBlockSheet(day: CivilDate(year: 2026, month: 9, day: 2), at: 13 * 60)
        #expect(app.blockSheet?.block.allDay == false && app.blockSheet?.block.duration == 120)
        #expect(app.blockSheet?.editing == false)
        #expect(app.blockSheet?.block.id.hasPrefix("b") == true)
    }

    @Test func trashSurvivesSnapshotRoundTrip() throws {
        var s = Snapshot()
        s.sessions = [rec("a")]
        Bin.trash("a", in: &s, now: 42)
        let back = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(s))
        #expect(back.trashed.map(\.record.id) == ["a"])
        #expect(back.trashed.first?.deletedAt == 42)
    }
}
