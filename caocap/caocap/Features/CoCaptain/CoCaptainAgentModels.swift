import Foundation

public struct CoCaptainAgentAction: Codable, Hashable {
    public let actionID: String
    public let args: [String: String]?

    public init(actionID: String, args: [String: String]? = nil) {
        self.actionID = actionID
        self.args = args
    }

    private enum CodingKeys: String, CodingKey {
        case actionID = "actionId"
        case args
    }
}

public struct CoCaptainNodeEditProposal: Codable, Hashable {
    public let role: NodeRole
    public let summary: String
    public let operations: [NodePatchOperation]

    public init(role: NodeRole, summary: String, operations: [NodePatchOperation]) {
        self.role = role
        self.summary = summary
        self.operations = operations
    }
}

public struct CoCaptainAgentPayload: Codable, Hashable {
    public let assistantMessage: String
    public let safeActions: [CoCaptainAgentAction]
    public let pendingActions: [CoCaptainAgentAction]
    public let nodeEdits: [CoCaptainNodeEditProposal]

    public init(
        assistantMessage: String,
        safeActions: [CoCaptainAgentAction] = [],
        pendingActions: [CoCaptainAgentAction] = [],
        nodeEdits: [CoCaptainNodeEditProposal] = []
    ) {
        self.assistantMessage = assistantMessage
        self.safeActions = safeActions
        self.pendingActions = pendingActions
        self.nodeEdits = nodeEdits
    }
}

public struct CoCaptainParsedResponse: Hashable {
    public let visibleText: String
    public let payload: CoCaptainAgentPayload?

    public init(visibleText: String, payload: CoCaptainAgentPayload?) {
        self.visibleText = visibleText
        self.payload = payload
    }
}

public enum ReviewItemStatus: String, Hashable {
    case pending
    case applied
    case conflicted
    case rejected
}

public struct ExecutionStatusItem: Identifiable, Hashable {
    public let id: UUID
    public let summary: String

    public init(id: UUID = UUID(), summary: String) {
        self.id = id
        self.summary = summary
    }
}

public enum PendingReviewSource: Hashable {
    case appAction(AppActionID)
    case nodeEdit(role: NodeRole, operations: [NodePatchOperation], baseText: String)
}

public struct PendingReviewItem: Identifiable, Hashable {
    public let id: UUID
    public let targetLabel: String
    public let summary: String
    public let preview: String
    public var status: ReviewItemStatus
    public let source: PendingReviewSource

    public init(
        id: UUID = UUID(),
        targetLabel: String,
        summary: String,
        preview: String,
        status: ReviewItemStatus = .pending,
        source: PendingReviewSource
    ) {
        self.id = id
        self.targetLabel = targetLabel
        self.summary = summary
        self.preview = preview
        self.status = status
        self.source = source
    }
}

public struct ReviewBundleItem: Identifiable, Hashable {
    public let id: UUID
    public let title: String
    public var items: [PendingReviewItem]

    public init(id: UUID = UUID(), title: String = "Pending changes", items: [PendingReviewItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public struct ChatBubbleItem: Identifiable, Hashable {
    public let id: UUID
    public var text: String
    public let isUser: Bool

    public init(id: UUID = UUID(), text: String, isUser: Bool) {
        self.id = id
        self.text = text
        self.isUser = isUser
    }

    public var attributedText: AttributedString {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        } else {
            return AttributedString(text)
        }
    }
}

public enum CoCaptainTimelineContent: Hashable {
    case message(ChatBubbleItem)
    case execution(ExecutionStatusItem)
    case reviewBundle(ReviewBundleItem)
}

public struct CoCaptainTimelineItem: Identifiable, Hashable {
    public let id: UUID
    public var content: CoCaptainTimelineContent

    public init(id: UUID = UUID(), content: CoCaptainTimelineContent) {
        self.id = id
        self.content = content
    }
}

extension AttributedString {
    init(_ text: String) {
        self = AttributedString(stringLiteral: text)
    }
}
