import Foundation
import OSLog

/// The interface through which `CoCaptainAgentCoordinator` communicates with
/// the underlying language model.
///
/// Abstracting the LLM behind this protocol allows unit tests to inject a
/// lightweight stub without touching `LLMService` or Firebase AI Logic.
@MainActor
public protocol CoCaptainLLMClient: AnyObject {
    /// Clears the model's conversation history for the given scope, starting a
    /// fresh chat session. Called when the user taps "Clear" in the chat UI.
    func resetChat(scope: CoCaptainAgentScope)
    /// Returns a recoverable validation error before the composer clears a draft.
    func submissionError(for attachments: [CoCaptainAttachment]) -> CoCaptainSubmissionError?
    /// Streams incremental model output for one user turn.
    ///
    /// - Parameters:
    ///   - userMessage: The raw text entered by the user.
    ///   - context: A serialised snapshot of the active canvas, or `nil` when
    ///     running in reduced / fallback mode.
    ///   - expectsStructuredResponse: When `true` the system prompt instructs the
    ///     model to wrap executable output in a `cocaptain_actions` XML block.
    ///   - availableActions: The set of `AppActionDefinition`s the model may call
    ///     via `request_app_action`. Sent as tool declarations in each turn.
    ///   - scope: Whether this turn targets the whole project or a single node.
    ///   - chatMode: Agent / Ask / Plan posture for prompt/context (Ask/Plan are prose-only).
    ///   - toolExecutor: Optional inline tool answers during the turn (unused for
    ///     retired read tools; kept for protocol compatibility).
    func streamAgentEvents(
        for userMessage: String,
        context: String?,
        expectsStructuredResponse: Bool,
        availableActions: [AppActionDefinition],
        scope: CoCaptainAgentScope,
        purpose: CoCaptainTurnPurpose,
        chatMode: CoCaptainChatMode,
        toolExecutor: CoCaptainToolExecutor?
    ) -> AsyncThrowingStream<CoCaptainLLMStreamEvent, Error>
}

public extension CoCaptainLLMClient {
    func submissionError(for attachments: [CoCaptainAttachment]) -> CoCaptainSubmissionError? {
        nil
    }

    /// Convenience overload for callers without an in-turn tool executor.
    func streamAgentEvents(
        for userMessage: String,
        context: String?,
        expectsStructuredResponse: Bool,
        availableActions: [AppActionDefinition],
        scope: CoCaptainAgentScope,
        purpose: CoCaptainTurnPurpose,
        chatMode: CoCaptainChatMode = .agent
    ) -> AsyncThrowingStream<CoCaptainLLMStreamEvent, Error> {
        streamAgentEvents(
            for: userMessage,
            context: context,
            expectsStructuredResponse: expectsStructuredResponse,
            availableActions: availableActions,
            scope: scope,
            purpose: purpose,
            chatMode: chatMode,
            toolExecutor: nil
        )
    }
}

extension LLMService: CoCaptainLLMClient {}

/// The complete result of one CoCaptain assistant turn, ready for the view
/// model to splice into the conversation timeline.
public struct CoCaptainAgentRunResult: Hashable {
    /// The text that appeared before the structured `cocaptain_actions` block,
    /// i.e. the model's conversational prose.
    public let preamble: String
    /// The chat text extracted from inside the structured payload, if present.
    public let payloadMessage: String?
    /// A confirmation item to append when one or more safe actions were executed.
    public let executionSummary: ExecutionStatusItem?
    /// Validated pending actions that the review lifecycle can
    /// stage, or `nil` when the model produced no reviewable changes.
    public let reviewDraft: CoCaptainReviewLifecycle.Draft?
    /// A question with tappable answer options to render after the messages,
    /// or `nil` when the assistant did not need to ask anything.
    public let clarifyingQuestion: CoCaptainClarifyingQuestion?

    public init(
        preamble: String,
        payloadMessage: String?,
        executionSummary: ExecutionStatusItem?,
        reviewDraft: CoCaptainReviewLifecycle.Draft?,
        clarifyingQuestion: CoCaptainClarifyingQuestion? = nil
    ) {
        self.preamble = preamble
        self.payloadMessage = payloadMessage
        self.executionSummary = executionSummary
        self.reviewDraft = reviewDraft
        self.clarifyingQuestion = clarifyingQuestion
    }

    /// The text the chat bubble should display.
    ///
    /// Prefers the preamble because it is the richer, prose form. Falls back to
    /// `payloadMessage` when the model placed all its text inside the XML block.
    public var visibleText: String {
        if preamble.isEmpty { return payloadMessage ?? "" }
        return preamble
    }
}

/// Bridges model output to app behavior while keeping mutating app actions in
/// an explicit review flow.
@MainActor
public final class CoCaptainAgentCoordinator {
    private let llmClient: any CoCaptainLLMClient
    private let contextBuilder: ProjectContextBuilder?
    private let outputAdapter: any CoCaptainAgentOutputAdapting
    private let validator: CoCaptainAgentValidator

    /// Creates a coordinator with optional dependency overrides for testing.
    ///
    /// All parameters have sensible production defaults; only supply non-nil
    /// values when you need to inject stubs or alternative implementations.
    public init(
        llmClient: (any CoCaptainLLMClient)? = nil,
        contextBuilder: ProjectContextBuilder? = nil,
        parser: CoCaptainAgentParser = CoCaptainAgentParser(),
        outputAdapter: (any CoCaptainAgentOutputAdapting)? = nil,
        validator: CoCaptainAgentValidator = CoCaptainAgentValidator()
    ) {
        self.llmClient = llmClient ?? LLMService.shared
        self.contextBuilder = contextBuilder
        // Wrap the XML adapter in the composite so function-call responses are
        // merged with fenced-XML responses when both arrive in the same turn.
        self.outputAdapter = outputAdapter ?? CoCaptainCompositeAgentAdapter(
            xmlAdapter: CoCaptainXMLAgentAdapter(parser: parser)
        )
        self.validator = validator
    }

    private let logger = Logger(subsystem: "com.caocap.CoCaptainAgentCoordinator", category: "Coordinator")
    private static let maxAgenticRetries = 2

    /// Resets the chat history for the given scope, forwarding directly to the
    /// LLM client. Defaults to the project scope for callers that don't track scope.
    public func resetChat(scope: CoCaptainAgentScope = .project) {
        llmClient.resetChat(scope: scope)
    }

    /// Validates capabilities before a view clears its composer draft.
    public func submissionError(
        for attachments: [CoCaptainAttachment]
    ) -> CoCaptainSubmissionError? {
        llmClient.submissionError(for: attachments)
    }

    /// Runs one assistant turn against the active project context. Structured
    /// responses are preferred so the UI can separate visible chat text from
    /// executable actions and reviewable pending work.
    public func run(
        userMessage: String,
        store: ProjectStore?,
        dispatcher: (any AppActionPerforming)?,
        scope: CoCaptainAgentScope = .project,
        purpose: CoCaptainTurnPurpose = .standard,
        turnPlan: CoCaptainTurnPlan? = nil,
        contextFocusNodeIDs: [UUID] = [],
        attachments: [CoCaptainAttachment] = [],
        onVisibleText: @escaping (String) -> Void
    ) async throws -> CoCaptainAgentRunResult {
        let resolvedTurnPlan = turnPlan ?? CoCaptainTurnPlan(purpose: purpose, mode: .agent)
        let context: String? = nil
        let policy = resolvedTurnPlan.effectivePolicy

        do {
            return try await runOnce(
                userMessage: userMessage,
                attachments: attachments,
                context: context,
                expectsStructuredResponse: policy.expectsStructuredResponse,
                store: store,
                dispatcher: dispatcher,
                scope: scope,
                purpose: purpose,
                turnPlan: resolvedTurnPlan,
                onVisibleText: onVisibleText,
                agenticRetriesRemaining: policy.allowsAgenticRetry ? Self.maxAgenticRetries : 0
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Fallback: if the structured+context prompt fails (often with opaque
            // `GenerateContentError error 0`), retry with a minimal prompt so chat stays usable.
            let fallbackResult = try await runOnce(
                userMessage: userMessage,
                attachments: attachments,
                context: nil,
                expectsStructuredResponse: false,
                store: store,
                dispatcher: dispatcher,
                scope: scope,
                purpose: purpose,
                turnPlan: resolvedTurnPlan,
                onVisibleText: onVisibleText,
                agenticRetriesRemaining: 0,
                connectionFallback: true
            )
            return connectionFallbackResult(
                fallbackResult,
                turnPlan: resolvedTurnPlan
            )
        }
    }

    /// Executes one full LLM round-trip and processes the response.
    ///
    /// - Parameters:
    ///   - agenticRetriesRemaining: How many corrective model retries remain when
    ///     the response fails parsing or validation.
    private func runOnce(
        userMessage: String,
        attachments: [CoCaptainAttachment] = [],
        context: String?,
        expectsStructuredResponse: Bool,
        store: ProjectStore?,
        dispatcher: (any AppActionPerforming)?,
        scope: CoCaptainAgentScope,
        purpose: CoCaptainTurnPurpose,
        turnPlan: CoCaptainTurnPlan,
        onVisibleText: @escaping (String) -> Void,
        agenticRetriesRemaining: Int,
        connectionFallback: Bool = false
    ) async throws -> CoCaptainAgentRunResult {
        let directive = try await generateDirective(
            userMessage: userMessage,
            attachments: attachments,
            context: context,
            expectsStructuredResponse: expectsStructuredResponse,
            availableActions: dispatcher?.availableActions ?? [],
            scope: scope,
            purpose: purpose,
            chatMode: turnPlan.mode,
            onVisibleText: onVisibleText
        )
        let policy = turnPlan.effectivePolicy
        let payload = (policy.expectsStructuredResponse || connectionFallback) ? directive.payload : nil

        let requiresAgenticWork = policy.enforcesExecutableWork

        if policy.expectsStructuredResponse {
            if !directive.diagnostics.isEmpty {
                // Invalid structured output: retry with feedback when policy allows.
                if agenticRetriesRemaining > 0 {
                    return try await runOnce(
                        userMessage: agenticRetryMessage(
                            for: userMessage,
                            validationIssues: directive.diagnostics
                        ),
                        context: context,
                        expectsStructuredResponse: true,
                        store: store,
                        dispatcher: dispatcher,
                        scope: scope,
                        purpose: purpose,
                        turnPlan: turnPlan,
                        onVisibleText: onVisibleText,
                        agenticRetriesRemaining: agenticRetriesRemaining - 1
                    )
                }

                return validationFailureResult(
                    preamble: directive.preamble,
                    issues: directive.diagnostics
                )
            }

            // Guided-edit (and similar) turns must produce executable work. Agent
            // mode does not: pure chat without an edit is a valid terminal outcome.
            if payload == nil, agenticRetriesRemaining > 0, requiresAgenticWork {
                return try await runOnce(
                    userMessage: agenticRetryMessage(
                        for: userMessage,
                        validationIssues: directive.diagnostics.isEmpty
                            ? ["Missing machine-readable CoCaptain action directive."]
                            : directive.diagnostics
                    ),
                    context: context,
                    expectsStructuredResponse: true,
                    store: store,
                    dispatcher: dispatcher,
                    scope: scope,
                    purpose: purpose,
                    turnPlan: turnPlan,
                    onVisibleText: onVisibleText,
                    agenticRetriesRemaining: agenticRetriesRemaining - 1
                )
            }

            if let payload {
                let validation = validator.validate(
                    payload: payload,
                    dispatcher: dispatcher,
                    requiresAgenticWork: requiresAgenticWork
                )

                if !validation.isValid {
                    if agenticRetriesRemaining > 0 {
                        return try await runOnce(
                            userMessage: agenticRetryMessage(
                                for: userMessage,
                                validationIssues: validation.issues
                            ),
                            context: context,
                            expectsStructuredResponse: true,
                            store: store,
                            dispatcher: dispatcher,
                            scope: scope,
                            purpose: purpose,
                            turnPlan: turnPlan,
                            onVisibleText: onVisibleText,
                            agenticRetriesRemaining: agenticRetriesRemaining - 1
                        )
                    }

                    return validationFailureResult(
                        preamble: directive.preamble,
                        issues: validation.issues
                    )
                }
            }
        } else if connectionFallback, let payload, policy.executesActions {
            let validation = validator.validate(
                payload: payload,
                dispatcher: dispatcher,
                requiresAgenticWork: requiresAgenticWork
            )
            if !validation.isValid {
                return validationFailureResult(
                    preamble: directive.preamble,
                    issues: validation.issues
                )
            }
        }

        if !policy.executesActions {
            return conversationalRunResult(from: directive)
        }

        // A clarifying question takes precedence over pending actions in the same
        // turn: the model was unsure, so nothing should be staged until the
        // user answers. Safe/pending actions are also held back.
        if !connectionFallback, let question = payload?.clarifyingQuestion {
            return CoCaptainAgentRunResult(
                preamble: directive.preamble,
                payloadMessage: payload?.assistantMessage,
                executionSummary: nil,
                reviewDraft: nil,
                clarifyingQuestion: question
            )
        }

        let safeActions = connectionFallback ? [] : (payload?.safeActions ?? [])
        let executionSummary = executeSafeActions(safeActions, dispatcher: dispatcher, store: store)
        let reviewDraft = makeReviewDraft(
            pendingActions: payload?.pendingActions ?? []
        )

        return CoCaptainAgentRunResult(
            preamble: directive.preamble,
            payloadMessage: payload?.assistantMessage,
            executionSummary: executionSummary,
            reviewDraft: reviewDraft
        )
    }

    private func generateDirective(
        userMessage: String,
        attachments: [CoCaptainAttachment] = [],
        context: String?,
        expectsStructuredResponse: Bool,
        availableActions: [AppActionDefinition],
        scope: CoCaptainAgentScope,
        purpose: CoCaptainTurnPurpose,
        chatMode: CoCaptainChatMode,
        onVisibleText: @escaping (String) -> Void
    ) async throws -> CoCaptainAgentDirective {
        var responseText = ""
        var functionCalls: [CoCaptainAgentFunctionCall] = []
        var seenFunctionCallIDs = Set<String>()
        // Ask / conversational turns omit tools and action catalogs so the
        // model cannot be steered into structured edit or app-action work.
        let stream: AsyncThrowingStream<CoCaptainLLMStreamEvent, Error>
        if !attachments.isEmpty, let multimodalClient = llmClient as? LLMService {
            stream = multimodalClient.streamAgentEvents(
                for: userMessage,
                attachments: attachments,
                context: context,
                expectsStructuredResponse: expectsStructuredResponse,
                availableActions: expectsStructuredResponse ? availableActions : [],
                scope: scope,
                purpose: purpose,
                chatMode: chatMode,
                toolExecutor: nil
            )
        } else {
            stream = llmClient.streamAgentEvents(
                for: userMessage,
                context: context,
                expectsStructuredResponse: expectsStructuredResponse,
                availableActions: expectsStructuredResponse ? availableActions : [],
                scope: scope,
                purpose: purpose,
                chatMode: chatMode,
                toolExecutor: nil
            )
        }

        let streamState = PerformanceSignposts.begin(PerformanceSignposts.Name.agentStream)
        defer { PerformanceSignposts.end(PerformanceSignposts.Name.agentStream, streamState) }

        for try await event in stream {
            try Task.checkCancellation()
            switch event {
            case .text(let chunk):
                responseText += chunk
                onVisibleText(outputAdapter.visibleText(from: responseText))
            case .functionCalls(let calls):
                for call in calls where shouldAppend(functionCall: call, seenIDs: &seenFunctionCallIDs) {
                    functionCalls.append(call)
                }
            }
        }
        let directive = outputAdapter.directive(from: responseText, functionCalls: functionCalls)
        if directive.payload != nil {
            // Rollout signal: track which wire format delivers structured output
            // so the XML prompt block can be deleted once tool usage dominates.
            logAgentEvent(
                "cocaptain_agent_output_source",
                parameters: ["source": directive.source.rawValue]
            )
        }
        return directive
    }

    /// A locally-built question offered after a failed turn so the user always
    /// has a tappable next step instead of a dead-end error message.
    private static var recoveryQuestion: CoCaptainClarifyingQuestion {
        CoCaptainClarifyingQuestion(
            prompt: LocalizationManager.shared.localizedString(
                "Want to try one of these instead?"
            ),
            options: [
                LocalizationManager.shared.localizedString("Try that again, please"),
                LocalizationManager.shared.localizedString("Break it into smaller steps"),
                LocalizationManager.shared.localizedString("Suggest what we could do next")
            ]
        )
    }

    private func logAgentEvent(
        _ name: String,
        parameters: [String: String]
    ) {
        AnalyticsService.shared.logEvent(name, parameters: parameters)
    }

    /// Returns visible prose only. Ignores any structured payload the model emitted.
    private func conversationalRunResult(from directive: CoCaptainAgentDirective) -> CoCaptainAgentRunResult {
        CoCaptainAgentRunResult(
            preamble: directive.preamble,
            payloadMessage: nil,
            executionSummary: nil,
            reviewDraft: nil
        )
    }

    /// When the structured prompt fails, annotate the fallback result so users
    /// know executable work may not have been staged.
    private func connectionFallbackResult(
        _ result: CoCaptainAgentRunResult,
        turnPlan: CoCaptainTurnPlan
    ) -> CoCaptainAgentRunResult {
        guard turnPlan.requiresDegradedConnectionNotice,
              result.reviewDraft == nil,
              result.executionSummary == nil else {
            return result
        }

        let notice = LocalizationManager.shared.localizedString(
            "cocaptain.fallback.editsUnavailable"
        )
        let preamble = result.preamble.isEmpty ? notice : "\(result.preamble)\n\n\(notice)"
        return CoCaptainAgentRunResult(
            preamble: preamble,
            payloadMessage: result.payloadMessage,
            executionSummary: result.executionSummary,
            reviewDraft: result.reviewDraft
        )
    }

    /// Builds a corrective system message that feeds validation issues back to
    /// the model along with the original request, giving it a second chance to
    /// produce a conforming structured payload.
    private func agenticRetryMessage(for userMessage: String, validationIssues: [String]) -> String {
        let issueList = validationIssues.map { "- \($0)" }.joined(separator: "\n")

        return """
        The previous response has not satisfied the machine-readable CoCaptain action contract.

        Validation issues:
        \(issueList)
        
        CRITICAL: 
        1. Do NOT just provide code in markdown chat. 
        2. For app navigation/tool actions, call `request_app_action`.
        3. Put mutating or non-autonomous app actions in `request_app_action` with `executionMode=pending`.
        4. Use `executionMode=safe` only for available, non-mutating, autonomous app actions.
        5. When the request is too vague to act on, call `ask_clarifying_question` instead of guessing.
        
        Original user request:
        \(userMessage)
        """
    }

    /// Guards against duplicate function-call events that can be emitted by the
    /// streaming SDK when a turn is retried or partially flushed.
    ///
    /// Function calls without an `id` are always accepted because they cannot
    /// be reliably deduplicated.
    private func shouldAppend(
        functionCall: CoCaptainAgentFunctionCall,
        seenIDs: inout Set<String>
    ) -> Bool {
        guard let id = functionCall.id else { return true }
        return seenIDs.insert(id).inserted
    }

    /// Returns a conversational recovery message when the model response cannot
    /// be executed. Validation details are logged for diagnostics, not shown in UI.
    private func validationFailureResult(
        preamble: String,
        issues: [String]
    ) -> CoCaptainAgentRunResult {
        if !issues.isEmpty {
            logger.debug("CoCaptain validation failure: \(issues.joined(separator: " | "), privacy: .public)")
        }

        let encouragement = LocalizationManager.shared.localizedString(
            "cocaptain.validationFailure.encouragement"
        )

        return CoCaptainAgentRunResult(
            preamble: preamble,
            payloadMessage: encouragement,
            executionSummary: nil,
            reviewDraft: nil,
            clarifyingQuestion: Self.recoveryQuestion
        )
    }

    /// Executes all safe (autonomous) actions immediately and returns a
    /// summary item to display in the timeline.
    ///
    /// A store checkpoint is created before execution so the user can revert
    /// a batch of automatic changes in one step if needed.
    private func executeSafeActions(
        _ actions: [CoCaptainAgentAction],
        dispatcher: (any AppActionPerforming)?,
        store: ProjectStore?
    ) -> ExecutionStatusItem? {
        guard let dispatcher, !actions.isEmpty else { return nil }

        // Create a checkpoint before executing multiple safe actions to allow revert
        store?.createAutoCheckpoint(label: "Before AI Actions")

        let executedSummaries = actions.compactMap { action -> String? in
            guard let id = AppActionID(rawValue: action.actionID) else { return nil }
            let result = dispatcher.perform(id, source: .agentAutomatic, arguments: action.args)
            return result.executed ? result.title : nil
        }

        guard !executedSummaries.isEmpty else { return nil }
        return ExecutionStatusItem(
            summary: LocalizationManager.shared.localizedString(
                "agent.executedSummary",
                arguments: [executedSummaries.joined(separator: ", ")]
            )
        )
    }

    /// Packages validated reviewable work for the review lifecycle.
    private func makeReviewDraft(
        pendingActions: [CoCaptainAgentAction]
    ) -> CoCaptainReviewLifecycle.Draft? {
        let draft = CoCaptainReviewLifecycle.Draft(
            pendingActions: pendingActions
        )
        return draft.isEmpty ? nil : draft
    }

}
