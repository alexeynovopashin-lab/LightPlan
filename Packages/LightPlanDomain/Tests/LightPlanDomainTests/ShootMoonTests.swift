import Foundation
import Testing
import LightPlanCore
@testable import LightPlanDomain

/// Пожелание «Луна» в форме по времени съёмки (30г.12, вариант А: Алексей 12.11 «А сейчас»).
struct ShootMoonTests {
    // MARK: «Луна» по времени съёмки (30г.12, вариант А)

    func moonSky(_ m: ShootMoon?, q: DayQuality? = .good, frac: Double = 0.5) -> WishSky {
        WishSky(quality: q, sunsetScore: nil, astroNight: true, moonLevel: 0, moonPercent: 0, moonFraction: frac, shootMoon: m)
    }

    /// Луны в съёмку нет — плашка с ответом карточки, раньше облаков и фазы; ответ передаётся как есть.
    @Test func moonAwayFromTheShootComesFirst() {
        let near = NightLight.moonNear(point: LightPoint(minute: 1260, name: nil), arc: 1356...1623, gap: 96)
        for n in [near, .moonNone] {
            let c = WishCheck.check(.moon, sky: moonSky(.away(n), q: .poor, frac: 0.05), city: false)
            #expect(c?.key == "moonAway" && c?.moon == n, "\(n)")
        }
    }

    /// Ночью «почти новая» — как веб (< 25 % в момент съёмки); днём и в сумерках — только луна, которую не увидеть (< 3 %).
    @Test func newMoonOnlyAtNightOrWhenUnseen() {
        #expect(WishCheck.check(.moon, sky: moonSky(.up(percent: 17, night: true)), city: false)?.key == "newMoon")
        #expect(WishCheck.check(.moon, sky: moonSky(.up(percent: 17, night: true)), city: false)?.params["pct"] == "17")
        #expect(WishCheck.check(.moon, sky: moonSky(.up(percent: 17, night: false)), city: false) == nil,
                "тонкий месяц днём или в сумерках — объект съёмки, а не «света не даст»")
        #expect(WishCheck.check(.moon, sky: moonSky(.up(percent: 2, night: false)), city: false)?.key == "newMoon")
        #expect(WishCheck.check(.moon, sky: moonSky(.up(percent: 3, night: false)), city: false) == nil)
        #expect(WishCheck.check(.moon, sky: moonSky(.up(percent: 25, night: true)), city: false) == nil)
        // Фаза в 22:00 при известном времени съёмки не спрашивается.
        #expect(WishCheck.check(.moon, sky: moonSky(.up(percent: 60, night: true), frac: 0.1), city: false) == nil)
        // Облака — после луны, как прежде.
        #expect(WishCheck.check(.moon, sky: moonSky(.up(percent: 60, night: true), q: .poor), city: false)?.key == "moonCloud")
    }

    /// Ответ карточки → луна съёмки: `moonUp` с «ночь ли» по солнцу ниже −6°, `moonNear`/`moonNone` — «нет луны».
    @Test func shootMoonFromTheCardAnswer() {
        let p = LightPoint(minute: 1140, name: "Мост")
        let up = NightLight.moonUp(point: p, arc: 1100...1300, percent: 40)
        #expect(ShootMoon.make(up) { _ in -6.1 } == .up(percent: 40, night: true))
        #expect(ShootMoon.make(up) { _ in -6.0 } == .up(percent: 40, night: false), "−6° ровно — ещё синий час")
        #expect(ShootMoon.make(.moonNone) { _ in 0 } == .away(.moonNone))
        #expect(ShootMoon.make(nil) { _ in 0 } == nil)
        #expect(ShootMoon.make(.starsNone([.notDark])) { _ in 0 } == nil)
    }
}
