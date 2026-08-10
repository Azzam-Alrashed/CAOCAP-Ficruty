import Foundation

/// Serializes the current canvas state into a structured plain-text block
/// suitable for injection into the LLM prompt context.
///
/// Both methods produce a snapshot of the project's node graph; the
/// node-scoped variant additionally highlights the selected node and its
/// immediate neighbors so the agent can reason more precisely about a
/// single Mini-App without losing awareness of the broader canvas.
public struct ProjectContextBuilder {
    /// Controls how much implementation detail is included in canvas context.
    public enum DetailLevel: Hashable {
        /// Full Mini-App source for edit turns.
        case implementation
        /// SRS/code summaries without large implementation payloads.
        case product
    }

    /// Characters of code/SRS shown for a slimmed (non-selected) Mini-App when
    /// the model can fetch full text on demand via `read_node_section`.
    private static let slimSectionHeadChars = 400

    /// When `true`, non-selected Mini-Apps get a short section head plus size
    /// stats instead of a large budget, because the model can read full text
    /// through the `read_node_section` tool. CAOCAP keeps LiteRT-LM tool
    /// calling disabled in the first release, so it retains the full budgets.
    private let usesOnDemandCodeReads: Bool

    public init(usesOnDemandCodeReads: Bool = true) {
        self.usesOnDemandCodeReads = usesOnDemandCodeReads
    }

    /// Builds a full-project context string from every node on the canvas.
    ///
    /// The returned string includes a node inventory listing and per-Mini-App
    /// SRS + code sections (with character budgets).
    @MainActor
    public func buildPromptContext(
        from store: ProjectStore,
        detailLevel: DetailLevel = .implementation
    ) -> String {
        let miniApps = store.nodes.filter { $0.type == .miniApp }
        let inventory = nodeInventory(store.nodes)
        let miniAppSections = miniApps.map { miniAppContext(for: $0, selected: false, detailLevel: detailLevel) }

        return [
            "Project Name: \(store.projectName)",
            "Workspace ID: \(store.fileName)",
            "Node Count: \(store.nodes.count)",
            "Mini-App Count: \(miniApps.count)",
            "Node Graph:\n\(inventory)",
            miniAppSections.isEmpty ? nil : "Mini-Apps:\n\n" + miniAppSections.joined(separator: "\n\n---\n\n")
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    /// Builds a node-scoped context string that emphasises a specific node.
    ///
    /// The selected node is rendered with expanded character budgets (3 000 for
    /// SRS, 6 000 for code) while linked neighbors are shown at a reduced budget
    /// to stay within prompt limits. Falls back to the full-project context if
    /// the requested `nodeID` is not found.
    @MainActor
    public func buildNodePromptContext(
        from store: ProjectStore,
        nodeID: UUID,
        detailLevel: DetailLevel = .implementation
    ) -> String {
        guard let selectedNode = store.nodes.first(where: { $0.id == nodeID }) else {
            return buildPromptContext(from: store, detailLevel: detailLevel)
        }

        let linkedNodes = linkedNeighbors(of: selectedNode, in: store.nodes)
        let linkedSections = linkedNodes.map { miniAppContext(for: $0, selected: false, detailLevel: detailLevel) }

        return [
            "Project Name: \(store.projectName)",
            "Workspace ID: \(store.fileName)",
            "Node Agent Scope: \(selectedNode.title)",
            selectedNode.agentProfile.systemPrompt.map { "Agent System Prompt:\n\($0)" },
            "Selected Node ID: \(selectedNode.id.uuidString)",
            "Selected Node Type: \(selectedNode.type.rawValue)",
            "Selected Node Role: \(selectedNode.role.rawValue)",
            selectedNode.agentState.memorySummary.map { "Node Agent Memory:\n\($0)" },
            "Selected Node Context:\n\(miniAppContext(for: selectedNode, selected: true, detailLevel: detailLevel))",
            linkedSections.isEmpty ? nil : "Linked Neighbor Nodes:\n\n\(linkedSections.joined(separator: "\n\n"))",
            "Project Inventory:\n\(nodeInventory(store.nodes))"
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    /// A one-liner inventory of all canvas nodes showing title, type, ID, and
    /// number of outgoing and incoming connections.
    private func nodeInventory(_ nodes: [SpatialNode]) -> String {
        nodes.map { node in
            let linkCount = (node.connectedNodeIds?.count ?? 0) + (node.nextNodeId == nil ? 0 : 1)
            return "- \(node.title) [\(node.type.rawValue)] id: \(node.id.uuidString) links: \(linkCount)"
        }.joined(separator: "\n")
    }

    /// Renders a context block for a single node.
    ///
    /// `selected` controls the character budget: the focused node gets a larger
    /// window so the agent can read its full SRS and enough code to reason about
    /// it, while neighbor nodes are capped to a brief summary to save prompt space.
    private func miniAppContext(
        for node: SpatialNode,
        selected: Bool,
        detailLevel: DetailLevel
    ) -> String {
        _ = detailLevel
        guard node.type == .miniApp, let miniApp = node.miniApp else {
            if node.type == .subCanvas {
                return "- \(node.title) [subCanvas] links to file: \(node.linkedCanvasFileName ?? "[None]")"
            }
            return "- \(node.title) [\(node.type.rawValue)]"
        }

        // Slim, non-selected Mini-Apps show a short head plus size stats;
        // the model reads full text on demand with `read_node_section`.
        let slim = usesOnDemandCodeReads && !selected
        let srsLimit = selected ? 3_000 : (slim ? Self.slimSectionHeadChars : 1_000)
        let codeLimit = selected ? 6_000 : (slim ? Self.slimSectionHeadChars : 1_600)

        let codeBlock = slim
            ? Self.sectionSummary(miniApp.codeText, limit: codeLimit)
            : Self.trimmed(miniApp.codeText, limit: codeLimit)
        let srsBlock = slim
            ? Self.sectionSummary(miniApp.srsText, limit: srsLimit)
            : Self.trimmed(miniApp.srsText, limit: srsLimit)

        return """
        - \(node.title) [miniApp] id: \(node.id.uuidString)
          SRS Readiness: \(miniApp.srsReadinessState.contextLabel)
          SRS:
        \(Self.indent(srsBlock, spaces: 4))

          Code:
        \(Self.indent(codeBlock, spaces: 4))
        """
    }

    /// A short head of a section plus its total size, used for slim entries.
    /// The trailing note tells the model how to fetch the full text.
    private static func sectionSummary(_ text: String, limit: Int) -> String {
        let lineCount = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
        let stats = "(\(lineCount) lines, \(text.count) characters total)"
        guard text.count > limit else {
            return text.isEmpty ? "(empty)" : "\(text)\n\(stats)"
        }
        return String(text.prefix(limit))
            + "\n[TRUNCATED — call read_node_section for the full text]\n\(stats)"
    }

    /// Collects all nodes that are directly linked to `selectedNode` in either
    /// direction — outgoing (`nextNodeId`, `connectedNodeIds`) and incoming (any
    /// node whose links point at `selectedNode`'s ID).
    private func linkedNeighbors(of selectedNode: SpatialNode, in nodes: [SpatialNode]) -> [SpatialNode] {
        var ids = Set<UUID>()
        if let nextNodeId = selectedNode.nextNodeId {
            ids.insert(nextNodeId)
        }
        for id in selectedNode.connectedNodeIds ?? [] {
            ids.insert(id)
        }
        for node in nodes where node.nextNodeId == selectedNode.id || node.connectedNodeIds?.contains(selectedNode.id) == true {
            ids.insert(node.id)
        }
        return nodes.filter { ids.contains($0.id) }
    }

    private static func trimmed(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n[TRUNCATED]"
    }

    private static func indent(_ text: String, spaces: Int) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + String($0) }
            .joined(separator: "\n")
    }
}
