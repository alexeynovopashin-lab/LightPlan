import Testing
@testable import LightPlanUI

/// 29.8в.27 (вариант F): в «Астро» «Ветер», «Небо» и «Тени» не стоят в закрытом списке «Света» — они в раскрытом; в «Просто» спойлера нет,
/// строки на месте. Что «Ветер» есть в раскрытом списке с тем же текстом, держит `LightTelemetryTests`; зазоры в точках меряет `make lightfit`.
struct LightCollapsedListTests {
    @Test func astroHidesWindSkyAndShadowFromTheCollapsedList() {
        for row in [LightCollapsedList.Row.wind, .sky, .shadow] { #expect(!LightCollapsedList.shows(row, astro: true)) }
    }

    @Test func simpleKeepsAllThreeRows() {
        for row in [LightCollapsedList.Row.wind, .sky, .shadow] { #expect(LightCollapsedList.shows(row, astro: false)) }
    }
}
