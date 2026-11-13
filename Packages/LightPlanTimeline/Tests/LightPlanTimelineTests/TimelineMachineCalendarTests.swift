import Testing
import LightPlanCore
import LightPlanTimeline

/// 30з.4: ползунок «Света» ходит по календарной шкале −60…1500 минут выбранного дня. Окно не зависит от места и сезона;
/// час до полуночи и час после — живое время соседних суток.
struct TimelineMachineCalendarTests {

    static let tomsk = Place(latitude: 56.49, longitude: 84.95, zone: ZoneID(fixedOffsetHours: 7))
    static let tromso = Place(latitude: 69.65, longitude: 18.96, zone: ZoneID(fixedOffsetHours: 1))
    static let day = CivilDate(year: 2026, month: 11, day: 13)

    private func machine(minute: Minutes? = nil, place: Place = tomsk, mode: RibbonMode = .lane) -> TimelineMachine {
        TimelineMachine(date: Self.day, minute: minute, place: place, ribbonMode: mode, scale: .calendar)
    }

    @Test("окно −60…1500 в любом городе, в июне и в декабре")
    func windowIsFixed() {
        for place in [Self.tomsk, Self.tromso] {
            for date in [CivilDate(year: 2026, month: 6, day: 21), CivilDate(year: 2026, month: 12, day: 21)] {
                let m = TimelineMachine(date: date, place: place, scale: .calendar)
                #expect(m.mint == -60 && m.maxt == 1500)
            }
        }
        // Прежняя (солнечная) машина — как была: окно 1440 минут вокруг солнечного полудня.
        let old = TimelineMachine(date: Self.day, place: Self.tomsk)
        #expect(old.maxt - old.mint == 1440 && old.mint != -60)
    }

    @Test("перетаскивание: левый край — минута −60, 720 — середина, правый край — 1500")
    func sliderMapsFractionToMinute() {
        // Каждый край — отдельным касанием: рывок через всю дорожку к упору был бы срывом суток, а проверяем только соответствие.
        for (x, minute) in [(14.0, -60.0), (200.0, 720.0), (386.0, 1500.0), (14.0 + 372.0 * 60 / 1560, 0.0), (14.0 + 372.0 * 1500 / 1560, 1440.0)] {
            var m = machine(minute: 720)
            _ = m.dragSlider(x: x, width: 400, thumb: 28)
            #expect(abs(m.viewMinute - minute) < 1e-6 && m.selectedDate == Self.day, "x=\(x) → \(m.viewMinute), ждали \(minute)")
            m.endSliderDrag()
        }
    }

    @Test("00:00 и 24:00 лежат внутри шкалы, не на краях")
    func midnightsAreInside() {
        var m = machine(minute: 0)
        #expect(m.viewMinute == 0)
        m = machine(minute: 1440)
        #expect(m.viewMinute == 1440 && m.selectedDate == Self.day)
    }

    @Test("за правым краем сутки меняются, минута остаётся тем же моментом: 1500 → следующий день, 60")
    func steppingPastTheRightEndKeepsTheMoment() {
        var m = machine(minute: 1490)
        let shift = m.stepViewMinute(by: 30)                        // 1520 = 01:20 следующего дня
        #expect(shift == 1 && m.selectedDate == Self.day.adding(days: 1))
        #expect(m.viewMinute == 80)
    }

    @Test("за левым краем — предыдущий день: −61 → 1379")
    func steppingPastTheLeftEnd() {
        var m = machine(minute: -50)
        let shift = m.stepViewMinute(by: -11)
        #expect(shift == -1 && m.selectedDate == Self.day.adding(days: -1))
        #expect(m.viewMinute == 1379)
    }

    @Test("срыв у правого края не отбрасывает ползунок на сутки назад — тот же момент в новых сутках")
    func windUpCarriesTheMoment() {
        var m = machine(minute: 720)
        var outcome = TimelineOutcome.idle
        // Давим к правому краю, пока не сорвёт.
        for _ in 0..<400 {
            outcome = m.dragSlider(x: 399, width: 400, thumb: 28)
            if case .fired = outcome { break }
            outcome = m.dwellSlider(dt: 0.05)
            if case .fired = outcome { break }
        }
        guard case .fired(let dir) = outcome else { Issue.record("не сорвало: \(outcome)"); return }
        #expect(dir == 1 && m.selectedDate == Self.day.adding(days: 1))
        #expect(m.viewMinute > 40 && m.viewMinute < 80, "viewMinute \(m.viewMinute)")   // ≈ 01:00 новых суток
    }

    @Test("«Когда смотрим»: 00:10 остаётся в выбранном дне, а не уходит к соседнему, как при солнечном окне")
    func showKeepsAnyMinuteOfTheDay() {
        var m = machine()
        let dir = m.show(day: Self.day, minute: 10)
        #expect(dir == 0 && m.selectedDate == Self.day && m.viewMinute == 10)
        // Прежняя машина в Томске (окно с 01:04) переводила бы 00:10 в предыдущие сутки.
        var old = TimelineMachine(date: Self.day, place: Self.tomsk)
        _ = old.show(day: Self.day, minute: 10)
        #expect(old.selectedDate != Self.day)
    }

    @Test("«сейчас» в 00:30 не прижимается к краю окна")
    func jumpToNowJustAfterMidnight() {
        var m = machine(minute: 720)
        _ = m.jumpToNow(day: Self.day, minute: 30)
        #expect(m.viewMinute == 30)
    }

    @Test("лента часов: смещение считается и для минут меньше нуля")
    func ribbonOffsetForNegativeMinutes() {
        let m = machine(minute: -30)
        let off = m.ribbonOffset(clipWidth: 360)
        #expect(off == (1440 - 30) * (360.0 / 1440) - 180)
    }

    @Test("setPlace на другое место окно не двигает")
    func windowSurvivesPlaceChange() {
        var m = machine(minute: -30)
        m.setPlace(Self.tromso)
        #expect(m.mint == -60 && m.maxt == 1500 && m.viewMinute == -30)
    }
}
