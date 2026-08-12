import Foundation
import SwiftUI
import Testing
@testable import caocap

@MainActor
struct CoCaptainReviewLifecycleTests {
    @Test func stagingPendingActionCapturesIdentityWithoutPerforming() throws {
        let dispatcher = LifecycleActionDispatcher()
        let session = CoCaptainReviewLifecycle()
            .session(scope: .project, store: makeStore(), dispatcher: dispatcher)

        let record = try #require(
            session.stage(
                draft(
                    actionID: .renameNode,
                    args: ["nodeId": UUID().uuidString, "title": "Renamed"]
                )
            )
        )

        #expect(record.id == record.bundle.id)
        #expect(record.bundle.items.count == 1)
        #expect(record.bundle.items.first?.status == .pending)
        #expect(record.bundle.items.first?.preview.contains("title=Renamed") == true)
        #expect(dispatcher.performed.isEmpty)
        #expect(session.hasUnresolvedReviews)
    }

    @Test func stagingUnknownAndUnavailableActionsProducesConflictedItems() throws {
        let session = CoCaptainReviewLifecycle()
            .session(scope: .project, store: makeStore(), dispatcher: LifecycleActionDispatcher())

        let unknownRecord = try #require(
            session.stage(
                CoCaptainReviewLifecycle.Draft(
                    pendingActions: [CoCaptainAgentAction(actionID: "launch_rocket")]
                )
            )
        )
        let unknownItem = try #require(unknownRecord.bundle.items.first)
        #expect(unknownItem.status == .conflicted)
        guard case .unavailableAction(let actionID, _) = unknownItem.source else {
            Issue.record("Expected unavailableAction source")
            return
        }
        #expect(actionID == "launch_rocket")

        let noDispatcherRecord = try #require(
            CoCaptainReviewLifecycle()
                .session(scope: .project, store: makeStore(), dispatcher: nil)
                .stage(draft(actionID: .createNode, args: ["title": "New"]))
        )
        #expect(noDispatcherRecord.bundle.items.first?.status == .conflicted)
    }

    @Test func appActionRequiresApprovalAndUsesAgentApprovedSource() throws {
        let dispatcher = LifecycleActionDispatcher()
        let session = CoCaptainReviewLifecycle()
            .session(scope: .project, store: makeStore(), dispatcher: dispatcher)
        let record = try #require(
            session.stage(
                draft(actionID: .createNode, args: ["title": "New", "x": "40", "y": "-20"])
            )
        )
        let itemID = try #require(record.bundle.items.first?.id)
        #expect(dispatcher.performed.isEmpty)

        let transition = try session.resolve(.approve(itemID: itemID), in: record.id).get()

        #expect(transition.record.bundle.items.first?.status == .applied)
        #expect(dispatcher.performed.first?.source == .agentApproved)
        #expect(dispatcher.performed.first?.id == .createNode)
        #expect(dispatcher.performed.first?.arguments?["title"] == "New")
        #expect(dispatcher.performed.first?.arguments?["x"] == "40")
        #expect(session.hasUnresolvedReviews == false)
    }

    @Test func renameDeleteAndConnectActionsStageAndApplyThroughReview() throws {
        let fromID = UUID()
        let toID = UUID()
        let dispatcher = LifecycleActionDispatcher(
            actions: [
                .renameNode,
                .deleteNode,
                .connectNodes
            ]
        )
        let session = CoCaptainReviewLifecycle()
            .session(scope: .project, store: makeStore(), dispatcher: dispatcher)
        let record = try #require(
            session.stage(
                CoCaptainReviewLifecycle.Draft(
                    pendingActions: [
                        CoCaptainAgentAction(
                            actionID: AppActionID.renameNode.rawValue,
                            args: ["nodeId": fromID.uuidString, "title": "Home"]
                        ),
                        CoCaptainAgentAction(
                            actionID: AppActionID.connectNodes.rawValue,
                            args: [
                                "fromNodeId": fromID.uuidString,
                                "toNodeId": toID.uuidString,
                                "kind": "next"
                            ]
                        ),
                        CoCaptainAgentAction(
                            actionID: AppActionID.deleteNode.rawValue,
                            args: ["nodeId": toID.uuidString]
                        )
                    ]
                )
            )
        )

        #expect(record.bundle.items.count == 3)
        #expect(record.bundle.title.lowercased().contains("3"))

        let transition = try session.resolve(.approveAll, in: record.id).get()

        #expect(transition.record.bundle.items.allSatisfy { $0.status == .applied })
        #expect(dispatcher.performed.map(\.id) == [.renameNode, .connectNodes, .deleteNode])
        #expect(dispatcher.performed.allSatisfy { $0.source == .agentApproved })
    }

    @Test func failedAppActionBecomesTerminalConflict() throws {
        let dispatcher = LifecycleActionDispatcher(executed: false)
        let session = CoCaptainReviewLifecycle()
            .session(scope: .project, store: makeStore(), dispatcher: dispatcher)
        let record = try #require(session.stage(draft(actionID: .createNode)))
        let itemID = try #require(record.bundle.items.first?.id)

        let transition = try session.resolve(.approve(itemID: itemID), in: record.id).get()

        #expect(transition.record.bundle.items.first?.status == .conflicted)
        #expect(session.hasUnresolvedReviews == false)
    }

    @Test func rejectAllRejectsPendingItemsWithoutPerforming() throws {
        let dispatcher = LifecycleActionDispatcher(
            actions: [.createNode, .renameNode]
        )
        let session = CoCaptainReviewLifecycle()
            .session(scope: .project, store: makeStore(), dispatcher: dispatcher)
        let record = try #require(
            session.stage(
                CoCaptainReviewLifecycle.Draft(
                    pendingActions: [
                        CoCaptainAgentAction(actionID: AppActionID.createNode.rawValue),
                        CoCaptainAgentAction(
                            actionID: AppActionID.renameNode.rawValue,
                            args: ["nodeId": UUID().uuidString, "title": "X"]
                        )
                    ]
                )
            )
        )

        let transition = try session.resolve(.rejectAll, in: record.id).get()

        #expect(transition.record.bundle.items.allSatisfy { $0.status == .rejected })
        #expect(transition.effects.count == 2)
        #expect(dispatcher.performed.isEmpty)
    }

    @Test func callerFailuresDoNotChangeRecord() throws {
        let dispatcher = LifecycleActionDispatcher()
        let session = CoCaptainReviewLifecycle()
            .session(scope: .project, store: makeStore(), dispatcher: dispatcher)
        let record = try #require(session.stage(draft(actionID: .createNode)))
        let itemID = try #require(record.bundle.items.first?.id)
        _ = try session.resolve(.reject(itemID: itemID), in: record.id).get()
        let before = try #require(session.records.first)

        let result = session.resolve(.approve(itemID: itemID), in: record.id)

        guard case .failure(.decisionNotAllowed(let failedID, .rejected)) = result else {
            Issue.record("Expected a typed invalid-transition failure")
            return
        }
        #expect(failedID == itemID)
        #expect(session.records.first == before)
    }

    @Test func nodePersistenceRemovesTerminalRecords() throws {
        let store = makeStore()
        let nodeID = try #require(store.nodes.first?.id)
        let dispatcher = LifecycleActionDispatcher()
        let lifecycle = CoCaptainReviewLifecycle()
        let session = lifecycle.session(
            scope: .node(nodeID),
            store: store,
            dispatcher: dispatcher
        )
        let record = try #require(session.stage(draft(actionID: .createNode)))

        #expect(store.nodes.first?.agentState.pendingReviewBundlesData.count == 1)
        #expect(
            lifecycle.session(scope: .node(nodeID), store: store, dispatcher: dispatcher)
                .records.first?.bundle.items.first?.status == .pending
        )

        let itemID = try #require(record.bundle.items.first?.id)
        _ = try session.resolve(.reject(itemID: itemID), in: record.id).get()
        #expect(store.nodes.first?.agentState.pendingReviewBundlesData.isEmpty == true)
        #expect(session.records.first?.bundle.items.first?.status == .rejected)
    }

    @Test func interleavedNodeSessionsPreserveBundlesStagedByOtherSessions() throws {
        let store = makeStore()
        let nodeID = try #require(store.nodes.first?.id)
        let dispatcher = LifecycleActionDispatcher()
        let lifecycle = CoCaptainReviewLifecycle()
        let firstSession = lifecycle.session(
            scope: .node(nodeID),
            store: store,
            dispatcher: dispatcher
        )
        let firstRecord = try #require(
            firstSession.stage(draft(actionID: .createNode, args: ["title": "First"]))
        )
        let firstItemID = try #require(firstRecord.bundle.items.first?.id)

        let secondSession = lifecycle.session(
            scope: .node(nodeID),
            store: store,
            dispatcher: dispatcher
        )
        let secondRecord = try #require(
            secondSession.stage(draft(actionID: .createNode, args: ["title": "Second"]))
        )

        _ = try firstSession.resolve(
            .reject(itemID: firstItemID),
            in: firstRecord.id
        ).get()

        let restored = lifecycle.session(
            scope: .node(nodeID),
            store: store,
            dispatcher: dispatcher
        )
        #expect(restored.records.map(\.id) == [secondRecord.id])
        #expect(store.nodes.first?.agentState.pendingReviewBundlesData.count == 1)
    }

    @Test func interleavedNodeSessionsMergeDecisionsWithinOneBundle() throws {
        let store = makeStore()
        let nodeID = try #require(store.nodes.first?.id)
        let dispatcher = LifecycleActionDispatcher(actions: [.createNode, .renameNode])
        let lifecycle = CoCaptainReviewLifecycle()
        let firstSession = lifecycle.session(
            scope: .node(nodeID),
            store: store,
            dispatcher: dispatcher
        )
        let record = try #require(
            firstSession.stage(
                CoCaptainReviewLifecycle.Draft(
                    pendingActions: [
                        CoCaptainAgentAction(
                            actionID: AppActionID.createNode.rawValue,
                            args: ["title": "A"]
                        ),
                        CoCaptainAgentAction(
                            actionID: AppActionID.renameNode.rawValue,
                            args: ["nodeId": nodeID.uuidString, "title": "B"]
                        )
                    ]
                )
            )
        )
        let firstItemID = try #require(record.bundle.items.first?.id)
        let secondItemID = try #require(record.bundle.items.last?.id)

        _ = try firstSession.resolve(
            .approve(itemID: firstItemID),
            in: record.id
        ).get()

        let secondSession = lifecycle.session(
            scope: .node(nodeID),
            store: store,
            dispatcher: dispatcher
        )
        _ = try secondSession.resolve(
            .approve(itemID: secondItemID),
            in: record.id
        ).get()

        let restored = lifecycle.session(
            scope: .node(nodeID),
            store: store,
            dispatcher: dispatcher
        )
        #expect(restored.records.isEmpty)
        #expect(dispatcher.performed.map(\.id) == [.createNode, .renameNode])
    }

    @Test func projectSessionsAreEphemeralAndClearIsScopeAware() throws {
        let store = makeStore()
        let nodeID = try #require(store.nodes.first?.id)
        let dispatcher = LifecycleActionDispatcher()
        let lifecycle = CoCaptainReviewLifecycle()
        let projectSession = lifecycle.session(
            scope: .project,
            store: store,
            dispatcher: dispatcher
        )
        _ = projectSession.stage(draft(actionID: .createNode, args: ["title": "Project"]))

        #expect(projectSession.records.count == 1)
        #expect(store.nodes.first?.agentState.pendingReviewBundlesData.isEmpty == true)
        #expect(
            lifecycle.session(scope: .project, store: store, dispatcher: dispatcher)
                .records.isEmpty
        )

        let nodeSession = lifecycle.session(
            scope: .node(nodeID),
            store: store,
            dispatcher: dispatcher
        )
        _ = nodeSession.stage(draft(actionID: .createNode, args: ["title": "Node"]))
        #expect(store.nodes.first?.agentState.pendingReviewBundlesData.count == 1)
        nodeSession.clear()
        #expect(nodeSession.records.isEmpty)
        #expect(store.nodes.first?.agentState.pendingReviewBundlesData.isEmpty == true)
    }

    @Test func restoreNormalizesLegacyIdentityAndSkipsCorruptRecords() throws {
        let store = makeStore()
        let nodeID = try #require(store.nodes.first?.id)
        let legacyTimelineID = UUID()
        let bundle = ReviewBundleItem(
            id: UUID(),
            items: [
                PendingReviewItem(
                    targetLabel: "Create Mini-App",
                    summary: "Legacy",
                    preview: "title=Legacy",
                    source: .appAction(.createNode, ["title": "Legacy"])
                )
            ]
        )
        let legacy = LegacyReviewRecord(
            timelineItemID: legacyTimelineID,
            bundle: bundle,
            createdAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var state = try #require(store.nodes.first?.agentState)
        state.pendingReviewBundlesData = [
            Data("{not-json".utf8),
            try encoder.encode(legacy)
        ]
        store.updateNodeAgentState(id: nodeID, agentState: state, persist: false)

        let session = CoCaptainReviewLifecycle()
            .session(scope: .node(nodeID), store: store, dispatcher: LifecycleActionDispatcher())

        let restored = try #require(session.records.first)
        #expect(session.records.count == 1)
        #expect(restored.id == legacyTimelineID)
        #expect(restored.bundle.id == legacyTimelineID)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let normalizedData = try #require(
            store.nodes.first?.agentState.pendingReviewBundlesData.first
        )
        let normalized = try decoder.decode(
            CoCaptainReviewLifecycle.Record.self,
            from: normalizedData
        )
        #expect(normalized.id == normalized.bundle.id)
    }

    @Test func restoreRemovesCorruptPersistenceWithoutAnotherNormalizationTrigger() throws {
        let store = makeStore()
        let nodeID = try #require(store.nodes.first?.id)
        var state = try #require(store.nodes.first?.agentState)
        state.pendingReviewBundlesData = [Data("{not-json".utf8)]
        store.updateNodeAgentState(id: nodeID, agentState: state, persist: false)

        let session = CoCaptainReviewLifecycle()
            .session(scope: .node(nodeID), store: store, dispatcher: nil)

        #expect(session.records.isEmpty)
        #expect(store.nodes.first?.agentState.pendingReviewBundlesData.isEmpty == true)
        #expect(
            CoCaptainReviewLifecycle.hasUnresolvedPersistedRecords(
                in: try #require(store.nodes.first?.agentState)
            ) == false
        )
    }

    private func makeStore(nodes: [SpatialNode]? = nil) -> ProjectStore {
        ProjectStore(
            fileName: "review-lifecycle-\(UUID().uuidString).json",
            projectName: "Review Lifecycle",
            initialNodes: nodes ?? [
                SpatialNode(
                    type: .miniApp,
                    position: .zero,
                    title: "Mini-App",
                    miniApp: MiniAppState()
                )
            ]
        )
    }

    private func draft(
        actionID: AppActionID,
        args: [String: String]? = nil
    ) -> CoCaptainReviewLifecycle.Draft {
        CoCaptainReviewLifecycle.Draft(
            pendingActions: [
                CoCaptainAgentAction(actionID: actionID.rawValue, args: args)
            ]
        )
    }
}

private struct LegacyReviewRecord: Codable {
    let timelineItemID: UUID
    let bundle: ReviewBundleItem
    let createdAt: Date
}

@MainActor
private final class LifecycleActionDispatcher: AppActionPerforming {
    struct PerformedAction: Equatable {
        let id: AppActionID
        let source: AppActionSource
        let arguments: [String: String]?
    }

    let availableActions: [AppActionDefinition]
    private let executed: Bool
    private(set) var performed: [PerformedAction] = []

    init(executed: Bool = true, actions: [AppActionID] = [.createNode, .renameNode]) {
        self.executed = executed
        self.availableActions = actions.map { id in
            AppActionDefinition(
                id: id,
                title: id.rawValue,
                icon: "sparkles",
                category: .project,
                isMutating: true,
                allowsAutonomousExecution: false
            )
        }
    }

    func definition(for id: AppActionID) -> AppActionDefinition? {
        availableActions.first { $0.id == id }
    }

    func perform(
        _ id: AppActionID,
        source: AppActionSource,
        arguments: [String: String]?
    ) -> AppActionResult {
        performed.append(PerformedAction(id: id, source: source, arguments: arguments))
        return AppActionResult(
            actionID: id,
            title: definition(for: id)?.localizedTitle ?? id.rawValue,
            executed: executed,
            message: executed ? "Performed" : "Failed"
        )
    }
}
