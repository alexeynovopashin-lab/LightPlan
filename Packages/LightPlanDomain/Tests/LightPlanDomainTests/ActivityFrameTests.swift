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
        #expect(f.next == .init(label: "до Прогулка", to: ms(tsk(16, 0))))
        #expect(f.call == nil && f.playlist == nil, "лента кнопок не несёт")
    }

    @Test func beforeTheFirstPointItIsSoon() {
        let f = make(wedding(), at: tsk(11, 50))
        #expect(f.status == "Скоро: Сборы жениха")
        #expect(f.current == -1)
        #expect(f.next?.label == "до Сборы жениха" && f.next?.to == ms(tsk(12, 0)))
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
        #expect(f.next?.label == "до Прогулка")
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
        #expect(early.island?.label == "до Прогулка")
        let farOut = make(s, at: tsk(14, 45))
        #expect(farOut.island == .init(label: "до Прогулка", to: ms(tsk(16, 0))))
        // За 59 минут — до золотого часа, хотя точка «Прогулка» уже прошла, а «Банкет» ещё не скоро.
        let inside = make(s, at: golden.addingTimeInterval(-59 * 60))
        #expect(inside.island == .init(label: "до золотого часа", to: ms(golden)))
        // Золотой час начался — снова следующая точка.
        let after = make(s, at: golden.addingTimeInterval(60))
        #expect(after.island == .init(label: "до Банкет", to: ms(tsk(19, 0))))
    }

    @Test func withoutAGoldenPointTheIslandIsTheNextPoint() {
        let f = make(wedding(), at: tsk(15, 0))
        #expect(f.island == f.next)
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
}
