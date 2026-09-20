import QuartzCore
import SwiftUI

/// Состояние песочницы. Числа выдуманные: солнца, погоды и записей здесь нет,
/// проверяется только механика края суток.
@Observable
@MainActor
final class TimebarModel {

    /// Сутки от сегодняшних. Меняются только передачей разряда.
    private(set) var day = 0
    /// Время внутри суток, в минутах от полуночи.
    private(set) var minutes = 700.0
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

    // MARK: - Выдуманные сутки

    /// Края суток. Нарочно гуляют ото дня ко дню, чтобы смена даты была видна
    /// не только по подписи. В приложении сюда придёт солнечная модель.
    var dayStart: Double { 300 + 20 * sin(Double(day) / 9) }
    var dayEnd: Double { 1260 - 20 * sin(Double(day) / 9) }

    var date: Date { Calendar.current.date(byAdding: .day, value: day, to: .now) ?? .now }

    /// Где стоит ползунок, 0…1.
    var position: Double {
        let span = dayEnd - dayStart
        return span > 0 ? min(max((minutes - dayStart) / span, 0), 1) : 0
    }

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
        setMinutes(dayStart + p * (dayEnd - dayStart))

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
        minutes = min(max(value, dayStart), dayEnd)
        let hour = Int(minutes) / 60
        if hourMark != hour {
            if hourMark >= 0 { haptics.detent() }
            hourMark = hour
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

        withAnimation(.easeIn(duration: 0.09)) {
            laneShift = Double(dir) * 34
            laneOpacity = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(95))
            day += dir
            // Встаём на противоположный край новых суток.
            minutes = dir > 0 ? dayStart : dayEnd
            hourMark = Int(minutes) / 60
            laneShift = Double(-dir) * 34
            withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.2)) { laneShift = 0 }
            withAnimation(.easeOut(duration: 0.16)) { laneOpacity = 1 }
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
