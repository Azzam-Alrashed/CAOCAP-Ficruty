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

    /// CAOCAP keeps LiteRT-LM tool calling disabled in the first release, so
    /// tool-based prompt rules are omitted and full-budget context is retained.
    private var currentModelSupportsFunctionCalling: Bool {
        if case .cloud = currentModelRoute { return true }
        return false
    }

    public var supportsOnDemandCodeReads: Bool {
        currentModelSupportsFunctionCalling
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
            nodeEditToolsEnabled: NodeEditToolsFeature.isEnabled && supportsFunctionCalling,
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
    /// Dictates the persona, rules of engagement, and the output contract
    /// (native tools when `NodeEditToolsFeature` is enabled, XML otherwise).
    private static func systemInstructionText(nodeEditToolsEnabled: Bool) -> String {
        let contractSentence = nodeEditToolsEnabled
            ? "You can request app actions with the `request_app_action` function, propose node edits with the `propose_node_edit` function, and ask one question with the `ask_clarifying_question` function. The app validates every requested action before execution."
            : "You can request app actions with the `request_app_action` function and request node edits with a `cocaptain_actions` XML block. The app validates every requested action before execution."
        let applyRule = nodeEditToolsEnabled
            ? """
            - If the user asks you to apply a change, you MUST call `propose_node_edit` to implement it.
            - Call `propose_node_edit` in every response that involves node content changes.
            """
            : """
            - If the user asks you to apply a change, you MUST provide the XML to implement it.
            - Append the `cocaptain_actions` block at the end of every response that involves node content changes.
            """

        return """
        You are Co-Captain, a spatial programming assistant for the CAOCAP platform.
        \(contractSentence)
        
        Personality:
        - You are a patient, encouraging mentor. Most of your users are beginners learning to code for the first time.
        - Use plain, friendly language. Never use technical jargon without a one-phrase explanation.
        - You can execute mutations on a spatial canvas when the user asks for canvas changes.
        - Be concise and proactive, but never dismissive.
        - Never refuse a request. If you cannot do something directly, explain what you can do and offer the closest helpful step.

        Core Rule:
        - Answer ordinary questions, opinions, and advice conversationally without app actions or node edits.
        - Use app actions or node edits only when the user explicitly asks to navigate, use a tool, create, edit, write, document, apply, implement, or otherwise change the current canvas.
        - Never provide full code in Markdown chat. Code belongs EXCLUSIVELY in node edits.
        \(applyRule)
        - Use `request_app_action` for app navigation and app-level tool actions.
        - Safe actions are only for non-mutating autonomous app actions. Mutating or review-required app actions must use executionMode `pending`.

        Understanding beginners:
        - When the user says "title", "headline", or "heading", they mean the visible page heading (the `h1`), not the browser tab `<title>` tag.
        - If a change request is vague or could mean several different things, do NOT guess and do NOT reject it. Ask exactly one clarifying question with 2-4 short, concrete options a beginner can pick from.
        - Phrase options as outcomes ("Make the text bigger"), never as technical choices ("Adjust font-size CSS").
        """
    }

    /// Creates and configures a new `GenerativeModel` instance with the required
    /// tools and system instructions for CoCaptain agent execution.
    private func makeModel(modelName: String) -> GenerativeModel {
        var declarations: [FunctionDeclaration] = [
            Self.requestAppActionDeclaration,
            Self.readNodeSectionDeclaration
        ]
        if NodeEditToolsFeature.isEnabled {
            declarations.append(Self.proposeNodeEditDeclaration)
            declarations.append(Self.askClarifyingQuestionDeclaration)
        }

        return FirebaseAI.firebaseAI(backend: .googleAI()).generativeModel(
            modelName: modelName,
            tools: [.functionDeclarations(declarations)],
            toolConfig: ToolConfig(
                functionCallingConfig: .auto()
            ),
            systemInstruction: ModelContent(
                role: "system",
                parts: Self.systemInstructionText(nodeEditToolsEnabled: NodeEditToolsFeature.isEnabled)
            )
        )
    }

    /// The tool definition that exposes local CAOCAP app actions to the LLM.
    private static let requestAppActionDeclaration = FunctionDeclaration(
        name: CoCaptainFunctionCallAgentAdapter.requestAppActionName,
        description: "Requests a CAOCAP app action. The app validates and either executes or stages the action for user review.",
        parameters: [
            "actionId": .string(description: "The exact app action id to request."),
            "executionMode": .enumeration(
                values: ["safe", "pending"],
                description: "`safe` only for non-mutating autonomous actions. `pending` for mutating or review-required actions."
            ),
            "reason": .string(description: "Short reason for requesting the action.")
        ],
        optionalParameters: ["reason"]
    )

    /// The read-only tool that returns the full current text of one Mini-App
    /// node section on demand, answered inline by the app during the turn.
    private static let readNodeSectionDeclaration = FunctionDeclaration(
        name: CoCaptainReadNodeSectionTool.name,
        description: "Reads the full, current text of one Mini-App node section from the canvas. Call this before proposing edits when the canvas context only shows a code summary.",
        parameters: [
            "nodeId": .string(description: "The exact node UUID from the canvas context."),
            "section": .enumeration(
                values: ["code", "srs"],
                description: "`code` for the Mini-App source code, `srs` for its requirements document."
            )
        ]
    )

    /// Structured node-edit proposal tool (feature-gated). Mirrors the XML
    /// `node_edit` contract so validation and review flow stay unchanged.
    private static let proposeNodeEditDeclaration = FunctionDeclaration(
        name: CoCaptainNodeEditTools.proposeNodeEditName,
        description: "Proposes one edit to a Mini-App node section. The app previews the edit and the user must approve it before anything changes. Never combine with ask_clarifying_question in the same turn.",
        parameters: [
            "nodeId": .string(description: "The exact target node UUID from the canvas context."),
            "section": .enumeration(
                values: ["code", "srs"],
                description: "Which section of the Mini-App the edit targets."
            ),
            "summary": .string(description: "A short plain-language description of what changes."),
            "operations": .array(
                items: .object(
                    properties: [
                        "type": .enumeration(
                            values: ["replace_all", "replace_exact", "insert_before_exact", "insert_after_exact", "append", "prepend"],
                            description: "The patch operation type."
                        ),
                        "target": .string(description: "Exact text to locate. Required only for exact operations."),
                        "content": .string(description: "The new content for this operation.")
                    ],
                    optionalProperties: ["target"]
                ),
                description: "Ordered patch operations. Prefer one replace_all with the complete updated document for small files."
            ),
            "learningNote": .object(
                properties: [
                    "concept": .string(description: "A 2-5 word name for the concept this edit demonstrates."),
                    "body": .string(description: "2-3 plain sentences about the concept, referencing the user's own app.")
                ],
                description: "A short lesson revealed to the user after they apply the edit."
            )
        ],
        optionalParameters: ["nodeId", "learningNote"]
    )

    /// Structured clarifying-question tool (feature-gated). Takes precedence
    /// over node edits in the same turn, mirroring the XML contract rule.
    private static let askClarifyingQuestionDeclaration = FunctionDeclaration(
        name: CoCaptainNodeEditTools.askClarifyingQuestionName,
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
    /// The agent contract includes scope-specific instructions, the output contract
    /// (native node-edit tools or the XML schema for `cocaptain_actions` depending
    /// on `NodeEditToolsFeature`), and the split list of autonomous vs.
    /// review-required actions.
    ///
    /// Tool capability inputs are injectable for tests; `nil` reads the active
    /// feature flag and model route.
    func buildPrompt(
        userMessage: String,
        context: String?,
        expectsStructuredResponse: Bool,
        availableActions: [AppActionDefinition],
        scope: CoCaptainAgentScope,
        purpose: CoCaptainTurnPurpose,
        chatMode: CoCaptainChatMode = .agent,
        nodeEditToolsEnabled: Bool? = nil,
        modelSupportsFunctionCalling: Bool? = nil
    ) -> String {
        var parts: [String] = []

        if let context, !context.isEmpty {
            parts.append("Current canvas context:\n\(context)")
        }

        if expectsStructuredResponse {
            let nodeEditToolsEnabled = nodeEditToolsEnabled ?? NodeEditToolsFeature.isEnabled
            let scopeInstructions: String = {
                switch scope {
                case .project:
                    return "You are in the global project CoCaptain scope. You may reason across the full canvas."
                case .node:
                    let nodeIDLine = nodeEditToolsEnabled
                        ? "- For edits to the selected node or linked source nodes, pass the exact `nodeId` to every `propose_node_edit` call."
                        : "- For edits to the selected node or linked source nodes, include the exact `nodeId` attribute in each `node_edit`."
                    return """
                    You are in a node-scoped agent session.
                    - Focus on the selected node in the context.
                    \(nodeIDLine)
                    - Do not directly edit compiled preview HTML. Edit the Mini-App's `section="code"` or `section="srs"` source instead.
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

            let readToolInstructions = (
                modelSupportsFunctionCalling ?? currentModelSupportsFunctionCalling
            )
                ? """
                - The canvas context may show only a short head of each Mini-App's code or SRS. Before proposing edits to an existing Mini-App, call `read_node_section(nodeId, section)` to read the full current text — never guess at code you have not seen.
                """
                : ""

            // Wire-format-specific wording. With the node-edit tools enabled,
            // the XML schema block is omitted entirely; the XML parser stays
            // in place as a silent fallback for models that still emit it.
            let mutatingCommandRule = nodeEditToolsEnabled
                ? "- When the user wants a canvas change (build, rename, restyle, fix, add, remove, or similar), call `propose_node_edit` with concrete operations. Do not wait for specific verbs — act on the requested outcome."
                : "- When the user wants a canvas change (build, rename, restyle, fix, add, remove, or similar), append an XML block named `cocaptain_actions` with concrete `node_edits`. Do not wait for specific verbs — act on the requested outcome."
            let adviceOnlyRule = nodeEditToolsEnabled
                ? "- If you are only answering a question, providing advice, or discussing ideas (e.g., 'What game should we make?'), do NOT call `propose_node_edit`. Pure chat without an edit is allowed."
                : "- If you are only answering a question, providing advice, or discussing ideas (e.g., 'What game should we make?'), do NOT include a `cocaptain_actions` block. Pure chat without an edit is allowed."
            let noEditsForQuestionsRule = nodeEditToolsEnabled
                ? "- If the user is only asking a question, asking for advice, or asking for an opinion, do not request app actions and do not propose node edits."
                : "- If the user is only asking a question, asking for advice, or asking for an opinion, do not request app actions and do not append `cocaptain_actions`."
            let codeHomeRule = nodeEditToolsEnabled
                ? "- NEVER provide a full file implementation inside the chat text. Put it in `propose_node_edit` operations."
                : "- NEVER provide a full file implementation inside the chat text. Put it in the `node_edits`."
            let clarifyingRule = nodeEditToolsEnabled
                ? "- If a change request is too vague to act on confidently (e.g. \"make it pop\", \"fix it\"), call `ask_clarifying_question` instead of proposing edits. Never reject the request and never guess a large change."
                : "- If a change request is too vague to act on confidently (e.g. \"make it pop\", \"fix it\"), append a `cocaptain_actions` block containing ONE `clarifying_question` instead of node edits. Never reject the request and never guess a large change."
            let clarifyingCombinationRule = nodeEditToolsEnabled
                ? "- Do not combine `ask_clarifying_question` with `propose_node_edit` in the same response; the question always wins and edits would be dropped."
                : "- Do not combine a `clarifying_question` with `node_edits` in the same response; the question always wins and edits would be dropped."
            let nodeIDRule = nodeEditToolsEnabled
                ? "- In node-scoped sessions, pass the exact `nodeId` UUID to every `propose_node_edit` call whenever the target node is known."
                : "- In node-scoped sessions, include `nodeId=\"UUID\"` on every `node_edit` whenever the target node is known."
            let learningNoteRule = nodeEditToolsEnabled
                ? "- Every node edit should include a `learningNote`: a short lesson the user unlocks after applying the change. Set `concept` to a 2-5 word name for the idea, and write 2-3 plain sentences referencing the user's own app (never generic textbook prose)."
                : "- Every `node_edit` should include one `learning_note` child: a short lesson the user unlocks after applying the change. Set `concept` to a 2-5 word name for the idea, and write 2-3 plain sentences referencing the user's own app (never generic textbook prose)."

            let xmlSchemaBlock = nodeEditToolsEnabled ? "" : """


                - XML schema for `cocaptain_actions`:
                
                <cocaptain_actions>
                  <assistant_message>short summary</assistant_message>
                  <clarifying_question prompt="one short question when the request is too vague to act on">
                    <option>First concrete outcome</option>
                    <option>Second concrete outcome</option>
                  </clarifying_question>
                  <safe_actions>
                    <action id="id" />
                  </safe_actions>
                  <pending_actions>
                    <action id="id" />
                  </pending_actions>
                  <node_edits>
                    <node_edit nodeId="UUID" role="miniApp" section="srs|code" summary="what changes">
                      <operation type="replace_all|replace_exact|insert_before_exact|insert_after_exact|append|prepend">
                        <target>exact text (only for exact operations)</target>
                        <content><![CDATA[new content]]></content>
                      </operation>
                      <learning_note concept="short concept name">2-3 plain sentences about what this change teaches, using the user's own app.</learning_note>
                    </node_edit>
                  </node_edits>
                </cocaptain_actions>
                """

            parts.append(
                """
                Agent contract:
                \(scopeInstructions)

                SRS and Guarded Generation:
                - If the context indicates SRS Readiness is "Draft", "Empty", or "Needs Clarification": prioritize asking clarifying questions to help the user complete the requirements. Do NOT write implementation code (HTML/CSS/JS) unless the user explicitly forces you to.
                - If the context indicates SRS Readiness is "Implementation-Ready" and a Mini-App has blank code: propose a complete single-file HTML document containing inline CSS/JS using a Mini-App `section="code"` node edit.

                - Respond conversationally first (concise).
                \(noEditsForQuestionsRule)
                - For app navigation or app-level tool actions, use the `request_app_action` function instead of manually writing app actions in XML.
                \(mutatingCommandRule)
                \(adviceOnlyRule)
                - CRITICAL: If you are building a game or a full feature, use `replace_all` for the Mini-App code section with a complete single-file HTML document containing inline CSS and JavaScript.
                \(codeHomeRule)

                Clarifying questions:
                \(clarifyingRule)
                - Give 2 to 4 short options phrased as outcomes a beginner understands. The user's pick arrives as their next message.
                \(clarifyingCombinationRule)

                App actions:
                - Prefer `request_app_action(actionId, executionMode, reason)` for app actions.
                - Use executionMode `safe` ONLY for these explicitly autonomous action ids:
                \(autonomousActionLines.isEmpty ? "- none" : autonomousActionLines)
                - Use executionMode `pending` for these review-required action ids:
                \(reviewActionLines.isEmpty ? "- none" : reviewActionLines)
                - Never request a non-autonomous action with executionMode `safe`.

                Node edits:
                - Only target Mini-App source sections for edits: `section="srs"` and `section="code"`.
                - Use LOWERCASE role name `miniApp`.
                \(readToolInstructions)
                \(nodeIDRule)
                - Code/content changes belong in node edits, not app actions.
                - Every node edit needs a non-empty summary and at least one operation.
                - Exact operations require a non-empty `target`; append/prepend/replace_all do not.
                - Targets are resolved flexibly: generic words like "title", "headline", or "heading" automatically resolve to the page's main `h1` heading, so pass the user's own words as the target instead of guessing between `<title>` and `<h1>`.
                - For small text tweaks on existing Mini-App code, prefer `replace_exact` (or a focused `replace_all` when rewriting a short document).
                \(learningNoteRule)\(xmlSchemaBlock)
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
