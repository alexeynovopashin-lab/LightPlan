import Testing
import LightPlanCore

struct CoreModuleTests {
    @Test func moduleLinks() {
        #expect(CoreModule.name == "LightPlanCore")
    }
}
