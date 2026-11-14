import Testing
import Foundation
@testable import LightPlanDomain
import LightPlanCore

/// Шаг 30б.3: что показывает экран активности в каждый момент съёмки — по словам Алексея 25–26.10 («свадьба — таймлайн»,
/// «студия — тот же таймлайн плюс отсчёт аренды и кнопки», «за час до золотого часа — отсчёт до него»).
struct ActivityFrameTests {

    private let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")

    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    /// Часы Томска (+7) 24.10.2026 → момент.
    private func tsk(_ h: Int, _ min: Int = 0) -> Date { utc(2026, 10, 24, h, min).addingTimeInterval(-7 * 3600) }
    private func ms(_ d: Date) -> Int64 { Moment(d).milliseconds }

    private func stop(_ h: Int, _ min: Int, _ name: String, sign: String? = nil) -> WidgetFeed.Stop {
        WidgetFeed.Stop(at: ms(tsk(h, min)), name: name, place: "", sign: sign)
    }

    /// Свадьба из слов Алексея: 12:00 Сборы, 14:30 Церемония, 16:00 Прогулка, 19:00 Банкет; съёмка 12:00–22:00.
    private func wedding(sunset: Bool = false, rents: [WidgetFeed.Rent] = [], open: Bool = false,
                         stops: [WidgetFeed.Stop]? = nil) -> WidgetFeed.Shoot {
        WidgetFeed.Shoot(
            id: "w1", start: ms(tsk(12)), end: ms(tsk(22)), open: open, title: "Свадьба", place: "Томск",
            wantsSunset: sunset, rents: rents,
            stops: stops ?? [stop(12, 0, "Сборы жениха", sign: "home"), stop(14, 30, "Церемония", sign: "ring"),
                             stop(16, 0, "Прогулка", sign: "walk"), stop(19, 0, "Банкет", sign: "cutlery")],
            genre: "wedding")
    }
    private func feed(_ s: WidgetFeed.Shoot, clock12: Bool = false) -> WidgetFeed {
        WidgetFeed(place: tomsk, shoots: [s], clock12: clock12)
    }
    private func make(_ s: WidgetFeed.Shoot, at now: Date, mode: ActivityFrame.Mode = .route,
                      reach: ActivityReach = .init(admin: true, playlist: true), clock12: Bool = false) -> ActivityFrame {
        ActivityFrame.make(feed: feed(s, clock12: clock12), shoot: s, now: now, mode: mode, reach: reach)
    }
    private func rent(_ fromH: Int, _ fromM: Int, _ toH: Int, _ toM: Int, deadlineMinutesBeforeEnd: Int = 5) -> WidgetFeed.Rent {
        WidgetFeed.Rent(from: ms(tsk(fromH, fromM)), to: ms(tsk(toH, toM)),
                        deadline: ms(tsk(toH, toM).addingTimeInterval(-Double(deadlineMinutesBeforeEnd) * 60)), studio: "Томсон")
    }

    // MARK: Лента и строка состояния

    @Test func weddingBetweenCeremonyAndWalk() {
        let f = make(wedding(), at: tsk(15, 0))
        #expect(f.mode == .route)
        #expect(f.status == "Сейчас: Церемония")
        #expect(f.range == "12:00 – 22:00 · 10 ч")
        #expect(f.points.map(\.time) == ["12:00", "14:30", "16:00", "19:00"])
        #expect(f.points.map(\.word) == ["Сборы", "Церемония", "Прогулка", "Банкет"])
        #expect(f.points.map(\.sign) == ["home", "ring", "walk", "cutlery"])
        #expect(f.current == 1)
        #expect(f.next == .init(label: "Далее: Прогулка", to: ms(tsk(16, 0))))
        #expect(f.call == nil && f.playlist == nil, "лента кнопок не несёт")
    }

    @Test func beforeTheFirstPointItIsSoon() {
        let f = make(wedding(), at: tsk(11, 50))
        #expect(f.status == "Скоро: Сборы жениха")
        #expect(f.current == -1)
        #expect(f.next?.label == "Далее: Сборы жениха" && f.next?.to == ms(tsk(12, 0)))
    }

    @Test func afterTheLastPointTheTimerCountsToTheEndOfTheShoot() {
        let f = make(wedding(), at: tsk(20, 0))
        #expect(f.status == "Сейчас: Банкет")
        #expect(f.current == 3)
        #expect(f.next == .init(label: "до конца свадьбы", to: ms(tsk(22, 0))))
        // Жанр не свадьба — «до конца съёмки».
        var other = wedding(); other.genre = "family"
        #expect(make(other, at: tsk(20, 0)).next?.label == "до конца съёмки")
    }

    @Test func aShootWithoutPointsJustRuns() {
        let f = make(wedding(stops: []), at: tsk(15, 0))
        #expect(f.status == "Идёт съёмка" && f.points.isEmpty && f.current == -1)
        #expect(f.next?.to == ms(tsk(22, 0)))
    }

    @Test func aFinishedShootSaysSoAndCountsNothing() {
        let f = make(wedding(), at: tsk(22, 30))
        #expect(f.status == "Съёмка закончена")
        #expect(f.next == nil)
        #expect(f.endsAt == ms(tsk(22, 0)))
    }

    @Test func anOpenShootHasNoEndAndKeepsRunning() {
        let f = make(wedding(open: true), at: tsk(23, 0))
        #expect(f.endsAt == nil)
        #expect(f.status == "Сейчас: Банкет")
        #expect(f.next == nil, "конца нет — считать нечего")
    }

    @Test func twelveHourClockIsWrittenIntoTheLabels() {
        let f = make(wedding(), at: tsk(15, 0), clock12: true)
        #expect(f.points.first?.time.contains("12:00") == true && f.points[1].time.contains("2:30") == true)
        #expect(f.points[1].time.uppercased().contains("PM"))
    }

    @Test func longNamesGiveOneWordAtMostElevenLetters() {
        #expect(ActivityFrame.word("Сборы жениха") == "Сборы")
        #expect(ActivityFrame.word("Фотосессия") == "Фотосессия")
        #expect(ActivityFrame.word("Достопримечательности") == "Достоприме…")
        #expect(ActivityFrame.word("") == "")
    }

    // MARK: Золотой час и свёрнутый остров

    @Test func goldenHourStandsOnTheLaneAfterThePointsOfTheSameHour() throws {
        let s = wedding(sunset: true)
        let golden = try #require(tomsk.goldenStart(on: CivilDate(year: 2026, month: 10, day: 24)))
        let f = make(s, at: tsk(15, 0))
        // Томск 24.10: золотой час в 17:01 (точное Солнце `.iau`; веб и спайк 30б с NOAA дают 17:02) — между «Прогулкой» 16:00 и «Банкетом» 19:00.
        #expect(f.points.map(\.word) == ["Сборы", "Церемония", "Прогулка", "Золотой", "Банкет"])
        let g = f.points[3]
        #expect(g.gold && g.sign == "golden" && g.at == ms(golden), "\(g)")
        #expect(g.time == "17:01", "\(g.time)")
        // Подсвечена точка маршрута, а не золотой час.
        #expect(make(s, at: tsk(17, 30)).current == 2)
        // После «Прогулки» следующий — золотой час, и его часы называются своим словом.
        #expect(f.next?.label == "Далее: Прогулка")
        #expect(make(s, at: tsk(16, 30)).next == .init(label: "до золотого часа", to: ms(golden)))
    }

    @Test func noWishNoGoldenPoint() {
        #expect(make(wedding(sunset: false), at: tsk(15, 0)).points.count == 4)
    }

    @Test func theIslandCountsToTheNextPointAndAnHourBeforeGoldenToGolden() throws {
        let s = wedding(sunset: true)
        let golden = try #require(tomsk.goldenStart(on: CivilDate(year: 2026, month: 10, day: 24)))
        // За полтора часа до золотого: следующая точка.
        let early = make(s, at: golden.addingTimeInterval(-90 * 60))
        #expect(early.island?.label == "Далее: Прогулка")
        let farOut = make(s, at: tsk(14, 45))
        #expect(farOut.island == .init(label: "Далее: Прогулка", to: ms(tsk(16, 0))))
        // За 59 минут — до золотого часа, хотя точка «Прогулка» уже прошла, а «Банкет» ещё не скоро.
        let inside = make(s, at: golden.addingTimeInterval(-59 * 60))
        #expect(inside.island == .init(label: "до золотого часа", to: ms(golden)))
        // Золотой час начался — снова следующая точка.
        let after = make(s, at: golden.addingTimeInterval(60))
        #expect(after.island == .init(label: "Далее: Банкет", to: ms(tsk(19, 0))))
    }

    @Test func withoutAGoldenPointTheIslandIsTheNextPoint() {
        let f = make(wedding(), at: tsk(15, 0))
        #expect(f.island == f.next)
    }

    // MARK: Свёрнутый остров на последней точке (30и.2)

    /// Слово Алексея 14.11: «положить иконку и таймер точки». Справа в свёрнутом острове — часы; после последней точки это время до
    /// конца съёмки — те же часы, что на плашке («до конца свадьбы»), а не отдельное правило. Проверено до правки: остров и так считал
    /// до конца (`island = next`), пустым он бывает только у съёмки без конца (завершается вручную) — тест держит оба случая.
    @Test func onTheLastPointTheIslandCountsToTheEndOfTheShootLikeThePlate() {
        let f = make(wedding(), at: tsk(20, 0))
        #expect(f.current == 3 && f.points.last?.word == "Банкет")
        #expect(f.island == .init(label: "до конца свадьбы", to: ms(tsk(22, 0))))
        #expect(f.island == f.next, "остров берёт часы плашки, не свои")
        // Золотой час уже позади — на последней точке он остров не перехватывает.
        let g = make(wedding(sunset: true), at: tsk(21, 0))
        #expect(g.island == .init(label: "до конца свадьбы", to: ms(tsk(22, 0))))
        // Не свадьба — «до конца съёмки».
        var other = wedding(); other.genre = "family"
        #expect(make(other, at: tsk(20, 0)).island?.label == "до конца съёмки")
    }

    @Test func theIslandOfAShootWithoutAnEndHasNothingToCountAndStaysEmpty() {
        let f = make(wedding(open: true), at: tsk(20, 0))
        #expect(f.current == 3 && f.endsAt == nil)
        #expect(f.island == nil, "конца нет — считать нечего, остров показывает только знак")
    }

    @Test func theLastPointKeepsTheFrameWithinTheLimit() {
        let long = (0..<20).map { stop(12 + $0 / 4, ($0 % 4) * 15, "Достопримечательность номер \($0)", sign: "walk") }
        let f = make(wedding(stops: long), at: tsk(21, 30))
        #expect(f.points.count <= ActivityFrame.maxPoints)
        #expect(f.encodedSize + ActivityFrame.propertiesReserve <= ActivityFrame.limit)
        #expect(f.island?.to == ms(tsk(22, 0)), "на последней точке остров считает до конца, в пределах 4 КБ")
    }

    // MARK: Студия

    @Test func studioModeKeepsTheLaneAndAddsExitAndButtons() {
        let s = wedding(rents: [rent(14, 0, 16, 0)])
        let f = make(s, at: tsk(15, 0), mode: .studio)
        #expect(f.mode == .studio && f.rentActive)
        #expect(f.points.count == 4, "лента в студии на месте")
        #expect(f.exit == .init(label: "Выход из зала", to: ms(tsk(15, 55))))
        #expect(f.studio == "Томсон")
        #expect(f.call == "Позвонить админу" && f.playlist == "Плейлист")
    }

    @Test func noAdminNumberNoCallButton() {
        let s = wedding(rents: [rent(14, 0, 16, 0)])
        let f = make(s, at: tsk(15, 0), mode: .studio, reach: .init(admin: false, playlist: true))
        #expect(f.call == nil && f.playlist == "Плейлист")
        let none = make(s, at: tsk(15, 0), mode: .studio, reach: .init())
        #expect(none.call == nil && none.playlist == nil && none.mode == .studio)
    }

    @Test func studioModeFallsBackToTheLaneWhenTheRentIsNotRunning() {
        let s = wedding(rents: [rent(14, 0, 16, 0)])
        // Аренда ещё впереди: режим «студия» не держится, но выход из зала уже на ленте — время известно заранее.
        let before = make(s, at: tsk(13, 0), mode: .studio)
        #expect(before.mode == .route && !before.rentActive)
        #expect(before.exit == .init(label: "Выход из зала", to: ms(tsk(15, 55))))
        #expect(before.call == nil && before.playlist == nil)
        // Аренда кончилась: выхода нет.
        let after = make(s, at: tsk(16, 30), mode: .studio)
        #expect(after.mode == .route && after.exit == nil && after.studio == "")
    }

    @Test func routeModeWithARentStillCountsTheExit() {
        let f = make(wedding(rents: [rent(14, 0, 16, 0)]), at: tsk(15, 0), mode: .route)
        #expect(f.mode == .route && f.rentActive)
        #expect(f.exit?.to == ms(tsk(15, 55)))
        #expect(f.call == nil, "кнопки включает только студийный режим")
    }

    @Test func theSecondRentIsPickedWhenTheFirstIsOver() {
        let s = wedding(rents: [rent(12, 0, 13, 0), rent(18, 0, 20, 0)])
        #expect(make(s, at: tsk(15, 0)).exit?.to == ms(tsk(19, 55)))
        #expect(make(s, at: tsk(12, 30)).exit?.to == ms(tsk(12, 55)))
    }

    // MARK: Размер и ссылки

    @Test func sixteenPointsFitTheSystemLimit() {
        let names = (1...20).map { "Достопримечательности \($0)" }
        let stops = names.enumerated().map { stop(12 + $0.offset / 3, ($0.offset % 3) * 20, $0.element, sign: "monument") }
        let s = wedding(sunset: true, rents: [rent(14, 0, 16, 0)], stops: stops)
        let f = make(s, at: tsk(15, 0), mode: .studio)
        #expect(f.points.count == ActivityFrame.maxPoints)
        // Свойства активности (id съёмки, момент запуска) — ещё около 100 байт; запас до 4 КБ остаётся.
        #expect(f.encodedSize + 200 < ActivityFrame.limit, Comment(rawValue: "кадр \(f.encodedSize) Б"))
    }

    @Test func aLongRouteKeepsTheWindowAroundNowNotTheStartOfTheDay() {
        let names = (0..<20).map { "Точка \($0)" }
        // По точке каждые 20 минут с 12:00: «сейчас» 18:20 — это точка 19 (последняя), окно должно её содержать.
        let stops = names.enumerated().map { stop(12 + $0.offset / 3, ($0.offset % 3) * 20, $0.element, sign: "camera") }
        let s = wedding(stops: stops)
        let late = make(s, at: tsk(18, 25))
        #expect(late.points.count == ActivityFrame.maxPoints)
        #expect(late.points.last?.word == "Точка" && late.status == "Сейчас: Точка 19", Comment(rawValue: late.status))
        #expect(late.current == late.points.count - 1 && late.points[late.current].time == "18:20")
        // Утром окно начинается с первой точки.
        let early = make(s, at: tsk(12, 5))
        #expect(early.points.first?.time == "12:00" && early.current == 0)
        // Посередине: подсвеченная точка внутри окна, и впереди есть что считать.
        let mid = make(s, at: tsk(15, 5))
        #expect(mid.current >= 0 && mid.points[mid.current].time == "15:00" && mid.next != nil)
        for f in [late, early, mid] { #expect(f.points.map(\.at) == f.points.map(\.at).sorted()) }
    }

    @Test func longNamesCannotPushTheFrameOverTheSystemLimit() {
        let long = String(repeating: "Очень длинное название точки ", count: 6)
        let stops = (0..<16).map { stop(12 + $0 / 2, ($0 % 2) * 30, long + "\($0)", sign: "camera") }
        let f = make(wedding(sunset: true, rents: [rent(14, 0, 16, 0)], stops: stops), at: tsk(15), mode: .studio)
        #expect(f.encodedSize + ActivityFrame.propertiesReserve <= ActivityFrame.limit, Comment(rawValue: "кадр \(f.encodedSize) Б"))
        #expect(f.status.count <= 60 + 10 && f.next?.label.count ?? 0 <= 60)
        #expect(f.points.count >= 2 && f.mode == .studio && f.call != nil, "кнопки и лента на месте")
    }

    @Test func aNameWithoutSpacesStaysShortOnTheLane() {
        let huge = String(repeating: "Ы", count: 5000)
        let f = make(wedding(stops: [stop(12, 0, huge, sign: "camera"), stop(14, 0, huge + "2", sign: "camera")]), at: tsk(13))
        #expect(f.points.count == 2 && f.points.allSatisfy { $0.word.count <= 11 }, "обе точки на месте, слово ленты ограничено")
        #expect(f.encodedSize + ActivityFrame.propertiesReserve <= ActivityFrame.limit, Comment(rawValue: "кадр \(f.encodedSize) Б"))
    }

    @Test func frameSurvivesTheRoundTripTheSystemDoesOnItsOwn() throws {
        let f = make(wedding(sunset: true, rents: [rent(14, 0, 16, 0)]), at: tsk(15, 0), mode: .studio)
        let back = try JSONDecoder().decode(ActivityFrame.self, from: JSONEncoder().encode(f))
        #expect(back == f)
    }

    @Test func linksAreOursOnly() {
        #expect(ActivityLink.of(ActivityLink.admin.url) == .admin)
        #expect(ActivityLink.of(ActivityLink.playlist.url) == .playlist)
        #expect(ActivityLink.of(URL(string: "lightplan://activity/other")!) == nil)
        #expect(ActivityLink.of(URL(string: "lightplan://day/2026-10-24")!) == nil)
        #expect(ActivityLink.of(URL(string: "https://activity/admin")!) == nil)
    }

    // MARK: Окно ленты из четырёх точек (30и.3, эскиз 14.11)

    /// Восемь точек с 12:00 каждый час: точка k стоит в 12+k часов.
    private func eight(open: Bool = false) -> WidgetFeed.Shoot {
        wedding(open: open, stops: (0..<8).map { stop(12 + $0, 0, "Точка \($0)", sign: "camera") })
    }

    @Test func windowOnTheFirstPointIsNowAndTheThreeNextWithAMoreTail() {
        let w = make(eight(), at: tsk(12, 10)).laneWindow
        #expect(w.range == 0..<4 && w.now == 0 && w.more == 4, Comment(rawValue: "\(w)"))
    }

    @Test func windowInTheMiddleIsOnePastNowTwoNextAndTheTail() {
        let f = make(eight(), at: tsk(15, 10))   // «сейчас» — точка 3 (15:00)
        let w = f.laneWindow
        #expect(f.current == 3)
        #expect(w.range == 2..<6 && w.now == 3 && w.more == 2, Comment(rawValue: "\(w)"))
        #expect(f.points[w.range.lowerBound].time == "14:00", "прошедшая точка одна")
    }

    @Test func windowOnTheLastPointIsThePreviousAndNowWithoutATail() {
        let f = make(eight(), at: tsk(19, 30))   // последняя — 19:00
        let w = f.laneWindow
        #expect(f.current == 7 && w.range == 6..<8 && w.now == 7 && w.more == 0, Comment(rawValue: "\(w)"))
    }

    @Test func windowBeforeTheFirstPointShowsTheFirstFourWithoutNow() {
        let w = make(eight(), at: tsk(11, 0)).laneWindow
        #expect(w.range == 0..<4 && w.now == nil && w.more == 4, Comment(rawValue: "\(w)"))
    }

    @Test func fourPointsOrFewerStandWhole() {
        // Свадьба из четырёх точек: на любой точке все четыре, без хвоста.
        for (h, m) in [(11, 0), (12, 30), (15, 0), (20, 0)] {
            let w = make(wedding(), at: tsk(h, m)).laneWindow
            #expect(w.range == 0..<4 && w.more == 0, Comment(rawValue: "\(h):\(m) \(w)"))
        }
        let two = make(wedding(stops: [stop(12, 0, "А", sign: "camera"), stop(18, 0, "Б", sign: "camera")]), at: tsk(13)).laneWindow
        #expect(two.range == 0..<2 && two.now == 0 && two.more == 0)
        let none = make(wedding(stops: []), at: tsk(13)).laneWindow
        #expect(none.range == 0..<0 && none.now == nil && none.more == 0)
    }

    @Test func theMoreWordComesFromTheTemplateWithoutTheNumber() {
        #expect(make(eight(), at: tsk(15)).moreWord == "и ещё")
        var w = ActivityWords(); w.more = "{n} more"
        let s = eight()
        let f = ActivityFrame.make(feed: feed(s), shoot: s, now: tsk(15), words: w)
        #expect(f.moreWord == "more")
    }

    @Test func aFrameWithoutTheMoreWordStillDecodes() throws {
        var f = make(eight(), at: tsk(15))
        f.moreWord = nil
        let back = try JSONDecoder().decode(ActivityFrame.self, from: JSONEncoder().encode(f))
        #expect(back.moreWord == nil && back == f)
    }

    // MARK: Правая половина свёрнутого острова не бывает пустой

    /// Съёмка 00:00–23:59, как у Алексея на телефоне 14.11.
    private func allDay(open: Bool, stops: [WidgetFeed.Stop]) -> WidgetFeed.Shoot {
        WidgetFeed.Shoot(id: "d1", start: ms(tsk(0, 0)), end: ms(tsk(23, 59)), open: open, title: "Свадьба", place: "Томск", stops: stops, genre: "wedding")
    }

    @Test func onTheLastPointTheIslandCountsToTheEndOfTheShoot() {
        let s = allDay(open: false, stops: [stop(0, 0, "Сборы", sign: "home"), stop(10, 0, "Церемония", sign: "ring")])
        let f = ActivityFrame.make(feed: feed(s), shoot: s, now: tsk(11, 0))
        #expect(f.current == 1)
        #expect(f.island == .init(label: "до конца свадьбы", to: ms(tsk(23, 59))))
        #expect(f.islandTimer == .down(.init(label: "до конца свадьбы", to: ms(tsk(23, 59)))))
    }

    @Test func aShootWithoutAnEndCountsUpFromItsStartInsteadOfLeavingTheIslandEmpty() {
        let s = allDay(open: true, stops: [stop(0, 0, "Сборы", sign: "home"), stop(10, 0, "Церемония", sign: "ring")])
        let f = ActivityFrame.make(feed: feed(s), shoot: s, now: tsk(11, 0))
        #expect(f.island == nil, "считать вниз не к чему")
        #expect(f.islandTimer == .up(since: tsk(0, 0)))
    }

    @Test func aFinishedShootShowsATickNotNothing() {
        let s = allDay(open: false, stops: [stop(0, 0, "Сборы", sign: "home")])
        let f = ActivityFrame.make(feed: feed(s), shoot: s, now: tsk(23, 59).addingTimeInterval(60))
        #expect(f.islandTimer == .done)
    }

    @Test func noPointsAtAllStillGivesTheIslandATimer() {
        let s = allDay(open: false, stops: [])
        let f = ActivityFrame.make(feed: feed(s), shoot: s, now: tsk(11, 0))
        #expect(f.islandTimer == .down(.init(label: "до конца свадьбы", to: ms(tsk(23, 59)))))
    }

    @Test func theIslandIsNeverEmptyAtAnyMinuteOfTheDay() {
        for open in [false, true] {
            let s = allDay(open: open, stops: [stop(0, 0, "Сборы", sign: "home"), stop(10, 0, "Церемония", sign: "ring")])
            for minute in stride(from: 0, to: 24 * 60 + 5, by: 7) {
                let f = ActivityFrame.make(feed: feed(s), shoot: s, now: tsk(0, 0).addingTimeInterval(Double(minute) * 60))
                switch f.islandTimer {
                case .down, .up, .done: break
                }
            }
        }
    }
}
