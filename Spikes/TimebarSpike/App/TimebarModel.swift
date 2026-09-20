import QuartzCore
import SwiftUI

/// Состояние песочницы. Числа выдуманные: солнца, погоды и записей здесь нет,
/// проверяется только механика края суток.
@Observable
@MainActor
final class TimebarModel {

    /// Сутки от сегодняшних. Меняет их передача разряда, драг ленты и барабан.
    private(set) var day = 0
    /// Настенное время суток, 0…1440. Лента ходит по всем суткам целиком,
    /// ползунок — только по светлой части (`dayStart…dayEnd`), как в вебе:
    /// два контроля смотрят на один момент, но имеют разный ход.
    private(set) var minutes = 700.0

    /// Чем показаны сутки под ползунком.
    enum RibbonMode: String, CaseIterable, Identifiable {
        /// Полоса: трое суток шириной в экран, время течёт непрерывно.
        case lane = "полоса"
        /// Барабан: ячейки по 50 pt, время суток не трогает вовсе.
        case drum = "барабан"

        var id: String { rawValue }
    }

    /// В вебе по умолчанию барабан.
    var ribbonMode = RibbonMode.drum
    /// Смещение барабана в ячейках от выбранной. Между хватами всегда 0.
    private(set) var drumPos = 0.0
    /// Пружина ленты при срыве и её прозрачность.
    private(set) var ribbonShift = 0.0
    private(set) var ribbonOpacity = 1.0
    private(set) var wind = Transmission()

    /// Сдвиг и прозрачность всего яруса: ими рисуется и натяжение, и срыв.
    private(set) var laneShift = 0.0
    private(set) var laneOpacity = 1.0
    private(set) var snapping = false

    private(set) var snaps = 0
    private(set) var grabs = 0
    /// Последние события, сверху свежие. По нему видно «ровно один переход за
    /// одно удержание», которого требует план.
    private(set) var journal: [String] = []

    let meter = FrameMeter()
    /// Не private: характер удара выбирают прямо на экране, пальцем.
    let haptics = Haptics()

    private var holding = false
    private var lastX: Double?
    private var hourMark = -1
    private var ticker: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var bleedFrom: Double?
    private var bleedStart: CFTimeInterval = 0
    private var ribbonLast = 0.0
    private var ribbonDragging = false
    private var settleLink: CADisplayLink?
    private var settleFrom = 0.0
    private var settleStart: CFTimeInterval = 0
    private var settleSeconds = 0.21
    private var settleCell = 0

    // MARK: - Выдуманные сутки

    /// Края суток. Нарочно гуляют ото дня ко дню, чтобы смена даты была видна
    /// не только по подписи. В приложении сюда придёт солнечная модель.
    var dayStart: Double { bounds(offset: 0).start }
    var dayEnd: Double { bounds(offset: 0).end }

    var date: Date { date(offset: 0) }

    func date(offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: day + offset, to: .now) ?? .now
    }

    /// Края светлой части чужих суток — лента рисует соседей, а не только свои.
    func bounds(offset: Int) -> (start: Double, end: Double) {
        let wave = sin(Double(day + offset) / 9)
        return (300 + 20 * wave, 1260 - 20 * wave)
    }

    /// Где стоит ползунок, 0…1. За краями светлой части он упирается, а
    /// лента продолжает идти — время при этом настоящее.
    var position: Double {
        let span = dayEnd - dayStart
        return span > 0 ? min(max((minutes - dayStart) / span, 0), 1) : 0
    }

    /// Рамка барабана подаётся вслед за натяжением ползунка ещё до срыва:
    /// видно, что дата уже под нагрузкой, а не дёргается из состояния покоя.
    var frameShift: Double { wind.strain * 0.6 }

    var clock: String {
        let m = Int(minutes.rounded())
        return String(format: "%02d:%02d", (m / 60) % 24, m % 60)
    }

    // MARK: - Жест

    /// Палец ведёт. `x` — в координатах дорожки, `width` — её ширина.
    func drag(x: Double, width: Double, thumb: Double) {
        if !holding {
            holding = true
            grabs += 1
            wind.grab()
            meter.start()
            note("взяли рукоятку")
        }
        guard !snapping, !wind.spent else {
            lastX = x
            return
        }

        let usable = max(width - thumb, 1)
        let p = min(max((x - thumb / 2) / usable, 0), 1)
        setMinutes(min(max(dayStart + p * (dayEnd - dayStart), dayStart), dayEnd))

        // Взвод начинается, только когда значение уже на упоре И палец
        // продолжает идти наружу.
        let atMax = minutes >= dayEnd - 0.5
        let atMin = minutes <= dayStart + 0.5
        let side = atMax && x > width - Transmission.edgeZone ? 1
                 : atMin && x < Transmission.edgeZone ? -1 : 0

        let dx = x - (lastX ?? x)
        lastX = x

        guard side != 0 else {
            // Ушли из зоны: накопленное стравливается, ярус возвращается сразу
            // (замысел, а не случайность — Алексей, 20 сентября 2026).
            if wind.raw != 0 { startBleed() }
            wind.release()
            haptics.windStop()
            laneShift = 0
            return
        }
        stopBleed()
        switch wind.drag(dx: dx, side: side) {
        case .fire(let dir): fire(dir)
        case .winding:
            laneShift = wind.strain
            haptics.windStart()
            haptics.windLevel(wind.progress)
            startTicker()
        case .idle:
            laneShift = 0
        }
    }

    /// Рукоятку отпустили.
    func release() {
        holding = false
        lastX = nil
        meter.stop()
        let had = wind.raw
        wind.release()
        haptics.windStop()
        laneShift = 0
        if had != 0, !snapping {
            note("отпустили не дожав, стравлено")
            startBleed()
        } else {
            wind.reset()
            stopTicker()
        }
    }

    private func setMinutes(_ value: Double) {
        minutes = value
        let hour = Int(minutes) / 60
        if hourMark != hour {
            if hourMark >= 0 { haptics.detent() }
            hourMark = hour
        }
    }

    // MARK: - Лента и барабан

    /// Куда сдвинута дорожка. Позицию всегда ставит код: нативного скролла
    /// здесь нет вовсе, иначе резиновый откат на упоре спорит с нашим счётом
    /// и даты «убегают» (DECISIONS, «Лента без нативного скролла»).
    func ribbonOffset(clipWidth: Double) -> Double {
        switch ribbonMode {
        case .lane:
            let pxPerMin = clipWidth / 1440
            return (1440 + minutes) * pxPerMin - clipWidth / 2
        case .drum:
            return (Double(Self.drumSpan) + drumPos) * Self.drumCell
                 + Self.drumCell / 2 - clipWidth / 2
        }
    }

    /// Ячейка барабана и сколько их по сторонам от выбранной.
    static let drumCell = 50.0
    static let drumSpan = 4

    /// `translation` — накопленный сдвиг пальца от начала жеста.
    ///
    /// Начало жеста ловится здесь, а не отдельным «взяли»: SwiftUI не обещает,
    /// что первый кадр придёт с нулевым сдвигом, и на нём уже может быть
    /// несколько точек. Пока началом считался ровно ноль, в счётчике оставался
    /// сдвиг прошлого жеста — и первый же кадр давал огромную разницу: дата
    /// менялась до того, как палец поехал (Алексей, 20 сентября 2026).
    func ribbonDrag(translation: Double, clipWidth: Double) {
        if !ribbonDragging {
            ribbonDragging = true
            drumStopSettle()
            meter.start()
            // Отсчёт всегда от того места, где жест застали.
            ribbonLast = translation
        }
        let dx = translation - ribbonLast
        ribbonLast = translation
        switch ribbonMode {
        case .lane:
            let pxPerMin = clipWidth / 1440
            setMinutes(wallFlip(minutes - dx / pxPerMin))
        case .drum:
            drumPos = drumFlip(drumPos - dx / Self.drumCell)
        }
    }

    /// Отпустили. `tapAt` — место пальца, если жест оказался тапом, а не
    /// драгом. Порог тот же, что в вебе: сдвиг меньше 6 pt — это тап.
    /// Без него любое дрожание пальца на ячейке перекидывало дату.
    func ribbonRelease(tapAt x: Double? = nil, clipWidth: Double = 0) {
        guard ribbonDragging else { return }
        ribbonDragging = false
        ribbonLast = 0
        meter.stop()
        guard ribbonMode == .drum else { return }
        if let x, case let offset = cellOffset(atX: x, clipWidth: clipWidth), offset != 0 {
            drumTap(offset: offset)
        } else {
            drumSettle()
        }
    }

    /// Какая ячейка лежит под пальцем, считая от выбранной.
    private func cellOffset(atX x: Double, clipWidth: Double) -> Int {
        let trackX = x + ribbonOffset(clipWidth: clipWidth)
        let index = Int(floor(trackX / Self.drumCell)) - Self.drumSpan
        return min(max(index, -Self.drumSpan), Self.drumSpan)
    }

    /// Тап по соседней ячейке. Сутки меняются сразу, а барабан доезжает до
    /// них на глазах: ячейки уже новые, но дорожка стоит там, где стояла, и
    /// съезжает к центру. В вебе тап мгновенный (замерено по коду), это
    /// улучшение по просьбе Алексея, 20 сентября 2026.
    func drumTap(offset: Int) {
        guard offset != 0, !gliding else { return }
        day += offset
        drumPos = Double(offset)
        // Чем дальше ехать, тем дольше: одинаковое время на одну и на четыре
        // ячейки читается как рывок.
        glide(from: Double(offset), seconds: 0.2 + 0.045 * Double(abs(offset)))
    }

    /// Переход через полночь: сразу, без порога и паузы. Читать собственное
    /// положение обратно не нужно — значит нечему рассинхронизироваться.
    private func wallFlip(_ t: Double) -> Double {
        var t = t
        while t < 0 || t >= 1440 {
            let dir = t < 0 ? -1 : 1
            day += dir
            t -= Double(dir) * 1440
        }
        return t
    }

    /// Барабан крутит только сутки: время суток он не трогает вовсе, ровно
    /// как в одометре младший разряд не трогает старший.
    private func drumFlip(_ pos: Double) -> Double {
        var pos = pos
        var flipped = false
        while pos < -0.5 || pos > 0.5 {
            let dir = pos > 0 ? 1 : -1
            day += dir
            pos -= Double(dir)
            flipped = true
        }
        // Лёгкий щелчок, а не трещотка: трещотка — это переданный разряд,
        // редкое усилие. Барабан же листают пачками, и тяжёлый удар на каждых
        // сутках читается как пулемёт (Алексей: «плохие ощущения»). В вебе
        // отдачи здесь нет вовсе, сравнивать не с чем.
        if flipped { haptics.detent() }
        return pos
    }

    /// Осадка: барабан обязан довернуть до своей ячейки сам, а не замереть
    /// между. Кубическое затухание, те же 210 мс, что у въезда после срыва.
    private func drumSettle() {
        guard drumPos != 0 else { return }
        glide(from: drumPos, seconds: 0.21)
    }

    /// Доводка барабана к своей ячейке: кубическое затухание, как в вебе.
    private func glide(from: Double, seconds: Double) {
        drumStopSettle()
        settleFrom = from
        settleStart = CACurrentMediaTime()
        settleSeconds = seconds
        settleCell = Int(from.rounded(.towardZero))
        let link = CADisplayLink(target: self, selector: #selector(settleStep))
        link.add(to: .main, forMode: .common)
        settleLink = link
    }

    private var gliding: Bool { settleLink != nil }

    private func drumStopSettle() {
        settleLink?.invalidate()
        settleLink = nil
    }

    @objc private func settleStep(_ link: CADisplayLink) {
        let k = min((link.timestamp - settleStart) / settleSeconds, 1)
        drumPos = settleFrom * pow(1 - k, 3)
        // Ячейки щёлкают под окном, пока барабан доезжает: механизм с
        // фиксатором, а не беззвучный слайд.
        let cell = Int(drumPos.rounded(.towardZero))
        if cell != settleCell {
            settleCell = cell
            haptics.detent()
        }
        if k >= 1 {
            drumPos = 0
            drumStopSettle()
        }
    }

    // MARK: - Срыв

    /// Ярус улетает за край и въезжает с другой стороны: видимая передача
    /// разряда, а не прыжок даты. Тайминги 90/200 мс — из веба.
    private func fire(_ dir: Int) {
        guard !snapping else { return }
        snapping = true
        wind.fired()
        stopTicker()
        haptics.snap()
        snaps += 1
        note("срыв \(dir > 0 ? "вперёд" : "назад"), удержание №\(grabs)")

        // Лента и барабан срываются тем же движением, что и ярус ползунка:
        // два разряда одного механизма должны быть видимо связаны, а не
        // ехать порознь. Ход у ленты свой — 40 pt против 34 у барабана.
        let ribbonOff = ribbonMode == .drum ? 34.0 : 40.0
        withAnimation(.easeIn(duration: 0.09)) {
            laneShift = Double(dir) * 34
            laneOpacity = 0
            ribbonShift = Double(-dir) * ribbonOff
            ribbonOpacity = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(95))
            day += dir
            // Встаём на противоположный край новых суток.
            minutes = dir > 0 ? dayStart : dayEnd
            hourMark = Int(minutes) / 60
            laneShift = Double(-dir) * 34
            ribbonShift = Double(dir) * ribbonOff
            withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.2)) {
                laneShift = 0
                ribbonShift = 0
            }
            withAnimation(.easeOut(duration: 0.16)) {
                laneOpacity = 1
                ribbonOpacity = 1
            }
            try? await Task.sleep(for: .milliseconds(210))
            snapping = false
        }
    }

    // MARK: - Кадры

    private func startTicker() {
        guard ticker == nil else { return }
        lastTick = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        ticker = link
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func startBleed() {
        bleedFrom = wind.raw
        bleedStart = CACurrentMediaTime()
        startTicker()
    }

    private func stopBleed() {
        bleedFrom = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTick = now }

        if let from = bleedFrom {
            let k = (now - bleedStart) / Transmission.bleed
            wind.bleed(from: from, k: k)
            if k >= 1 {
                wind.reset()
                bleedFrom = nil
                stopTicker()
            }
            return
        }

        // Упершийся палец двигать уже некуда — доводит удержанием.
        guard holding, !snapping else {
            stopTicker()
            return
        }
        let dt = max(now - lastTick, 0)
        switch wind.dwell(dt: dt) {
        case .fire(let dir): fire(dir)
        case .winding:
            laneShift = wind.strain
            haptics.windLevel(wind.progress)
        case .idle: stopTicker()
        }
    }

    private func note(_ text: String) {
        let stamp = Date.now.formatted(date: .omitted, time: .standard)
        journal.insert("\(stamp)  \(text)", at: 0)
        if journal.count > 12 { journal.removeLast() }
    }
}
