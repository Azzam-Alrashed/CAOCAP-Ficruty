import Foundation

/// Describes the conversational objective for a CoCaptain turn.
///
/// Turns use the standard agent behavior; chat mode selects Ask / Plan / Agent posture.
public enum CoCaptainTurnPurpose: String, Hashable, Codable {
    case standard

    var promptInstructions: String? { nil }

    /// Default execution posture for this purpose before chat-mode is applied.
    var executionPolicy: CoCaptainTurnExecutionPolicy { .agent }
}

/// User-selected CoCaptain chat mode (Cursor-style Agent / Ask / Plan).
///
/// Agent is the default. Ask and Plan are prose-only: no tools, no staging,
/// product-level context. Plan steers toward numbered step outlines.
/// The composer picker persists the choice under `storageKey`.
public enum CoCaptainChatMode: String, Hashable, CaseIterable, Identifiable, Codable {
    case agent
    case ask
    case plan

    public var id: String { rawValue }

    /// App Storage key for persisting the last chosen mode.
    public static let storageKey = "cocaptain.chatMode"

    /// Localized short label for the composer mode control.
    var displayName: String {
        switch self {
        case .agent:
            return LocalizationManager.shared.localizedString("Agent")
        case .ask:
            return LocalizationManager.shared.localizedString("Ask")
        case .plan:
            return LocalizationManager.shared.localizedString("Plan")
        }
    }

    /// Placeholder copy that reflects the active mode in the composer field.
    var composerPlaceholder: String {
        switch self {
        case .agent:
            return LocalizationManager.shared.localizedString("cocaptain.composer.placeholder.agent")
        case .ask:
            return LocalizationManager.shared.localizedString("cocaptain.composer.placeholder.ask")
        case .plan:
            return LocalizationManager.shared.localizedString("cocaptain.composer.placeholder.plan")
        }
    }

    /// Short explanation used in the mode menu so builders can predict whether
    /// a turn may propose canvas work.
    var explanation: String {
        switch self {
        case .agent:
            return LocalizationManager.shared.localizedString(
                "Can propose changes; you approve before they apply"
            )
        case .ask:
            return LocalizationManager.shared.localizedString(
                "Answers questions without changing the canvas"
            )
        case .plan:
            return LocalizationManager.shared.localizedString(
                "Creates a step-by-step plan without implementing it"
            )
        }
    }

    /// SF Symbol for the compact mode chip.
    var systemImageName: String {
        switch self {
        case .agent:
            return "sparkles"
        case .ask:
            return "bubble.left"
        case .plan:
            return "list.bullet.rectangle"
        }
    }

    /// True when the mode must not mutate the canvas via shortcuts or staging.
    var isProseOnly: Bool {
        switch self {
        case .agent:
            return false
        case .ask, .plan:
            return true
        }
    }

    var executionPolicy: CoCaptainTurnExecutionPolicy {
        switch self {
        case .agent:
            return .agent
        case .ask:
            return .ask
        case .plan:
            return .plan
        }
    }

    /// Richer canvas context for Agent; lighter product-oriented context for Ask/Plan.
    var contextDetailLevel: ProjectContextBuilder.DetailLevel {
        switch self {
        case .agent:
            return .implementation
        case .ask, .plan:
            return .product
        }
    }

    /// Extra prompt posture for the selected mode. Ask/Plan forbid tools and edits.
    var promptInstructions: String? {
        switch self {
        case .agent:
            return nil
        case .ask:
            return """
            Ask mode objective:
            - Answer with helpful, beginner-friendly prose only.
            - Do not request app actions, invoke tools, or emit a `cocaptain_actions` block.
            - Do not mention nodes, patches, XML, Firebase wiring, or other implementation details unless the user explicitly asks.
            - Focus on product ideas, explanations, and next-step advice grounded in the supplied canvas context.
            - Match the language used by the user.
            """
        case .plan:
            return """
            Plan mode objective:
            - Outline a clear, beginner-friendly plan for what to build or change next.
            - Prefer a short numbered list of concrete steps (usually 3 to 7).
            - Explain the approach and order of work; do not implement changes yet.
            - Do not request app actions, invoke tools, or emit a `cocaptain_actions` block.
            - Do not mention nodes, patches, XML, Firebase wiring, or other implementation details unless the user explicitly asks.
            - Match the language used by the user.
            """
        }
    }
}

/// Merges turn purpose with chat mode to select execution behavior.
public struct CoCaptainTurnPlan: Equatable {
    public let purpose: CoCaptainTurnPurpose
    public let mode: CoCaptainChatMode

    public init(purpose: CoCaptainTurnPurpose, mode: CoCaptainChatMode = .agent) {
        self.purpose = purpose
        self.mode = mode
    }

    /// Standard turns follow the chat-mode picker.
    var effectivePolicy: CoCaptainTurnExecutionPolicy {
        mode.executionPolicy
    }

    /// Canvas context richness for this turn.
    var contextDetailLevel: ProjectContextBuilder.DetailLevel {
        mode.contextDetailLevel
    }

    /// Connection-fallback footers apply when the turn expected canvas work capability.
    var requiresDegradedConnectionNotice: Bool {
        let policy = effectivePolicy
        return policy.expectsStructuredResponse && policy.executesActions
    }
}

/// Controls whether a CoCaptain turn runs the full agent contract or stays conversational.
///
/// Derived from `CoCaptainTurnPlan` so prompt instructions and execution behavior
/// stay aligned in one place.
struct CoCaptainTurnExecutionPolicy: Equatable {
    enum Kind: Equatable {
        /// Standard Agent mode: tools available, pure chat allowed, retry on invalid structure.
        case agent
        /// Ask mode: prose only (no tools / staging).
        case ask
        /// Plan mode: outline-only prose (no tools / staging).
        case plan
    }

    let kind: Kind
    let expectsStructuredResponse: Bool
    let enforcesExecutableWork: Bool
    let executesActions: Bool
    let allowsAgenticRetry: Bool

    /// Standard Agent mode: structured tools on, chat without an edit OK,
    /// retry only when structured output is invalid (not when the model chats).
    static let agent = CoCaptainTurnExecutionPolicy(
        kind: .agent,
        expectsStructuredResponse: true,
        enforcesExecutableWork: false,
        executesActions: true,
        allowsAgenticRetry: true
    )

    /// Ask mode: prose-only, no staging or agentic retry.
    static let ask = CoCaptainTurnExecutionPolicy(
        kind: .ask,
        expectsStructuredResponse: false,
        enforcesExecutableWork: false,
        executesActions: false,
        allowsAgenticRetry: false
    )

    /// Plan mode: same execution shape as Ask, different prompt posture.
    static let plan = CoCaptainTurnExecutionPolicy(
        kind: .plan,
        expectsStructuredResponse: false,
        enforcesExecutableWork: false,
        executesActions: false,
        allowsAgenticRetry: false
    )
}

/// The terminal outcome of one specific CoCaptain turn.
///
/// The turn purpose lets onboarding react only to the response it initiated,
/// instead of inferring intent from a global response counter.
public struct CoCaptainTurnCompletion: Equatable {
    public let turnID: UUID
    public let purpose: CoCaptainTurnPurpose
    public let succeeded: Bool
    public let presentedReviewBundle: Bool

    public init(
        turnID: UUID,
        purpose: CoCaptainTurnPurpose,
        succeeded: Bool,
        presentedReviewBundle: Bool = false
    ) {
        self.turnID = turnID
        self.purpose = purpose
        self.succeeded = succeeded
        self.presentedReviewBundle = presentedReviewBundle
    }
}

/// Identifies the portion of the canvas that a CoCaptain agent session targets.
///
/// The scope controls both which context is serialised for the model and
/// which chat history is maintained — project-level and node-level sessions
/// are kept independent so switching nodes doesn't pollute the project chat.
public enum CoCaptainAgentScope: Hashable {
    /// The entire active project canvas.
    case project
    /// A single named node within the canvas, identified by its UUID.
    case node(UUID)

    /// A stable string suitable for keying per-scope state in a dictionary
    /// or persisted store (e.g. scroll-position keying in the timeline).
    public var storageKey: String {
        switch self {
        case .project:
            return "project"
        case .node(let id):
            return "node:\(id.uuidString)"
        }
    }
}

/// The lifecycle state of one CoCaptain agent turn, used by the view model
/// to gate UI interactions and display appropriate loading/feedback states.
public enum AgentExecutionState: Equatable {
    /// No request is in progress; the assistant is ready to accept input.
    case idle
    /// The model is streaming a response.
    case thinking
    /// Safe actions are being executed against the active project store.
    case applying
    /// The model produced review items that the user must approve or reject
    /// before changes are committed.
    case awaitingReview
    /// A terminal error occurred during the turn; the associated string
    /// carries a user-facing description.
    case error(String)
}

/// Short, observable progress labels shown while an agent turn is active.
///
/// These phases describe product-visible work only. They must never expose raw
/// model reasoning or hidden tool payloads.
public enum CoCaptainProgressPhase: String, Hashable, Codable {
    case connecting
    case readingContext
    case thinking
    case preparingChanges
    case applying

    public var localizedTitle: String {
        switch self {
        case .connecting:
            return LocalizationManager.shared.localizedString("Connecting")
        case .readingContext:
            return LocalizationManager.shared.localizedString("Reading canvas")
        case .thinking:
            return LocalizationManager.shared.localizedString("Thinking")
        case .preparingChanges:
            return LocalizationManager.shared.localizedString("Preparing changes")
        case .applying:
            return LocalizationManager.shared.localizedString("Applying")
        }
    }
}

/// A single app-level action emitted by the model, referencing a registered
/// `AppActionID` by its raw string and optional key-value arguments.
///
/// Actions arrive as either safe (auto-executed) or pending (user-reviewed)
/// depending on the enclosing XML block or function-call `executionMode`.
public struct CoCaptainAgentAction: Codable, Hashable {
    /// The raw string identifier that maps to a registered `AppActionID`.
    public let actionID: String
    /// Optional arguments passed to the action handler (e.g. `["url": "..."]`).
    public let args: [String: String]?

    public init(actionID: String, args: [String: String]? = nil) {
        self.actionID = actionID
        self.args = args
    }

    private enum CodingKeys: String, CodingKey {
        // The wire format uses camelCase; the struct uses the canonical Swift name.
        case actionID = "actionId"
        case args
    }
}

/// A short model-authored lesson previously attached to applied edits.
///
/// Kept for timeline history decoding; new turns no longer emit learning notes.
public struct CoCaptainLearningNote: Codable, Hashable {
    /// A 2-5 word name for the concept the edit demonstrates.
    public let concept: String
    /// 2-3 plain sentences explaining the concept using the user's own app.
    public let body: String

    public init(concept: String, body: String) {
        self.concept = concept
        self.body = body
    }
}

/// One polite question the assistant asks when a request is too vague to act
/// on. The options render as tappable chips; picking one becomes the user's
/// next message, so no request is ever rejected outright.
public struct CoCaptainClarifyingQuestion: Hashable, Codable {
    public static let minimumOptions = 2
    public static let maximumOptions = 4

    /// The question text, phrased for non-technical users.
    public let prompt: String
    /// Two to four short, concrete answers the user can tap.
    public let options: [String]

    public init(prompt: String, options: [String]) {
        self.prompt = prompt
        self.options = options
    }
}

/// The decoded, structured output from one CoCaptain model turn.
///
/// The payload separates the model's prose from its executable intent.
/// `safeActions` run immediately (non-mutating, autonomous); `pendingActions`
/// enter the review queue for explicit user approval.
public struct CoCaptainAgentPayload: Codable, Hashable {
    /// The chat-visible text the model produced alongside its actions.
    public let assistantMessage: String
    /// Actions that the coordinator may execute autonomously without user review
    /// because they are non-mutating or explicitly marked as safe.
    public let safeActions: [CoCaptainAgentAction]
    /// Actions that require explicit user approval before being dispatched.
    public let pendingActions: [CoCaptainAgentAction]
    /// A structured question the model asks instead of guessing when the
    /// request is ambiguous. Takes precedence over pending actions in the same turn.
    public let clarifyingQuestion: CoCaptainClarifyingQuestion?

    public init(
        assistantMessage: String,
        safeActions: [CoCaptainAgentAction] = [],
        pendingActions: [CoCaptainAgentAction] = [],
        clarifyingQuestion: CoCaptainClarifyingQuestion? = nil
    ) {
        self.assistantMessage = assistantMessage
        self.safeActions = safeActions
        self.pendingActions = pendingActions
        self.clarifyingQuestion = clarifyingQuestion
    }
}

/// A wire-format-independent JSON value for function-call arguments.
///
/// Mirrors the shape of `FirebaseAILogic.JSONValue` without importing the SDK
/// into the agent contract, and — unlike the old `[String: String]` argument
/// map — preserves nested objects and arrays for structured tool arguments.
public indirect enum AgentJSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AgentJSONValue])
    case object([String: AgentJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AgentJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AgentJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    /// A scalar string rendering: strings pass through, numbers and booleans
    /// are stringified, compound values and null return `nil`.
    public var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value == value.rounded() && abs(value) < 1e15
                ? String(Int(value))
                : String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null, .object, .array:
            return nil
        }
    }

    public var arrayValue: [AgentJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var objectValue: [String: AgentJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}

extension AgentJSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByNilLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(nilLiteral: ()) { self = .null }
    public init(arrayLiteral elements: AgentJSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, AgentJSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

/// Constants for the `ask_clarifying_question` tool.
public enum CoCaptainClarifyingQuestionTools {
    public static let askClarifyingQuestionName = "ask_clarifying_question"
}

/// Answers a model tool call inline during a streaming turn.
///
/// Returns the tool's textual result when the call is a read-style tool the
/// app can execute immediately, or `nil` when the call should instead be
/// collected and routed through the output adapters (e.g. `request_app_action`).
public typealias CoCaptainToolExecutor = @MainActor (CoCaptainAgentFunctionCall) async -> String?

/// A Gemini function-call payload delivered via the streaming API.
///
/// When the model invokes a declared tool (e.g. `request_app_action`), the
/// SDK surfaces it as a function call alongside or instead of text. The
/// composite adapter merges these with any XML-fenced actions.
public struct CoCaptainAgentFunctionCall: Hashable {
    /// The registered tool name as declared in the function declarations schema.
    public let name: String
    /// The arguments the model supplied for this invocation, preserving
    /// nested objects and arrays.
    public let arguments: [String: AgentJSONValue]
    /// An opaque ID assigned by the model; used to deduplicate duplicate
    /// function-call events that can arrive during streaming.
    public let id: String?

    public init(name: String, arguments: [String: AgentJSONValue], id: String? = nil) {
        self.name = name
        self.arguments = arguments
        self.id = id
    }

    /// Returns a trimmed, non-empty scalar argument value for `key`.
    public func stringArgument(_ key: String) -> String? {
        guard let value = arguments[key]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return nil
        }
        return value
    }
}

/// A single event emitted by the LLM streaming API during one assistant turn.
public enum CoCaptainLLMStreamEvent: Hashable {
    /// An incremental text chunk to be appended to the running response buffer.
    case text(String)
    /// One or more function calls produced by the model in a single delta.
    case functionCalls([CoCaptainAgentFunctionCall])
}

public struct CoCaptainParsedResponse: Hashable {
    /// The text before any structured payload or code blocks.
    public let preamble: String
    public let payload: CoCaptainAgentPayload?
    public let diagnostic: String?

    public init(preamble: String, payload: CoCaptainAgentPayload?, diagnostic: String? = nil) {
        self.preamble = preamble
        self.payload = payload
        self.diagnostic = diagnostic
    }

    /// Backwards compatibility or merged view
    public var visibleText: String {
        if preamble.isEmpty {
            return payload?.assistantMessage ?? ""
        }
        return preamble
    }
}

/// Tracks the lifecycle of a single `PendingReviewItem` as the user
/// approves, rejects, or encounters a conflict.
public enum ReviewItemStatus: String, Hashable, Codable {
    /// The item has not yet been acted upon by the user.
    case pending
    /// The user approved the item and it was applied to the store.
    case applied
    /// The item could not be applied cleanly — e.g. the action is no longer
    /// available in the current app context.
    case conflicted
    /// The user explicitly dismissed the item without applying it.
    case rejected

    /// The canonical definition used by review persistence, bulk decisions,
    /// badges, and pipeline state.
    public var isUnresolved: Bool {
        self == .pending
    }

    /// A short localized label suitable for display in the review chip.
    public var localizedTitle: String {
        switch self {
        case .pending:
            return LocalizationManager.shared.localizedString("Pending")
        case .applied:
            return LocalizationManager.shared.localizedString("Applied")
        case .conflicted:
            return LocalizationManager.shared.localizedString("Needs another try")
        case .rejected:
            return LocalizationManager.shared.localizedString("Rejected")
        }
    }
}

/// A confirmation record that appears in the timeline after the coordinator
/// has automatically executed one or more safe app actions.
public struct ExecutionStatusItem: Identifiable, Hashable, Codable {
    public let id: UUID
    /// A comma-joined, human-readable list of the action titles that were run.
    public let summary: String
    /// True when the action can be reversed through the active ProjectStore undo manager.
    public let allowsUndo: Bool

    public init(id: UUID = UUID(), summary: String, allowsUndo: Bool = false) {
        self.id = id
        self.summary = summary
        self.allowsUndo = allowsUndo
    }
}

/// An in-chat call-to-action card that nudges the user toward a specific app
/// action — for example, upgrading to a paid tier or enabling a feature.
public struct CoCaptainProductCTAItem: Identifiable, Hashable, Codable {
    public let id: UUID
    /// The bold headline displayed at the top of the CTA card.
    public let title: String
    /// Supporting copy explaining why the action is recommended.
    public let message: String
    /// Label of the primary action button.
    public let primaryButtonTitle: String
    /// The `AppActionID` that fires when the user taps the primary button.
    public let actionID: AppActionID

    public init(
        id: UUID = UUID(),
        title: String,
        message: String,
        primaryButtonTitle: String,
        actionID: AppActionID
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
        self.actionID = actionID
    }
}

/// Describes the origin of a `PendingReviewItem`, driving how the Review
/// Lifecycle resolves the item after an explicit user decision.
public enum PendingReviewSource: Hashable, Codable {
    /// An app-level action (e.g. navigate, open settings) waiting for approval.
    case appAction(AppActionID, [String: String]?)
    /// An action that could not be staged because its identifier is unknown or
    /// no matching action is available in the current app context.
    case unavailableAction(actionID: String, reason: String)
}

/// One actionable change within a `ReviewBundleItem`, representing a pending
/// app action that the user can approve or reject.
public struct PendingReviewItem: Identifiable, Hashable, Codable {
    public let id: UUID
    /// The node the change relates to, if applicable. Used to scroll the canvas
    /// to the relevant node when the review card is tapped.
    public let targetNodeID: UUID?
    /// A short display name for the target (usually the action title).
    public let targetLabel: String
    /// The model-authored description of what this change does.
    public let summary: String
    /// A short text snippet previewing the action.
    public let preview: String
    /// Optional before-window retained for legacy review cards.
    public let beforePreview: String?
    /// Current lifecycle state of this item.
    public var status: ReviewItemStatus
    /// How this item was produced and how it should be applied or rejected.
    public let source: PendingReviewSource
    /// Human-readable explanation of why this item entered the conflicted state.
    /// Nil when the item has not yet conflicted.
    public var conflictDescription: String?

    public init(
        id: UUID = UUID(),
        targetNodeID: UUID? = nil,
        targetLabel: String,
        summary: String,
        preview: String,
        beforePreview: String? = nil,
        status: ReviewItemStatus = .pending,
        source: PendingReviewSource,
        conflictDescription: String? = nil
    ) {
        self.id = id
        self.targetNodeID = targetNodeID
        self.targetLabel = targetLabel
        self.summary = summary
        self.preview = preview
        self.beforePreview = beforePreview
        self.status = status
        self.source = source
        self.conflictDescription = conflictDescription
    }
}

/// A named collection of `PendingReviewItem`s produced by a single agent turn.
///
/// The bundle appears as one timeline card with per-item Apply/Reject controls
/// and bulk Apply All / Reject All buttons.
public struct ReviewBundleItem: Identifiable, Hashable, Codable {
    public let id: UUID
    /// The heading shown at the top of the review card in the timeline.
    public let title: String
    /// The individual items within this bundle; mutable so the view model
    /// can update statuses in place without replacing the entire timeline entry.
    public var items: [PendingReviewItem]

    public init(
        id: UUID = UUID(),
        title: String = LocalizationManager.shared.localizedString("Pending changes"),
        items: [PendingReviewItem]
    ) {
        self.id = id
        self.title = title
        self.items = items
    }
}

/// A single chat message in the CoCaptain timeline, from either the user
/// or the assistant.
public enum CoCaptainMessageFeedback: String, Hashable, Codable {
    case helpful
    case notHelpful
}

/// One-shot request from a timeline action to restore a prior user message into
/// the composer for editing.
public struct CoCaptainComposerDraft: Identifiable, Hashable {
    public let id: UUID
    public let text: String
    public let mentions: [CoCaptainNodeMention]
    public let attachments: [CoCaptainAttachment]
    public let shouldFocus: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        mentions: [CoCaptainNodeMention],
        attachments: [CoCaptainAttachment],
        shouldFocus: Bool = true
    ) {
        self.id = id
        self.text = text
        self.mentions = mentions
        self.attachments = attachments
        self.shouldFocus = shouldFocus
    }
}

public struct ChatBubbleItem: Identifiable, Hashable, Codable {
    public let id: UUID
    /// The raw message text; mutable so streaming chunks can be appended
    /// to the last assistant bubble while the model is responding.
    public var text: String
    /// `true` when this bubble originates from the user, `false` for the assistant.
    public let isUser: Bool
    public let mentions: [CoCaptainNodeMention]
    public let attachments: [CoCaptainAttachment]
    /// The user message this assistant response belongs to.
    public let inReplyToMessageID: UUID?
    /// Captured on user messages so retries preserve the original execution posture.
    public let turnMode: CoCaptainChatMode?
    public let turnPurpose: CoCaptainTurnPurpose?
    /// Lightweight local feedback used to acknowledge the user's rating.
    public var feedback: CoCaptainMessageFeedback?

    public init(
        id: UUID = UUID(),
        text: String,
        isUser: Bool,
        mentions: [CoCaptainNodeMention] = [],
        attachments: [CoCaptainAttachment] = [],
        inReplyToMessageID: UUID? = nil,
        turnMode: CoCaptainChatMode? = nil,
        turnPurpose: CoCaptainTurnPurpose? = nil,
        feedback: CoCaptainMessageFeedback? = nil
    ) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.mentions = mentions
        self.attachments = attachments
        self.inReplyToMessageID = inReplyToMessageID
        self.turnMode = turnMode
        self.turnPurpose = turnPurpose
        self.feedback = feedback
    }

    /// The message rendered as an `AttributedString` with full markdown support.
    ///
    /// Attempts full markdown parsing first; if that fails (e.g. due to
    /// malformed input), falls back to inline-only syntax; and finally
    /// returns a plain-text `AttributedString` as a last resort so the
    /// UI never shows a blank bubble.
    public var markdownText: AttributedString {
        let source = isUser ? text : ChatBubbleMarkdownNormalizer.normalizeAssistantText(text)
        let fullOptions = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        if let attributed = try? AttributedString(markdown: source, options: fullOptions) {
            return attributed
        }

        let fallbackOptions = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: fallbackOptions)) ?? AttributedString(source)
    }
}

/// A timeline card presenting a clarifying question with tappable answer
/// options. Once answered, the chosen option is recorded so the card locks.
public struct CoCaptainClarifyingQuestionItem: Identifiable, Hashable, Codable {
    public let id: UUID
    public let question: CoCaptainClarifyingQuestion
    /// The option the user tapped, or `nil` while the question is open.
    public var answeredOption: String?

    public init(
        id: UUID = UUID(),
        question: CoCaptainClarifyingQuestion,
        answeredOption: String? = nil
    ) {
        self.id = id
        self.question = question
        self.answeredOption = answeredOption
    }
}

/// A timeline card revealing the lesson behind an applied edit.
///
/// Appears after the execution confirmation once the user taps Apply, so the
/// learning moment lands right when the change becomes real on the canvas.
public struct CoCaptainMentorNoteItem: Identifiable, Hashable, Codable {
    public let id: UUID
    public let note: CoCaptainLearningNote

    public init(id: UUID = UUID(), note: CoCaptainLearningNote) {
        self.id = id
        self.note = note
    }
}

/// The discriminated content carried by a single row in the CoCaptain
/// timeline, covering all visual card types the UI can render.
/// A recoverable failure or user-stopped turn rendered separately from assistant prose.
public struct CoCaptainErrorItem: Identifiable, Hashable, Codable {
    public enum Kind: String, Hashable, Codable {
        case model
        case network
        case attachment
        case quota
        case stopped
    }

    public let id: UUID
    public let kind: Kind
    public let title: String
    public let message: String
    public let technicalDetails: String?
    public let sourceMessageID: UUID?
    public let isRecoverable: Bool

    public init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        message: String,
        technicalDetails: String? = nil,
        sourceMessageID: UUID? = nil,
        isRecoverable: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.technicalDetails = technicalDetails
        self.sourceMessageID = sourceMessageID
        self.isRecoverable = isRecoverable
    }
}

public enum CoCaptainTimelineContent: Hashable, Codable {
    /// A user or assistant chat bubble.
    case message(ChatBubbleItem)
    /// A confirmation banner summarising auto-executed safe actions.
    case execution(ExecutionStatusItem)
    /// An in-chat upsell or feature nudge card.
    case productCTA(CoCaptainProductCTAItem)
    /// A set of proposed changes awaiting user review.
    case reviewBundle(ReviewBundleItem)
    /// A polite question with tappable answer options.
    case clarifyingQuestion(CoCaptainClarifyingQuestionItem)
    /// A "What you just learned" card revealed after an edit is applied.
    case mentorNote(CoCaptainMentorNoteItem)
    /// A typed failure or stopped-turn notice with an optional retry action.
    case error(CoCaptainErrorItem)
}

/// One identifiable row in the CoCaptain conversation timeline.
///
/// The `content` is mutable so the view model can patch streaming text or
/// update review-item statuses without rebuilding the whole list.
public struct CoCaptainTimelineItem: Identifiable, Hashable, Codable {
    public let id: UUID
    public var content: CoCaptainTimelineContent
    public let createdAt: Date

    public init(id: UUID = UUID(), content: CoCaptainTimelineContent, createdAt: Date = Date()) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
    }
}

extension AttributedString {
    /// Convenience initialiser that creates a plain `AttributedString` from a
    /// `String` without requiring an explicit `stringLiteral:` label, matching
    /// the ergonomics of `String` init used in fallback paths.
    init(_ text: String) {
        self = AttributedString(stringLiteral: text)
    }
}
