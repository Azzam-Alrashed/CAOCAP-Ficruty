import Foundation

/// Generic assistant suggestion presentation model retained for non-node guidance.
public struct ProjectSuggestion: Identifiable, Equatable {
    public enum Severity { case info, warning }

    public let id: UUID
    public let title: String
    public let detail: String
    public let suggestedPrompt: String
    public let severity: Severity

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        suggestedPrompt: String,
        severity: Severity = .info
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.suggestedPrompt = suggestedPrompt
        self.severity = severity
    }
}
