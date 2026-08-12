import CoreGraphics
import Foundation
import Testing
@testable import caocap

struct CoCaptainAgentTests {
    @Test func standardPurposeHasNoPromptInstructions() {
        #expect(CoCaptainTurnPurpose.standard.promptInstructions == nil)
        #expect(CoCaptainTurnPurpose.standard.executionPolicy == .agent)
    }

    @Test func turnPlanMapsModeToEffectivePolicy() {
        let agent = CoCaptainTurnPlan(purpose: .standard, mode: .agent)
        let ask = CoCaptainTurnPlan(purpose: .standard, mode: .ask)
        let plan = CoCaptainTurnPlan(purpose: .standard, mode: .plan)

        #expect(agent.effectivePolicy == .agent)
        #expect(ask.effectivePolicy == .ask)
        #expect(plan.effectivePolicy == .plan)
        #expect(CoCaptainTurnExecutionPolicy.agent.expectsStructuredResponse)
        #expect(CoCaptainTurnExecutionPolicy.agent.enforcesExecutableWork == false)
        #expect(CoCaptainTurnExecutionPolicy.agent.allowsAgenticRetry)
        #expect(CoCaptainTurnExecutionPolicy.agent.executesActions)
        #expect(CoCaptainTurnExecutionPolicy.ask.expectsStructuredResponse == false)
        #expect(CoCaptainTurnExecutionPolicy.ask.executesActions == false)
        #expect(CoCaptainTurnExecutionPolicy.plan.expectsStructuredResponse == false)
        #expect(CoCaptainTurnExecutionPolicy.plan.executesActions == false)
        #expect(agent.requiresDegradedConnectionNotice)
        #expect(!ask.requiresDegradedConnectionNotice)
        #expect(agent.contextDetailLevel == .implementation)
        #expect(ask.contextDetailLevel == .product)
        #expect(!CoCaptainChatMode.agent.isProseOnly)
        #expect(CoCaptainChatMode.ask.isProseOnly)
        #expect(CoCaptainChatMode.plan.isProseOnly)
    }

    @MainActor
    @Test func projectContextEmitsGraphMetadataWithoutCodeText() throws {
        let nodeID = UUID()
        let linkedID = UUID()
        let store = ProjectStore(
            fileName: "context-\(UUID().uuidString).json",
            projectName: "Test Project",
            initialNodes: [
                SpatialNode(
                    id: nodeID,
                    type: .miniApp,
                    position: CGPoint(x: 12, y: -8),
                    title: "Cafe Menu",
                    subtitle: "Orders",
                    icon: "cup.and.saucer",
                    connectedNodeIds: [linkedID],
                    miniApp: MiniAppState(codeText: "<h1>Secret code</h1>")
                ),
                SpatialNode(
                    id: linkedID,
                    type: .miniApp,
                    position: CGPoint(x: 100, y: 0),
                    title: "Kitchen",
                    miniApp: MiniAppState(codeText: "<h1>Do not leak</h1>")
                )
            ]
        )

        let context = ProjectContextBuilder().buildPromptContext(from: store)

        #expect(context.contains("Project Name: Test Project"))
        #expect(context.contains("Node Graph:"))
        #expect(context.contains("Cafe Menu [miniApp] id: \(nodeID.uuidString)"))
        #expect(context.contains("position: (12, -8)"))
        #expect(context.contains("connected: \(linkedID.uuidString)"))
        #expect(context.contains("subtitle: Orders"))
        #expect(context.contains("icon: cup.and.saucer"))
        #expect(!context.contains("Code:"))
        #expect(!context.contains("Secret code"))
        #expect(!context.contains("read_node_section"))
        #expect(!context.contains("Do not leak"))
    }

    @MainActor
    @Test func productContextOmitsPositionsAndLinkIDs() throws {
        let store = makeStore()
        let context = ProjectContextBuilder().buildPromptContext(from: store, detailLevel: .product)

        #expect(context.contains("Mini-App [miniApp]"))
        #expect(!context.contains("position:"))
        #expect(!context.contains("connected:"))
        #expect(!context.contains("Code:"))
        #expect(!context.contains("Mini-App Firebase wiring rules"))
    }

    @MainActor
    @Test func nodeContextIncludesSelectedNodeAndLinkedNeighbors() throws {
        let linkedID = UUID()
        let selectedID = UUID()
        let unrelatedID = UUID()
        let store = ProjectStore(
            fileName: "node-context-\(UUID().uuidString).json",
            projectName: "Node Context",
            initialNodes: [
                SpatialNode(
                    id: selectedID,
                    type: .miniApp,
                    position: .zero,
                    title: "Selected",
                    connectedNodeIds: [linkedID],
                    miniApp: MiniAppState()
                ),
                SpatialNode(
                    id: linkedID,
                    type: .miniApp,
                    position: CGPoint(x: 40, y: 0),
                    title: "Linked",
                    miniApp: MiniAppState()
                ),
                SpatialNode(
                    id: unrelatedID,
                    type: .miniApp,
                    position: CGPoint(x: 80, y: 0),
                    title: "Unrelated",
                    miniApp: MiniAppState()
                )
            ]
        )

        let context = ProjectContextBuilder().buildNodePromptContext(from: store, nodeID: selectedID)

        #expect(context.contains("Selected Node ID: \(selectedID.uuidString)"))
        #expect(context.contains("Selected Node Context:"))
        #expect(context.contains("Linked Neighbor Nodes:"))
        #expect(context.contains("Linked [miniApp] id: \(linkedID.uuidString)"))
        #expect(context.contains("Unrelated [miniApp] id: \(unrelatedID.uuidString)"))
        #expect(!context.contains("Code:"))
    }

    @Test func parserExtractsPendingAndSafeActionsFromXML() throws {
        let parser = CoCaptainAgentParser()
        let response = """
        Sure.
        <cocaptain_actions>
          <assistant_message>Opening settings and proposing a rename.</assistant_message>
          <safe_actions>
            <action id="go_root" />
          </safe_actions>
          <pending_actions>
            <action id="rename_node" nodeId="ABC" title="Home" />
          </pending_actions>
        </cocaptain_actions>
        """

        let parsed = parser.parse(response)

        #expect(parsed.payload?.assistantMessage == "Opening settings and proposing a rename.")
        #expect(parsed.payload?.safeActions.map(\.actionID) == ["go_root"])
        #expect(parsed.payload?.pendingActions.first?.actionID == "rename_node")
        #expect(parsed.payload?.pendingActions.first?.args?["nodeId"] == "ABC")
        #expect(parsed.payload?.pendingActions.first?.args?["title"] == "Home")
        #expect(parsed.preamble.contains("Sure."))
    }

    @Test func parserIgnoresLegacyNodeEditBlocks() throws {
        let parser = CoCaptainAgentParser()
        let response = """
        <cocaptain_actions>
          <assistant_message>Legacy edit ignored.</assistant_message>
          <pending_actions>
            <action id="create_node" title="New" />
          </pending_actions>
          <node_edits>
            <node_edit role="miniApp" section="code" summary="Update headline">
              <operation type="replace_all">
                <content><![CDATA[<h1>Nope</h1>]]></content>
              </operation>
            </node_edit>
          </node_edits>
        </cocaptain_actions>
        """

        let parsed = parser.parse(response)

        #expect(parsed.payload?.pendingActions.map(\.actionID) == ["create_node"])
        #expect(parsed.payload?.pendingActions.first?.args?["title"] == "New")
    }

    @Test func parserExtractsClarifyingQuestion() {
        let parser = CoCaptainAgentParser()
        let response = """
        <cocaptain_actions>
          <assistant_message>Need a bit more detail.</assistant_message>
          <clarifying_question prompt="What should we change?">
            <option>Rename the node</option>
            <option>Connect two nodes</option>
            <option>Delete a node</option>
          </clarifying_question>
        </cocaptain_actions>
        """

        let parsed = parser.parse(response)
        let question = parsed.payload?.clarifyingQuestion

        #expect(question?.prompt == "What should we change?")
        #expect(question?.options == ["Rename the node", "Connect two nodes", "Delete a node"])
    }

    @Test func parserDropsMalformedClarifyingQuestion() {
        let parser = CoCaptainAgentParser()
        let response = """
        <cocaptain_actions>
          <assistant_message>Fallback.</assistant_message>
          <clarifying_question prompt="Too few options">
            <option>Only one</option>
          </clarifying_question>
        </cocaptain_actions>
        """

        let parsed = parser.parse(response)
        #expect(parsed.payload?.clarifyingQuestion == nil)
        #expect(parsed.payload?.assistantMessage == "Fallback.")
    }

    @Test func parserUsesLastCompleteActionsBlock() throws {
        let parser = CoCaptainAgentParser()
        let response = """
        Earlier draft.
        <cocaptain_actions>
          <assistant_message>Old</assistant_message>
          <pending_actions>
            <action id="create_node" />
          </pending_actions>
        </cocaptain_actions>
        Final answer.
        <cocaptain_actions>
          <assistant_message>New</assistant_message>
          <pending_actions>
            <action id="rename_node" title="Final" />
          </pending_actions>
        </cocaptain_actions>
        """

        let parsed = parser.parse(response)
        #expect(parsed.payload?.assistantMessage == "New")
        #expect(parsed.payload?.pendingActions.first?.actionID == "rename_node")
        #expect(parsed.payload?.pendingActions.first?.args?["title"] == "Final")
    }

    @Test func parserFallsBackOnMissingClosingTag() throws {
        let parser = CoCaptainAgentParser()
        let response = """
        Hello
        <cocaptain_actions>
          <assistant_message>Broken
        """

        let parsed = parser.parse(response)
        #expect(parsed.payload == nil)
        #expect(parsed.visibleText.contains("Hello"))
    }

    @MainActor
    @Test func validatorRejectsDuplicateAndOverlappingActions() {
        let dispatcher = TestActionDispatcher()
        let validator = CoCaptainAgentValidator()

        let result = validator.validate(
            payload: CoCaptainAgentPayload(
                assistantMessage: "x",
                safeActions: [
                    CoCaptainAgentAction(actionID: AppActionID.goRoot.rawValue),
                    CoCaptainAgentAction(actionID: AppActionID.goRoot.rawValue)
                ],
                pendingActions: [
                    CoCaptainAgentAction(actionID: AppActionID.goRoot.rawValue),
                    CoCaptainAgentAction(actionID: AppActionID.createNode.rawValue),
                    CoCaptainAgentAction(actionID: AppActionID.createNode.rawValue)
                ]
            ),
            dispatcher: dispatcher,
            requiresAgenticWork: false
        )

        #expect(!result.isValid)
        #expect(result.issues.contains(where: { $0.contains("duplicated") }))
        #expect(result.issues.contains(where: { $0.contains("both") }))
    }

    @MainActor
    @Test func validatorRejectsUnsafeSafeActionsAndUnknownPendingActions() {
        let dispatcher = TestActionDispatcher()
        let validator = CoCaptainAgentValidator()

        let result = validator.validate(
            payload: CoCaptainAgentPayload(
                assistantMessage: "x",
                safeActions: [
                    CoCaptainAgentAction(actionID: AppActionID.createNode.rawValue)
                ],
                pendingActions: [
                    CoCaptainAgentAction(actionID: "launch_rocket")
                ]
            ),
            dispatcher: dispatcher,
            requiresAgenticWork: true
        )

        #expect(!result.isValid)
        #expect(result.issues.contains(where: { $0.contains("not autonomous") }))
        #expect(result.issues.contains(where: { $0.contains("Unknown pending action") }))
    }

    @MainActor
    @Test func validatorAcceptsQuestionOnlyPayloadAsAgenticWork() {
        let result = CoCaptainAgentValidator().validate(
            payload: CoCaptainAgentPayload(
                assistantMessage: "Need clarity",
                clarifyingQuestion: CoCaptainClarifyingQuestion(
                    prompt: "What next?",
                    options: ["Rename", "Connect"]
                )
            ),
            dispatcher: TestActionDispatcher(),
            requiresAgenticWork: true
        )

        #expect(result.isValid)
    }

    @Test func functionCallAdapterMapsSafeAndPendingActions() throws {
        let adapter = CoCaptainFunctionCallAgentAdapter()
        let directive = adapter.directive(
            from: [
                CoCaptainAgentFunctionCall(
                    name: CoCaptainFunctionCallAgentAdapter.requestAppActionName,
                    arguments: [
                        "actionId": .string(AppActionID.goRoot.rawValue),
                        "executionMode": .string("SAFE")
                    ]
                ),
                CoCaptainAgentFunctionCall(
                    name: CoCaptainFunctionCallAgentAdapter.requestAppActionName,
                    arguments: [
                        "action_id": .string(AppActionID.renameNode.rawValue),
                        "executionMode": .string("pending"),
                        "nodeId": .string("NODE"),
                        "title": .string("Home")
                    ]
                )
            ],
            visibleText: "Working"
        )

        #expect(directive.source == .functionCall)
        #expect(directive.payload?.safeActions.map(\.actionID) == [AppActionID.goRoot.rawValue])
        #expect(directive.payload?.pendingActions.first?.actionID == AppActionID.renameNode.rawValue)
        #expect(directive.payload?.pendingActions.first?.args?["nodeId"] == "NODE")
        #expect(directive.payload?.pendingActions.first?.args?["title"] == "Home")
    }

    @Test func functionCallAdapterReportsMalformedCalls() throws {
        let adapter = CoCaptainFunctionCallAgentAdapter()
        let directive = adapter.directive(
            from: [
                CoCaptainAgentFunctionCall(
                    name: CoCaptainFunctionCallAgentAdapter.requestAppActionName,
                    arguments: ["executionMode": .string("pending")]
                ),
                CoCaptainAgentFunctionCall(
                    name: "unknown_tool",
                    arguments: ["actionId": .string("go_root")]
                )
            ]
        )

        #expect(directive.payload == nil)
        #expect(directive.diagnostics.contains(where: { $0.contains("missing `actionId`") }))
        #expect(directive.diagnostics.contains(where: { $0.contains("Unknown function call") }))
    }

    @Test func clarifyingQuestionFunctionAdapterMapsAskClarifyingQuestion() throws {
        let adapter = CoCaptainClarifyingQuestionFunctionAdapter()
        let directive = adapter.directive(
            from: [
                CoCaptainAgentFunctionCall(
                    name: CoCaptainClarifyingQuestionTools.askClarifyingQuestionName,
                    arguments: [
                        "prompt": .string("What should we do?"),
                        "options": .array([.string("Rename"), .string("Delete"), .string("Connect")])
                    ]
                )
            ],
            visibleText: "Need a choice"
        )

        #expect(directive.source == .clarifyingQuestionFunctionCall)
        #expect(directive.payload?.clarifyingQuestion?.prompt == "What should we do?")
        #expect(directive.payload?.clarifyingQuestion?.options.count == 3)
    }

    @Test func clarifyingQuestionAdapterDropsLegacyProposeNodeEdit() throws {
        let adapter = CoCaptainClarifyingQuestionFunctionAdapter()
        let directive = adapter.directive(
            from: [
                CoCaptainAgentFunctionCall(
                    name: "propose_node_edit",
                    arguments: [
                        "nodeId": .string(UUID().uuidString),
                        "summary": .string("Old edit")
                    ]
                )
            ]
        )

        #expect(directive.payload == nil)
        #expect(directive.diagnostics.contains(where: { $0.contains("no longer supported") }))
    }

    @Test func compositeAdapterPrefersFunctionActionsOverXMLActions() throws {
        let adapter = CoCaptainCompositeAgentAdapter()
        let response = """
        <cocaptain_actions>
          <assistant_message>XML pending</assistant_message>
          <pending_actions>
            <action id="delete_node" nodeId="N1" />
          </pending_actions>
        </cocaptain_actions>
        """
        let directive = adapter.directive(
            from: response,
            functionCalls: [
                CoCaptainAgentFunctionCall(
                    name: CoCaptainFunctionCallAgentAdapter.requestAppActionName,
                    arguments: [
                        "actionId": .string(AppActionID.goRoot.rawValue),
                        "executionMode": .string("safe")
                    ]
                )
            ]
        )

        #expect(directive.source == .combined)
        #expect(directive.payload?.assistantMessage == "XML pending")
        #expect(directive.payload?.safeActions.map(\.actionID) == [AppActionID.goRoot.rawValue])
        // Function-call actions win; XML pending actions are not merged.
        #expect(directive.payload?.pendingActions.isEmpty == true)
    }

    @Test func agentJSONValuePreservesNestedObjectsAndArrays() throws {
        let value: AgentJSONValue = [
            "prompt": "Choose",
            "options": ["A", "B"],
            "nested": ["count": 2]
        ]
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AgentJSONValue.self, from: data)

        #expect(decoded.objectValue?["prompt"]?.stringValue == "Choose")
        #expect(decoded.objectValue?["options"]?.arrayValue?.count == 2)
        #expect(decoded.objectValue?["nested"]?.objectValue?["count"]?.stringValue == "2")
    }

    @MainActor
    @Test func coordinatorExecutesSafeActionsAndStagesPendingReviews() async throws {
        let llm = TestLLMClient(
            response: """
            <cocaptain_actions>
              <assistant_message>Ready.</assistant_message>
              <safe_actions>
                <action id="go_root" />
              </safe_actions>
              <pending_actions>
                <action id="rename_node" nodeId="N1" title="Home" />
              </pending_actions>
            </cocaptain_actions>
            """
        )
        let dispatcher = TestActionDispatcher()
        let coordinator = CoCaptainAgentCoordinator(llmClient: llm)

        let result = try await coordinator.run(
            userMessage: "Rename the node",
            store: makeStore(),
            dispatcher: dispatcher,
            scope: .project,
            turnPlan: CoCaptainTurnPlan(purpose: .standard, mode: .agent),
            onVisibleText: { _ in }
        )

        #expect(dispatcher.performed == [.goRoot])
        #expect(result.executionSummary != nil)
        #expect(result.reviewDraft?.pendingActions.map(\.actionID) == [AppActionID.renameNode.rawValue])
        #expect(result.reviewDraft?.pendingActions.first?.args?["title"] == "Home")
        #expect(result.clarifyingQuestion == nil)
    }

    @MainActor
    @Test func coordinatorStagesFunctionCalledPendingAction() async throws {
        let llm = TestLLMClient(
            response: "Proposing a connect.",
            functionCalls: [[
                CoCaptainAgentFunctionCall(
                    name: CoCaptainFunctionCallAgentAdapter.requestAppActionName,
                    arguments: [
                        "actionId": .string(AppActionID.connectNodes.rawValue),
                        "executionMode": .string("pending"),
                        "fromNodeId": .string("A"),
                        "toNodeId": .string("B"),
                        "kind": .string("next")
                    ]
                )
            ]]
        )
        let coordinator = CoCaptainAgentCoordinator(llmClient: llm)

        let result = try await coordinator.run(
            userMessage: "Connect A to B",
            store: makeStore(),
            dispatcher: TestActionDispatcher(),
            scope: .project,
            turnPlan: CoCaptainTurnPlan(purpose: .standard, mode: .agent),
            onVisibleText: { _ in }
        )

        #expect(result.reviewDraft?.pendingActions.first?.actionID == AppActionID.connectNodes.rawValue)
        #expect(result.reviewDraft?.pendingActions.first?.args?["fromNodeId"] == "A")
        #expect(result.reviewDraft?.pendingActions.first?.args?["toNodeId"] == "B")
        #expect(result.executionSummary == nil)
    }

    @MainActor
    @Test func coordinatorReturnsClarifyingQuestionAndDropsAccompanyingActions() async throws {
        let llm = TestLLMClient(
            response: """
            <cocaptain_actions>
              <assistant_message>Need clarity.</assistant_message>
              <clarifying_question prompt="What should we change?">
                <option>Rename</option>
                <option>Delete</option>
              </clarifying_question>
              <pending_actions>
                <action id="rename_node" title="Guess" />
              </pending_actions>
            </cocaptain_actions>
            """
        )
        let coordinator = CoCaptainAgentCoordinator(llmClient: llm)

        let result = try await coordinator.run(
            userMessage: "Change it",
            store: makeStore(),
            dispatcher: TestActionDispatcher(),
            scope: .project,
            turnPlan: CoCaptainTurnPlan(purpose: .standard, mode: .agent),
            onVisibleText: { _ in }
        )

        #expect(result.clarifyingQuestion?.prompt == "What should we change?")
        #expect(result.reviewDraft == nil || result.reviewDraft?.isEmpty == true)
        #expect(result.executionSummary == nil)
    }

    @MainActor
    @Test func coordinatorRetriesInvalidStructuredPayload() async throws {
        let llm = TestLLMClient(
            responses: [
                """
                <cocaptain_actions>
                  <assistant_message>Bad</assistant_message>
                  <safe_actions>
                    <action id="create_node" />
                  </safe_actions>
                </cocaptain_actions>
                """,
                """
                <cocaptain_actions>
                  <assistant_message>Fixed</assistant_message>
                  <pending_actions>
                    <action id="create_node" title="Cafe" x="10" y="20" />
                  </pending_actions>
                </cocaptain_actions>
                """
            ]
        )
        let coordinator = CoCaptainAgentCoordinator(llmClient: llm)

        let result = try await coordinator.run(
            userMessage: "Add a cafe node",
            store: makeStore(),
            dispatcher: TestActionDispatcher(),
            scope: .project,
            turnPlan: CoCaptainTurnPlan(purpose: .standard, mode: .agent),
            onVisibleText: { _ in }
        )

        #expect(llm.receivedMessages.count == 2)
        #expect(result.reviewDraft?.pendingActions.first?.actionID == AppActionID.createNode.rawValue)
        #expect(result.reviewDraft?.pendingActions.first?.args?["title"] == "Cafe")
        #expect(result.reviewDraft?.pendingActions.first?.args?["x"] == "10")
        #expect(result.executionSummary == nil)
    }

    @MainActor
    @Test func askModeNeverStagesReviewFromStructuredModelOutput() async throws {
        let llm = TestLLMClient(
            response: """
            <cocaptain_actions>
              <assistant_message>Should stay prose.</assistant_message>
              <pending_actions>
                <action id="create_node" title="Nope" />
              </pending_actions>
            </cocaptain_actions>
            """
        )
        let coordinator = CoCaptainAgentCoordinator(llmClient: llm)

        let result = try await coordinator.run(
            userMessage: "Create a node",
            store: makeStore(),
            dispatcher: TestActionDispatcher(),
            scope: .project,
            turnPlan: CoCaptainTurnPlan(purpose: .standard, mode: .ask),
            onVisibleText: { _ in }
        )

        #expect(result.reviewDraft == nil || result.reviewDraft?.isEmpty == true)
        #expect(result.executionSummary == nil)
        #expect(result.clarifyingQuestion == nil)
    }

    @MainActor
    @Test func agentPureProseResponseDoesNotRetry() async throws {
        let llm = TestLLMClient(response: "Here is some advice without tools.")
        let coordinator = CoCaptainAgentCoordinator(llmClient: llm)

        let result = try await coordinator.run(
            userMessage: "How should I organize this?",
            store: makeStore(),
            dispatcher: TestActionDispatcher(),
            scope: .project,
            turnPlan: CoCaptainTurnPlan(purpose: .standard, mode: .agent),
            onVisibleText: { _ in }
        )

        #expect(llm.receivedMessages.count == 1)
        #expect(result.reviewDraft == nil || result.reviewDraft?.isEmpty == true)
        #expect(result.visibleText.contains("advice"))
    }

    @MainActor
    @Test func commandIntentResolverMatchesNavigationCommands() throws {
        let resolver = CommandIntentResolver()
        let actions = TestActionDispatcher().availableActions

        #expect(resolver.resolve("go home", availableActions: actions) == .goRoot)
        #expect(resolver.resolve("open settings", availableActions: actions) == .openSettings)
        #expect(resolver.resolve("don't go home", availableActions: actions) == nil)
        #expect(resolver.resolve("create a project", availableActions: actions) == nil)
    }

    @Test func chatModeStorageKeyAndComposerCopyAreStable() {
        #expect(CoCaptainChatMode.storageKey == "cocaptain.chatMode")
        #expect(!CoCaptainChatMode.agent.displayName.isEmpty)
        #expect(!CoCaptainChatMode.ask.composerPlaceholder.isEmpty)
        #expect(CoCaptainChatMode.plan.promptInstructions != nil)
    }

    @MainActor
    private func makeStore() -> ProjectStore {
        ProjectStore(
            fileName: "agent-test-\(UUID().uuidString).json",
            projectName: "Test Project",
            initialNodes: [
                SpatialNode(
                    type: .miniApp,
                    position: .zero,
                    title: "Mini-App",
                    theme: .blue,
                    miniApp: MiniAppState()
                )
            ]
        )
    }
}

@MainActor
private final class TestLLMClient: CoCaptainLLMClient {
    private let responses: [String]
    private let functionCalls: [[CoCaptainAgentFunctionCall]]
    private var streamCount = 0
    var receivedMessages: [String] = []

    init(response: String) {
        self.responses = [response]
        self.functionCalls = []
    }

    init(response: String, functionCalls: [[CoCaptainAgentFunctionCall]]) {
        self.responses = [response]
        self.functionCalls = functionCalls
    }

    init(responses: [String]) {
        self.responses = responses
        self.functionCalls = []
    }

    func resetChat(scope: CoCaptainAgentScope) {}

    func streamAgentEvents(
        for userMessage: String,
        context: String?,
        expectsStructuredResponse: Bool,
        availableActions: [AppActionDefinition],
        scope: CoCaptainAgentScope,
        purpose: CoCaptainTurnPurpose,
        chatMode: CoCaptainChatMode = .agent,
        toolExecutor: CoCaptainToolExecutor? = nil
    ) -> AsyncThrowingStream<CoCaptainLLMStreamEvent, Error> {
        receivedMessages.append(userMessage)
        let index = streamCount
        let response = responses[min(index, responses.count - 1)]
        let calls = functionCalls.indices.contains(index) ? functionCalls[index] : []
        streamCount += 1

        return AsyncThrowingStream { continuation in
            continuation.yield(.text(response))
            if !calls.isEmpty {
                continuation.yield(.functionCalls(calls))
            }
            continuation.finish()
        }
    }
}

@MainActor
private final class TestActionDispatcher: AppActionPerforming {
    let availableActions: [AppActionDefinition] = [
        AppActionDefinition(
            id: .goRoot,
            title: "Go to Root",
            icon: "house.fill",
            category: .navigation,
            isMutating: false,
            allowsAutonomousExecution: true
        ),
        AppActionDefinition(
            id: .createNode,
            title: "Create Mini-App",
            icon: "plus.square",
            category: .project,
            isMutating: true,
            allowsAutonomousExecution: false
        ),
        AppActionDefinition(
            id: .renameNode,
            title: "Rename Node",
            icon: "pencil",
            category: .project,
            isMutating: true,
            allowsAutonomousExecution: false
        ),
        AppActionDefinition(
            id: .deleteNode,
            title: "Delete Node",
            icon: "trash",
            category: .project,
            isMutating: true,
            allowsAutonomousExecution: false
        ),
        AppActionDefinition(
            id: .connectNodes,
            title: "Connect Nodes",
            icon: "link",
            category: .project,
            isMutating: true,
            allowsAutonomousExecution: false
        ),
        AppActionDefinition(
            id: .openSettings,
            title: "Open Settings",
            icon: "gearshape.fill",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: true
        ),
        AppActionDefinition(
            id: .help,
            title: "Help",
            icon: "questionmark.circle",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: true
        )
    ]

    private(set) var performed: [AppActionID] = []

    func definition(for id: AppActionID) -> AppActionDefinition? {
        availableActions.first { $0.id == id }
    }

    func perform(
        _ id: AppActionID,
        source: AppActionSource,
        arguments: [String: String]?
    ) -> AppActionResult {
        performed.append(id)
        return AppActionResult(
            actionID: id,
            title: definition(for: id)?.localizedTitle ?? id.rawValue,
            executed: true,
            message: "Performed"
        )
    }
}
