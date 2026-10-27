import Testing
import Foundation
@testable import LightPlanDomain
import LightPlanCore

/// Шаг 30б.2в-5: средний виджет Braun без маршрута — «Семья виджетов» Алексея (27.10): Б (съёмка идёт, маршрута нет), Г (съёмка сегодня
/// впереди), Д (день без съёмок), Е (вечер после заката). Тут правила и файл; картинки и числа раскладки — в `WidgetBraunIdleViewTests`.
struct WidgetBraunIdleTests {

    private let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    /// Часы Томска (+7) 25.10.2026 (воскресенье, как «сегодня» на доске) плюс `day − 25` суток.
    private func tsk(_ h: Int, _ m: Int = 0, day d: Int = 25) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }
    private func ms(_ d: Date) -> Int64 { Moment(d).milliseconds }
    private func shoot(_ id: String, from: Date, to: Date, names: String? = nil, genre: String? = "wedding",
                       stops: [WidgetFeed.Stop] = [], title: String = "Свадьба") -> WidgetFeed.Shoot {
        WidgetFeed.Shoot(id: id, start: ms(from), end: ms(to), title: title, stops: stops, genre: genre, names: names)
    }
    private func feed(_ shoots: [WidgetFeed.Shoot] = [], forecast: [WidgetFeed.Rating] = []) -> WidgetFeed {
        WidgetFeed(place: tomsk, shoots: shoots, forecast: forecast)
    }
    private let today = CivilDate(year: 2026, month: 10, day: 25)

    // MARK: Файл: оценка заката

    @Test func anOldFileWithoutAForecastStillLoads() throws {
        let old = Data(#"{"place":{"name":"Томск","latitude":56.5,"longitude":85,"zone":"Asia/Tomsk"},"shoots":[],"lang":"ru","clock12":false}"#.utf8)
        let f = try #require(WidgetFeed.decode(old))
        #expect(f.forecast.isEmpty)
        #expect(f.rating(on: today) == nil)
        let stub = Data(#"{"place":{"name":"Томск","latitude":56.5,"longitude":85,"zone":"Asia/Tomsk"}}"#.utf8)
        #expect(WidgetFeed.decode(stub)?.forecast.isEmpty == true)
    }

    @Test func theForecastRoundTripsAndAForeignQualityCodeDoesNotSpoilTheFile() throws {
        let f = feed(forecast: [.init(day: "2026-10-25", score: 62, quality: .good), .init(day: "2026-10-26", score: nil, quality: .fog)])
        #expect(WidgetFeed.decode(f.encoded()) == f)
        #expect(f.rating(on: today)?.score == 62 && f.rating(on: today)?.category == .good)
        #expect(f.rating(on: today.adding(days: 1))?.score == nil, "часа заката в прогнозе нет — есть только категория")
        let future = Data(#"{"place":{"name":"","latitude":56.5,"longitude":85,"zone":"Asia/Tomsk"},"forecast":[{"day":"2026-10-25","score":70,"quality":"aurora"}]}"#.utf8)
        let g = try #require(WidgetFeed.decode(future))
        #expect(g.rating(on: today)?.category == nil, "незнакомая категория — не знаем слова, но файл читается")
    }

    @Test func makeCarriesTheForecastAndNothingIsInventedWithout() {
        let r = WidgetFeed.Rating(day: "2026-10-25", score: 80, quality: .excellent)
        let with = WidgetFeed.make(place: tomsk, sessions: [], studios: [], spots: [], now: tsk(9), manualEnd: false,
                                   offset: { _, _ in 7 }, title: { _ in "" }, words: .init(), forecast: [r], lang: "ru", clock12: false)
        #expect(with.forecast == [r])
        let without = WidgetFeed.make(place: tomsk, sessions: [], studios: [], spots: [], now: tsk(9), manualEnd: false,
                                      offset: { _, _ in 7 }, title: { _ in "" }, words: .init(), lang: "ru", clock12: false)
        #expect(without.forecast.isEmpty)
    }

    @Test func theRatingLineExistsOnlyWithATodayForecast() {
        let none = feed().frame(at: tsk(14))
        #expect(none.rating == nil && BraunIdle.ratingWord(none) == nil, "прогноза нет — строки оценки нет")
        let tomorrowOnly = feed(forecast: [.init(day: "2026-10-26", score: 62, quality: .good)]).frame(at: tsk(14))
        #expect(tomorrowOnly.rating == nil && BraunIdle.ratingWord(tomorrowOnly) == nil, "завтрашняя оценка сегодняшней не подставляется")
        let ok = feed(forecast: [.init(day: "2026-10-25", score: 62, quality: .good)]).frame(at: tsk(14))
        #expect(ok.rating?.score == 62 && BraunIdle.ratingWord(ok) == "хороший")
    }

    @Test func ratingWordsAreTheFiveOfTheBoardAndTheAppsWordsWin() {
        let w = WidgetFeed.Words()
        #expect(DayQuality.allCases.map { w.rating($0) } == ["отличный", "хороший", "обычный", "плохой", "туман"])
        #expect(WidgetFeed.Words([.rateGood: "good"]).rating(.good) == "good")
    }

    @Test func daysAheadAreSaidInTheRightCaseAndTheAppsPhrasesWin() {
        let w = WidgetFeed.Words()
        #expect([2, 3, 4, 5, 11, 21, 22].map { w.inDays($0) } ==
                ["через 2 дня", "через 3 дня", "через 4 дня", "через 5 дней", "через 11 дней", "через 21 день", "через 22 дня"])
        var own = WidgetFeed.Words()
        own.table["inDays.3"] = "in 3 days"
        #expect(own.inDays(3) == "in 3 days" && own.inDays(2) == "через 2 дня")
    }

    // MARK: Какое состояние

    @Test func aShootLaterTodayIsTheShootAheadFormAndOnlyThenThePerimeterHasTicks() {
        let f = feed([shoot("w", from: tsk(12), to: tsk(23))]).frame(at: tsk(9, 30))
        #expect(f.kind == .upcoming && BraunIdle.shootToday(f) && BraunIdle.form(f) == .shootAhead)
        let tomorrow = feed([shoot("w", from: tsk(12, day: 26), to: tsk(23, day: 26))]).frame(at: tsk(9, 30))
        #expect(tomorrow.kind == .upcoming && !BraunIdle.shootToday(tomorrow), "завтрашняя съёмка периметр не рисует")
        #expect(BraunIdle.form(tomorrow) == .noShoots)
        let empty = feed().frame(at: tsk(14))
        #expect(!BraunIdle.shootToday(empty) && BraunIdle.form(empty) == .noShoots)
    }

    @Test func afterTheSunsetItIsTheEveningFormWithTomorrowsSunrise() throws {
        let f0 = feed()
        let set = try #require(f0.frame(at: tsk(12)).day?.sunset)
        let before = f0.frame(at: set.addingTimeInterval(-60)), after = f0.frame(at: set.addingTimeInterval(60))
        #expect(BraunIdle.form(before) == .noShoots && !BraunIdle.isNight(before))
        #expect(BraunIdle.form(after) == .evening && BraunIdle.isNight(after))
        #expect(after.tomorrow?.sunrise != nil && after.tomorrow?.day == today.adding(days: 1))
        // Вечером перед съёмкой левая колонка вечерняя, а риски остаются (съёмка сегодня).
        let late = feed([shoot("e", from: set.addingTimeInterval(3600), to: set.addingTimeInterval(7200))]).frame(at: after.now)
        #expect(BraunIdle.shootToday(late) && BraunIdle.isNight(late))
    }

    @Test func aShootRunningWithoutARouteIsTheBareForm() {
        let bare = feed([shoot("w", from: tsk(12), to: tsk(24, 30))]).frame(at: tsk(15, 18))
        #expect(bare.kind == .live && BraunIdle.isBare(bare))
        let stop = WidgetFeed.Stop(at: ms(tsk(12)), name: "Сборы", sign: "makeup")
        let routed = feed([shoot("w", from: tsk(12), to: tsk(24, 30), stops: [stop])]).frame(at: tsk(15, 18))
        #expect(!BraunIdle.isBare(routed), "есть точки — барабан маршрута, как раньше")
        #expect(!BraunIdle.isBare(feed().frame(at: tsk(15, 18))))
    }

    // MARK: Б — круг на всю съёмку

    @Test func theCircleOfTheBareFormCountsTheWholeShoot() {
        // Доска: свадьба 12:00–00:30, в 15:18 осталось 9 ч 12 мин из 12 ч 30 мин → горит 44 точки.
        #expect(BraunIdle.wholeShootLit(left: (9 * 60 + 12) * 60, total: 750 * 60) == 44)
        #expect(BraunIdle.wholeShootLit(left: 750 * 60, total: 750 * 60) == 60 && BraunIdle.wholeShootLit(left: 0, total: 750 * 60) == 0)
        #expect(BraunIdle.wholeShootLit(left: 10, total: 0) == 0)
        let nine = BraunDial.countdown(minutes: 552), ten = BraunDial.countdown(minutes: 10 * 60 + 12)
        #expect(nine == [BraunDial.Part(9, .hour), BraunDial.Part(12, .minute)])
        #expect(BraunIdle.countdownSizes(diameter: 116, parts: nine) == (22, 13), "«9 ч 12 мин» — крупно")
        #expect(BraunIdle.countdownSizes(diameter: 116, parts: ten) == (20, 12), "обе части двузначные — мельче, как `dial()` доски")
        #expect(BraunIdle.countdownSizes(diameter: 104, parts: nine) == (20, 12), "на 104 всегда 20 / 12")
        #expect(BraunIdle.countdownSizes(diameter: 116, parts: BraunDial.countdown(minutes: 42)) == (22, 13))
    }

    @Test func theLightDrumCentresOnTheNextEventAndReachesTomorrowsDawn() throws {
        let f = feed()
        let at = f.frame(at: tsk(15, 18))
        let d = BraunIdle.lightDrum(at)
        #expect(d.map { $0?.kind } == [nil, .sunrise, .golden, .sunset, nil], "доска, 15:18: рассвет, золотой час в центре, закат; завтрашний рассвет днём не лезет")
        #expect(d.allSatisfy { $0?.tomorrow != true })
        let dawn = f.frame(at: tsk(5))
        #expect(BraunIdle.lightDrum(dawn).map { $0?.kind } == [nil, nil, .sunrise, .golden, .sunset], "до рассвета в центре сегодняшний рассвет")
        let set = try #require(at.day?.sunset)
        let night = BraunIdle.lightDrum(f.frame(at: set.addingTimeInterval(300)))
        #expect(night.map { $0?.kind } == [.golden, .sunset, .sunrise, nil, nil] && night[2]?.tomorrow == true, "после заката в центре завтрашний рассвет")
    }

    @Test func theDrumRowsAreOfOneHeightAndTheEdgesFade() {
        let s = BraunIdle.drumSlots(diameter: 116, centerLines: 1)
        #expect(s.map(\.y) == [0, 22, 44, 72, 94] && s.map(\.height) == [22, 22, 28, 22, 22], "круг 116: строки по 22, центр 28 на середине")
        let two = BraunIdle.drumSlots(diameter: 104, centerLines: 2)
        #expect(two.map(\.height) == [15.5, 15.5, 42, 15.5, 15.5] && two[2].y == 31, "круг 104 и центр в две строки: (104 − 42) / 4 = 15,5")
        let fade = BraunIdle.drumFade(height: 116)
        #expect(fade.map(\.at) == [0, 4, 9, 15, 20, 26, 90, 96, 101, 107, 112, 116] && fade.map(\.opacity) == [0, 0.3, 0.55, 0.8, 0.95, 1, 1, 0.95, 0.8, 0.55, 0.3, 0])
    }

    // MARK: Левая колонка: цвет времени

    @Test func lightTimesAreDimThenAmberThenPlain() throws {
        let f = feed().frame(at: tsk(9, 30))
        let d = try #require(f.day)
        #expect(BraunIdle.roles(now: f.now, [d.sunrise, d.golden, d.sunset]) == [.past, .next, .far], "09:30 — рассвет прошёл, золотой час ближайший")
        let noon = tsk(13)
        #expect(BraunIdle.roles(now: noon, [d.sunrise, d.golden, d.sunset]) == [.past, .next, .far])
        let dusk = try #require(d.golden).addingTimeInterval(60)
        #expect(BraunIdle.roles(now: dusk, [d.sunrise, d.golden, d.sunset]) == [.past, .past, .next])
        let after = try #require(d.sunset).addingTimeInterval(60)
        #expect(BraunIdle.roles(now: after, [d.sunrise, d.golden, d.sunset]) == [.past, .past, .past], "после заката всё тусклое")
        #expect(BraunIdle.roles(now: f.now, [nil, nil, nil]) == [.past, .past, .past])
        #expect(BraunIdle.gaugeLevel(score: 62) == 0.62 && BraunIdle.gaugeLevel(score: 140) == 1 && BraunIdle.gaugeLevel(score: -3) == 0)
        #expect(BraunIdle.gaugeMarks == [20, 40, 60, 80])
    }

    // MARK: Неделя справа

    @Test func theWeekListIsTheNextSevenDaysThreeRowsAtMost() {
        let shoots = [
            shoot("a", from: tsk(11, day: 28), to: tsk(13, day: 28), names: "Семья Ивановых", genre: "family", title: "Семья"),
            shoot("b", from: tsk(13, day: 30), to: tsk(15, day: 30), names: "Мария и Дмитрий"),
            shoot("c", from: tsk(10, day: 31), to: tsk(12, day: 31)),
            shoot("d", from: tsk(10, day: 1), to: tsk(12, day: 1)),
            shoot("late", from: tsk(10, day: 2), to: tsk(12, day: 2)),   // 8-е сутки: за неделей
        ]
        let f = feed(shoots).frame(at: tsk(14))
        #expect(f.week.map(\.id) == ["a", "b", "c"], "три строки; четвёртая и восьмые сутки в список не идут")
        let week = feed([shoots[3], shoots[4]]).frame(at: tsk(14))
        #expect(week.week.isEmpty && BraunIdle.weekRows(week).isEmpty, "съёмка на восьмые сутки — недели без съёмок")
    }

    @Test func weekRowsSayTheDayOnTheSecondLine() {
        let f = feed([
            shoot("a", from: tsk(11, day: 28), to: tsk(13, day: 28), names: "Семья Ивановых", genre: "family", title: "Семья"),
            shoot("b", from: tsk(13, day: 30), to: tsk(15, day: 30), names: "Мария и Дмитрий"),
        ]).frame(at: tsk(14))
        let rows = BraunIdle.weekRows(f)
        #expect(rows.map(\.line2) == ["ср 28 · 11:00 · через 3 дня", "пт 30 · 13:00"], "«через 3 дня» — только у ближайшей, в конце второй строки")
        #expect(rows.map(\.names) == ["Семья Ивановых", "Мария и Дмитрий"] && rows.map(\.genre) == ["family", "wedding"])
        #expect(rows[0].near && !rows[1].near)

        let g = feed([shoot("w", from: tsk(12), to: tsk(24, 30), names: "Анна и Игорь"),
                      shoot("a", from: tsk(11, day: 28), to: tsk(13, day: 28), names: "Семья Ивановых", genre: "family")]).frame(at: tsk(9, 30))
        #expect(BraunIdle.weekRows(g).map(\.line2) == ["сегодня · 12:00", "ср 28 · 11:00"], "ближайшая сегодня — без «через», день словом")
        let tom = feed([shoot("t", from: tsk(11, day: 26), to: tsk(13, day: 26), names: "Ольга Ветрова", genre: "portrait")]).frame(at: tsk(14))
        #expect(BraunIdle.weekRows(tom).first?.line2 == "завтра · 11:00")
        // Имён нет — название жанра.
        let anon = feed([shoot("n", from: tsk(11, day: 27), to: tsk(13, day: 27))]).frame(at: tsk(14))
        #expect(BraunIdle.weekRows(anon).first?.names == "Свадьба")
    }

    @Test func anEmptyWeekIsOneLineUntilTheLastDay() {
        let f = feed().frame(at: tsk(14))
        #expect(BraunIdle.emptyWeekLine(f) == "до сб 31 съёмок нет", "25.10 + 6 суток = суббота 31.10 — слово доски")
        let busy = feed([shoot("a", from: tsk(11, day: 28), to: tsk(13, day: 28))]).frame(at: tsk(14))
        #expect(BraunIdle.emptyWeekLine(busy) == nil, "съёмки есть — строки нет")
        let bad = WidgetFeed(place: .init(name: "", latitude: 0, longitude: 0, zone: "Nowhere/Void")).frame(at: tsk(14))
        #expect(BraunIdle.emptyWeekLine(bad) == nil)
        var own = feed()
        own.words.table["noShootsUntil"] = "no shoots until {d}"
        #expect(BraunIdle.emptyWeekLine(own.frame(at: tsk(14))) == "no shoots until сб 31", "слово — из файла")
    }

    @Test func rowHeightsKeepThreeRowsInsideThePlate() {
        let big = BraunIdle.weekRowHeights(plateHeight: 170), small = BraunIdle.weekRowHeights(plateHeight: 158)
        func total(_ h: (near: Double, other: Double)) -> Double { h.near + 2 * h.other + 2 * BraunIdle.weekRowGap }
        #expect(big.near == 46 && big.other == 40 && total(big) == 130 && total(big) <= 170 - 32)
        #expect(total(small) <= 158 - 32, "на 158 pt три строки тоже влезают между полями")
    }

    // MARK: Лента

    @Test func theMediumTimelineMovesTheDayRingOnlyOnAShootDay() throws {
        let withShoot = feed([shoot("w", from: tsk(14), to: tsk(23))])
        let now = tsk(9, 30)
        let medium = withShoot.timeline(from: now, shape: .medium).dates
        let tenMinute = medium.filter { $0 > now && Int($0.timeIntervalSince1970) % 600 == 0 }
        #expect(tenMinute.count >= 40, "риски светового дня идут по ленте раз в 10 минут: \(tenMinute.count)")
        let none = feed().timeline(from: now, shape: .medium).dates, plain = feed().timeline(from: now).dates
        #expect(none == plain, "без съёмки сегодня периметр чист — лишних записей нет")
        // Лента не длиннее предела.
        #expect(medium.count <= WidgetFeed.entryLimit)
    }
}
