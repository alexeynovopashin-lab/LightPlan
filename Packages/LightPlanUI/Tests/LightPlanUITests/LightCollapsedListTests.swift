import Testing
import CoreGraphics
@testable import LightPlanUI

/// 29.8в.27: «Астро» подстраивается под измеренную высоту. Шапка «Астро» сжата всегда; важный набор стоит всегда; всё свободное отдаётся
/// строкам «Тени» → «Небо» → «Ветер» (первым уходит «Ветер»); нехватка — полоса под дугой поднимается с 22 до 34 pt. «Просто» — всё
/// на месте. Зазоры в точках меряет `make lightfit`.
struct LightCollapsedListTests {
    private static let row: CGFloat = 35
    private static let heights = [row, row, row]
    private static let action: CGFloat = 38
    /// Низ «Подробно» в базе (без строк, шапка «Астро» сжата, полоса 22) в координатах содержимого: у замера 29.8в.27 это ≈ 530.
    private static let base: CGFloat = 530

    private static func plan(_ vis: CGFloat) -> LightCollapsedList.Plan {
        LightCollapsedList.plan(visibleHeight: vis, baselineBottom: base, actionHeight: action, rowHeights: heights)
    }
    /// Низ «Подробно» после плана: база + строки − подъём полосы.
    private static func bottom(after p: LightCollapsedList.Plan) -> CGFloat {
        let rowsHeight: CGFloat = CGFloat(p.rows) * row
        return base + rowsHeight - p.extraTuck
    }
    /// Запас над зазором 8 pt после плана за вычетом запаса на округление: высота прокрутки − (низ «Подробно» с учётом плана + кнопка + 1).
    private static func spare(_ vis: CGFloat, _ p: LightCollapsedList.Plan) -> CGFloat {
        let used: CGFloat = bottom(after: p) + action
        return vis - used - LightCollapsedList.slack
    }

    /// Замеры 29.8в.27 в запасах базы (высота прокрутки − база − кнопка): 17 Pro Max 100, 15 Pro Max 79, 17 (402) 18, 15/16 (393) −1, SE −211.
    @Test func plansForTheMeasuredPhones() {
        func at(_ spareBase: CGFloat) -> LightCollapsedList.Plan { Self.plan(Self.base + Self.action + spareBase) }
        #expect(at(100) == .init(rows: 2, extraTuck: 0))
        #expect(at(79) == .init(rows: 2, extraTuck: 0))
        #expect(at(18) == .init(rows: 0, extraTuck: 0))
        #expect(at(-1) == .init(rows: 0, extraTuck: 2))
        #expect(at(-211) == .init(rows: 0, extraTuck: 12))
        #expect(at(106) == .init(rows: 3, extraTuck: 0))
        #expect(at(105) == .init(rows: 2, extraTuck: 0))
        #expect(at(71) == .init(rows: 2, extraTuck: 0))
        #expect(at(70) == .init(rows: 1, extraTuck: 0))
        #expect(at(0.5) == .init(rows: 0, extraTuck: 0.5))
    }

    /// Свип высоты видимой области 560…1000 pt шагом 20 (слова Алексея 21.10): число строк не убывает с высотой, полоса растёт только на малых
    /// высотах; пока хватает уступок, кнопка съёмки над панелью (запас ≥ 0); провала нет: запас меньше одной строки,
    /// если только не стоят все три строки.
    @Test func heightSweep() {
        var prev: LightCollapsedList.Plan?
        for vis in stride(from: CGFloat(560), through: 1000, by: 20) {
            let p = Self.plan(vis)
            if let q = prev {
                #expect(p.rows >= q.rows, "строк меньше при большей высоте \(vis)")
                #expect(p.extraTuck <= q.extraTuck, "полоса выросла при большей высоте \(vis)")
            }
            let capped = p.extraTuck >= LightCollapsedList.maxExtraTuck
            if !capped { #expect(Self.spare(vis, p) >= -0.001, "кнопка под панелью при \(vis)") }
            if p.rows < 3 && !capped { #expect(Self.spare(vis, p) < Self.row + 0.001, "провал при \(vis): \(Self.spare(vis, p))") }
            if p.rows > 0 { #expect(p.extraTuck == 0) }
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
            let normalized: CGFloat = measured - rowsHeight + p.extraTuck
            let again = LightCollapsedList.plan(visibleHeight: vis, baselineBottom: normalized, actionHeight: Self.action, rowHeights: Self.heights)
            #expect(p == again, "vis \(vis)")
        }
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

    // MARK: - 30з.5 «Просто»: остаток высоты — строкам

    private static func simple(_ spare: CGFloat, base: Int = 5, hasAir: Bool = false) -> LightCollapsedList.SimplePlan {
        LightCollapsedList.planSimple(spare: spare, baseRows: base + (hasAir ? 1 : 0), optionalHeights: [35, 35])
    }

    /// Нехватка даже на пять строк: «Небо» и «Ветер» не встают, купол поднимается как раньше (сдвиг отрицательный, режет `setShift`).
    @Test func simpleDropsWindFirstThenSky() {
        // Подъём купола общий на все строки: k строк нужны запас ≥ 35k + 1 − maxDomeLift (48), то есть 23 для двух, −12 для одной.
        #expect(Self.simple(23).optionalRows == 2)
        #expect(Self.simple(22.9).optionalRows == 1)    // «Ветер» уходит первым
        #expect(Self.simple(-12).optionalRows == 1)
        #expect(Self.simple(-12.1).optionalRows == 0)   // «Небо» уходит вторым
        #expect(Self.simple(-100).optionalRows == 0)
        #expect(Self.simple(-100).rowExtra == 0)
    }

    /// Пока строки помещаются, купол не опускается ниже базы и поля строк не отрицательные; запас строки не отдают небу.
    @Test func simpleSpareGoesToRowsNotToTheSky() {
        let p = Self.simple(120)                              // 70 на «Небо» и «Ветер», 50 остаётся на семь строк
        #expect(p.optionalRows == 2)
        #expect(p.rowExtra > 6.5 && p.rowExtra <= 50 / 7)
        #expect(p.shift >= 0 && p.shift < 7 * (1.0 / 3) + 0.001)   // небу — только то, что не делится на 1/3 pt
        #expect(abs(7 * p.rowExtra + p.shift - 50) < 0.001)
    }

    @Test func simpleRowGrowthIsCapped() {
        let p = Self.simple(1000)
        #expect(p.rowExtra == LightCollapsedList.maxRowExtra)
        #expect(abs(7 * p.rowExtra + p.shift - 930) < 0.001)
    }

    /// Строки не растут из нехватки, а запас считается от базы: лишний «Воздух» делит остаток на восемь.
    @Test func simpleAirIsOneMoreRow() {
        let p = Self.simple(120, hasAir: true)
        #expect(abs(8 * p.rowExtra + p.shift - 50) < 0.001)
    }

    /// Больше высоты — не меньше строк и не меньше полей; небо не растёт, пока поля не упёрлись в предел.
    @Test func simpleSweepIsMonotone() {
        var prev: LightCollapsedList.SimplePlan?
        for spare in stride(from: CGFloat(-120), through: 400, by: 1) {
            let p = Self.simple(spare)
            if let q = prev {
                #expect(p.optionalRows >= q.optionalRows, "\(spare)")
                #expect(p.optionalRows > q.optionalRows || p.rowExtra >= q.rowExtra - 0.001, "\(spare)")
            }
            if p.rowExtra < LightCollapsedList.maxRowExtra { #expect(p.shift < 8 * (1.0 / 3) + 0.001 || p.shift < 0, "\(spare)") }
            prev = p
        }
    }
}
