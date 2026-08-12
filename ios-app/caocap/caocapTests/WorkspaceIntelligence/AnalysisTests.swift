import Foundation
import Testing
@testable import caocap

struct AnalysisTests {

    @Test func analyzerIdentifiesEmptyCode() throws {
        let nodes = [
            SpatialNode(type: .miniApp, position: .zero, title: "Mini-App", miniApp: MiniAppState(codeText: ""))
        ]
        let analyzer = ProjectAnalyzer()
        let suggestions = analyzer.analyze(nodes: nodes)
        
        #expect(suggestions.contains { $0.title == "Mini-App code is empty" })
    }

    @Test func analyzerDoesNotSuggestAnythingForEmptyCanvas() throws {
        let nodes: [SpatialNode] = []
        let analyzer = ProjectAnalyzer()
        let suggestions = analyzer.analyze(nodes: nodes)
        
        #expect(suggestions.isEmpty)
    }

    @Test func analyzerIdentifiesIncompleteHTML() {
        let nodes = [
            SpatialNode(
                type: .miniApp,
                position: .zero,
                title: "Mini-App",
                miniApp: MiniAppState(codeText: "<h1>Fragment only</h1>")
            )
        ]
        let suggestions = ProjectAnalyzer().analyze(nodes: nodes)

        #expect(suggestions.contains { $0.title == "Mini-App code may be incomplete" })
    }

    @Test func analyzerFlagsPendingNodeReviews() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bundle = ReviewBundleItem(
            items: [
                PendingReviewItem(
                    targetLabel: "Rename Node",
                    summary: "Pending",
                    preview: "title=Home",
                    source: .appAction(.renameNode, ["nodeId": UUID().uuidString, "title": "Home"])
                )
            ]
        )
        let record = CoCaptainReviewLifecycle.Record(bundle: bundle)
        var agentState = NodeAgentState()
        agentState.pendingReviewBundlesData = [try encoder.encode(record)]

        let nodes = [
            SpatialNode(
                type: .miniApp,
                position: .zero,
                title: "Mini-App",
                miniApp: MiniAppState(codeText: "<html><body><h1>Hi</h1></body></html>"),
                agentState: agentState
            )
        ]

        let suggestions = ProjectAnalyzer().analyze(nodes: nodes)
        #expect(suggestions.contains { $0.title == "Mini-App has pending CoCaptain reviews" })
    }

    @MainActor
    @Test func viewModelDoesNotShowSuggestionsForEmptyCanvas() throws {
        let viewModel = CoCaptainViewModel()
        let store = ProjectStore(fileName: "test_project.json", projectName: "Test")
        
        #expect(viewModel.analysisItems.isEmpty)
        
        viewModel.store = store
        
        #expect(viewModel.analysisItems.isEmpty)
    }
}
