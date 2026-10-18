import Testing
import Foundation
import SwiftUI
@testable import LightPlanUI

/// Какое стекло у дисков AR (шаг 29.8в.9а) и подставные места меток для замера (`-LPSunARMarkPos`).
@MainActor
struct SunARGlassStyleTests {

    private func defaults() -> UserDefaults {
        let name = "SunARGlassStyleTests." + UUID().uuidString
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("по умолчанию — системное стекло: оно гнёт и дугу, и кадр (замер в симуляторе); своё — флагом устройства")
    func defaultIsSystemGlass() {
        let d = defaults()
        #expect(SunARGlassStyle.current(d) == .system)
        SunARGlassStyle.set(.own, d)
        #expect(SunARGlassStyle.current(d) == .own)
        SunARGlassStyle.set(.system, d)
        #expect(SunARGlassStyle.current(d) == .system)
        d.set("стекло", forKey: SunARGlassStyle.key)
        #expect(SunARGlassStyle.current(d) == .system, "мусор во флаге — по умолчанию")
    }

    @Test("-LPSunARMarkPos ставит названные метки на точки окна, остальные не трогает; без флага метки как есть")
    func debugPlacedMovesNamedMarks() {
        let marks = [SunARMark(id: "sun.picked", kind: .sun, center: CGPoint(x: 10, y: 20), diameter: 34, fade: 1, altitude: 3),
                     SunARMark(id: "sun.now", kind: .sun, center: CGPoint(x: 30, y: 40), diameter: 48, fade: 0.4, altitude: -2,
                               belowHorizon: true)]
        let key = "LPSunARMarkPos"
        UserDefaults.standard.removeObject(forKey: key)
        #expect(SunARMarks.debugPlaced(marks) == marks)
        UserDefaults.standard.set("sun.now:220.5,461;moon.now:1,1", forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let placed = SunARMarks.debugPlaced(marks)
        #expect(placed[0] == marks[0])
        #expect(placed[1].center == CGPoint(x: 220.5, y: 461))
        #expect(placed[1].diameter == 48 && placed[1].fade == 0.4 && placed[1].altitude == -2 && placed[1].belowHorizon)
    }
}
