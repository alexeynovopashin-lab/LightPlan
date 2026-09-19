import Testing
import LightPlanDomain

struct DomainModuleTests {
    @Test func moduleLinks() {
        #expect(DomainModule.name == "LightPlanDomain")
    }
}
