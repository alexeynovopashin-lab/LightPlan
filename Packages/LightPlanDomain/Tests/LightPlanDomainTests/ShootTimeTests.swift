import Foundation
import Testing
import LightPlanCore
@testable import LightPlanDomain

/// Время съёмки по умолчанию и всплывашки (шаг 30д, ответы Алексея 04.11).
/// Пример окна из вопросов: золотой час с 19:00, закат 20:00, синий до 20:25.
@Suite struct ShootTimeTests {
    let day = CivilDate(year: 2026, month: 6, day: 10)
    let sunset = LightGoal(wish: .sunset, event: 1200, from: 1140, to: 1225)
    let sunrise = LightGoal(wish: .sunrise, event: 300, from: 250, to: 370)
    let stars = LightGoal(wish: .stars, event: 1300, from: 1300, to: 1440 + 200, darkUntil: 200)

    func shoot(_ id: String, _ from: Int, _ to: Int, kind: RecordKind = .shoot, day d: CivilDate? = nil) -> Session {
        Session(id: id, kind: kind, day: d ?? day, start: from, end: to, duration: to - from, genre: .portrait)
    }

    func busy(_ from: Int, _ dur: Int, day d: CivilDate? = nil, allDay: Bool = false) -> Block {
        var b = Block(id: "b\(from)", kind: .busy, from: d ?? day)
        b.allDay = allDay
        if !allDay { b.start = from; b.duration = dur }
        return b
    }

    func facts(_ goals: [LightGoal] = [], start: Int = 720, spans: [(Int, Int)] = [], step: Int = 5) -> EventForm.TimeFacts {
        EventForm.TimeFacts(goals: goals, defaultStart: start, step: step) { s, d in
            spans.filter { s < $0.1 && $0.0 < s + d }.map(\.1).max()
        }
    }

    func form(start: Int?, fromLight: Bool = false, genre: Genre = .portrait, wishes: [Wish] = []) -> EventForm {
        var f = EventForm.new(id: "n", day: day, start: start, fromLight: fromLight, genre: genre, light: nil, step: 1)
        f.wishes = wishes
        return f
    }

    // MARK: время по умолчанию (ответы 1А и 2Б)

    func def(_ s: [Session] = [], _ b: [Block] = [], step: Int = 5) -> Int {
        ShootTime.defaultStart(day: day, sessions: s, blocks: b, eventsLayer: true, step: step)
    }

    @Test func emptyDayStartsAtNoon() { #expect(def() == 720) }

    @Test func nextShootStartsRightAfterTheLastOne() {
        #expect(def([shoot("a", 720, 780)]) == 780)                                  // 12:00–13:00 → 13:00
        #expect(def([shoot("a", 540, 600)]) == 600)                                  // утренняя: после неё, а не в полдень
        #expect(def([shoot("a", 1020, 1080), shoot("b", 720, 780)]) == 1080)         // после последней, а не первой
        #expect(def([shoot("b", 720, 780), shoot("a", 1020, 1080)]) == 1080)         // порядок в списке ни при чём
    }

    @Test func meetingsAndBusyHoursAlsoTakeTime() {
        #expect(def([shoot("m", 720, 780, kind: .meet)]) == 780)
        #expect(def([], [busy(720, 120)]) == 840)
    }

    @Test func wholeDayBlockDoesNotMoveTime() { #expect(def([], [busy(0, 0, allDay: true)]) == 720) }

    @Test func otherDaysDoNotMatterExceptLastNightTail() {
        let next = day.adding(days: 1), prev = day.adding(days: -1)
        #expect(def([shoot("a", 720, 780, day: next)]) == 720)
        #expect(def([shoot("a", 1320, 1380, day: prev)]) == 720)
        #expect(def([shoot("a", 1320, 1440 + 800, day: prev)]) == 800)               // вчерашняя идёт до 13:20 сегодня
    }

    @Test func endOffTheStepRoundsUpNotIntoTheRecord() { #expect(def([shoot("a", 700, 787)]) == 790) }

    @Test func fullDayStaysOnTheChosenDay() { #expect(def([shoot("a", 1320, 1500)]) == 1435) }

    // MARK: окно света по настоящему солнцу

    @Test func goalsComeFromTheSun() throws {
        let place = Place(latitude: 55.75, longitude: 37.62, zone: ZoneID("Europe/Moscow")!)
        let nov = CivilDate(year: 2026, month: 11, day: 10)
        let sun = SolarDay(date: nov, place: place)
        let set = try #require(LightGoal.of(.sunset, sun: sun))
        #expect(set.from == Int(sun.goldenB!.rounded()) && set.event == Int(sun.set!.rounded()) && set.to == Int(sun.blueB!.rounded()))
        let rise = try #require(LightGoal.of(.sunrise, sun: sun))
        #expect(rise.from == Int(sun.blueA!.rounded()) && rise.event == Int(sun.rise!.rounded()) && rise.to == Int(sun.goldenA!.rounded()))
        #expect(rise.from < rise.event && rise.event < rise.to)
        let dark = try #require(LightGoal.of(.stars, sun: sun))
        #expect(dark.from == Int(sun.astroB!.rounded()))
        #expect(LightGoal.of(.clear, sun: sun) == nil && LightGoal.of(.moon, sun: sun) == nil)
        // Белая ночь: астрономической ночи нет — и предлагать нечего
        #expect(LightGoal.of(.stars, sun: SolarDay(date: CivilDate(year: 2026, month: 6, day: 21), place: place)) == nil)
        // Полярный день в Тромсё: заката нет
        let tromso = Place(latitude: 69.65, longitude: 18.96, zone: ZoneID("Europe/Oslo")!)
        #expect(LightGoal.of(.sunset, sun: SolarDay(date: CivilDate(year: 2026, month: 6, day: 21), place: tromso)) == nil)
    }

    // MARK: правило между концами (ответы 3А, 4А)

    func n(_ start: Int, _ dur: Int = 60, _ g: LightGoal? = nil) -> TimeNudge {
        ShootTime.nudge(start: start, duration: dur, goal: g ?? sunset)
    }

    @Test func tableFromTheQuestion() {
        #expect(n(900) == .ask(to: 1140))           // 15:00 при закате в 20:00 — всплывашка
        #expect(n(1080) == .ask(to: 1140))          // 18:00–19:00 только дошла до окна
        #expect(n(1170) == .keep)                   // 19:30 в золотом часе
        #expect(n(1200) == .keep)                   // ровно закат
        #expect(n(1210) == .keep)                   // синий час
        #expect(n(1225) == .shift(to: 1140))        // ровно конец синего: света уже нет
        #expect(n(1230) == .shift(to: 1140))        // 20:30 после синего — сдвиг без вопроса
        #expect(n(1260) == .shift(to: 1140))        // 21:00 — как сказал Алексей
    }

    @Test func shootTouchingLightFromBeforeIsLeftAlone() {
        #expect(n(1100) == .keep)                   // 18:20–19:20 заходит в окно
        #expect(n(720, 480) == .keep)               // свадьба 12:00–20:00 уже включает закат
    }

    @Test func shootLongerThanWindowEndsWithIt() {
        #expect(ShootTime.target(duration: 60, goal: sunset) == 1140)
        #expect(ShootTime.target(duration: 180, goal: sunset) == 1225 - 180)
        #expect(n(600, 180) == .ask(to: 1045))
    }

    @Test func nothingToDoWhenAlreadyAtTarget() { #expect(n(1140) == .keep) }

    @Test func sunriseWorksTheSameWay() {
        #expect(n(120, 60, sunrise) == .ask(to: 250))
        #expect(n(280, 60, sunrise) == .keep)
        #expect(n(900, 60, sunrise) == .shift(to: 250))
    }

    @Test func starsAreAskedAboutByDayAndLeftAloneInTheDark() {
        #expect(n(900, 60, stars) == .ask(to: 1300))
        #expect(n(1320, 60, stars) == .keep)
        #expect(n(60, 60, stars) == .keep)          // 01:00 — темнота прошлой ночи
        #expect(n(600, 60, stars) == .ask(to: 1300))
    }

    // MARK: новая запись

    @Test func sliderTimeIsTheShootTime() {
        for g in [Genre.portrait, .wedding, .landscape] {
            let f = EventForm.new(id: "n", day: day, start: 827, fromLight: true, genre: g,
                                  light: FormLightWindow(start: 1140, end: 1225), step: 5)
            #expect(f.start == 827 && !f.timeIsProposed, "жанр \(g)")
        }
    }

    @Test func genreChangeKeepsSliderTime() {
        var f = EventForm.new(id: "n", day: day, start: 827, fromLight: true, genre: .portrait,
                              light: FormLightWindow(start: 1140, end: 1225), step: 5)
        f.pick(.wedding, light: FormLightWindow(start: 1140, end: 1225))
        #expect(f.start == 827)
    }

    @Test func slotTapStillSnapsAndStays() {
        let f = EventForm.new(id: "n", day: day, start: 902, fromLight: false, genre: .portrait,
                              light: FormLightWindow(start: 1140, end: 1225), step: 5)
        #expect(f.start == 900 && !f.timeIsProposed)
    }

    @Test func newFormTakesProposedMinute() {
        let f = EventForm.new(id: "n", day: day, start: nil, fromLight: true, proposed: 780, genre: .portrait,
                              light: FormLightWindow(start: 1140, end: 1225), step: 5)
        #expect(f.start == 780 && f.timeIsProposed && !f.timeFromLight)
    }

    // MARK: время, которое никто не называл

    @Test func proposedTimeFollowsSunsetSilentlyWithHighlight() {
        var f = form(start: nil)
        let ask = f.toggleWish(.sunset) { _ in facts([sunset]) }
        #expect(ask == nil && f.start == 1140 && f.timeIsProposed && f.timeShifted)
    }

    @Test func proposedTimeReturnsWhenSunsetIsOff() {
        var f = form(start: nil)
        _ = f.toggleWish(.sunset) { _ in facts([sunset]) }
        let ask = f.toggleWish(.sunset) { _ in facts([], start: 780) }
        #expect(ask == nil && f.start == 780 && f.timeIsProposed && !f.timeShifted && !f.timeFromLight)
    }

    @Test func dayChangeMovesProposedTime() {
        var f = form(start: nil)
        f.setStart(day: day.adding(days: 1))
        #expect(f.settleTime(facts(start: 780)) == nil && f.start == 780 && f.timeIsProposed)
    }

    // MARK: время, названное человеком

    @Test func namedTimeWithSunsetAsksAndMoves() {
        var f = form(start: 900)
        let ask = f.toggleWish(.sunset) { _ in facts([sunset]) }
        #expect(ask == TimeAsk(kind: .light(.sunset), at: 1200, to: 1140, keep: 900))
        #expect(f.start == 900)                     // до ответа время не тронуто
        #expect(f.answer(ask!, move: true) { _ in facts([sunset]) } == nil)
        #expect(f.start == 1140 && !f.timeShifted && !f.timeIsProposed)
    }

    @Test func keepAnswerIsRememberedUntilSunsetIsPressedAgain() {
        var f = form(start: 900)
        let ask = f.toggleWish(.sunset) { _ in facts([sunset]) }!
        #expect(f.answer(ask, move: false) { _ in facts([sunset]) } == nil)
        #expect(f.start == 900)
        f.setStart(minute: 840)
        #expect(f.settleTime(facts([sunset])) == nil && f.start == 840)   // больше не спрашиваем
        _ = f.toggleWish(.sunset) { _ in facts() }                        // сняли
        #expect(f.toggleWish(.sunset) { _ in facts([sunset]) } != nil)    // нажали заново — спрашиваем
    }

    @Test func timeSetLaterAsksOnce() {
        var f = form(start: 1170, wishes: [.sunset])
        #expect(f.settleTime(facts([sunset])) == nil)
        f.setStart(minute: 900)
        #expect(f.settleTime(facts([sunset]))?.to == 1140)
    }

    @Test func lateTimeShiftsSilentlyEvenAfterKeep() {
        var f = form(start: 900, wishes: [.sunset])
        let ask = f.settleTime(facts([sunset]))!
        _ = f.answer(ask, move: false) { _ in facts([sunset]) }
        f.setStart(minute: 1260)
        #expect(f.settleTime(facts([sunset])) == nil && f.start == 1140 && f.timeShifted)
    }

    @Test func handsOnTimeClearsHighlight() {
        var f = form(start: 1260, wishes: [.sunset])
        _ = f.settleTime(facts([sunset]))
        #expect(f.timeShifted)
        f.setStart(minute: 1170)
        #expect(!f.timeShifted)
    }

    @Test func otherWishesAskNothing() {
        var f = form(start: 900)
        #expect(f.toggleWish(.clear) { _ in facts() } == nil)
        #expect(f.toggleWish(.moon) { _ in facts() } == nil)         // «Луна» — в плане обновлений
        #expect(f.start == 900)
    }

    @Test func turningOffDoesNotAsk() {
        var f = form(start: 900, wishes: [.sunset])
        #expect(f.toggleWish(.sunset) { _ in facts() } == nil)
    }

    @Test func turningOneOffDoesNotAskAboutTheOther() {
        var f = form(start: 900, wishes: [.sunset, .stars])
        #expect(f.toggleWish(.stars) { _ in facts([sunset]) } == nil && f.start == 900)
    }

    @Test func wishWithoutLightDoesNotAskAboutTheOrderedOne() {
        var f = form(start: 900, wishes: [.sunset])
        #expect(f.toggleWish(.clear) { _ in facts([sunset]) } == nil && f.start == 900)
    }

    @Test func sunriseIsCheckedAgainstForecast() {
        func sky(_ q: DayQuality?) -> WishSky {
            WishSky(quality: q, sunsetScore: nil, astroNight: true, moonLevel: nil, moonPercent: nil, moonFraction: 0.5)
        }
        #expect(WishCheck.check(.sunrise, sky: sky(.poor), city: false)?.key == "noSunrise")
        #expect(WishCheck.check(.sunrise, sky: sky(.excellent), city: false) == nil)
        #expect(WishCheck.check(.sunrise, sky: sky(nil), city: false) == nil)
    }

    @Test func goalBeyondTheDayIsNotOffered() throws {
        // Южнее белых ночей темнота в июне наступает уже после полуночи: минуты такой съёмки нет на этот день
        let day = CivilDate(year: 2026, month: 6, day: 21)
        let zone = ZoneID("Asia/Barnaul")!
        let late = stride(from: 40.0, to: 56.0, by: 0.25).map { SolarDay(date: day, place: Place(latitude: $0, longitude: 83.77, zone: zone)) }
            .first { ($0.astroB ?? 0) >= 1440 }
        let sun = try #require(late, "широты, где темнота наступает после полуночи, не нашлось")
        #expect(LightGoal.of(.stars, sun: sun) == nil)
    }

    @Test func sunriseAndStarsInTheForm() {
        var a = form(start: 120)
        #expect(a.toggleWish(.sunrise) { _ in facts([sunrise]) } == TimeAsk(kind: .light(.sunrise), at: 300, to: 250, keep: 120))
        var b = form(start: 900)
        #expect(b.toggleWish(.sunrise) { _ in facts([sunrise]) } == nil && b.start == 250 && b.timeShifted)
        var c = form(start: 900)
        #expect(c.toggleWish(.stars) { _ in facts([stars]) } == TimeAsk(kind: .light(.stars), at: 1300, to: 1300, keep: 900))
    }

    @Test func shootTouchingAnyOrderedLightIsLeftAlone() {
        var f = form(start: 1170, wishes: [.sunset, .stars])
        #expect(f.settleTime(facts([sunset, stars])) == nil && f.start == 1170)
    }

    @Test func meetingIsNotAskedAboutLight() {
        var f = EventForm.new(id: "m", day: day, start: 900, fromLight: false, mode: .meet, genre: .portrait, light: nil)
        #expect(f.settleTime(facts([sunset])) == nil && f.start == 900)
    }

    @Test func undatedFormAsksNothing() {
        var f = form(start: 900, wishes: [.sunset])
        f.dayUnset = true
        #expect(f.settleTime(facts([sunset], spans: [(900, 960)])) == nil)
    }

    // MARK: наложение (пункт Г)

    @Test func overlapAsksToMoveRightAfterTheOther() {
        var f = form(start: 720)
        f.setStart(minute: 720)
        let ask = f.settleTime(facts(spans: [(720, 780)]))
        #expect(ask == TimeAsk(kind: .busy, at: 780, to: 780, keep: 720))
        #expect(f.answer(ask!, move: true) { _ in facts(spans: [(720, 780)]) } == nil)
        #expect(f.start == 780)
    }

    @Test func overlapJumpsOverTheNextRecordToo() {
        var f = form(start: 720)
        #expect(f.settleTime(facts(spans: [(720, 780), (800, 860)]))?.to == 860)
    }

    @Test func overlapHasNoSpotBeforeMidnightStaysQuiet() {
        var f = form(start: 1380)
        #expect(f.settleTime(facts(spans: [(1380, 1500)])) == nil)
    }

    @Test func overlapKeepIsRemembered() {
        var f = form(start: 720)
        let ask = f.settleTime(facts(spans: [(720, 780)]))!
        #expect(f.answer(ask, move: false) { _ in facts(spans: [(720, 780)]) } == nil)
        #expect(f.settleTime(facts(spans: [(720, 780)])) == nil && f.start == 720)
    }

    @Test func lightAnswerLeadsToOverlapQuestion() {
        var f = form(start: 900)
        let spans = [(1140, 1200)]
        let ask = f.toggleWish(.sunset) { _ in facts([sunset], spans: spans) }!
        #expect(ask.kind == .light(.sunset))
        let next = f.answer(ask, move: true) { _ in facts([sunset], spans: spans) }
        #expect(next == TimeAsk(kind: .busy, at: 1200, to: 1200, keep: 1140))
    }

    @Test func silentShiftIntoOverlapAsksAboutOverlap() {
        var f = form(start: 1260, wishes: [.sunset])
        let ask = f.settleTime(facts([sunset], spans: [(1140, 1200)]))
        #expect(f.start == 1140 && ask?.kind == .busy)
    }

    @Test func overlapCountsOnlyRealOverlapAndHoursBusy() {
        // Вплотную — не наложение: 13:00 после 12:00–13:00 не спрашивает
        let s = shoot("a", 720, 780)
        let ctx = ClashContext(zones: NoZones(), appOffsetHours: 3, travel: { _, _ in .unavailable }, travelThreshold: 40, eventsLayer: true)
        func c(_ start: Int) -> ClashCandidate {
            ClashCandidate(day: day, start: start, end: start + 60, placeKey: "", skipIndex: nil, wishes: [], point: nil, trip: false, tripOff: false)
        }
        #expect(ShootTime.busyUntil(c(780), sessions: [s], blocks: [], context: ctx) == nil)
        // «Впритык» в другое место и «два заказа на закат» — свои плашки, не повод двигать время
        var far = s
        far.place = "Парк"
        var nearby = c(800)
        nearby.placeKey = "дом"
        #expect(Overlaps.clashes(for: nearby, sessions: [far], blocks: [], context: ctx).contains { $0.kind == .tripTight })
        #expect(ShootTime.busyUntil(nearby, sessions: [far], blocks: [], context: ctx) == nil)
        #expect(ShootTime.busyUntil(c(750), sessions: [s], blocks: [], context: ctx) == 780)
        #expect(ShootTime.busyUntil(c(900), sessions: [], blocks: [busy(880, 60)], context: ctx) == 940)
        #expect(ShootTime.busyUntil(c(900), sessions: [], blocks: [busy(0, 0, allDay: true)], context: ctx) == nil)
    }
}

private struct NoZones: ZoneResolving {
    func utcOffsetHours(latitude: Double, longitude: Double, on day: CivilDate) -> Double { 3 }
}
