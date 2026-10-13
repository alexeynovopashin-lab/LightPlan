import Foundation
import Testing
import LightPlanCore
import LightPlanTimeline
@testable import LightPlanUI

/// 29.6а: смена суток на барабане таймбара у беты — затвор (`swoosh()` в `drumDayFlip`, beta 32248) и тик;
/// в нативе не было ни звука, ни тика. Один затвор на вызов, у ленты часов — тишина, тумблер «Щелчки слайдера» гасит.
@MainActor
struct TimebarDayFlipSoundTests {

    private func state(_ mode: RibbonMode = .drum) -> TimebarState {
        let zone = ZoneID(fixedOffsetHours: 3)
        return TimebarState(place: Place(latitude: 55.75, longitude: 37.62, zone: zone),
                            date: CivilDate(year: 2026, month: 10, day: 13), ribbonMode: mode)
    }

    private func played(_ body: () -> Void) -> [SoundPlay] {
        let before = SoundCenter.journal.count
        body()
        return Array(SoundCenter.journal.dropFirst(before))
    }

    private func enabled(_ on: Bool) -> Any? {
        let was = UserDefaults.standard.object(forKey: SoundCenter.enabledKey)
        UserDefaults.standard.set(on, forKey: SoundCenter.enabledKey)
        return was
    }

    @Test func dragAcrossTheDayBoundarySoundsTheShutterOnce() {
        let was = enabled(true)
        defer { UserDefaults.standard.set(was, forKey: SoundCenter.enabledKey) }
        let s = state()
        s.dragRibbon(translation: 0, clipWidth: 390)      // касание: первый кадр жеста только ставит точку отсчёта
        // 30 pt при ячейке 50 — 0,6 ячейки: порог 0,5 пройден, сутки сменились.
        let log = played { s.dragRibbon(translation: -30, clipWidth: 390) }
        #expect(log.count == 1, "\(log)")
        #expect(log.first?.cue == .shutter && log.first?.gain == 0.2695 && log.first?.event == "timebarDayFlip")
        // Ещё 5 pt — до следующего порога далеко: тишина.
        #expect(played { s.dragRibbon(translation: -35, clipWidth: 390) }.isEmpty)
    }

    @Test func movementInsideTheCellIsSilent() {
        let was = enabled(true)
        defer { UserDefaults.standard.set(was, forKey: SoundCenter.enabledKey) }
        let s = state()
        s.dragRibbon(translation: 0, clipWidth: 390)
        #expect(played { s.dragRibbon(translation: -20, clipWidth: 390) }.isEmpty)
    }

    @Test func severalDaysInOneCallStillOneShutter() {
        let was = enabled(true)
        defer { UserDefaults.standard.set(was, forKey: SoundCenter.enabledKey) }
        let s = state()
        s.dragRibbon(translation: 0, clipWidth: 390)
        // 130 pt = 2,6 ячейки за один вызов: три суток, один затвор — как один `if (flipped) swoosh()`.
        #expect(played { s.dragRibbon(translation: -130, clipWidth: 390) }.count == 1)
    }

    @Test func hourRibbonHasNoShutter() {
        let was = enabled(true)
        defer { UserDefaults.standard.set(was, forKey: SoundCenter.enabledKey) }
        let s = state(.lane)
        s.dragRibbon(translation: 0, clipWidth: 390)
        // 390 pt по ленте суток — 1440 минут: сутки сменились, у беты (`ribbonDayFlip`) звука нет.
        let log = played { s.dragRibbon(translation: -390, clipWidth: 390) }
        #expect(log.filter { $0.cue == .shutter }.isEmpty, "\(log)")
    }

    @Test func toggleOffSilencesTheShutter() {
        let was = enabled(false)
        defer { UserDefaults.standard.set(was, forKey: SoundCenter.enabledKey) }
        let s = state()
        s.dragRibbon(translation: 0, clipWidth: 390)
        #expect(played { s.dragRibbon(translation: -30, clipWidth: 390) }.isEmpty)
    }
}
