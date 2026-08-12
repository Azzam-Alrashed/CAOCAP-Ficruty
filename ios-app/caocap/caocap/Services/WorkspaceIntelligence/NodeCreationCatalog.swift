import Foundation

/// A creatable node type surfaced in the Omnibox when the user searches.
public struct NodeCreationOption: Identifiable, Equatable {
    public let id: NodeType
    public let title: String
    public let icon: String
    public let keywords: [String]

    public init(id: NodeType, title: String, icon: String, keywords: [String]) {
        self.id = id
        self.title = title
        self.icon = icon
        self.keywords = keywords
    }
}

/// Searchable catalog of node types the user can create from the command palette.
public struct NodeCreationCatalog {
    public static let options: [NodeCreationOption] = [
        NodeCreationOption(
            id: .miniApp,
            title: "Create Mini-App",
            icon: NodeType.miniApp.defaultIcon,
            keywords: ["mini-app", "mini app", "app", "preview", "code"]
        ),
        NodeCreationOption(
            id: .subCanvas,
            title: "Create Sub-Canvas",
            icon: "folder.fill",
            keywords: ["sub-canvas", "sub canvas", "nested", "workspace"]
        )
    ]

    public init() {}

    public func search(query: String) -> [NodeCreationOption] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        return Self.options.compactMap { option in
            var score = 0
            let titleLower = option.title.lowercased()

            if titleLower.contains(trimmed) {
                score += 40
            }
            if option.id.displayName.lowercased().contains(trimmed) {
                score += 30
            }
            if option.keywords.contains(where: { Self.keyword($0, matches: trimmed) }) {
                score += 20
            }

            return score > 0 ? option : nil
        }
    }

    private static func keyword(_ keyword: String, matches query: String) -> Bool {
        if keyword == query { return true }
        return keyword
            .split(separator: " ")
            .map(String.init)
            .contains(query)
    }
}
