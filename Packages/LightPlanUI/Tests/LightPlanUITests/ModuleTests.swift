import Testing
import LightPlanUI

struct UIModuleTests {
    @Test func moduleLinks() {
        #expect(UIModule.name == "LightPlanUI")
    }
}
