import Testing
import Foundation
@testable import LightPlanDomain
import LightPlanCore

/// Итерация 26, шаг 3: строка «Звёзды» и «Луна» в карточке — правило новое,
/// у веба его нет (DECISIONS 29.09). Небо подставлено числами, чтобы проверять
/// правило, а не астрономию (её держат тесты ядра 9а).
struct NightLightTests {

    let day = CivilDate(year: 2026, month: 8, day: 14)

    func shoot(_ start: Int, _ end: Int, _ wishes: [Wish], route: [RoutePoint] = []) -> Session {
        var s = Session(id: "n", day: day, start: start, end: end, genre: .landscape)
        s.wishes = wishes
        s.route = route
        return s
    }

    /// Окно 22:30 – 23:59 в сутки съёмки, 00:00 – 03:10 в следующие.
    func night(_ p: GeoPoint?, _ d: CivilDate) -> StarNight {
        let spans: [ClosedRange<Int>] = [0...190, 1350...1439]
        return StarNight(spans: spans, dark: true, moonBlocks: false, moonPercent: 10)
    }

    @Test func starsInsideWindowStitchedOverMidnight() {
        let s = shoot(23 * 60, 25 * 60, [.stars])
        let got = NightLight.stars(s, route: [], spots: [], studios: [], night: night)
        // Окно сшито через полночь: 22:30 – 03:10 следующих суток.
        #expect(got == .starsIn(point: LightPoint(minute: 1380, name: nil), window: 1350...(1440 + 190)))
    }

    @Test func starsMissSaysNearestWindowEvenFar() {
        let s = shoot(14 * 60, 15 * 60, [.stars])
        guard case .starsNear(_, let w, let gap)? = NightLight.stars(s, route: [], spots: [], studios: [], night: night) else {
            Issue.record("ждали «мимо»"); return
        }
        #expect(w == 1350...(1440 + 190))
        #expect(gap == 1350 - 900)
    }

    @Test func starsWithoutWindowSayWhy() {
        let s = shoot(23 * 60, 24 * 60, [.stars])
        let white = NightLight.stars(s, route: [], spots: [], studios: []) { _, _ in
            StarNight(spans: [], dark: false, moonBlocks: false, moonPercent: nil)
        }
        #expect(white == .starsNoDark)
        let moon = NightLight.stars(s, route: [], spots: [], studios: []) { _, _ in
            StarNight(spans: [], dark: true, moonBlocks: true, moonPercent: 87)
        }
        #expect(moon == .starsMoon(percent: 87))
        let low = NightLight.stars(s, route: [], spots: [], studios: []) { _, _ in
            StarNight(spans: [], dark: true, moonBlocks: false, moonPercent: 0)
        }
        #expect(low == .starsLow)
    }

    @Test func noWishNoLine() {
        let s = shoot(23 * 60, 24 * 60, [.sunset])
        #expect(NightLight.stars(s, route: [], spots: [], studios: [], night: night) == nil)
        #expect(NightLight.moon(s, route: [], spots: [], studios: [], arcs: { _, _ in [] }, lit: { _, _, _ in 0 }) == nil)
    }

    @Test func moonUpAtRoutePoint() {
        let route = [RoutePoint(start: 20 * 60, name: "Поле"), RoutePoint(start: 22 * 60, name: "Озеро")]
        let s = shoot(20 * 60, 23 * 60, [.moon], route: route)
        let got = NightLight.moon(s, route: route, spots: [], studios: [],
                                  arcs: { _, _ in [21 * 60...(30 * 60)] }, lit: { _, _, t in t == 22 * 60 ? 64 : 0 })
        #expect(got == .moonUp(point: LightPoint(minute: 1320, name: "Озеро"), arc: 1260...1800, percent: 64))
    }

    @Test func moonMissAndNone() {
        let s = shoot(12 * 60, 13 * 60, [.moon])
        let near = NightLight.moon(s, route: [], spots: [], studios: [],
                                   arcs: { _, _ in [21 * 60...(30 * 60)] }, lit: { _, _, _ in 0 })
        #expect(near == .moonNear(point: LightPoint(minute: 780, name: nil), arc: 1260...1800, gap: 480))
        let none = NightLight.moon(s, route: [], spots: [], studios: [], arcs: { _, _ in [] }, lit: { _, _, _ in 0 })
        #expect(none == .moonNone)
    }

    /// «Звёзды» без «Заката» о золотом часе не говорят (Алексей 29.09).
    @Test func goldenOnlyForSunset() {
        let s = shoot(19 * 60, 20 * 60, [.stars, .moon])
        let golden = LightCase.of(s, route: [], spots: [], studios: [],
                                  evening: { _, _ in EveningLight(goldenB: 1140, blueB: 1230) }, skyIsBad: { _ in false })
        #expect(golden == nil)
        var withSunset = s
        withSunset.wishes = [.sunset]
        let said = LightCase.of(withSunset, route: [], spots: [], studios: [],
                                evening: { _, _ in EveningLight(goldenB: 1140, blueB: 1230) }, skyIsBad: { _ in false })
        #expect(said != nil)
    }
}
