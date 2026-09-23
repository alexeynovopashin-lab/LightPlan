import Testing
import LightPlanCore
import LightPlanTimeline

/// `TimelineMachine` — выбранный день, минута, окно суток, лента и барабан,
/// машина взвода и срыва (план, итерация 16). Место фиксированное и
/// выдуманное: сама солнечная модель сверена стендом паритета отдельно
/// (итерации 6…9), здесь важна только механика перехода через сутки.
struct TimelineMachineTests {

    static let place = Place(latitude: 45, longitude: 0, zone: ZoneID(fixedOffsetHours: 0))

    // MARK: - Переход через сутки, месяц, год

    @Test func stepViewMinuteCrossesMonthBoundary() {
        let day = CivilDate(year: 2026, month: 1, day: 31)
        let probe = TimelineMachine(date: day, place: Self.place)
        var m = TimelineMachine(date: day, minute: probe.maxt - 5, place: Self.place, ribbonMode: .lane)

        let shift = m.stepViewMinute(by: 40)

        #expect(shift == 1)
        #expect(m.consumeDayShift() == 1)
        #expect(m.selectedDate == CivilDate(year: 2026, month: 2, day: 1))
    }

    @Test func stepViewMinuteCrossesYearBoundary() {
        let day = CivilDate(year: 2026, month: 12, day: 31)
        let probe = TimelineMachine(date: day, place: Self.place)
        var m = TimelineMachine(date: day, minute: probe.maxt - 5, place: Self.place, ribbonMode: .lane)

        let shift = m.stepViewMinute(by: 40)

        #expect(shift == 1)
        #expect(m.selectedDate == CivilDate(year: 2027, month: 1, day: 1))
    }

    @Test func stepViewMinuteBackwardCrossesToPreviousMonth() {
        let day = CivilDate(year: 2026, month: 3, day: 1)
        let probe = TimelineMachine(date: day, place: Self.place)
        var m = TimelineMachine(date: day, minute: probe.mint + 5, place: Self.place, ribbonMode: .lane)

        let shift = m.stepViewMinute(by: -40)

        #expect(shift == -1)
        #expect(m.selectedDate == CivilDate(year: 2026, month: 2, day: 28))
    }

    @Test func tapDrumCellCrossesYearBoundary() {
        var m = TimelineMachine(date: CivilDate(year: 2026, month: 12, day: 31), place: Self.place, ribbonMode: .drum)

        let shift = m.tapDrumCell(offset: 1)

        #expect(shift == 1)
        #expect(m.selectedDate == CivilDate(year: 2027, month: 1, day: 1))
        // Барабан не трогает время суток вовсе.
        let before = m.viewMinute
        #expect(m.tapDrumCell(offset: 0) == 0)
        #expect(m.viewMinute == before)
    }

    @Test func drumDragBeyondOneCellFlipsDay() {
        var m = TimelineMachine(date: CivilDate(year: 2026, month: 6, day: 15), place: Self.place, ribbonMode: .drum)
        let start = m.selectedDate

        // Первый кадр только берёт отсчёт (перевод накопленного сдвига), день
        // ещё не меняется; второй кадр сдвигает на целую ячейку и больше.
        _ = m.dragRibbon(translation: 0, clipWidth: 300)
        let shift = m.dragRibbon(translation: -60, clipWidth: 300)

        #expect(shift == 1)
        #expect(m.selectedDate == start.adding(days: 1))
    }

    // MARK: - Слайдер: передача разряда через полное API

    @Test func slidingToEdgeAndDwellingFiresExactlyOnce() {
        var m = TimelineMachine(date: CivilDate(year: 2026, month: 6, day: 15), place: Self.place)
        let start = m.selectedDate
        let width = 300.0, thumb = 26.0

        // Довели ползунок до правого упора.
        _ = m.dragSlider(x: width, width: width, thumb: thumb)
        #expect(m.viewMinute == m.maxt)

        var fired = 0
        var t = 0.0
        while t < 1.1 {
            if case .fired(let dir) = m.dwellSlider(dt: 1.0 / 60) {
                fired += 1
                #expect(dir == 1)
            }
            t += 1.0 / 60
        }
        #expect(fired == 1)
        #expect(m.selectedDate == start.adding(days: 1))
        // Встали на противоположный край новых суток — метка не гуляет.
        #expect(m.viewMinute == m.mint)
    }

    @Test func slidingToEdgeAndReleasingEarlyNeverFires() {
        var m = TimelineMachine(date: CivilDate(year: 2026, month: 6, day: 15), place: Self.place)
        let start = m.selectedDate
        let width = 300.0, thumb = 26.0

        _ = m.dragSlider(x: width, width: width, thumb: thumb)
        var t = 0.0
        var fired = false
        while t < 0.5 {
            if case .fired = m.dwellSlider(dt: 1.0 / 60) { fired = true }
            t += 1.0 / 60
        }
        #expect(!fired)

        m.endSliderDrag()
        if case .fired = m.dwellSlider(dt: 1.0 / 60) { fired = true }
        #expect(!fired)
        #expect(m.selectedDate == start)
    }

    // MARK: - Перецентровка: положение ленты — чистая функция состояния

    @Test func ribbonOffsetHasNoHiddenDrift() {
        var m = TimelineMachine(date: CivilDate(year: 2026, month: 6, day: 15), place: Self.place, ribbonMode: .lane)
        _ = m.dragRibbon(translation: 0, clipWidth: 300)
        _ = m.dragRibbon(translation: -5_000, clipWidth: 300) // рывок на несколько суток разом

        let fresh = TimelineMachine(date: m.selectedDate, minute: m.viewMinute, place: Self.place, ribbonMode: .lane)
        // Позиция ленты зависит только от публичного состояния, а не от того,
        // каким путём до него дошли, — иначе метка могла бы «поехать».
        #expect(m.ribbonOffset(clipWidth: 300) == fresh.ribbonOffset(clipWidth: 300))
    }

    /// Сутки на ленте нарисованы от полуночи до полуночи (`buildRibbonDay`),
    /// и под меткой должна стоять выбранная минута настенных часов — веб
    /// `ribbonCenterPx`: `(1440 + viewMin) · px/мин − ширина/2`. Машина
    /// вычитала ещё начало окна суток (`mint` = солнечный полдень − 12 ч), и
    /// в Барнауле (+7, полдень 13:17) лента стояла на 77 минут раньше
    /// ползунка — замер пары снимков 19б. На долготе 0 при поясе 0 `mint`
    /// близок к нулю, поэтому тесты с `Self.place` этого не видели.
    @Test func laneCentersWallMinuteNotWindowMinute() {
        let barnaul = Place(latitude: 53.35, longitude: 83.77, zone: ZoneID(fixedOffsetHours: 7))
        let m = TimelineMachine(date: CivilDate(year: 2026, month: 9, day: 23), minute: 780, place: barnaul, ribbonMode: .lane)
        #expect(m.mint > 60)                                  // окно суток правда сдвинуто
        let clip = 392.0, pxPerMin = clip / 1440
        let centerMinute = (m.ribbonOffset(clipWidth: clip) + clip / 2) / pxPerMin - 1440
        #expect(abs(centerMinute - 780) < 1e-9)
    }

    @Test func settleDrumReturnsToZero() {
        var m = TimelineMachine(date: CivilDate(year: 2026, month: 6, day: 15), place: Self.place, ribbonMode: .drum)
        _ = m.tapDrumCell(offset: 2)
        #expect(m.drumOffset == 2)

        let from = m.settleDrum()
        #expect(from == 2)
        #expect(m.drumOffset == 0)
    }

    // MARK: - «Сейчас»

    @Test func jumpToNowMovesDayAndClampsMinute() {
        var m = TimelineMachine(date: CivilDate(year: 2026, month: 3, day: 1), place: Self.place, ribbonMode: .drum)
        _ = m.tapDrumCell(offset: 3) // барабан гулял — «сейчас» должно вернуть его в покой
        let today = CivilDate(year: 2026, month: 3, day: 5)

        let shift = m.jumpToNow(day: today, minute: 700)

        #expect(shift == 1)
        #expect(m.selectedDate == today)
        #expect(m.viewMinute == min(max(700, m.mint), m.maxt))
        #expect(m.drumOffset == 0)
    }

    @Test func jumpToNowSameDayOnlyMovesMinute() {
        let day = CivilDate(year: 2026, month: 3, day: 1)
        var m = TimelineMachine(date: day, place: Self.place)

        let shift = m.jumpToNow(day: day, minute: m.mint + 10)

        #expect(shift == 0)
        #expect(m.selectedDate == day)
    }
}
