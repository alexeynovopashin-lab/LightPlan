import Testing
import LightPlanData

struct DataModuleTests {
    @Test func moduleLinks() {
        #expect(DataModule.name == "LightPlanData")
    }
}
