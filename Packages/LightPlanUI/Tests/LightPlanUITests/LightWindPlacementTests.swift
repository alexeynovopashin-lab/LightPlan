import Testing
@testable import LightPlanUI

/// 29.8в.27: «Ветер» живёт в раскрытом списке только в «Астро» (слово Алексея 21.10); в «Просто» спойлера нет — строка на месте.
/// Что строка есть в раскрытом списке с тем же текстом, держит `LightTelemetryTests`; зазоры в точках меряет `make lightfit`.
struct LightWindPlacementTests {
    @Test func astroKeepsWindOnlyInTheExpandedList() {
        #expect(!LightWindPlacement.inCollapsedList(astro: true))
    }

    @Test func simpleKeepsWindInTheCollapsedList() {
        #expect(LightWindPlacement.inCollapsedList(astro: false))
    }
}
