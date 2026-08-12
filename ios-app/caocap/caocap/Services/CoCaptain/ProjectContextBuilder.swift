import Foundation

/// Serializes the current canvas graph into a structured plain-text block
/// suitable for injection into the LLM prompt context.
///
/// Both methods produce a snapshot of the project's node graph; the
/// node-scoped variant additionally highlights the selected node and its
/// immediate neighbors so the agent can reason about graph operations.
public struct ProjectContextBuilder {
    /// Controls how verbose node detail is in canvas context.
    public enum DetailLevel: Hashable {
        /// Include position and link IDs for edit/layout turns.
        case implementation
        /// Titles/types/roles only.
        case product
    }

    public init(usesOnDemandCodeReads: Bool = false) {
        // Parameter retained for call-site compatibility; code reads are retired.
        _ = usesOnDemandCodeReads
    }

    /// Builds a full-project context string from every node on the canvas.
    @MainActor
    public func buildPromptContext(
        from store: ProjectStore,
        detailLevel: DetailLevel = .implementation
    ) -> String {
        let inventory = nodeInventory(store.nodes, detailLevel: detailLevel)

        return [
            "Project Name: \(store.projectName)",
            "Workspace ID: \(store.fileName)",
            "Node Count: \(store.nodes.count)",
            "Node Graph:\n\(inventory)"
        ]
        .joined(separator: "\n\n")
    }

    /// Builds a node-scoped context string that emphasises a specific node.
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
        let linkedSections = linkedNodes.map {
            nodeDetail(for: $0, detailLevel: detailLevel)
        }

        return [
            "Project Name: \(store.projectName)",
            "Workspace ID: \(store.fileName)",
            "Node Agent Scope: \(selectedNode.title)",
            selectedNode.agentProfile.systemPrompt.map { "Agent System Prompt:\n\($0)" },
            "Selected Node ID: \(selectedNode.id.uuidString)",
            "Selected Node Type: \(selectedNode.type.rawValue)",
            "Selected Node Role: \(selectedNode.role.rawValue)",
            selectedNode.agentState.memorySummary.map { "Node Agent Memory:\n\($0)" },
            "Selected Node Context:\n\(nodeDetail(for: selectedNode, detailLevel: detailLevel))",
            linkedSections.isEmpty ? nil : "Linked Neighbor Nodes:\n\n\(linkedSections.joined(separator: "\n\n"))",
            "Project Inventory:\n\(nodeInventory(store.nodes, detailLevel: .product))"
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    private func nodeInventory(_ nodes: [SpatialNode], detailLevel: DetailLevel) -> String {
        nodes.map { nodeDetail(for: $0, detailLevel: detailLevel) }.joined(separator: "\n")
    }

    private func nodeDetail(for node: SpatialNode, detailLevel: DetailLevel) -> String {
        let linkCount = (node.connectedNodeIds?.count ?? 0) + (node.nextNodeId == nil ? 0 : 1)
        var lines = [
            "- \(node.title) [\(node.type.rawValue)] id: \(node.id.uuidString) role: \(node.role.rawValue) links: \(linkCount)"
        ]

        if let subtitle = node.subtitle, !subtitle.isEmpty {
            lines.append("  subtitle: \(subtitle)")
        }
        if let icon = node.icon, !icon.isEmpty {
            lines.append("  icon: \(icon)")
        }

        if detailLevel == .implementation {
            lines.append(
                "  position: (\(Int(node.position.x)), \(Int(node.position.y))) theme: \(node.theme.rawValue)"
            )
            if let next = node.nextNodeId {
                lines.append("  next: \(next.uuidString)")
            }
            if let connected = node.connectedNodeIds, !connected.isEmpty {
                lines.append("  connected: \(connected.map(\.uuidString).joined(separator: ", "))")
            }
            if node.type == .subCanvas {
                lines.append("  linkedCanvas: \(node.linkedCanvasFileName ?? "[None]")")
            }
        }

        return lines.joined(separator: "\n")
    }

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
}
