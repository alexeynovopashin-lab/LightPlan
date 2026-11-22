import Testing
import Foundation
@testable import LightPlanDomain
import LightPlanCore

/// Шаг 31.7 «Рассвет в виджетах и планировщике» (Алексей 19.11: вариант «А» на оба вопроса эскиза `dawn_31_7_sketch_2026-11-19.html`
/// и все места «зеркально закату»). Томск 25.10.2026: утренний золотой час ≈ 07:30–09:00, вечерний ≈ 16:20–17:50 (точные — из `light(on:)`).
struct DawnWidgetsTests {

    private let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    private let today = CivilDate(year: 2026, month: 10, day: 25)
    private func tsk(_ h: Int, _ m: Int = 0, day d: Int = 25) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }
    private func ms(_ d: Date) -> Int64 { Moment(d).milliseconds }
    private func feed(_ shoots: [WidgetFeed.Shoot] = [], forecast: [WidgetFeed.Rating] = []) -> WidgetFeed {
        WidgetFeed(place: tomsk, shoots: shoots, forecast: forecast)
    }
    private func light(_ off: Int = 0) throws -> WidgetFeed.DayLight { try #require(tomsk.light(on: today.adding(days: off))) }

    // MARK: Свет дня

    @Test("утренний золотой час — от −4° до +6°, раньше восхода; у события свой")
    func theMorningGoldenHourIsTheDawnPairOfTheEveningOne() throws {
        let l = try light()
        let m = try #require(l.morningGolden), r = try #require(l.sunrise), end = try #require(l.goldenEnd)
        #expect(m < r && r < end, "утренний золотой час обнимает восход, как вечерний — закат")
        let minutes = end.timeIntervalSince(m) / 60
        #expect(minutes > 60 && minutes < 120, "у Томска в октябре — час-полтора: \(minutes)")
        #expect(l.goldenStart(.dawn) == m && l.goldenStart(.sunset) == l.golden)
        #expect(l.goldenNow(at: tsk(6)) == m, "ночью до рассвета — утренний")
        #expect(l.goldenNow(at: end.addingTimeInterval(-60)) == m, "до конца утреннего золотого часа — утренний")
        #expect(l.goldenNow(at: end.addingTimeInterval(60)) == l.golden, "после — вечерний")
    }

    // MARK: Вопрос 1: три дня вперёд

    @Test("три дня вперёд: у каждого дня время и балл рассвета и заката")
    func theDaysAheadCarryTheDawnAndTheSunset() throws {
        let fc: [WidgetFeed.Rating] = [
            .init(day: "2026-10-26", score: 72, quality: .good, sunrise: 48),
            .init(day: "2026-10-27", score: 35, quality: .plain, sunrise: 81),
            .init(day: "2026-10-28", score: nil, quality: .poor, sunrise: nil),
        ]
        let f = feed(forecast: fc).frame(at: tsk(14))
        let rows = BraunIdle.sunsetRows(f)
        #expect(rows.map(\.riseScore) == [48, 81, nil] && rows.map(\.score) == [72, 35, nil])
        #expect(rows.map(\.word) == [nil, nil, "серый"], "слово неба — только когда нет ни одного балла")
        let rise = try #require(f.ahead.first?.sunrise)
        #expect(rise == (try light(1)).sunrise)
        #expect(rows.first?.riseTime == f.clock(rise, in: f.zone) && rows.allSatisfy { $0.riseTime.contains(":") })
        // Один балл есть — слова нет, второй — «—» у вида.
        let half = BraunIdle.sunsetRows(feed(forecast: [.init(day: "2026-10-26", score: nil, quality: .good, sunrise: 60)]).frame(at: tsk(14)))
        #expect(half.first?.word == nil && half.first?.riseScore == 60 && half.first?.score == nil)
    }

    @Test("малый: флажок над лучшим из шести баллов, у ничьей — ранний")
    func theSmallFlagPointsAtTheBestOfSixScores() throws {
        let fc: [WidgetFeed.Rating] = [
            .init(day: "2026-10-26", score: 72, quality: .good, sunrise: 48),
            .init(day: "2026-10-27", score: 35, quality: .plain, sunrise: 81),
            .init(day: "2026-10-28", score: 64, quality: .good, sunrise: 20),
        ]
        guard case .sunsets(let cells, let best) = SmallSky.window(feed(forecast: fc).frame(at: tsk(14))) else { Issue.record("ждали дни"); return }
        #expect(cells.map(\.dawn) == [48, 81, 20] && cells.map(\.score) == [72, 35, 64])
        #expect(best == SmallSky.Best(day: 1, event: .dawn), "лучший — рассвет вт 27 (81), а не лучший закат пн 26 (72)")
        let tie: [WidgetFeed.Rating] = [.init(day: "2026-10-26", score: 70, quality: .good, sunrise: 70)]
        guard case .sunsets(_, let b2) = SmallSky.window(feed(forecast: tie).frame(at: tsk(14))) else { return }
        #expect(b2 == SmallSky.Best(day: 0, event: .dawn), "ничья в дне — рассвет, он раньше")
    }

    // MARK: Вопрос 2: одно время золотого часа

    @Test("средний «◐»: утром утренний, днём вечерний, после заката — завтрашний утренний")
    func theMediumGoldenRowFollowsTheEventOnTopOfLight() throws {
        let l = try light(), t = try light(1)
        let end = try #require(l.goldenEnd), set = try #require(l.sunset)
        #expect(BraunIdle.golden(feed().frame(at: tsk(6))) == l.morningGolden)
        #expect(BraunIdle.golden(feed().frame(at: end.addingTimeInterval(-60))) == l.morningGolden)
        #expect(BraunIdle.golden(feed().frame(at: end.addingTimeInterval(60))) == l.golden)
        #expect(BraunIdle.golden(feed().frame(at: set.addingTimeInterval(60))) == t.morningGolden, "30.10: после заката виджет — о завтрашнем рассвете")
    }

    @Test("большой: середина ножек — тот же золотой час, но после заката остаётся сегодняшний вечерний")
    func theBigFeetGoldenStaysOnToday() throws {
        let l = try light()
        let set = try #require(l.sunset)
        #expect(BigWidget.golden(feed().frame(at: tsk(7))) == l.morningGolden)
        #expect(BigWidget.golden(feed().frame(at: tsk(13))) == l.golden)
        #expect(BigWidget.golden(feed().frame(at: set.addingTimeInterval(600))) == l.golden)
    }

    @Test("роли строк: ближайшее — самое раннее будущее, даже если оно ниже по месту")
    func rolesPickTheEarliestFutureTime() throws {
        let l = try light()
        let now = tsk(6)
        let roles = BraunIdle.roles(now: now, [l.sunrise, l.morningGolden, l.sunset])
        #expect(roles == [.far, .next, .far], "утренний золотой час (◐) раньше восхода (↑) — он и янтарный")
        #expect(BraunIdle.roles(now: now, [nil, l.morningGolden, l.sunset]) == [.past, .next, .far])
    }

    // MARK: Зеркала

    @Test("круг экрана блокировки считает до ближайшего золотого часа")
    func theLockCircleCountsToTheNearestGoldenHour() throws {
        let l = try light(), t = try light(1)
        let m = try #require(l.morningGolden), g = try #require(l.golden)
        let dawn = try #require(feed().frame(at: tsk(5)).nextGolden)
        #expect(dawn.at == m && dawn.from < m && m.timeIntervalSince(dawn.from) == 12 * 3600, "утром — до утреннего; дуга — от 12 ч до него")
        let day = try #require(feed().frame(at: tsk(12)).nextGolden)
        #expect(day.at == g && day.from == l.sunrise, "днём — до вечернего, дуга от восхода, как до 31.7")
        let eve = try #require(feed().frame(at: g.addingTimeInterval(60)).nextGolden)
        #expect(eve.at == t.morningGolden && eve.from == g, "после начала вечернего — до завтрашнего утреннего")
        // Лента круга: минуты и до утреннего.
        let line = feed().timeline(from: tsk(5), limit: 1000, shape: .circular).dates
        #expect(line.contains { $0 > tsk(5) && $0 < m && abs($0.timeIntervalSince(tsk(6))) < 1 }, "06:00 — минута отсчёта до утреннего")
    }

    @Test("строка и плашка съёмки с «Рассветом»: утренний золотой час, пока не взошло солнце")
    func aDawnShootGetsTheMorningGoldenHour() throws {
        let l = try light()
        let m = try #require(l.morningGolden), rise = try #require(l.sunrise)
        let dawn = WidgetFeed.Shoot(id: "d", start: ms(tsk(7)), end: ms(tsk(10)), title: "Портрет", wantsSunrise: true)
        #expect(feed([dawn]).frame(at: tsk(5)).primary?.golden == m)
        #expect(feed([dawn]).frame(at: rise.addingTimeInterval(-60)).primary?.golden == m)
        #expect(feed([dawn]).frame(at: rise.addingTimeInterval(60)).primary?.golden == nil, "солнце взошло — золотой час рассвета не «нужен»")
        let none = WidgetFeed.Shoot(id: "n", start: ms(tsk(7)), end: ms(tsk(10)), title: "Портрет")
        #expect(feed([none]).frame(at: tsk(5)).primary?.golden == nil, "без пожелания — без золотого часа, как было")
        // Оба пожелания: по началу съёмки — вечерняя съёмка берёт вечерний.
        let both = WidgetFeed.Shoot(id: "b", start: ms(tsk(15)), end: ms(tsk(18)), title: "Портрет", wantsSunset: true, wantsSunrise: true)
        #expect(feed([both]).frame(at: tsk(12)).primary?.golden == l.golden)
        let bothAM = WidgetFeed.Shoot(id: "a", start: ms(tsk(7)), end: ms(tsk(10)), title: "Портрет", wantsSunset: true, wantsSunrise: true)
        #expect(feed([bothAM]).frame(at: tsk(5)).primary?.golden == m)
    }

    @Test("плашка съёмки: точка «Золотой» и отсчёт у утренней съёмки с «Рассветом»")
    func theActivityGetsAMorningGoldenPoint() throws {
        let l = try light()
        let m = try #require(l.morningGolden)
        let stops = [WidgetFeed.Stop(at: ms(tsk(7)), name: "сбор"), WidgetFeed.Stop(at: ms(tsk(9, 30)), name: "кафе")]
        let s = WidgetFeed.Shoot(id: "d", start: ms(tsk(7)), end: ms(tsk(10)), title: "Портрет", stops: stops, wantsSunrise: true)
        let f = ActivityFrame.make(feed: feed([s]), shoot: s, now: tsk(7, 5))
        let gold = try #require(f.points.first { $0.gold })
        #expect(gold.at == ms(m) && f.points.map(\.gold) == [false, true, false], "сбор · ◐ Золотой · кафе")
        #expect(f.next?.to == ms(m), "отсчёт до золотого часа")
        let plain = WidgetFeed.Shoot(id: "p", start: ms(tsk(7)), end: ms(tsk(10)), title: "Портрет", stops: stops)
        #expect(ActivityFrame.make(feed: feed([plain]), shoot: plain, now: tsk(7, 5)).points.allSatisfy { !$0.gold })
    }

    @Test("файл: «Рассвет» пишется, старый файл без ключа читается")
    func theFileCarriesTheDawnWish() throws {
        var a = Session(id: "a", day: today, start: 7 * 60, end: 10 * 60, genre: .portrait)
        a.wishes = [.sunrise]
        let b = Session(id: "b", day: today, start: 12 * 60, end: 13 * 60, genre: .portrait)
        let f = WidgetFeed.make(place: tomsk, sessions: [a, b], studios: [], spots: [], now: tsk(5), manualEnd: false,
                                offset: { _, _ in 7 }, title: { _ in "x" }, words: .init(), lang: "ru", clock12: false)
        #expect(f.shoots.map(\.wantsDawn) == [true, false])
        #expect(WidgetFeed.decode(f.encoded()) == f)
        let json = String(decoding: f.encoded(), as: UTF8.self)
        #expect(json.components(separatedBy: "wantsSunrise").count == 2, "ключ — только у съёмки с «Рассветом»")
        let old = Data(#"{"place":{"name":"Т","latitude":56.5,"longitude":85,"zone":"Asia/Tomsk"},"shoots":[{"id":"x","start":0,"end":1,"open":false,"title":"t","place":"","wantsSunset":true,"rents":[],"stops":[]}]}"#.utf8)
        #expect(WidgetFeed.decode(old)?.shoots.first?.wantsDawn == false)
    }

    @Test("лента: начало утреннего золотого часа — момент смены плашки")
    func theTimelineWakesAtTheMorningGoldenHour() throws {
        let m = try #require(try light(1).morningGolden)
        #expect(feed().changes(from: tsk(20)).contains(m))
    }
}
