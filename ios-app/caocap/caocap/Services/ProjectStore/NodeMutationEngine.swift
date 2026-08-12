import Foundation
import SwiftUI
import os

/// Edge kind for connect/disconnect mutations.
public enum NodeConnectionKind: String {
    /// Sequential `nextNodeId` pointer.
    case next
    /// Bidirectional-friendly `connectedNodeIds` membership.
    case connected
}

/// Performs all mutable node operations on behalf of `ProjectStore`.
///
/// `NodeMutationEngine` is deliberately decoupled from `ProjectStore` so its
/// mutation logic can be tested in isolation. Side effects (saving,
/// triggering downstream agents) are routed back to the store
/// through a set of closure callbacks that are wired up once during initialisation.
///
/// All methods are `@MainActor`-isolated because they mutate `inout [SpatialNode]`
/// arrays that are observed by SwiftUI.
@Observable
@MainActor
final class NodeMutationEngine {
    /// The undo manager injected by the view layer; `nil` when no responder chain undo is available.
    var undoManager: UndoManager?
    /// Incremented whenever an undo entry is registered, allowing views to invalidate undo/redo state.
    var undoStackChanged: Int = 0
    private let logger = Logger(subsystem: "com.caocap.App", category: "NodeMutationEngine")
    
    // MARK: - Side-effect callbacks (wired by ProjectStore)

    /// Called when the mutation should trigger a project save. The `Bool` indicates
    /// whether the saving indicator should be shown to the user.
    var onRequestSave: ((Bool) -> Void)?
    /// Called when an upstream node's code changes and connected downstream
    /// nodes with auto-trigger enabled should be notified.
    var onTriggerDownstreamAgents: ((UUID, [SpatialNode]) -> Void)?
    /// Returns the current canvas viewport offset so newly created nodes can be
    /// placed at the visible centre rather than at the canvas origin.
    var onViewportChange: (() -> CGSize)?
    /// Executes a node-array mutation closure and then persists the result.
    /// Used by undo closures to apply inverse mutations through `ProjectStore`
    /// rather than holding a direct reference back to it.
    var onPerformUndoMutation: (( @escaping (inout [SpatialNode]) -> Void ) -> Void)?
    
    /// Changes a node's fundamental type and initialises type-specific state.
    ///
    /// Switching to `.miniApp` bootstraps a `MiniAppState` with default code text.
    /// Switching to `.subCanvas` generates a new canvas file name if one doesn't exist yet.
    /// Switching to `.standard` clears any `MiniAppState` from the node.
    public func updateNodeType(nodes: inout [SpatialNode], id: UUID, type: NodeType, persist: Bool = true) {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            let oldType = nodes[index].type
            
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.onPerformUndoMutation? { currentNodes in
                        target.updateNodeType(nodes: &currentNodes, id: id, type: oldType, persist: persist)
                    }
                }
            }
            undoStackChanged += 1
            
            nodes[index].type = type
            nodes[index].theme = nodeTheme(for: type)
            nodes[index].icon = nodeIcon(for: type)
            
            switch type {
            case .miniApp:
                nodes[index].miniApp = nodes[index].miniApp ?? MiniAppState(
                    codeText: ProjectTemplateProvider.defaultCode
                )
            case .standard:
                nodes[index].miniApp = nil
            case .subCanvas:
                nodes[index].miniApp = nil
                if nodes[index].linkedCanvasFileName == nil {
                    nodes[index].linkedCanvasFileName = CanvasFileNaming.newCanvasFileName()
                }
            }
            
            if persist {
                onRequestSave?(true)
            }
        }
    }
    
    /// Convenience alias that forwards to `updateMiniAppCode`.
    /// Exists so callers can treat any node as having generic text content.
    public func updateNodeTextContent(nodes: inout [SpatialNode], id: UUID, text: String, persist: Bool = true) {
        updateMiniAppCode(nodes: &nodes, id: id, text: text, persist: persist)
    }

    /// Replaces the source text of a Mini-App node and notifies downstream agents.
    public func updateMiniAppCode(nodes: inout [SpatialNode], id: UUID, text: String, persist: Bool = true) {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            ensureMiniAppState(for: &nodes[index])
            let oldText = nodes[index].miniApp?.codeText ?? ""

            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.onPerformUndoMutation? { currentNodes in
                        target.updateMiniAppCode(nodes: &currentNodes, id: id, text: oldText, persist: persist)
                    }
                }
            }
            undoStackChanged += 1

            nodes[index].miniApp?.codeText = text

            if persist {
                onRequestSave?(true)
            }
            onTriggerDownstreamAgents?(id, nodes)
        }
    }

    /// Replaces the agent execution state of a node (e.g. `.thinking`, `.idle`).
    /// Does not register an undo entry — agent state is considered transient.
    public func updateNodeAgentState(nodes: inout [SpatialNode], id: UUID, agentState: NodeAgentState, persist: Bool = true) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[index].agentState = agentState
        if persist {
            onRequestSave?(true)
        }
    }

    /// Appends a single agent message to the node's conversation history.
    public func appendNodeAgentMessage(nodes: inout [SpatialNode], id: UUID, message: NodeAgentMessage, persist: Bool = true) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[index].agentState.messages.append(message)
        if persist {
            onRequestSave?(true)
        }
    }

    /// Clears all agent messages from a node's session. Review persistence is
    /// owned and cleared separately by `CoCaptainReviewLifecycle`.
    public func clearNodeAgentMessages(nodes: inout [SpatialNode], id: UUID, persist: Bool = true) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[index].agentState.messages = []
        if persist {
            onRequestSave?(true)
        }
    }
    
    /// Applies a batch of position updates in one undo-registered operation.
    /// The undo closure restores all previous positions simultaneously, which
    /// prevents partial-revert artifacts when multiple nodes are moved together.
    public func updateNodePositions(nodes: inout [SpatialNode], _ positions: [UUID: CGPoint], animated: Bool = true) {
        let oldPositions = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
        
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.onPerformUndoMutation? { currentNodes in
                    target.updateNodePositions(nodes: &currentNodes, oldPositions, animated: animated)
                }
            }
        }
        undoStackChanged += 1
        
        let applyPositions: (inout [SpatialNode]) -> Void = { n in
            for (id, pos) in positions {
                if let index = n.firstIndex(where: { $0.id == id }) {
                    n[index].position = pos
                }
            }
        }
        
        if animated {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                applyPositions(&nodes)
            }
        } else {
            applyPositions(&nodes)
        }
        
        onRequestSave?(true)
    }
    
    /// Lays out all nodes using `NodeLayoutOrganizer` and triggers a haptic
    /// success notification when complete.
    public func organizeNodes(nodes: inout [SpatialNode]) {
        guard !nodes.isEmpty else { return }
        
        let organizer = NodeLayoutOrganizer()
        let nodePositions = organizer.organize(nodes: nodes)
        
        updateNodePositions(nodes: &nodes, nodePositions, animated: true)
        HapticsManager.shared.notification(.success)
    }
    
    /// Creates a new node of the given type and appends it to the canvas.
    /// The new node is placed at the current viewport centre (or `position` when
    /// provided), given a unique title, and type-specific state is bootstrapped.
    public func addNode(
        nodes: inout [SpatialNode],
        type: NodeType = .miniApp,
        title: String? = nil,
        position: CGPoint? = nil
    ) {
        let baseTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let uniqueTitle = generateUniqueTitle(
            nodes: nodes,
            base: (baseTitle?.isEmpty == false) ? baseTitle! : type.defaultTitle
        )

        let subtitle = type.defaultSubtitle
        let linkedFileName: String? = type == .subCanvas ? CanvasFileNaming.newCanvasFileName() : nil
        let miniApp = type == .miniApp ? MiniAppState(
            codeText: ProjectTemplateProvider.defaultCode
        ) : nil
        let offset = onViewportChange?() ?? .zero
        let resolvedPosition = position ?? CGPoint(x: -offset.width, y: -offset.height)

        let newNode = SpatialNode(
            id: UUID(),
            type: type,
            position: resolvedPosition,
            title: uniqueTitle,
            subtitle: subtitle,
            icon: nodeIcon(for: type),
            theme: nodeTheme(for: type),
            miniApp: miniApp,
            linkedCanvasFileName: linkedFileName
        )
        
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.onPerformUndoMutation? { currentNodes in
                    target.deleteNode(nodes: &currentNodes, id: newNode.id, persist: true)
                }
            }
        }
        undoStackChanged += 1

        withAnimation(.spring()) {
            nodes.append(newNode)
        }
        onRequestSave?(true)
    }

    public func nodeIcon(for type: NodeType) -> String {
        type.defaultIcon
    }

    public func nodeTheme(for type: NodeType) -> NodeTheme {
        type.defaultTheme
    }

    /// Returns a title derived from `base` that is not already used by another node.
    /// If `base` is taken it tries "base 1", "base 2", etc. Case-insensitive.
    public func generateUniqueTitle(nodes: [SpatialNode], base: String) -> String {
        var candidate = base
        var count = 1
        if nodes.contains(where: { $0.title.lowercased() == candidate.lowercased() }) {
            while nodes.contains(where: { $0.title.lowercased() == "\(base) \(count)".lowercased() }) {
                count += 1
            }
            candidate = "\(base) \(count)"
        }
        return candidate
    }

    /// Renames a node, silently discarding the rename when the title is blank
    /// or is already used by a different node (case-insensitive).
    public func updateNodeTitle(nodes: inout [SpatialNode], id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Prevent duplicate titles across the canvas.
        if nodes.contains(where: { $0.id != id && $0.title.lowercased() == trimmed.lowercased() }) {
            return 
        }
        
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            nodes[index].title = trimmed
            onRequestSave?(true)
        }
    }

    /// Updates a node's subtitle, coercing an empty or whitespace-only string to `nil`.
    public func updateNodeSubtitle(nodes: inout [SpatialNode], id: UUID, subtitle: String?) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        nodes[index].subtitle = trimmed?.isEmpty == true ? nil : trimmed
        onRequestSave?(true)
    }

    /// Updates a node's SF Symbol icon name, coercing an empty or whitespace-only string to `nil`.
    public func updateNodeIcon(nodes: inout [SpatialNode], id: UUID, icon: String?) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = icon?.trimmingCharacters(in: .whitespacesAndNewlines)
        nodes[index].icon = trimmed?.isEmpty == true ? nil : trimmed
        onRequestSave?(true)
    }

    /// Links `fromID` → `toID` using `kind` (defaults to `.next`).
    public func connectNodes(
        nodes: inout [SpatialNode],
        fromID: UUID,
        toID: UUID,
        kind: NodeConnectionKind = .next
    ) {
        guard fromID != toID,
              nodes.contains(where: { $0.id == fromID }),
              nodes.contains(where: { $0.id == toID }),
              let index = nodes.firstIndex(where: { $0.id == fromID }) else { return }

        switch kind {
        case .next:
            nodes[index].nextNodeId = toID
        case .connected:
            var connections = nodes[index].connectedNodeIds ?? []
            if !connections.contains(toID) {
                connections.append(toID)
            }
            nodes[index].connectedNodeIds = connections
        }
        onRequestSave?(true)
    }

    /// Removes a link from `fromID` to `toID`. When `kind` is nil, clears both
    /// `next` and `connected` relationships for that pair.
    public func disconnectNodes(
        nodes: inout [SpatialNode],
        fromID: UUID,
        toID: UUID,
        kind: NodeConnectionKind? = nil
    ) {
        guard let index = nodes.firstIndex(where: { $0.id == fromID }) else { return }
        let clearNext = kind == nil || kind == .next
        let clearConnected = kind == nil || kind == .connected

        if clearNext, nodes[index].nextNodeId == toID {
            nodes[index].nextNodeId = nil
        }
        if clearConnected, let connections = nodes[index].connectedNodeIds {
            nodes[index].connectedNodeIds = connections.filter { $0 != toID }
            if nodes[index].connectedNodeIds?.isEmpty == true {
                nodes[index].connectedNodeIds = nil
            }
        }
        onRequestSave?(true)
    }
    
    /// Removes a node from the canvas and cleans up all references to it in other
    /// nodes' `nextNodeId` and `connectedNodeIds` fields.
    ///
    /// The undo operation restores the full pre-deletion node array rather than
    /// re-inserting at the original index, which is simpler and avoids index drift.
    public func deleteNode(nodes: inout [SpatialNode], id: UUID, persist: Bool = true) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        
        let nodesBeforeDeletion = nodes
        
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.onPerformUndoMutation? { currentNodes in
                    currentNodes = nodesBeforeDeletion
                    if persist {
                        target.onRequestSave?(true)
                    }
                }
            }
        }
        undoStackChanged += 1

        withAnimation(.spring()) {
            nodes.remove(at: index)
            
            for i in 0..<nodes.count {
                if nodes[i].nextNodeId == id {
                    nodes[i].nextNodeId = nil
                }
                if let connections = nodes[i].connectedNodeIds {
                    nodes[i].connectedNodeIds = connections.filter { $0 != id }
                    if nodes[i].connectedNodeIds?.isEmpty == true {
                        nodes[i].connectedNodeIds = nil
                    }
                }
            }
        }
        
        if persist {
            onRequestSave?(true)
        }
    }

    /// Lazily bootstraps a `MiniAppState` on a `.miniApp` node if it is missing.
    /// Guards against operating on non-Mini-App node types.
    private func ensureMiniAppState(for node: inout SpatialNode) {
        guard node.type == .miniApp else { return }
        if node.miniApp == nil {
            node.miniApp = MiniAppState(
                codeText: ProjectTemplateProvider.defaultCode
            )
        }
    }
}
