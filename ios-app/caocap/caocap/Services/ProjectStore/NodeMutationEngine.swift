import Foundation
import SwiftUI
import os

/// Performs all mutable node operations on behalf of `ProjectStore`.
///
/// `NodeMutationEngine` is deliberately decoupled from `ProjectStore` so its
/// mutation logic can be tested in isolation. Side effects (saving, recompiling
/// the live preview, triggering downstream agents) are routed back to the store
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
    /// Called when node code or Firebase config changes require recompiling the live HTML preview.
    var onCompileLivePreview: ((inout [SpatialNode]) -> Void)?
    /// Called when an upstream node's SRS or code changes and connected downstream
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
    /// Switching to `.miniApp` bootstraps a `MiniAppState` with default SRS and code text.
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
                    srsReadinessState: SRSReadinessEvaluator().evaluate(text: SRSScaffold.defaultText, currentState: nil),
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
            onCompileLivePreview?(&nodes)
        }
    }
    
    /// Convenience alias that forwards to `updateMiniAppCode`.
    /// Exists so callers can treat any node as having generic text content.
    public func updateNodeTextContent(nodes: inout [SpatialNode], id: UUID, text: String, persist: Bool = true) {
        updateMiniAppCode(nodes: &nodes, id: id, text: text, persist: persist)
    }

    /// Updates the Software Requirements Specification (SRS) text for a Mini-App node
    /// and re-evaluates its readiness state. Also notifies downstream agents.
    public func updateMiniAppSRS(nodes: inout [SpatialNode], id: UUID, text: String, persist: Bool = true) {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            ensureMiniAppState(for: &nodes[index])
            let oldText = nodes[index].miniApp?.srsText ?? ""
            let oldReadiness = nodes[index].miniApp?.srsReadinessState

            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.onPerformUndoMutation? { currentNodes in
                        target.updateMiniAppSRS(nodes: &currentNodes, id: id, text: oldText, persist: persist)
                    }
                }
            }
            undoStackChanged += 1

            nodes[index].miniApp?.srsText = text
            nodes[index].miniApp?.srsReadinessState = SRSReadinessEvaluator().evaluate(text: text, currentState: oldReadiness)

            if persist {
                onRequestSave?(true)
            }
            onTriggerDownstreamAgents?(id, nodes)
        }
    }

    /// Replaces the runnable HTML/JS source of a Mini-App node and triggers a
    /// live preview recompile as well as downstream agent notifications.
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
            onCompileLivePreview?(&nodes)

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
    /// The new node is placed at the current viewport centre, given a unique title,
    /// and appropriate type-specific state is bootstrapped automatically.
    public func addNode(nodes: inout [SpatialNode], type: NodeType = .miniApp) {
        let uniqueTitle = generateUniqueTitle(nodes: nodes, base: type.defaultTitle)

        let subtitle = type.defaultSubtitle
        let linkedFileName: String? = type == .subCanvas ? CanvasFileNaming.newCanvasFileName() : nil
        let miniApp = type == .miniApp ? MiniAppState(
            srsReadinessState: SRSReadinessEvaluator().evaluate(text: SRSScaffold.defaultText, currentState: nil),
            codeText: ProjectTemplateProvider.defaultCode
        ) : nil
        let offset = onViewportChange?() ?? .zero

        let newNode = SpatialNode(
            id: UUID(),
            type: type,
            position: CGPoint(x: -offset.width, y: -offset.height), // Scale is applied in view usually, simplified here based on ProjectStore
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
        onCompileLivePreview?(&nodes)
        onRequestSave?(true)
    }

    /// Creates a `.standard` shortcut node pinned to a specific canvas action,
    /// placed at the given position. Used when the user pins an action from the
    /// command palette to their canvas.
    public func addShortcutNode(
        nodes: inout [SpatialNode],
        action: NodeAction,
        title: String,
        icon: String,
        at position: CGPoint
    ) {
        let newNode = SpatialNode(
            type: .standard,
            position: position,
            title: title,
            icon: icon,
            theme: .indigo,
            action: action
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
    
    /// Removes a node from the canvas and cleans up all references to it in other
    /// nodes' `nextNodeId` and `connectedNodeIds` fields.
    ///
    /// Protected nodes (e.g. pinned system nodes) are silently skipped.
    /// The undo operation restores the full pre-deletion node array rather than
    /// re-inserting at the original index, which is simpler and avoids index drift.
    public func deleteNode(nodes: inout [SpatialNode], id: UUID, persist: Bool = true) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        
        if nodes[index].isProtected {
            let title = nodes[index].title
            logger.warning("Attempted to delete protected node: \(title)")
            return
        }
        
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
                srsReadinessState: SRSReadinessEvaluator().evaluate(text: SRSScaffold.defaultText, currentState: nil),
                codeText: ProjectTemplateProvider.defaultCode
            )
        }
    }
}
