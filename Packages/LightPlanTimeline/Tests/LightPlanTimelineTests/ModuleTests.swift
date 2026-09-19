import Testing
import LightPlanTimeline

struct TimelineModuleTests {
    @Test func moduleLinks() {
        #expect(TimelineModule.name == "LightPlanTimeline")
    }
}
