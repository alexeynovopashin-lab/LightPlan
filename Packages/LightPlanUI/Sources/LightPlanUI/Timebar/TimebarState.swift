import Foundation
import QuartzCore
import SwiftUI
import LightPlanCore
import LightPlanTimeline
import LightPlanData

/// Таймбар, подключённый к настоящим данным: обёртка над чистой
/// `TimelineMachine` (итерация 16), которая добавляет то, что план отнёс к
/// UI — анимацию срыва и доезжания, отдачу, звук, дорожку света, знаки
/// погоды и луны, кнопку «сейчас».
///
/// Порт `Spikes/TimebarSpike/App/TimebarModel.swift` (итерация 3) на
/// настоящую передачу разряда: там числа были выдуманы (сутки гуляли
/// синусом), здесь их поставляет `SolarDay` того же дня и места.
@MainActor
@Observable
public final class TimebarState {

    public private(set) var place: Place
    public private(set) var machine: TimelineMachine
    public private(set) var solarDay: SolarDay

    /// Луна вместо погоды в ячейках барабана и ленты — купол итерации 18
    /// решит, чем управлять этим тумблером; по умолчанию выключен, барабан
    /// показывает погоду (как в вебе, `skyMode = "sun"` по умолчанию).
    public var showMoon = false

    // MARK: - Анимация яруса и дорожки (срыв)

    public private(set) var laneShift = 0.0
    public private(set) var laneOpacity = 1.0
    public private(set) var ribbonShift = 0.0
    public private(set) var ribbonOpacity = 1.0
    public private(set) var snapping = false

    private let weather: WeatherStore?
    private let language: String
    private let lexicon: Lexicon
    private let clock: ClockText

    let haptics = TimebarHaptics()
    let sound = TimebarSound()

    private var solarDayDate: CivilDate
    private var sliderHolding = false
    private var hourMark = -1

    private let ticker = FrameTicker()
    private var lastTick: CFTimeInterval = 0
    private var bleedFrom: Double?
    private var bleedStart: CFTimeInterval = 0

    private let glideTicker = FrameTicker()
    private var settleFrom = 0.0
    private var settleStart: CFTimeInterval = 0
    private var settleSeconds = 0.21
    private var settleLastCell = 0
    /// Смещение барабана на время доводки; `nil` — барабан стоит там, где
    /// его оставила машина (`machine.drumOffset`).
    public private(set) var drumGlide: Double?

    public init(place: Place, date: CivilDate, weather: WeatherStore? = nil,
                language: String = "ru", ribbonMode: RibbonMode = .drum) {
        self.place = place
        self.machine = TimelineMachine(date: date, place: place, ribbonMode: ribbonMode)
        self.weather = weather
        self.language = language
        self.lexicon = Lexicon(language)
        self.clock = ClockText(language: language)
        self.solarDay = SolarDay(date: date, place: place)
        self.solarDayDate = date
    }

    /// Место сменилось (карта, геокодер) — окно суток пересчитывается на тот
    /// же выбранный день.
    public func setPlace(_ newPlace: Place) {
        place = newPlace
        machine.setPlace(newPlace)
        syncSolarDay()
    }

    public func setRibbonMode(_ mode: RibbonMode) {
        machine.setRibbonMode(mode)
        drumGlide = nil
        stopGlide()
    }

    private func syncSolarDay() {
        guard solarDayDate != machine.selectedDate else { return }
        solarDay = SolarDay(date: machine.selectedDate, place: place)
        solarDayDate = machine.selectedDate
    }

    // MARK: - Слайдер: передача разряда

    public func dragSlider(x: Double, width: Double, thumb: Double) {
        sliderHolding = true
        let outcome = machine.dragSlider(x: x, width: width, thumb: thumb)
        switch outcome {
        case .idle:
            checkHourMark()
            laneShift = 0
            haptics.windStop()
            // Ушли из зоны, не дожав: ярус гаснет сразу (замысел, не
            // случайность — DECISIONS «Ярус возвращается сразу»), а
            // накопленное стравливается тикером.
            if machine.wind.raw != 0 { startBleed(from: machine.wind.raw) }
        case .winding:
            checkHourMark()
            bleedFrom = nil
            laneShift = machine.wind.strain
            haptics.windLevel(machine.wind.progress)
            startTicker()
        case .fired(let dir):
            // Момент передачи разряда сильнее часового щелчка — отдельного
            // детента на стыке суток не даём, трещотка сама несёт вес.
            bleedFrom = nil
            fire(dir)
        }
    }

    public func releaseSlider() {
        sliderHolding = false
        let raw = machine.wind.raw
        machine.endSliderDrag()
        laneShift = 0
        haptics.windStop()
        if raw != 0, !snapping {
            startBleed(from: raw)
        } else {
            machine.resetWind()
            stopTicker()
        }
    }

    private func checkHourMark() {
        let hour = Int(machine.viewMinute) / 60
        guard hourMark != hour else { return }
        if hourMark >= 0 { haptics.detent() }
        hourMark = hour
    }

    // MARK: - Лента и барабан

    public var drumOffset: Double { drumGlide ?? machine.drumOffset }

    public func dragRibbon(translation: Double, clipWidth: Double) {
        stopGlide()
        let shift = machine.dragRibbon(translation: translation, clipWidth: clipWidth)
        if machine.ribbonMode == .lane { checkHourMark() }
        if shift != 0 { syncSolarDay() }
    }

    /// `tapAt` — место пальца, если жест оказался тапом (сдвиг меньше 6 pt),
    /// а не драгом.
    public func releaseRibbon(tapAt x: Double? = nil, clipWidth: Double = 0) {
        machine.endRibbonDrag()
        guard machine.ribbonMode == .drum else { return }
        if let x, let offset = cellOffset(atX: x, clipWidth: clipWidth), offset != 0 {
            drumTap(offset: offset)
        } else {
            drumSettle()
        }
    }

    private func cellOffset(atX x: Double, clipWidth: Double) -> Int? {
        let trackX = x + machine.ribbonOffset(clipWidth: clipWidth)
        let span = TimelineMachine.drumSpan
        let index = Int(floor(trackX / TimelineMachine.drumCell)) - span
        return min(max(index, -span), span)
    }

    /// Тап по соседней ячейке: сутки меняются сразу, барабан доезжает на глазах.
    private func drumTap(offset: Int) {
        guard offset != 0, !glideTicker.isActive else { return }
        let shift = machine.tapDrumCell(offset: offset)
        guard shift != 0 else { return }
        syncSolarDay()
        let from = machine.settleDrum()
        // Чем дальше ехать, тем дольше — одинаковое время на одну и на
        // четыре ячейки читалось бы как рывок.
        startGlide(from: from, seconds: 0.2 + 0.045 * Double(abs(offset)))
    }

    /// Отпустили без тапа: барабан обязан довернуть до своей ячейки сам.
    private func drumSettle() {
        let from = machine.settleDrum()
        guard from != 0 else { return }
        startGlide(from: from, seconds: 0.21)
    }

    private func startGlide(from: Double, seconds: Double) {
        settleFrom = from
        settleStart = CACurrentMediaTime()
        settleSeconds = seconds
        settleLastCell = Int(from.rounded(.towardZero))
        drumGlide = from
        glideTicker.stop()
        glideTicker.start { [weak self] now in self?.glideStep(now) }
    }

    private func stopGlide() {
        glideTicker.stop()
    }

    private func glideStep(_ now: CFTimeInterval) {
        let k = min((now - settleStart) / settleSeconds, 1)
        let value = settleFrom * pow(1 - k, 3)
        drumGlide = value
        // Ячейки щёлкают под окном, пока барабан доезжает.
        let cell = Int(value.rounded(.towardZero))
        if cell != settleLastCell {
            settleLastCell = cell
            haptics.detent()
        }
        if k >= 1 {
            drumGlide = nil
            stopGlide()
        }
    }

    // MARK: - Срыв

    private func fire(_ dir: Int) {
        snapping = true
        stopTicker()
        haptics.snap()
        sound.playSnap()
        syncSolarDay()

        let ribbonOff = machine.ribbonMode == .drum ? 34.0 : 40.0
        withAnimation(.easeIn(duration: 0.09)) {
            laneShift = Double(dir) * 34
            laneOpacity = 0
            ribbonShift = Double(-dir) * ribbonOff
            ribbonOpacity = 0
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(95))
            guard let self else { return }
            self.laneShift = Double(-dir) * 34
            self.ribbonShift = Double(dir) * ribbonOff
            withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.2)) {
                self.laneShift = 0
                self.ribbonShift = 0
            }
            withAnimation(.easeOut(duration: 0.16)) {
                self.laneOpacity = 1
                self.ribbonOpacity = 1
            }
            try? await Task.sleep(for: .milliseconds(210))
            self.snapping = false
        }
    }

    // MARK: - Кадры: взвод удержанием и стравливание

    private func startTicker() {
        guard !ticker.isActive else { return }
        lastTick = CACurrentMediaTime()
        ticker.start { [weak self] now in self?.tick(now) }
    }

    private func stopTicker() {
        ticker.stop()
    }

    private func startBleed(from raw: Double) {
        bleedFrom = raw
        bleedStart = CACurrentMediaTime()
        startTicker()
    }

    private func tick(_ now: CFTimeInterval) {
        defer { lastTick = now }

        if let from = bleedFrom {
            let k = (now - bleedStart) / Transmission.bleed
            machine.bleedWind(from: from, progress: k)
            if k >= 1 {
                machine.resetWind()
                bleedFrom = nil
                stopTicker()
            }
            return
        }

        guard sliderHolding, !snapping else { stopTicker(); return }
        let dt = max(now - lastTick, 0)
        switch machine.dwellSlider(dt: dt) {
        case .fired(let dir): fire(dir)
        case .winding:
            laneShift = machine.wind.strain
            haptics.windLevel(machine.wind.progress)
        case .idle: stopTicker()
        }
    }

    // MARK: - «Сейчас»

    /// Настенное время места прямо сейчас — грубая дата берёт смещение
    /// пояса, а дальше `WallTime` уточняет день и минуту (тот же приём, что
    /// у `jumpToNow` итерации 16).
    private func wallNow() -> WallTime {
        let now = Moment(Date())
        let approx = CivilDate(daysSince1970: Int((Double(now.milliseconds) / 86_400_000).rounded(.down)))
        let offset = place.zone.utcOffsetHours(on: approx)
        return WallTime(moment: now, utcOffsetHours: offset)
    }

    private func minutesNowRelative(to date: CivilDate) -> Double {
        let offset = place.zone.utcOffsetHours(on: date)
        let midnight = WallTime(day: date, minutes: 0).moment(utcOffsetHours: offset)
        let now = Moment(Date())
        return Double(now.milliseconds - midnight.milliseconds) / 60_000
    }

    /// Метка видна, только когда отмотали от настоящего момента больше чем
    /// на две минуты — как в вебе.
    public var nowButtonVisible: Bool {
        abs(machine.viewMinute - minutesNowRelative(to: machine.selectedDate)) > 2
    }

    /// «Сейчас» на шкале выбранных суток — `nil`, если выбран не
    /// сегодняшний день места: тогда у купола (итерация 18) кольца нет
    /// вовсе, а не кольцо на чужом времени.
    public var nowMinute: Minutes? {
        wallNow().day == machine.selectedDate ? minutesNowRelative(to: machine.selectedDate) : nil
    }

    /// «сейчас» — тот же день, просто другое время; «сегодня» — момент
    /// дальше, чем один экран, вернуться нужно и датой тоже.
    public var nowButtonLabel: String {
        "↺ " + lexicon.t(wallNow().day == machine.selectedDate ? "today.now2" : "today.day")
    }

    /// Тот же день — переставляем виджет сразу (лента в «Просто» скрыта, ей
    /// нечем анимировать); другой день — прыжок, как в вебе `applyDate()`.
    public func jumpToNow() {
        stopGlide()
        drumGlide = nil
        let wall = wallNow()
        withAnimation(.easeOut(duration: 0.2)) {
            _ = machine.jumpToNow(day: wall.day, minute: Double(wall.minutes))
        }
        syncSolarDay()
    }

    // MARK: - Края: восход и закат

    public enum EdgeContent {
        case time(icon: String, minutes: Minutes)
        case text(String)
    }

    public var riseEdge: EdgeContent {
        switch solarDay.polar {
        case .day: return .text(lexicon.t("sun.noSetFull"))
        case .night: return .text(lexicon.t("sun.noRiseFull"))
        case .normal: return .time(icon: "sunrise", minutes: solarDay.rise ?? solarDay.mint)
        }
    }

    public var setEdge: EdgeContent? {
        switch solarDay.polar {
        case .day, .night: return nil
        case .normal: return .time(icon: "sunset", minutes: solarDay.set ?? solarDay.maxt)
        }
    }

    public func clockString(_ minutes: Minutes) -> String { clock.fmt(minutes) }

    // MARK: - Даты ленты и барабана

    public func date(offset: Int) -> CivilDate { machine.selectedDate.adding(days: offset) }

    private func asFoundationDate(_ cd: CivilDate) -> Date {
        DateText.carrier(year: cd.year, month: cd.month - 1, day: cd.day, in: timeZone)
    }

    private var timeZone: TimeZone { TimeZone(identifier: place.zone.identifier) ?? .current }
    private var dateText: DateText { DateText(language: language, timeZone: timeZone) }

    /// «21 АВГ» — подпись дня ленты и барабана.
    public func dayLabel(offset: Int) -> String { dateText.dMonShort(asFoundationDate(date(offset: offset))).uppercased() }
    public func weekdayShort(offset: Int) -> String { dateText.wdShort(asFoundationDate(date(offset: offset))) }
    public func dayNumber(offset: Int) -> Int { date(offset: offset).day }

    /// Границы светлой части чужих суток — лента рисует соседей, а не
    /// только свои.
    public func bounds(offset: Int) -> (start: Minutes, end: Minutes) {
        let d = date(offset: offset)
        let day = d == machine.selectedDate ? solarDay : SolarDay(date: d, place: place)
        return (day.mint, day.maxt)
    }

    // MARK: - Знаки барабана и ленты

    /// Погодный знак дня — только там, где есть настоящий прогноз
    /// (инвариант «прибор не врёт»): выдумку офлайн барабан не рисует.
    public func weatherSignName(offset: Int) -> String? {
        guard let weather else { return nil }
        let d = date(offset: offset)
        let day = weather.day(for: d)
        return day.real ? day.quality.signIconName : nil
    }

    /// Фаза луны в этот день, в полдень — как в вебе (`moonPhase(date, 720)`).
    /// У луны, в отличие от погоды, ограничения нет: фаза считается точно на
    /// любую дату.
    public func moonFraction(offset: Int) -> Double {
        MoonPhase(date: date(offset: offset), minutes: 720, zone: place.zone).fraction
    }

    /// Убывающая луна зеркалит знак: освещена левая половина.
    public func moonMirrored(offset: Int) -> Bool {
        MoonPhase(date: date(offset: offset), minutes: 720, zone: place.zone).cycle >= 0.5
    }
}
