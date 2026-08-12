import Testing
@testable import caocap

struct RootCanvasProviderTests {
    @Test func rootStartsEmpty() {
        #expect(RootCanvasProvider.nodes.isEmpty)
        #expect(RootCanvasProvider.snapshot.nodes.isEmpty)
        #expect(RootCanvasProvider.snapshot.projectName == "Root")
        #expect(RootCanvasProvider.snapshot.viewportScale == RootCanvasProvider.defaultViewportScale)
    }
}
