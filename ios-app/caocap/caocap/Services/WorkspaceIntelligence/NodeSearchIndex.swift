import Foundation
import CoreGraphics

/// Represents a node found during a spatial search.
public struct NodeSearchResult: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let snippet: String
    public let role: NodeRole
    public let position: CGPoint
    public let relevanceScore: Int
}

/// A pure service for indexing and searching project nodes.
public struct NodeSearchIndex {
    public init() {}

    /// Searches the provided nodes for the given query and returns ranked results.
    public func search(query: String, in nodes: [SpatialNode]) -> [NodeSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        return nodes
            .compactMap { node -> NodeSearchResult? in
                var score = 0
                let titleLower = node.title.lowercased()
                let miniAppContent = [
                    node.miniApp?.srsText,
                    node.miniApp?.codeText
                ]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                let contentLower = miniAppContent.lowercased()
                let roleLower = node.role.displayName.lowercased()
                let typeLower = node.type.displayName.lowercased()
                let subtitleLower = (node.subtitle ?? "").lowercased()

                if titleLower == trimmed {
                    score += 100
                } else if titleLower.hasPrefix(trimmed) {
                    score += 60
                } else if titleLower.contains(trimmed) {
                    score += 30
                }

                if roleLower == trimmed || typeLower == trimmed {
                    score += 50
                } else if roleLower.contains(trimmed) || typeLower.contains(trimmed) {
                    score += 25
                }

                if subtitleLower.contains(trimmed) {
                    score += 15
                }

                if contentLower.contains(trimmed) {
                    score += 10
                }

                guard score > 0 else { return nil }

                let snippet = (!miniAppContent.isEmpty ? miniAppContent : nil).flatMap {
                    $0.isEmpty ? nil : String($0.prefix(60).replacingOccurrences(of: "\n", with: " "))
                } ?? node.subtitle ?? ""

                return NodeSearchResult(
                    id: node.id,
                    title: node.title,
                    snippet: snippet,
                    role: node.role,
                    position: node.position,
                    relevanceScore: score
                )
            }
            .sorted { $0.relevanceScore > $1.relevanceScore }
    }
}
