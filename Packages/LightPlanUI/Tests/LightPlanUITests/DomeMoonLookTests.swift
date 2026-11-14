import Testing
import SwiftUI
@testable import LightPlanUI

/// 28к.6, луна светлой темы (М2): диск ночно-синий #34476B, белая кромка и освещённая часть, диаметр 22 pt (было 15). Тёмная тема — прежняя.
struct DomeMoonLookTests {
    private func rgb(_ c: Color) -> [Int] {
        let r = c.resolve(in: EnvironmentValues())
        return [r.red, r.green, r.blue].map { Int(($0 * 255).rounded()) }
    }

    @Test func lightMoonIsTwentyTwoPointsNightBlueWithWhiteRim() {
        #expect(DomeMoonLook.discRadius(light: true) * 2 == 22)
        #expect(rgb(DomeMoonLook.disc(light: true)) == [0x34, 0x47, 0x6B])
        #expect(rgb(DomeMoonLook.lit(light: true)) == [255, 255, 255])
        #expect(DomeMoonLook.lightRim > 0)
    }

    /// Тёмная тема побитно прежняя: радиус 7,5 (диаметр 15), диск #16161A, светлая часть #CFD6DE.
    @Test func darkMoonIsUnchanged() {
        #expect(DomeMoonLook.discRadius(light: false) == 7.5)
        #expect(rgb(DomeMoonLook.disc(light: false)) == [0x16, 0x16, 0x1A])
        #expect(rgb(DomeMoonLook.lit(light: false)) == [0xCF, 0xD6, 0xDE])
    }
}
