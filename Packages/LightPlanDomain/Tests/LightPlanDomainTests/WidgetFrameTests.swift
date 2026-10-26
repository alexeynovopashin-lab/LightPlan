import Testing
import Foundation
@testable import LightPlanDomain
import LightPlanCore

/// Шаг 30б.2: что виджет показывает в каждый момент — по словам Алексея 24.10 («Нет съемок — рассвет, затем закат.
/// Есть съемки — ближайшая и свет, если он нужен; во время съемки — отсчёт студийного времени, следующая точка, маршрут»).
struct WidgetFrameTests {

    private let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    private let day = CivilDate(year: 2026, month: 10, day: 24)

    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    /// Часы Томска (+7) 24.10 → момент.
    private func tsk(_ h: Int, _ min: Int = 0, day d: Int = 24) -> Date { utc(2026, 10, d, h, min).addingTimeInterval(-7 * 3600) }
    private func ms(_ d: Date) -> Int64 { Moment(d).milliseconds }

    private func shoot(_ id: String = "s1", from: Date, to: Date, sunset: Bool = false, rents: [WidgetFeed.Rent] = [],
                       stops: [WidgetFeed.Stop] = [], open: Bool = false, spot: WidgetFeed.Spot? = nil) -> WidgetFeed.Shoot {
        WidgetFeed.Shoot(id: id, start: ms(from), end: ms(to), open: open, title: "Свадьба", place: "Набережная",
                         spot: spot, wantsSunset: sunset, rents: rents, stops: stops)
    }
    private func feed(_ shoots: [WidgetFeed.Shoot] = []) -> WidgetFeed { WidgetFeed(place: tomsk, shoots: shoots) }

    // MARK: Нет съёмок — рассвет, потом закат

    @Test func freeDayIsDawnThenSunsetThenTomorrowsDawn() throws {
        let f = feed()
        let l = try #require(tomsk.light(on: day))
        let rise = try #require(l.sunrise), set = try #require(l.sunset)

        let before = f.frame(at: rise.addingTimeInterval(-600))
        #expect(before.kind == .light)
        #expect(before.light?.kind == .sunrise && before.light?.at == rise && before.light?.dayOffset == 0)

        let between = f.frame(at: rise.addingTimeInterval(600))
        #expect(between.light?.kind == .sunset && between.light?.at == set)

        let after = f.frame(at: set.addingTimeInterval(600))
        let next = try #require(tomsk.light(on: day.adding(days: 1))?.sunrise)
        #expect(after.light?.kind == .sunrise && after.light?.at == next && after.light?.dayOffset == 1)
        // Томск 24.10: золотой час с 17:02 (замер спайка), закат через час без нескольких минут — 17:50…18:05.
        let local = set.timeIntervalSince(tsk(0)) / 60
        #expect((17 * 60 + 50)...(18 * 60 + 5) ~= Int(local), "закат \(local) мин от полуночи")
    }

    @Test func polarDayAndNightGiveAWordNotATime() {
        let tromso = WidgetFeed.Spot(name: "Tromsø", latitude: 69.6496, longitude: 18.956, zone: "Europe/Oslo")
        let june = WidgetFeed(place: tromso).frame(at: utc(2026, 6, 21, 12))
        #expect(june.light?.kind == .polarDay && june.light?.at == nil)
        let dec = WidgetFeed(place: tromso).frame(at: utc(2026, 12, 21, 12))
        #expect(dec.light?.kind == .polarNight && dec.light?.at == nil)
    }

    @Test func nothingYetWithoutAPlace() {
        let bad = WidgetFeed(place: .init(name: "", latitude: 0, longitude: 0, zone: "Nowhere/Void"))
        #expect(bad.frame(at: utc(2026, 10, 24, 5)).kind == .blank)
    }

    // MARK: Есть съёмка — ближайшая и свет, если он нужен

    @Test func todaysShootTakesThePlateAndBringsLightOnlyIfItAsksForIt() throws {
        let want = feed([shoot(from: tsk(15), to: tsk(19), sunset: true)])
        let f = want.frame(at: tsk(9))
        #expect(f.kind == .upcoming)
        #expect(f.primary?.shoot.id == "s1" && f.primary?.dayOffset == 0)
        let golden = try #require(f.primary?.golden)
        #expect(abs(golden.timeIntervalSince(tsk(17, 2).addingTimeInterval(48))) < 180)
        #expect(f.url == WidgetFeed.shootURL("s1"))

        let dull = feed([shoot(from: tsk(15), to: tsk(19), sunset: false)]).frame(at: tsk(9))
        #expect(dull.primary?.golden == nil)
    }

    @Test func goldenLineStaysUntilSunsetThenGoes() throws {
        let f = feed([shoot(from: tsk(15), to: tsk(19), sunset: true)])
        let set = try #require(tomsk.light(on: day)?.sunset)
        #expect(f.frame(at: tsk(17, 30)).primary?.golden != nil)
        #expect(f.frame(at: set.addingTimeInterval(60)).primary?.golden == nil)
    }

    @Test func tomorrowCountsTodayAndThreeDaysAwayGivesWayToLight() {
        let tomorrow = feed([shoot(from: tsk(10, day: 25), to: tsk(12, day: 25))]).frame(at: tsk(20))
        #expect(tomorrow.kind == .upcoming && tomorrow.primary?.dayOffset == 1)

        let far = feed([shoot(from: tsk(10, day: 27), to: tsk(12, day: 27))]).frame(at: tsk(8))
        #expect(far.kind == .light)
        #expect(far.shoots.first?.id == "s1" && far.shoots.first?.dayOffset == 3, "ближайшая съёмка уходит в нижнюю строку")
        #expect(far.url == WidgetFeed.dayURL(day))
    }

    @Test func aShootInAnotherZoneIsCountedByItsOwnClocks() throws {
        // Москва +3: съёмка 25.10 в 01:00 по Москве — это 24.10 22:00 UTC+0… в Томске уже 05:00 25-го.
        let msk = WidgetFeed.Spot(name: "", latitude: 55.75, longitude: 37.62, zone: "fixed:10800")
        let start = utc(2026, 10, 24, 22), end = utc(2026, 10, 25, 1)
        let f = feed([shoot(from: start, to: end, spot: msk)])
        // 24.10 20:00 по Москве: в Москве 24-е, и съёмка уже «завтра»? Нет — 25.10 01:00 МСК = завтра.
        let eve = f.frame(at: utc(2026, 10, 24, 17))
        #expect(eve.primary?.dayOffset == 1)
        #expect(eve.primary?.zone.secondsFromGMT() == 10800)
        #expect(f.clock(start, in: try #require(eve.primary?.zone)) == "01:00")
    }

    // MARK: Во время съёмки — студийный час, следующая точка, маршрут

    private func studioShoot() -> WidgetFeed.Shoot {
        let rent = WidgetFeed.Rent(from: ms(tsk(14)), to: ms(tsk(16)), deadline: ms(tsk(15, 55)), studio: "Томсон")
        let stops = [WidgetFeed.Stop(at: ms(tsk(14)), name: "Студия", place: "Томсон, зал Эдисон"),
                     WidgetFeed.Stop(at: ms(tsk(16, 30)), name: "Прогулка", place: "Набережная"),
                     WidgetFeed.Stop(at: ms(tsk(18)), name: "Банкет", place: "")]
        return shoot(from: tsk(14), to: tsk(19), rents: [rent], stops: stops)
    }

    @Test func liveShootCountsStudioTimeAndNamesTheNextPoint() throws {
        let f = feed([studioShoot()]).frame(at: tsk(14, 30))
        #expect(f.kind == .live)
        let p = try #require(f.primary)
        #expect(p.countdown?.kind == .studio && p.countdown?.to == tsk(15, 55) && p.countdown?.studio == "Томсон")
        #expect(p.next?.name == "Прогулка" && p.left.map(\.name) == ["Прогулка", "Банкет"])
    }

    @Test func afterTheStudioDeadlineTheCountdownIsToTheEndOfTheShoot() throws {
        let p = try #require(feed([studioShoot()]).frame(at: tsk(16, 10)).primary)
        #expect(p.countdown?.kind == .end && p.countdown?.to == tsk(19))
    }

    @Test func aShootClosedByHandHasNoEndToCountTo() throws {
        let s = shoot(from: tsk(14), to: tsk(19), open: true)
        let f = feed([s])
        #expect(f.frame(at: tsk(22)).kind == .live, "незакрытая вручную съёмка идёт, пока не нажмут")
        #expect(f.frame(at: tsk(22)).primary?.countdown == nil)
    }

    @Test func afterTheEndTheNextShootOrTheLightComesBack() throws {
        let f = feed([shoot("a", from: tsk(10), to: tsk(12)), shoot("b", from: tsk(15), to: tsk(17))])
        #expect(f.frame(at: tsk(11)).primary?.shoot.id == "a")
        let mid = f.frame(at: tsk(13))
        #expect(mid.kind == .upcoming && mid.primary?.shoot.id == "b")
        #expect(f.frame(at: tsk(13)).shoots.map(\.id) == ["b"])
        let done = f.frame(at: tsk(18))
        #expect(done.kind == .light && done.shoots.isEmpty)
    }

    @Test func twoNearestShootsFeedTheMediumList() {
        let f = feed([shoot("a", from: tsk(10), to: tsk(11)), shoot("b", from: tsk(12), to: tsk(13)),
                      shoot("c", from: tsk(14), to: tsk(15))])
        #expect(f.frame(at: tsk(8)).shoots.map(\.id) == ["a", "b"])
    }

    // MARK: Когда плашка меняется сама

    @Test func changesCoverStartsStopsDeadlinesAndLight() throws {
        let f = feed([studioShoot()])
        let c = f.changes(from: tsk(9))
        #expect(c.first == tsk(9))
        #expect(c == c.sorted() && Set(c).count == c.count)
        for d in [tsk(14), tsk(15, 55), tsk(16, 30), tsk(18), tsk(19)] { #expect(c.contains(d), "нет \(d)") }
        let l = try #require(tomsk.light(on: day))
        let set = try #require(l.sunset)
        let nextRise = try #require(tomsk.light(on: day.adding(days: 1))?.sunrise)
        #expect(c.contains(set) && c.contains(nextRise))
        #expect(c.count <= WidgetFeed.entryLimit)
    }

    @Test func nothingChangesInsideAnInterval() {
        let f = feed([studioShoot()])
        let c = f.changes(from: tsk(9))
        for (a, b) in zip(c, c.dropFirst()) {
            let mid = a.addingTimeInterval(b.timeIntervalSince(a) / 2)
            #expect(strip(f.frame(at: a)) == strip(f.frame(at: mid)), "между \(a) и \(b)")
        }
    }

    /// Замечание ревью к 30б.2: лента режется на 60 моментах, а перезагрузка просилась через 36 часов — между ними
    /// виджет держал бы устаревшую плашку. Насыщенный день (свадьба с точкой каждые 20 минут) — перезагрузка не позже
    /// последнего показанного момента; обычный день — по-прежнему 36 часов.
    @Test func aDenseDayReloadsAtTheLastShownMomentNotAfter() {
        let stops = (0..<90).map { WidgetFeed.Stop(at: ms(tsk(10).addingTimeInterval(Double($0) * 20 * 60)), name: "Точка \($0)") }
        let f = feed([shoot(from: tsk(10), to: tsk(10).addingTimeInterval(31 * 3600), stops: stops)])
        let now = tsk(9)
        let line = f.timeline(from: now, limit: 60)
        #expect(line.dates.count == 60)
        #expect(line.dates == f.changes(from: now, limit: 60))
        #expect(line.reload <= line.dates.last!, "перезагрузка \(line.reload) позже последнего момента \(line.dates.last!)")
        #expect(line.reload > now)
    }

    @Test func anOrdinaryDayReloadsAfterThirtySixHours() {
        let f = feed([studioShoot()])
        let now = tsk(9)
        let line = f.timeline(from: now)
        #expect(line.reload == now.addingTimeInterval(36 * 3600))
        #expect(line.dates == f.changes(from: now))
        #expect(feed().timeline(from: now).reload == now.addingTimeInterval(36 * 3600))
    }


    // MARK: Лента по формам (30б.2в-2)

    /// Свадьба Алексея: 12:00–00:30, на кольцо в 12:52 нужны минуты, чтобы «62 мин» не замерзло.
    private func wedding() -> WidgetFeed.Shoot {
        shoot(from: tsk(12), to: tsk(0, 30, day: 25), sunset: true,
              rents: [.init(from: ms(tsk(12)), to: ms(tsk(14)), deadline: ms(tsk(13, 54)), studio: "Томсон")],
              stops: [.init(at: ms(tsk(12)), name: "Пара в студии"), .init(at: ms(tsk(14)), name: "Обед")])
    }

    @Test func theRingGetsAMomentEveryMinuteWhileTheShootGoesAndNotBefore() {
        let f = feed([wedding()])
        let now = tsk(12, 52, day: 24).addingTimeInterval(20)
        for shape in [WidgetShape.small, .medium] {
            let line = f.timeline(from: now, shape: shape)
            #expect(line.dates.count == WidgetFeed.entryLimit, "обрезана на \(WidgetFeed.entryLimit) записях: свадьба в 12,5 часа")
            #expect(line.reload == line.dates.last, "и новая лента просится на последнем показанном моменте")
            let minutes = line.dates.dropFirst().prefix(60)
            #expect(minutes.first == tsk(12, 53) && minutes.last != nil)
            // Первые часы — ровно по минуте, кроме событий (13:54 — выход из студии, 14:00 — «Обед»).
            let first = Array(line.dates.dropFirst().prefix(60))
            for (a, b) in zip(first, first.dropFirst()) { #expect(b.timeIntervalSince(a) <= 60, "дырка между \(a) и \(b)") }
        }
        // До начала съёмки минут нет: плашка до того не кольцо.
        let early = f.timeline(from: tsk(9), shape: .medium)
        #expect(!early.dates.contains(tsk(9, 1)) && !early.dates.contains(tsk(11, 30)))
        #expect(early.dates.contains(tsk(12)) && early.dates.contains(tsk(12, 1)), "с начала съёмки — по минуте")
    }

    @Test func theRingStopsCountingWhenTheShootEnds() {
        let f = feed([wedding()])
        let line = f.timeline(from: tsk(0, 10, day: 25), limit: 1000, shape: .small)
        #expect(line.dates.contains(tsk(0, 30, day: 25)) && !line.dates.contains(tsk(0, 31, day: 25)), "после конца минут нет")
        #expect(line.reload == tsk(0, 10, day: 25).addingTimeInterval(36 * 3600), "лента не обрезана — перезагрузка через 36 часов")
    }

    @Test func otherShapesDoNotPayForTheRingsMinutes() {
        let f = feed([wedding()])
        let now = tsk(12, 52)
        let events = f.timeline(from: now).dates
        for shape in [WidgetShape.inline, .rectangular] {
            #expect(f.timeline(from: now, shape: shape).dates == events, "строка и прямоугольник меняются только на событиях")
        }
        #expect(events.count < 30)
    }

    @Test func theCircleCountsMinutesUpToTheGoldenHourAndStopsThere() throws {
        let f = feed()
        let golden = try #require(tomsk.light(on: day)?.golden)
        let now = golden.addingTimeInterval(-3 * 3600 + 5)
        let line = f.timeline(from: now, limit: 1000, shape: .circular)
        let minutes = line.dates.filter { $0 > now && $0 <= golden }
        #expect(minutes.count >= 178, "три часа по минуте: \(minutes.count)")
        #expect(line.dates.contains(golden), "в золотой час круг гаснет — это событие")
        let after = line.dates.filter { $0 > golden && $0 < tsk(0, day: 25) }
        #expect(after.count <= 1, "после золотого часа и до полуночи минут нет: \(after.count)")
        #expect(Set(line.dates.filter { $0 > tsk(0, day: 25) }.prefix(3)).contains(tsk(0, 1, day: 25)), "с полуночи считается завтрашний")
    }

    @Test func theLargeDayArcMovesEveryTenMinutesOnlyWithoutAShoot() throws {
        let l = try #require(tomsk.light(on: day))
        let rise = try #require(l.sunrise), set = try #require(l.sunset)
        let free = feed().timeline(from: rise.addingTimeInterval(-60), limit: 1000, shape: .large)
        let arc = free.dates.filter { $0 > rise && $0 < set }
        #expect(arc.count >= Int(set.timeIntervalSince(rise) / 600) - 1, "десять минут между восходом и закатом: \(arc.count)")
        // Съёмка занимает вид — дуги нет, её минуты не нужны.
        let busy = feed([shoot(from: tsk(9), to: tsk(17))]).timeline(from: tsk(8), limit: 1000, shape: .large)
        let plain = feed([shoot(from: tsk(9), to: tsk(17))]).timeline(from: tsk(8), limit: 1000)
        #expect(busy.dates.filter { $0 > tsk(9) && $0 < tsk(17) } == plain.dates.filter { $0 > tsk(9) && $0 < tsk(17) },
                "пока съёмка идёт, большой виджет меняется только на событиях")
    }

    /// Бюджет: день свадьбы с минутным кольцом — сколько раз виджет просит новую ленту, если каждый раз перезагружается ровно в срок.
    /// У WidgetKit лимит на перезагрузки (40–70 в сутки на виджет), а не на записи, поэтому лента длинная и просьб мало.
    @Test func aWeddingDayWithTheRingAsksForAFewReloadsNotForOnePerMinute() {
        let f = feed([wedding()])
        for (shape, from, to, most) in [(WidgetShape.medium, tsk(12), tsk(0, 30, day: 25), 6), (.small, tsk(12), tsk(0, 30, day: 25), 6),
                                        (.circular, tsk(0), tsk(17), 8)] {
            var at = from, reloads = 0, entries = 0
            while at < to && reloads < 100 {
                let line = f.timeline(from: at, shape: shape)
                entries += line.dates.count
                #expect(line.reload > at)
                at = line.reload
                reloads += 1
            }
            #expect(reloads <= most, "\(shape): \(reloads) просьб о новой ленте, записей \(entries)")
            print("лента \(shape): \(reloads) перезагрузок, \(entries) записей за \(Int(to.timeIntervalSince(from) / 3600)) ч")
        }
    }

    @Test func noShapeEverEndsItsStripBeforeTheReload() {
        // Условие 30б.2-ленты для каждой формы: лента обрезана — перезагрузка на последнем показанном моменте; нет — через 36 часов.
        let f = feed([wedding()])
        for shape in WidgetShape.allCases {
            for now in [tsk(9), tsk(12, 52), tsk(23, 50), tsk(3, day: 25)] {
                let line = f.timeline(from: now, shape: shape)
                #expect(line.dates.first == now && line.dates == line.dates.sorted() && Set(line.dates).count == line.dates.count)
                #expect(line.dates.count <= WidgetFeed.entryLimit)
                let cut = line.dates.count == WidgetFeed.entryLimit
                #expect(line.reload == (cut ? line.dates.last! : now.addingTimeInterval(36 * 3600)), "\(shape) с \(now)")
                #expect(line.reload > now)
            }
        }
    }

    /// Кадр от «сейчас» отличается только полем `now`.
    private func strip(_ f: WidgetFrame) -> WidgetFrame { var g = f; g.now = Date(timeIntervalSince1970: 0); return g }

    // MARK: Файл

    @Test func theFileKeepsEverythingAndReadsTheOldStub() throws {
        let full = feed([studioShoot()])
        var withWords = full
        withWords.words = .init([.sunrise: "Dawn"])
        withWords.lang = "en-GB"
        withWords.clock12 = true
        #expect(WidgetFeed.decode(withWords.encoded()) == withWords)
        #expect(withWords.words[.sunrise] == "Dawn" && withWords.words[.sunset] == "Закат")

        // Файл с именами, знаками и жанром читается, а файл 30б.2 (без них) читается тоже.
        let named = WidgetFeed.Shoot(id: "n", start: 1, end: 2, title: "Свадьба", stops: [.init(at: 1, name: "ЗАГС", sign: "rings")],
                                     genre: "wedding", names: "Анна+Игорь")
        let withNames = WidgetFeed(place: tomsk, shoots: [named])
        #expect(WidgetFeed.decode(withNames.encoded()) == withNames)
        let stub = Data(#"{"place":{"name":"Т","latitude":1,"longitude":2,"zone":"UTC"},"shoots":[{"id":"x","start":1,"end":2,"open":false,"title":"С","place":"","wantsSunset":false,"rents":[],"stops":[{"at":1,"name":"А","place":""}]}]}"#.utf8)
        let old30 = try #require(WidgetFeed.decode(stub))
        #expect(old30.shoots[0].names == nil && old30.shoots[0].genre == nil && old30.shoots[0].stops[0].sign == nil)
        let old = Data(#"{"place":{"name":"Томск","latitude":56.5,"longitude":84.97,"zone":"Asia/Tomsk"}}"#.utf8)
        let decoded = try #require(WidgetFeed.decode(old))
        #expect(decoded.shoots.isEmpty && decoded.lang == "ru" && !decoded.clock12)
    }

    @Test func linksRoundTrip() {
        #expect(WidgetFeed.day(in: WidgetFeed.dayURL(day)) == day)
        #expect(WidgetFeed.day(in: URL(string: "lightplan://day/2026-13-40")!) == nil)
        #expect(WidgetFeed.day(in: URL(string: "lightplan://shoot/abc")!) == nil)
        #expect(WidgetFeed.shootURL("abc").absoluteString == "lightplan://shoot/abc")
    }

    @Test func onlyTheMainAppIsClean() {
        #expect(WidgetFeed.isMainApp(bundleID: "Novopashin.LightPlan.Widget"))
        #expect(WidgetFeed.isMainApp(bundleID: "Novopashin.LightPlan"))
        #expect(!WidgetFeed.isMainApp(bundleID: "Novopashin.LightPlan.slotB.Widget"))
        #expect(!WidgetFeed.isMainApp(bundleID: "Novopashin.LightPlan.wt26.Widget"))
    }

    @Test func clockFollowsTheAppsHabit() {
        var f = feed()
        #expect(f.clock(tsk(17, 2), in: TimeZone(secondsFromGMT: 7 * 3600)!) == "17:02")
        f.clock12 = true
        f.lang = "en-US"
        #expect(f.clock(tsk(17, 2), in: TimeZone(secondsFromGMT: 7 * 3600)!).hasPrefix("5:02"))
    }

    // MARK: Сборка файла из записей

    @Test func makeTakesTheTitleNotTheClientAndDropsWhatIsOver() throws {
        var a = Session(id: "a", day: day, start: 15 * 60, end: 19 * 60, genre: .wedding)
        a.contact = "Иванова Мария +7 913 000-00-00"
        a.wishes = [.sunset]
        a.studioId = "st"
        a.latitude = 56.49
        a.longitude = 84.95
        a.rentFrom = 14 * 60
        a.rentTo = 16 * 60
        a.route = [RoutePoint(start: 15 * 60, name: "ЗАГС", placeText: "ЗАГС №1"), RoutePoint(start: nil, name: "Без часа")]
        let past = Session(id: "past", day: day, start: 6 * 60, end: 8 * 60, genre: .portrait)
        let later = Session(id: "later", day: day.adding(days: 9), start: 600, end: 700, genre: .portrait)
        var meet = Session(id: "meet", kind: .meet, day: day, start: 16 * 60, end: 17 * 60)
        meet.genre = .family
        let studio = Studio(id: "st", name: "Томсон", latitude: 56.49, longitude: 84.95)

        let feed = WidgetFeed.make(
            place: tomsk, sessions: [a, past, later, meet], studios: [studio], spots: [], now: tsk(9), manualEnd: false,
            offset: { _, _ in 7 }, title: { $0.genre?.rawValue ?? "?" }, names: { _ in "Мария" },
            sign: { n, _, studio in studio ? "studio" : "sign:" + n }, words: .init(), lang: "ru", clock12: false)
        #expect(feed.shoots.map(\.id) == ["a"], "прошедшая, дальняя неделя и встреча не идут")
        let s = try #require(feed.shoots.first)
        // В файле имена (их показывают «Домой»), но ни фамилии, ни номера из записи клиента.
        #expect(s.title == "wedding" && s.genre == "wedding" && s.names == "Мария")
        #expect(!feed.encoded().contains(Data("Иванова".utf8)) && !feed.encoded().contains(Data("913".utf8)), "ни фамилии, ни телефона")
        #expect(s.start == ms(tsk(15)) && s.end == ms(tsk(19)) && s.wantsSunset && !s.open)
        #expect(s.stops.map(\.name) == ["ЗАГС"] && s.stops.first?.place == "ЗАГС №1")
        #expect(s.stops.first?.sign == "sign:ЗАГС", "знак точки считает приложение и кладёт в файл")
        // Студия на 14:00–16:00 с часом в 55 минут: выйти в 15:55.
        #expect(s.rents.first?.deadline == ms(tsk(15, 55)) && s.rents.first?.studio == "Томсон")
        #expect(s.spot?.zone == "fixed:25200" && s.spot?.latitude == 56.49)
    }

    @Test func makeKeepsAShootClosedByHandUntilItIsClosed() {
        let s = Session(id: "s", day: day, start: 10 * 60, end: 12 * 60, genre: .portrait)
        let make = { (done: Int?, manual: Bool) -> [WidgetFeed.Shoot] in
            var s = s
            s.doneAt = done
            return WidgetFeed.make(place: tomsk, sessions: [s], studios: [], spots: [], now: self.tsk(20), manualEnd: manual,
                                   offset: { _, _ in 7 }, title: { _ in "x" }, words: .init(), lang: "ru", clock12: false).shoots
        }
        #expect(make(nil, true).first?.open == true, "ещё не нажали «Завершить»")
        #expect(make(nil, false).isEmpty, "обычная съёмка давно кончилась")
        #expect(make(11 * 60, true).isEmpty, "закрыта кнопкой")
    }
}
