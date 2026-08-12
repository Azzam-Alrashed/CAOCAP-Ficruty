import Foundation
import FirebaseAILogic
import OSLog
import Observation

/// A singleton service that manages the interaction with the Gemini LLM via Firebase AI Logic.
///
/// Uses `FirebaseAI.firebaseAI(backend: .googleAI())` — the correct Firebase AI Logic
/// Swift API as of the `FirebaseAILogic` SDK.
///
/// Provides a streaming interface and maintains chat history for multi-turn conversations.
@Observable @MainActor
public final class LLMService {

    public static let shared = LLMService()

    private let logger = Logger(subsystem: "com.caocap.app", category: "LLMService")

    // MARK: - Model & Session

    /// Lazily initialised so Firebase is guaranteed to be configured before first use.
    @ObservationIgnored
    private lazy var model: GenerativeModel = makeModel(modelName: preferredModelName)

    /// Currently-selected model name (can be overridden via `UserDefaults`).
    ///
    /// Rationale: `FirebaseAILogic.GenerateContentError` can surface as a generic `error 0`
    /// for misconfigured/unsupported model names; using a stable default and allowing
    /// overrides helps unblock runtime debugging without code changes.
    private var preferredModelName: String {
        CoCaptainModelSelectionPolicy.resolvedModelName(
            UserDefaults.standard.string(forKey: "cocaptain.modelName")
        )
    }

    private var currentModelRoute: CoCaptainModelRoute {
        CoCaptainModelRoutingPolicy.route(
            requestedModelName: UserDefaults.standard.string(forKey: "cocaptain.modelName"),
            eligibility: .current,
            isLocalModelReady: LocalGemmaModelManager.shared.isLocalModelCached,
            connectivity: NetworkConnectivityMonitor.shared.currentStatus
        )
    }

    /// The active chat session that maintains history.
    private var chats: [CoCaptainAgentScope: FirebaseAILogic.Chat] = [:]
    private let tokenUsageLimiter = TokenUsageLimiter.shared
    private let subscriptionManager = SubscriptionManager.shared
    private var lastUsedModelName: String?

    /// The maximum number of in-turn tool-response messages sent back to the
    /// model on one user turn. Bounds cost and prevents read-tool loops.
    private static let maximumToolResponseRounds = 4

    private init() {}

    // MARK: - API

    /// Resets the current chat session, clearing all history.
    public func resetChat(scope: CoCaptainAgentScope = .project) {
        chats[scope] = nil
        LocalGemmaModelManager.shared.resetChat(scope: scope)
        logger.info("Chat session reset for \(scope.storageKey, privacy: .public).")
    }

    public func submissionError(
        for attachments: [CoCaptainAttachment]
    ) -> CoCaptainSubmissionError? {
        guard !attachments.isEmpty else { return nil }
        if case .cloud = currentModelRoute { return nil }
        return .attachmentsRequireCloud
    }

    /// Generates a streaming response for the given user prompt, maintaining conversation history.
    ///
    /// - Parameter prompt: The raw user message.
    /// - Returns: An `AsyncThrowingStream` of partial response strings.
    public func streamResponse(for prompt: String) -> AsyncThrowingStream<String, Error> {
        let events = streamAgentEvents(
            for: prompt,
            context: nil,
            expectsStructuredResponse: false,
            availableActions: [],
            scope: .project,
            purpose: .standard,
            chatMode: .agent
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in events {
                        if case .text(let text) = event {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The primary API for CoCaptain: streams structured agent events for the given message.
    ///
    /// The method:
    /// 1. Builds the full prompt (context + instructions + user message).
    /// 2. Refreshes StoreKit entitlements, then runs a preflight token-budget check.
    /// 3. Routes to local LiteRT-LM when selected or automatically while offline,
    ///    otherwise delegates to the Firebase AI Logic Gemini session.
    /// 4. Yields `.text` chunks as they arrive and `.functionCalls` when the
    ///    model uses the `request_app_action` tool.
    ///
    /// - Parameters:
    ///   - userMessage: The raw message entered by the user.
    ///   - context: Optional serialized canvas context from `ProjectContextBuilder`.
    ///   - expectsStructuredResponse: When `true`, the full agent contract and
    ///     XML schema are appended to the prompt so the model knows to emit actions.
    ///   - availableActions: Actions the model may reference in its response.
    ///   - scope: Whether the session is project-wide or scoped to a single node.
    public func streamAgentEvents(
        for userMessage: String,
        context: String?,
        expectsStructuredResponse: Bool,
        availableActions: [AppActionDefinition],
        scope: CoCaptainAgentScope = .project,
        purpose: CoCaptainTurnPurpose = .standard,
        chatMode: CoCaptainChatMode = .agent,
        toolExecutor: CoCaptainToolExecutor? = nil
    ) -> AsyncThrowingStream<CoCaptainLLMStreamEvent, Error> {
        streamAgentEvents(
            for: userMessage,
            attachments: [],
            context: context,
            expectsStructuredResponse: expectsStructuredResponse,
            availableActions: availableActions,
            scope: scope,
            purpose: purpose,
            chatMode: chatMode,
            toolExecutor: toolExecutor
        )
    }

    public func streamAgentEvents(
        for userMessage: String,
        attachments: [CoCaptainAttachment],
        context: String?,
        expectsStructuredResponse: Bool,
        availableActions: [AppActionDefinition],
        scope: CoCaptainAgentScope = .project,
        purpose: CoCaptainTurnPurpose = .standard,
        chatMode: CoCaptainChatMode = .agent,
        toolExecutor: CoCaptainToolExecutor? = nil
    ) -> AsyncThrowingStream<CoCaptainLLMStreamEvent, Error> {
        let route = currentModelRoute
        let supportsFunctionCalling: Bool
        if case .cloud = route {
            supportsFunctionCalling = true
        } else {
            supportsFunctionCalling = false
        }
        let prompt = buildPrompt(
            userMessage: userMessage,
            context: context,
            expectsStructuredResponse: expectsStructuredResponse,
            availableActions: availableActions,
            scope: scope,
            purpose: purpose,
            chatMode: chatMode,
            modelSupportsFunctionCalling: supportsFunctionCalling
        )

        let currentPreferred: String
        let isLocal: Bool
        switch route {
        case .local:
            currentPreferred = CoCaptainModelSelectionPolicy.localModelName
            isLocal = true
        case .cloud(let modelName):
            currentPreferred = modelName
            isLocal = false
        case .unavailableOffline:
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: CoCaptainRoutingError.offlineModelUnavailable)
            }
        }

        if isLocal {
            if let submissionError = submissionError(for: attachments) {
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: submissionError)
                }
            }
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        if await self.finishStreamIfPreflightFails(prompt: prompt, continuation: continuation) {
                            return
                        }

                        var responseText = ""
                        logger.debug("Starting local LiteRT-LM stream.")

                        let stream = LocalGemmaModelManager.shared.streamResponse(
                            to: prompt,
                            scope: scope
                        )

                        for try await chunk in stream {
                            responseText += chunk
                            continuation.yield(.text(chunk))
                        }

                        self.tokenUsageLimiter.record(
                            prompt: prompt,
                            response: responseText,
                            isSubscribed: self.subscriptionManager.isSubscribed
                        )
                        continuation.finish()
                        logger.info("Local LiteRT-LM stream completed.")
                    } catch {
                        logger.error("Local LiteRT-LM stream error: \(error.localizedDescription, privacy: .public)")
                        LocalGemmaModelManager.shared.resetChat(scope: scope)
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        // Initialize chat session or reconfigure if the selected model has changed
        if chats[scope] == nil || lastUsedModelName != currentPreferred {
            lastUsedModelName = currentPreferred
            logger.info("Initializing generative model with \(currentPreferred, privacy: .public) for scope \(scope.storageKey, privacy: .public)")
            model = makeModel(modelName: currentPreferred)
            chats[scope] = model.startChat()
        }

        // Get the chat session for the given scope
        guard let session = self.chats[scope] else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(domain: "LLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize chat session"]))
            }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if await self.finishStreamIfPreflightFails(prompt: prompt, continuation: continuation) {
                        return
                    }

                    var responseText = ""
                    var toolResponseText = ""
                    var toolResponseRounds = 0
                    // `nil` sends the initial prompt; subsequent iterations carry
                    // function responses back to the model on the same session.
                    var nextToolResponseMessage: [ModelContent]?
                    logger.debug("Starting LLM stream with history.")
                    logger.debug("Model: \(self.preferredModelName, privacy: .public) scope=\(scope.storageKey, privacy: .public) structured=\(expectsStructuredResponse, privacy: .public) contextChars=\((context ?? "").count, privacy: .public)")

                    repeat {
                        try Task.checkCancellation()
                        // Use the captured session to prevent nil-unwrapping crashes if self.chats changes
                        let stream: AsyncThrowingStream<GenerateContentResponse, Error>
                        if let message = nextToolResponseMessage {
                            stream = try session.sendMessageStream(message)
                        } else if attachments.isEmpty {
                            stream = try session.sendMessageStream(prompt)
                        } else {
                            var parts: [any Part] = [TextPart(prompt)]
                            parts.append(contentsOf: attachments.map {
                                InlineDataPart(data: $0.data, mimeType: $0.mimeType)
                            })
                            stream = try session.sendMessageStream([ModelContent(parts: parts)])
                        }
                        nextToolResponseMessage = nil

                        var roundFunctionCalls: [CoCaptainAgentFunctionCall] = []
                        for try await chunk in stream {
                            if let text = chunk.text {
                                responseText += text
                                continuation.yield(.text(text))
                            }
                            roundFunctionCalls.append(
                                contentsOf: chunk.functionCalls.map(CoCaptainAgentFunctionCall.init)
                            )
                        }

                        // Read-style tools are answered inline; everything else
                        // (e.g. `request_app_action`) keeps its collect-and-route
                        // behavior through the output adapters.
                        var functionResponses: [FunctionResponsePart] = []
                        var routedCalls: [CoCaptainAgentFunctionCall] = []
                        for call in roundFunctionCalls {
                            if toolResponseRounds < Self.maximumToolResponseRounds,
                               let toolExecutor,
                               let result = await toolExecutor(call) {
                                toolResponseText += result
                                functionResponses.append(
                                    FunctionResponsePart(
                                        name: call.name,
                                        response: ["result": .string(result)],
                                        functionId: call.id
                                    )
                                )
                            } else {
                                routedCalls.append(call)
                            }
                        }

                        if !routedCalls.isEmpty {
                            continuation.yield(.functionCalls(routedCalls))
                        }

                        guard !functionResponses.isEmpty else { break }
                        toolResponseRounds += 1
                        // gemini-3.x / Firebase AI Logic reject role "function".
                        // Match GenerativeModelSession: send FunctionResponsePart as "user".
                        nextToolResponseMessage = [
                            ModelContent(role: "user", parts: functionResponses)
                        ]
                    } while true

                    // Record the full multi-round exchange, including tool-response
                    // payloads, against the free-tier budget in one shot.
                    self.tokenUsageLimiter.record(
                        prompt: prompt + toolResponseText,
                        response: responseText,
                        isSubscribed: self.subscriptionManager.isSubscribed
                    )
                    continuation.finish()
                    logger.info("LLM stream completed after \(toolResponseRounds, privacy: .public) tool round(s).")
                } catch {
                    let reflected = String(reflecting: error)
                    logger.error("LLM stream error: \(reflected, privacy: .public)")
                    
                    if reflected.contains("429") || reflected.contains("quota") || reflected.contains("RESOURCE_EXHAUSTED") {
                        continuation.yield(.text("[Sandbox Mode] API Quota limit reached. This is a simulated response to allow you to continue testing your Node Linking and Prompt Templates."))
                        continuation.finish()
                        return
                    }

                    // Attempt a one-time recovery by resetting the chat session.
                    // This helps when the underlying session is in a bad state.
                    self.chats[scope] = nil
                    continuation.finish(throwing: error)
                }
            }
            // Support cooperative cancellation from the caller side
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Refreshes StoreKit entitlements, then enforces the free-tier cap.
    /// Returns `true` when the stream should stop with a thrown limit error.
    private func finishStreamIfPreflightFails(
        prompt: String,
        continuation: AsyncThrowingStream<CoCaptainLLMStreamEvent, Error>.Continuation
    ) async -> Bool {
        await subscriptionManager.refreshEntitlements()
        if case .failure(let error) = tokenUsageLimiter.preflight(
            prompt: prompt,
            isSubscribed: subscriptionManager.isSubscribed
        ) {
            continuation.finish(throwing: error)
            return true
        }
        return false
    }

    /// The base system instruction loaded into the Gemini context window.
    /// Dictates the persona, rules of engagement, and the output contract.
    private static func systemInstructionText() -> String {
        """
        You are Co-Captain, a spatial programming assistant for the CAOCAP platform.
        You can request app actions with the `request_app_action` function and ask one question with the `ask_clarifying_question` function. The app validates every requested action before execution.
        
        Personality:
        - You are a patient, encouraging mentor. Most of your users are beginners learning to code for the first time.
        - Use plain, friendly language. Never use technical jargon without a one-phrase explanation.
        - Be concise and proactive, but never dismissive.
        - Never refuse a request. If you cannot do something directly, explain what you can do and offer the closest helpful step.

        Core Rule:
        - Answer ordinary questions, opinions, and advice conversationally without app actions.
        - Use app actions when the user asks to change the canvas graph or app state (create, rename, delete, connect, move, theme, organize, navigate, etc.).
        - Do not propose Mini-App HTML/code edits; use graph AppActions instead.
        - Prefer `request_app_action` for canvas and app-level changes. Pass action-specific string arguments when the catalog requires them (for example nodeId, title, fromNodeId, toNodeId, x, y, type, theme, kind).
        - Safe actions are only for non-mutating autonomous app actions. Mutating or review-required app actions must use executionMode `pending`.

        Understanding beginners:
        - If a change request is vague or could mean several different things, do NOT guess and do NOT reject it. Ask exactly one clarifying question with 2-4 short, concrete options a beginner can pick from.
        - Phrase options as outcomes ("Rename this node to Welcome"), never as technical implementation details.
        """
    }

    /// Creates and configures a new `GenerativeModel` instance with the required
    /// tools and system instructions for CoCaptain agent execution.
    private func makeModel(modelName: String) -> GenerativeModel {
        let declarations: [FunctionDeclaration] = [
            Self.requestAppActionDeclaration,
            Self.askClarifyingQuestionDeclaration
        ]

        return FirebaseAI.firebaseAI(backend: .googleAI()).generativeModel(
            modelName: modelName,
            tools: [.functionDeclarations(declarations)],
            toolConfig: ToolConfig(
                functionCallingConfig: .auto()
            ),
            systemInstruction: ModelContent(
                role: "system",
                parts: Self.systemInstructionText()
            )
        )
    }

    /// The tool definition that exposes local CAOCAP app actions to the LLM.
    private static let requestAppActionDeclaration = FunctionDeclaration(
        name: CoCaptainFunctionCallAgentAdapter.requestAppActionName,
        description: "Requests a CAOCAP app action. The app validates and either executes or stages the action for user review. Include action-specific string args when needed (nodeId, title, etc.).",
        parameters: [
            "actionId": .string(description: "The exact app action id to request."),
            "executionMode": .enumeration(
                values: ["safe", "pending"],
                description: "`safe` only for non-mutating autonomous actions. `pending` for mutating or review-required actions."
            ),
            "reason": .string(description: "Short reason for requesting the action."),
            "nodeId": .string(description: "Target node UUID when the action needs one."),
            "fromNodeId": .string(description: "Source node UUID for connect/disconnect."),
            "toNodeId": .string(description: "Destination node UUID for connect/disconnect."),
            "title": .string(description: "New title for rename_node or create_node."),
            "subtitle": .string(description: "Subtitle for update_node_subtitle."),
            "icon": .string(description: "SF Symbol name for update_node_icon."),
            "type": .string(description: "NodeType raw value for create_node or transform_node."),
            "theme": .string(description: "NodeTheme raw value for theme_node."),
            "kind": .string(description: "Connection kind: next or connected."),
            "x": .string(description: "Canvas X position as a number string."),
            "y": .string(description: "Canvas Y position as a number string.")
        ],
        optionalParameters: [
            "reason",
            "nodeId",
            "fromNodeId",
            "toNodeId",
            "title",
            "subtitle",
            "icon",
            "type",
            "theme",
            "kind",
            "x",
            "y"
        ]
    )

    /// Structured clarifying-question tool. Prefer this over guessing when a
    /// request is too vague to act on.
    private static let askClarifyingQuestionDeclaration = FunctionDeclaration(
        name: CoCaptainClarifyingQuestionTools.askClarifyingQuestionName,
        description: "Asks the user one short question with 2-4 tappable options when their request is too vague to act on. Never reject a request; ask instead of guessing.",
        parameters: [
            "prompt": .string(description: "One short question phrased for a non-technical user."),
            "options": .array(
                items: .string(description: "A short outcome the user can pick."),
                description: "2 to 4 concrete outcomes phrased in beginner language."
            )
        ]
    )

    /// Assembles the final prompt string sent to the model.
    ///
    /// Sections are joined in order: canvas context (when provided), the agent
    /// contract (when `expectsStructuredResponse` is `true`), and the user request.
    /// The agent contract includes scope-specific instructions and the split list
    /// of autonomous vs. review-required actions.
    func buildPrompt(
        userMessage: String,
        context: String?,
        expectsStructuredResponse: Bool,
        availableActions: [AppActionDefinition],
        scope: CoCaptainAgentScope,
        purpose: CoCaptainTurnPurpose,
        chatMode: CoCaptainChatMode = .agent,
        modelSupportsFunctionCalling: Bool? = nil
    ) -> String {
        _ = modelSupportsFunctionCalling
        var parts: [String] = []

        if let context, !context.isEmpty {
            parts.append("Current canvas context:\n\(context)")
        }

        if expectsStructuredResponse {
            let scopeInstructions: String = {
                switch scope {
                case .project:
                    return "You are in the global project CoCaptain scope. You may reason across the full canvas."
                case .node:
                    return """
                    You are in a node-scoped agent session.
                    - Focus on the selected node in the context.
                    - Prefer graph AppActions such as rename_node, update_node_subtitle, update_node_icon, theme_node, connect_nodes, delete_node, and move_node with the selected node's id.
                    """
                }
            }()

            let autonomousActionLines = availableActions
                .filter(\.allowsAutonomousExecution)
                .map { action in
                    "- \(action.id.rawValue): \(action.title) [mutating=\(action.isMutating)]"
                }
                .joined(separator: "\n")

            let reviewActionLines = availableActions
                .filter { !$0.allowsAutonomousExecution }
                .map { action in
                    "- \(action.id.rawValue): \(action.title) [mutating=\(action.isMutating), autonomous=\(action.allowsAutonomousExecution)]"
                }
                .joined(separator: "\n")

            parts.append(
                """
                Agent contract:
                \(scopeInstructions)

                - Respond conversationally first (concise).
                - If the user is only asking a question, asking for advice, or asking for an opinion, do not request app actions.
                - When the user wants a canvas graph change (create, rename, delete, connect, move, theme, organize, transform), call `request_app_action` with the matching action id and required arguments.
                - Useful graph actions and args:
                  - create_node: optional type, title, x, y
                  - delete_node: nodeId
                  - rename_node: nodeId, title
                  - update_node_subtitle: nodeId, subtitle
                  - update_node_icon: nodeId, icon
                  - connect_nodes / disconnect_nodes: fromNodeId, toNodeId, optional kind (`next` or `connected`)
                  - move_node: nodeId, x, y (autonomous / safe)
                  - theme_node: nodeId, theme
                  - transform_node: nodeId, type
                - If you are only answering a question, providing advice, or discussing ideas, do NOT call tools. Pure chat is allowed.

                Clarifying questions:
                - If a change request is too vague to act on confidently, call `ask_clarifying_question` instead of guessing. Never reject the request.
                - Give 2 to 4 short options phrased as outcomes a beginner understands. The user's pick arrives as their next message.
                - Do not combine `ask_clarifying_question` with `request_app_action` in the same response when the question is required to choose the action.

                App actions:
                - Prefer `request_app_action(actionId, executionMode, reason)` plus any extra string args the action needs.
                - Use executionMode `safe` ONLY for these explicitly autonomous action ids:
                \(autonomousActionLines.isEmpty ? "- none" : autonomousActionLines)
                - Use executionMode `pending` for these review-required action ids:
                \(reviewActionLines.isEmpty ? "- none" : reviewActionLines)
                - Never request a non-autonomous action with executionMode `safe`.

                Compatibility XML (optional fallback):
                - Models may still emit a trailing `cocaptain_actions` block with `assistant_message`, `clarifying_question`, `safe_actions`, and `pending_actions`.
                - Do not emit `node_edit` / `node_edits`; those elements are ignored.
                """
            )
        }

        if let purposeInstructions = purpose.promptInstructions {
            parts.append(purposeInstructions)
        }

        if let modeInstructions = chatMode.promptInstructions {
            parts.append(modeInstructions)
        }

        parts.append("User request:\n\(userMessage)")
        return parts.joined(separator: "\n\n")
    }
}

/// Convenience initialiser that maps a Firebase SDK `FunctionCallPart` into
/// the app's internal `CoCaptainAgentFunctionCall` value type, preserving
/// nested objects and arrays.
private extension CoCaptainAgentFunctionCall {
    init(_ functionCall: FunctionCallPart) {
        self.init(
            name: functionCall.name,
            arguments: functionCall.args.mapValues(AgentJSONValue.init),
            id: functionCall.functionId
        )
    }
}

/// Bridges the SDK's `JSONValue` into the app's wire-format-independent
/// `AgentJSONValue`, recursing through compound values.
private extension AgentJSONValue {
    init(_ jsonValue: FirebaseAILogic.JSONValue) {
        switch jsonValue {
        case .null:
            self = .null
        case .bool(let value):
            self = .bool(value)
        case .number(let value):
            self = .number(value)
        case .string(let value):
            self = .string(value)
        case .object(let value):
            self = .object(value.mapValues(AgentJSONValue.init))
        case .array(let value):
            self = .array(value.map(AgentJSONValue.init))
        }
    }
}
