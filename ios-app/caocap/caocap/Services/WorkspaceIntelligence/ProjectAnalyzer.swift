import Foundation

/// Represents a potential improvement or action identified by analyzing the project nodes.
public struct ProjectSuggestion: Identifiable, Equatable {
    public let id: UUID
    /// Short title for the suggestion.
    public let title: String
    /// More detailed explanation for the user.
    public let detail: String
    /// The prompt that will be sent to CoCaptain if the user applies this suggestion.
    public let suggestedPrompt: String
    public let severity: Severity

    /// The urgency or impact level of the suggestion.
    public enum Severity {
        case info
        case warning
    }

    public init(id: UUID = UUID(), title: String, detail: String, suggestedPrompt: String, severity: Severity = .info) {
        self.id = id
        self.title = title
        self.detail = detail
        self.suggestedPrompt = suggestedPrompt
        self.severity = severity
    }
}

/// A pure service that inspects the current node graph and surfaces structural recommendations.
public struct ProjectAnalyzer {
    public init() {}

    /// Analyzes the given nodes and returns a list of actionable suggestions.
    public func analyze(nodes: [SpatialNode]) -> [ProjectSuggestion] {
        var suggestions: [ProjectSuggestion] = []

        let miniApps = nodes.filter { $0.type == .miniApp }
        let connectedNodeIDs = Set(
            nodes.flatMap { node -> [UUID] in
                var ids = node.connectedNodeIds ?? []
                if let next = node.nextNodeId { ids.append(next) }
                return ids
            }
        )

        for miniAppNode in miniApps {
            let codeText = miniAppNode.miniApp?.codeText ?? ""
            let isCodeEmpty = codeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if isCodeEmpty {
                suggestions.append(ProjectSuggestion(
                    title: "\(miniAppNode.title) code is empty",
                    detail: "CoCaptain can generate a starter app for this Mini-App.",
                    suggestedPrompt: "Generate a starter single-file HTML/CSS/JS app for \(miniAppNode.title).",
                    severity: .warning
                ))
            } else if !codeText.lowercased().contains("<html") {
                suggestions.append(ProjectSuggestion(
                    title: "\(miniAppNode.title) code may be incomplete",
                    detail: "Mini-App code usually starts with a full HTML document. CoCaptain can rebuild it as a single file.",
                    suggestedPrompt: "Rebuild \(miniAppNode.title) as a complete single-file HTML Mini-App.",
                    severity: .warning
                ))
            }

            if !connectedNodeIDs.contains(miniAppNode.id), miniApps.count > 1 {
                suggestions.append(ProjectSuggestion(
                    title: "\(miniAppNode.title) is isolated",
                    detail: "Link this Mini-App to related nodes so CoCaptain can use neighbor context during edits.",
                    suggestedPrompt: "Suggest how \(miniAppNode.title) should connect to the other Mini-Apps on this canvas.",
                    severity: .info
                ))
            }

            if CoCaptainReviewLifecycle.hasUnresolvedPersistedRecords(
                in: miniAppNode.agentState
            ) {
                suggestions.append(ProjectSuggestion(
                    title: "\(miniAppNode.title) has pending CoCaptain reviews",
                    detail: "Open this node's CoCaptain panel to approve or reject staged changes.",
                    suggestedPrompt: "Summarize the pending review items for \(miniAppNode.title).",
                    severity: .warning
                ))
            }
        }

        return suggestions
    }
}
