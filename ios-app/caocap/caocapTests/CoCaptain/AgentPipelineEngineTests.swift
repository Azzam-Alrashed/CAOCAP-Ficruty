import XCTest
import SwiftUI
@testable import caocap

@MainActor
final class AgentPipelineEngineTests: XCTestCase {
    var engine: AgentPipelineEngine!
    var store: ProjectStore!

    override func setUp() async throws {
        engine = AgentPipelineEngine()
        store = ProjectStore(
            fileName: "pipeline-test-\(UUID().uuidString).json",
            projectName: "Pipeline Test",
            initialNodes: [
                SpatialNode(type: .miniApp, position: .zero, title: "Dest", miniApp: MiniAppState())
            ]
        )
    }

    func testTriggerDownstreamAgentsFindsNodes() async throws {
        UserDefaults.standard.set(true, forKey: ProjectStore.experimentalAgentPipesEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: ProjectStore.experimentalAgentPipesEnabledKey) }

        let sourceNode = SpatialNode(type: .miniApp, position: .zero, title: "Source")
        var destNode = SpatialNode(type: .miniApp, position: .zero, title: "Dest")
        destNode.agentProfile.isAutoTriggerEnabled = true

        engine.triggerDownstreamAgents(from: sourceNode.id, nodes: [sourceNode, destNode], store: store)
    }

    func testStageReviewDraftPersistsAndDerivesAwaitingReview() {
        let nodeID = store.nodes[0].id
        let dispatcher = PipelineActionDispatcher()
        let draft = CoCaptainReviewLifecycle.Draft(
            pendingActions: [
                CoCaptainAgentAction(
                    actionID: AppActionID.renameNode.rawValue,
                    args: ["nodeId": nodeID.uuidString, "title": "Synced"]
                )
            ]
        )

        let record = engine.stageReviewDraft(
            draft,
            nodeID: nodeID,
            store: store,
            dispatcher: dispatcher
        )

        XCTAssertNotNil(record)
        XCTAssertEqual(engine.executionState(for: nodeID, in: store), .awaitingReview)
        let restored = CoCaptainReviewLifecycle()
            .session(scope: .node(nodeID), store: store, dispatcher: dispatcher)
        XCTAssertEqual(restored.records.count, 1)
        XCTAssertEqual(restored.records[0].id, record?.id)
        XCTAssertEqual(restored.records[0].bundle.items.first?.status, .pending)

        if let record, let itemID = record.bundle.items.first?.id {
            let resolver = CoCaptainReviewLifecycle()
                .session(scope: .node(nodeID), store: store, dispatcher: dispatcher)
            _ = resolver.resolve(.reject(itemID: itemID), in: record.id)
        }
        XCTAssertEqual(engine.executionState(for: nodeID, in: store), .idle)
    }
}

@MainActor
private final class PipelineActionDispatcher: AppActionPerforming {
    let availableActions: [AppActionDefinition] = [
        AppActionDefinition(
            id: .renameNode,
            title: "Rename Node",
            icon: "pencil",
            category: .project,
            isMutating: true,
            allowsAutonomousExecution: false
        )
    ]

    func definition(for id: AppActionID) -> AppActionDefinition? {
        availableActions.first { $0.id == id }
    }

    func perform(
        _ id: AppActionID,
        source: AppActionSource,
        arguments: [String: String]?
    ) -> AppActionResult {
        AppActionResult(
            actionID: id,
            title: definition(for: id)?.localizedTitle ?? id.rawValue,
            executed: true,
            message: "Performed"
        )
    }
}
