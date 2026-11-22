import Testing
import Foundation
import LightPlanCore
@testable import LightPlanDomain

/// 30и.15: малый виджет «окно неба» (Н2, Алексей 16.11). Небо, холмы, окошко календаря и записи ленты.
struct WidgetSmallSkyTests {
    private static let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    /// Часы Томска (UTC+7), октябрь 2026.
    private static func tsk(_ h: Int, _ m: Int = 0, day d: Int = 24) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }
    private static func shoot(_ id: String, _ from: Date, names: String = "Орловы", genre: String = "family") -> WidgetFeed.Shoot {
        .init(id: id, start: Moment(from).milliseconds, end: Moment(from.addingTimeInterval(7200)).milliseconds, title: "Семья", genre: genre, names: names)
    }
    private static let forecast: [WidgetFeed.Rating] = [
        .init(day: "2026-10-24", score: 62, quality: .good, sunrise: 34), .init(day: "2026-10-25", score: 82, quality: .excellent),
        .init(day: "2026-10-26", score: nil, quality: .fog), .init(day: "2026-10-27", score: 41, quality: .plain),
    ]
    private static func frame(at now: Date, shoots: [WidgetFeed.Shoot] = []) -> WidgetFrame {
        WidgetFeed(place: tomsk, shoots: shoots, forecast: forecast).frame(at: now)
    }

    // MARK: Небо

    @Test func theSunWalksFromTheLeftHillToTheRightOne() throws {
        let f = Self.frame(at: Self.tsk(13))
        let rise = try #require(f.day?.sunrise), set = try #require(f.day?.sunset)
        #expect(SmallSky.look(Self.frame(at: rise)).sun.map { abs($0) < 1e-9 } == true, "на восходе — на кромке левого холма")
        #expect(SmallSky.look(Self.frame(at: set)).sun.map { abs($0 - 1) < 1e-9 } == true, "на закате — на кромке правого")
        let mid = Date(timeIntervalSince1970: (rise.timeIntervalSince1970 + set.timeIntervalSince1970) / 2)
        #expect(SmallSky.look(Self.frame(at: mid)).sun.map { abs($0 - 0.5) < 1e-9 } == true, "в середине дня — в середине окна")
        #expect(SmallSky.look(f).sky == .day)
    }

    @Test func theSkyFollowsTheSunsHeight() throws {
        let set = try #require(Self.frame(at: Self.tsk(13)).day?.sunset)
        let dusk = SmallSky.look(Self.frame(at: set.addingTimeInterval(15 * 60)))
        #expect(dusk.sky == .twilight, "через 15 минут после заката — закатное небо")
        #expect(dusk.sun.map { $0 > 1 && $0 <= 1 + SmallSky.sunReach } == true, "Солнце уходит за правый холм, не дальше предела")
        let night = SmallSky.look(Self.frame(at: Self.tsk(21)))
        #expect(night.sky == .night && night.sun == nil, "ночью Солнца в окне нет")
        #expect((0...1).contains(night.moonCycle) && (0...1).contains(night.moonFraction))
        #expect(night.moonCycle == BigWidget.sky(Self.frame(at: Self.tsk(21)))?.moonCycle, "Луна та же, что на куполе большого")
        #expect(night.moonWaxing == (night.moonCycle < 0.5))
    }

    /// Места нет (пояс не читается): кадр пустой, и окна неба нет — малый рисует прежний вид с «—», а не небо без Солнца и Луны.
    @Test func withoutAPlaceThereIsNoSkyWindow() {
        let none = WidgetFeed.Spot(name: "Где-то", latitude: 0, longitude: 0, zone: "")
        let f = WidgetFeed(place: none, shoots: [], forecast: []).frame(at: Self.tsk(13))
        #expect(f.kind == .blank && !SmallSky.shows(f))
    }

    // MARK: Холмы

    @Test func theHillsCarryTodayUntilSunsetThenTomorrow() throws {
        let day = Self.frame(at: Self.tsk(13))
        let h = SmallSky.hills(day)
        #expect(h.rise.score == 34 && h.set.score == 62, "сегодняшние оценки рассвета и заката")
        #expect(h.rise.time == day.clock(try #require(day.day?.sunrise), in: day.zone))
        let evening = Self.frame(at: Self.tsk(21))
        let e = SmallSky.hills(evening)
        #expect(e.rise.time == evening.clock(try #require(evening.tomorrow?.sunrise), in: evening.zone), "после заката — завтрашний восход")
        #expect(e.set.score == 82 && e.rise.score == nil, "оценки завтрашнего дня; рассвета в прогнозе нет — числа нет")
    }

    // MARK: Окошко

    @Test func theWindowShowsTheNearestShootsDateWithItsNeighbours() {
        let f = Self.frame(at: Self.tsk(20), shoots: [Self.shoot("f", Self.tsk(11, day: 26)), Self.shoot("m", Self.tsk(10, day: 28), names: "Ольга+Паша", genre: "wedding")])
        guard case .shoot(let c) = SmallSky.window(f) else { Issue.record("ждали съёмку"); return }
        #expect(c.id == "f" && c.day == 26 && c.before == 25 && c.after == 27)
        #expect(c.line == "пн · 11:00" && c.names == "Орловы" && c.genre == "family")
    }

    @Test func theDateWheelWrapsOverTheEndOfTheMonth() {
        let f = Self.frame(at: Self.tsk(20, day: 29), shoots: [Self.shoot("x", Self.tsk(9, day: 31), names: "")])
        guard case .shoot(let c) = SmallSky.window(f) else { Issue.record("ждали съёмку"); return }
        #expect(c.day == 31 && c.before == 30 && c.after == 1, "за 31 октября идёт 1")
        #expect(c.names == "Семья", "без имён — название съёмки")
    }

    @Test func anEmptyWeekShowsThreeSunsetsAndPointsAtTheBest() {
        let f = Self.frame(at: Self.tsk(20))
        guard case .sunsets(let cells, let best) = SmallSky.window(f) else { Issue.record("ждали закаты"); return }
        #expect(cells.map(\.day) == ["вс", "пн", "вт"])
        #expect(cells.map(\.score) == [82, nil, 41], "часа заката в прогнозе нет — числа нет")
        #expect(best?.day == 0 && best?.event == .sunset, "рассветных баллов в этом прогнозе нет — лучший из закатов")
    }

    @Test func theBestDayIsTheHighestScoreAndTheEarlierOnATie() {
        #expect(SmallSky.best([41, 82, 82]) == 1)
        #expect(SmallSky.best([nil, 20, nil]) == 1)
        #expect(SmallSky.best([nil, nil, nil]) == nil, "баллов нет — указателя нет")
        #expect(SmallSky.best([]) == nil)
    }

    @Test func aRunningShootIsNotTheSkyWindow() {
        let live = Self.frame(at: Self.tsk(12), shoots: [Self.shoot("l", Self.tsk(11))])
        #expect(live.kind == .live && !SmallSky.shows(live), "идущую съёмку малый показывает кольцом")
        #expect(SmallSky.shows(Self.frame(at: Self.tsk(12))))
    }

    // MARK: Лента

    @Test func theSmallTimelineMovesTheSunEveryTenMinutesOnlyAroundTheDay() throws {
        let feed = WidgetFeed(place: Self.tomsk, shoots: [], forecast: Self.forecast)
        let now = Self.tsk(0, 5)
        let small = feed.timeline(from: now, shape: .small).dates
        let plain = Set(feed.timeline(from: now).dates)
        let added = small.filter { !plain.contains($0) }
        let f = feed.frame(at: Self.tsk(13))
        let rise = try #require(f.day?.sunrise), set = try #require(f.day?.sunset)
        #expect(added.allSatisfy { $0 >= rise.addingTimeInterval(-7200 - 1) && $0 <= set.addingTimeInterval(7200) || $0 > Self.tsk(0, day: 25) },
                "сегодня записи только от двух часов до восхода до двух после заката")
        let noonHour = added.filter { $0 >= Self.tsk(12) && $0 < Self.tsk(13) }
        #expect(noonHour.count == 6, "в светлый час — шесть записей: \(noonHour.count)")
        #expect(added.filter { $0 >= Self.tsk(1) && $0 < Self.tsk(3) }.isEmpty, "глубокой ночью Солнце не двигается")
        #expect(small.count <= WidgetFeed.entryLimit)
    }
}
