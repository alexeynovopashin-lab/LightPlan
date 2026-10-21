import Testing
import CoreGraphics
@testable import LightPlanUI

/// 29.8в.27: «Астро» подстраивается под измеренную высоту. Важный набор стоит всегда; «Тени» → «Небо» → «Ветер» — пока помещается кнопка
/// «Запланировать съёмку» над панелью; не хватает — уходят «Ветер», «Небо», «Тени», потом сжимается шапка, потом поднимается полоса под
/// дугой. «Просто» — всё на месте. Зазоры в точках меряет `make lightfit`.
struct LightCollapsedListTests {
    private static let row: CGFloat = 35
    private static let heights = [row, row, row]
    private static let action: CGFloat = 38
    /// Низ «Подробно» в базе (без строк, шапка в четыре строки, полоса 22) в координатах содержимого: у замера 29.8в.27 это ≈ 544.
    private static let base: CGFloat = 544
    /// Выигрыш сжатой шапки при заданных месте и погоде (`plan` берёт его по умолчанию).
    private static let gain: CGFloat = 14

    /// Низ «Подробно» после плана: база + строки − выигрыш сжатой шапки − подъём полосы.
    private static func bottom(after p: LightCollapsedList.Plan) -> CGFloat {
        let rowsHeight: CGFloat = CGFloat(p.rows) * row
        let headerSaved: CGFloat = p.compactHeader ? gain : 0
        return base + rowsHeight - headerSaved - p.extraTuck
    }

    private static func plan(_ vis: CGFloat) -> LightCollapsedList.Plan {
        LightCollapsedList.plan(visibleHeight: vis, baselineBottom: base, actionHeight: action, rowHeights: heights)
    }
    /// Запас над зазором 8 pt после плана за вычетом запаса на округление: высота прокрутки − (низ «Подробно» с учётом плана + кнопка + 1).
    private static func spare(_ vis: CGFloat, _ p: LightCollapsedList.Plan) -> CGFloat {
        let used: CGFloat = bottom(after: p) + action
        return vis - used - LightCollapsedList.slack
    }

    /// Замеры 29.8в.27 в запасах базы (высота прокрутки − база − кнопка): 17 Pro Max 86, 15 Pro Max 65, 17 (402) 4, 15/16 (393) −15, SE −225.
    @Test func plansForTheMeasuredPhones() {
        func at(_ spareBase: CGFloat) -> LightCollapsedList.Plan { Self.plan(Self.base + Self.action + spareBase) }
        #expect(at(86) == .init(rows: 2, compactHeader: false, extraTuck: 0))
        #expect(at(65) == .init(rows: 1, compactHeader: false, extraTuck: 0))
        #expect(at(4) == .init(rows: 0, compactHeader: false, extraTuck: 0))
        #expect(at(-15) == .init(rows: 0, compactHeader: true, extraTuck: 2))
        #expect(at(-225) == .init(rows: 0, compactHeader: true, extraTuck: 12))
        #expect(at(106) == .init(rows: 3, compactHeader: false, extraTuck: 0))
        #expect(at(105) == .init(rows: 2, compactHeader: false, extraTuck: 0))
        #expect(at(0.5) == .init(rows: 0, compactHeader: true, extraTuck: 0))
    }

    /// Свип высоты видимой области 560…1000 pt шагом 20 (слова Алексея 21.10): число строк не убывает с высотой, шапка и полоса сжимаются
    /// только на малых высотах; пока хватает уступок, кнопка съёмки над панелью (запас ≥ 0); провала нет: запас меньше одной строки,
    /// если только не стоят все три строки на несжатом экране.
    @Test func heightSweep() {
        var prev: LightCollapsedList.Plan?
        for vis in stride(from: CGFloat(560), through: 1000, by: 20) {
            let p = Self.plan(vis)
            if let q = prev {
                #expect(p.rows >= q.rows, "строк меньше при большей высоте \(vis)")
                #expect(!(p.compactHeader && !q.compactHeader), "шапка сжалась при большей высоте \(vis)")
                #expect(p.extraTuck <= q.extraTuck, "полоса выросла при большей высоте \(vis)")
            }
            let capped = p.compactHeader && p.extraTuck >= LightCollapsedList.maxExtraTuck
            if !capped { #expect(Self.spare(vis, p) >= -0.001, "кнопка под панелью при \(vis)") }
            if p.rows < 3 && !capped { #expect(Self.spare(vis, p) < Self.row + 0.001, "провал при \(vis): \(Self.spare(vis, p))") }
            if p.rows > 0 { #expect(!p.compactHeader && p.extraTuck == 0) }
            prev = p
        }
    }

    /// После показа строк «Подробно» опустилось на их высоту; решение считается от базы и не мигает.
    @Test func decisionDoesNotFlipOnceApplied() {
        for vis in stride(from: CGFloat(560), through: 1000, by: 1) {
            let p = Self.plan(vis)
            // Измерение после применения плана, приведённое к базе так же, как это делает экран.
            let measured: CGFloat = Self.bottom(after: p)
            let rowsHeight: CGFloat = CGFloat(p.rows) * Self.row
            let headerSaved: CGFloat = p.compactHeader ? Self.gain : 0
            let normalized: CGFloat = measured - rowsHeight + headerSaved + p.extraTuck
            let again = LightCollapsedList.plan(visibleHeight: vis, baselineBottom: normalized, actionHeight: Self.action, rowHeights: Self.heights)
            #expect(p == again, "vis \(vis)")
        }
    }

    /// Без места и погоды шапка и так в три строки: сжатие ничего не даёт, нехватку берёт на себя только полоса под дугой.
    @Test func headerGainNeedsSomethingToRemove() {
        #expect(LightCollapsedList.headerGain(hasPlaceSub: true, hasWeather: true) == 14)
        #expect(LightCollapsedList.headerGain(hasPlaceSub: true, hasWeather: false) == 14)
        #expect(LightCollapsedList.headerGain(hasPlaceSub: false, hasWeather: true) == 14)
        #expect(LightCollapsedList.headerGain(hasPlaceSub: false, hasWeather: false) == 0)
        let p = LightCollapsedList.plan(visibleHeight: Self.base + Self.action - 5, baselineBottom: Self.base, actionHeight: Self.action,
                                        rowHeights: Self.heights, headerGain: 0)
        #expect(p == .init(rows: 0, compactHeader: false, extraTuck: 6))
    }

    @Test func rowsComeBackInTheirOnScreenOrder() {
        #expect(LightCollapsedList.shown(astro: true, fit: 0, hasForecast: true).isEmpty)
        #expect(LightCollapsedList.shown(astro: true, fit: 1, hasForecast: true) == [.shadow])
        #expect(LightCollapsedList.shown(astro: true, fit: 2, hasForecast: true) == [.shadow, .sky])
        #expect(LightCollapsedList.shown(astro: true, fit: 3, hasForecast: true) == [.shadow, .sky, .wind])
        #expect(LightCollapsedList.shown(astro: true, fit: 9, hasForecast: true) == [.shadow, .sky, .wind])
    }

    /// Без прогноза у экрана только «Тени» (небо и ветер — из прогноза).
    @Test func withoutForecastOnlyShadowExists() {
        #expect(LightCollapsedList.present(hasForecast: false) == [.shadow])
        #expect(LightCollapsedList.shown(astro: true, fit: 3, hasForecast: false) == [.shadow])
    }

    @Test func simpleAlwaysShowsEverything() {
        #expect(LightCollapsedList.shown(astro: false, fit: 0, hasForecast: true) == [.shadow, .sky, .wind])
        #expect(LightCollapsedList.shown(astro: false, fit: 0, hasForecast: false) == [.shadow])
    }
}
