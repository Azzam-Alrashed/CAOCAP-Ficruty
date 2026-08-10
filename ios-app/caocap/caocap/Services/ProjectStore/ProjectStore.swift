import Foundation
import Observation
import OSLog
import SwiftUI

/// Owns the mutable state for one spatial project, including nodes, viewport
/// position, persistence, undo wiring, and live preview compilation.
@Observable
@MainActor
public class ProjectStore {
    public static let experimentalAgentPipesEnabledKey = "experimental_agent_pipes_enabled"

    /// The display name of the project.
    public var projectName: String = "Untitled Project"
    
    /// The collection of nodes currently visible on the canvas.
    public var nodes: [SpatialNode] = []
    
    /// The saved offset of the infinite canvas.
    public var viewportOffset: CGSize = .zero
    
    /// The saved scale/zoom level of the infinite canvas.
    public var viewportScale: CGFloat = 1.0
    
    /// Tracks if a save operation is currently pending or in progress.
    public var isSaving: Bool { saveController.isSaving }

    /// Non-nil when the on-disk project could not be opened with the current schema.
    public var unsupportedProjectMessage: String?
    
    /// Historical checkpoints for this project.
    public var history: [SnapshotMetadata] {
        checkpointManager.history
    }
    
    private let logger = Logger(subsystem: "com.caocap.app", category: "Persistence")
    private let persistence: ProjectPersistenceService
    private let saveController: ProjectSaveController
    private let checkpointManager: CheckpointManager
    private let livePreviewOrchestrator = LivePreviewOrchestrator()
    private let mutationEngine = NodeMutationEngine()
    private let agentPipeline = AgentPipelineEngine()
    
    
    /// Tracks active background agents working on specific nodes.
    public var activeAgentStates: [UUID: AgentExecutionState] {
        agentPipeline.executionStates(for: nodes)
    }
    
    /// The current version of the project file schema. Incremented when
    /// structural changes are made to nodes or the project envelope.
    public static let currentSchemaVersion = ProjectPersistenceService.currentSchemaVersion
    
    public let fileName: String
    
    /// Called when daily challenges are newly completed after a live preview compile.
    public var onChallengesCompleted: (([DailyChallengeDefinition]) -> Void)?
    
    public init(
        fileName: String = "canvas_v1.json",
        projectName: String = "Untitled Project",
        initialNodes: [SpatialNode]? = nil,
        initialViewportScale: CGFloat = 1.0,
        persistence: ProjectPersistenceService = ProjectPersistenceService(),
        activityRecorder: (any ActivityRecording)? = nil
    ) {
        self.fileName = fileName
        self.projectName = projectName
        self.viewportScale = initialViewportScale
        self.persistence = persistence
        self.saveController = ProjectSaveController(
            persistence: persistence,
            activityRecorder: activityRecorder
        )
        self.checkpointManager = CheckpointManager(persistence: persistence)
        wireMutationEngineCallbacks()
        load(initialNodes: initialNodes, initialViewportScale: initialViewportScale)
    }

    /// Wires the NodeMutationEngine's side-effect callbacks back into ProjectStore.
    /// Must be called once after all stored properties are initialized.
    private func wireMutationEngineCallbacks() {
        mutationEngine.onRequestSave = { [weak self] showIndicator in
            self?.requestSave(showIndicator: showIndicator)
        }
        mutationEngine.onCompileLivePreview = { [weak self] nodes in
            guard let self else { return }
            self.compileLivePreviewsAndEvaluateChallenges(nodes: &nodes)
        }
        mutationEngine.onTriggerDownstreamAgents = { [weak self] id, nodes in
            self?.triggerDownstreamAgents(from: id, nodes: nodes)
        }
        mutationEngine.onViewportChange = { [weak self] in
            self?.viewportOffset ?? .zero
        }
        // This is the critical callback: allows undo closures in NodeMutationEngine
        // to mutate ProjectStore.nodes and trigger saves.
        mutationEngine.onPerformUndoMutation = { [weak self] mutation in
            guard let self else { return }
            mutation(&self.nodes)
            self.undoStackChanged += 1
        }
    }

    
    /// Loads the project data from disk. If no file is found, initializes with default nodes.
    public func load(initialNodes: [SpatialNode]? = nil, initialViewportScale: CGFloat = 1.0) {
        PerformanceSignposts.measure(PerformanceSignposts.Name.projectLoad) {
            if !persistence.projectExists(fileName: fileName) {
                logger.info("No saved project found for \(self.fileName). Initializing with defaults.")
                self.nodes = initialNodes ?? []
                self.viewportScale = initialViewportScale

                // Ensure Mini-App previews are compiled immediately for new projects.
                compileLivePreviewsAndEvaluateChallenges(nodes: &nodes)

                // Only perform an initial save for permanent project files.
                if !self.fileName.contains("onboarding") {
                    requestSave(showIndicator: false)
                }
                return
            }

            do {
                let snapshot = try persistence.load(fileName: fileName)
                unsupportedProjectMessage = nil
                apply(snapshot: snapshot)
                logger.info("Successfully loaded project (v\(snapshot.schemaVersion)) from disk.")
            } catch ProjectPersistenceError.unsupportedSchemaVersion(let version, let current) {
                if let version {
                    logger.error("Project schema version \(version) is not supported (expected \(current)). Using defaults without overwriting file.")
                    unsupportedProjectMessage = "This project was created with an older CAOCAP format and cannot be opened in this version."
                } else {
                    logger.error("Project is missing schema version (expected \(current)). Using defaults without overwriting file.")
                    unsupportedProjectMessage = "This project is missing format information and cannot be opened in this version."
                }
                self.nodes = initialNodes ?? []
            } catch {
                logger.error("Failed to load project: \(error.localizedDescription)")
                unsupportedProjectMessage = "This project could not be opened. Create a fresh Mini-App canvas to continue."
                self.nodes = initialNodes ?? []
            }

            // Ensure Mini-App previews are synced with embedded code on startup.
            compileLivePreviewsAndEvaluateChallenges(nodes: &nodes)

            // Load history
            checkpointManager.loadHistory(for: fileName)
        }
    }
    
    /// Persists a snapshot of the current project state using a temporary file
    /// and atomic replacement so interrupted writes do not corrupt the main file.
    public func save(showIndicator: Bool = true) {
        saveController.save(
            snapshot: currentSnapshot(),
            fileName: fileName,
            showIndicator: showIndicator
        )
    }

    public func prepareForDataReset() async {
        saveController.cancelPendingSave()
        await saveController.waitForActiveWrites()
    }
    
    /// Schedules a save operation to run after a short delay (500ms).
    /// If another save is requested before the delay expires, the previous request is cancelled.
    public func requestSave(showIndicator: Bool = true) {
        saveController.requestSave(
            showIndicator: showIndicator,
            fileName: fileName,
            snapshotFactory: { [weak self] in
                self?.currentSnapshot() ?? ProjectSnapshot(schemaVersion: Self.currentSchemaVersion, projectName: "", nodes: [], viewportOffset: .zero, viewportScale: 1.0)
            },
            onDebounceComplete: { [weak self] in
                guard let self = self else { return }
                self.compileLivePreviewsAndEvaluateChallenges(nodes: &self.nodes)
            }
        )
    }
    
    /// Autonomously triggers agents on downstream nodes when an upstream node updates.
    public func triggerDownstreamAgents(from sourceNodeID: UUID) {
        triggerDownstreamAgents(from: sourceNodeID, nodes: nodes)
    }

    private func triggerDownstreamAgents(from sourceNodeID: UUID, nodes: [SpatialNode]) {
        agentPipeline.triggerDownstreamAgents(from: sourceNodeID, nodes: nodes, store: self)
    }

    /// Creates a durable checkpoint of the current project state.
    public func createCheckpoint(label: String = "Manual Checkpoint") {
        checkpointManager.createCheckpoint(snapshot: currentSnapshot(), fileName: fileName, label: label)
    }

    /// Creates an automatic checkpoint before significant mutations (e.g. Co-Captain edits).
    public func createAutoCheckpoint(label: String = "Pre-AI Snapshot") {
        checkpointManager.createAutoCheckpoint(snapshot: currentSnapshot(), fileName: fileName, label: label)
    }

    /// Restores the project graph from a historical checkpoint.
    public func restore(from metadata: SnapshotMetadata) {
        guard let snapshot = checkpointManager.restore(from: metadata, fileName: fileName) else { return }
        withAnimation(.spring()) {
            apply(snapshot: snapshot)
        }
        save()
        compileLivePreviewsAndEvaluateChallenges(nodes: &nodes)
    }

    /// Deletes a historical checkpoint from disk and local state.
    public func deleteCheckpoint(metadata: SnapshotMetadata) {
        checkpointManager.deleteCheckpoint(metadata: metadata, fileName: fileName)
    }

    /// Non-blocking, thread-safe snapshot loader.
    nonisolated public func loadSnapshot(metadata: SnapshotMetadata) async -> ProjectSnapshot? {
        let fileName = self.fileName
        let persistence = self.persistence
        return await Task.detached(priority: .userInitiated) {
            try? persistence.loadSnapshot(metadata: metadata, for: fileName)
        }.value
    }

    private func currentSnapshot() -> ProjectSnapshot {
        ProjectSnapshot(
            schemaVersion: Self.currentSchemaVersion,
            projectName: projectName,
            nodes: nodes,
            viewportOffset: viewportOffset,
            viewportScale: viewportScale
        )
    }

    private func apply(snapshot: ProjectSnapshot) {
        self.projectName = snapshot.projectName ?? self.projectName
        self.nodes = snapshot.nodes.map { $0.applyingCanonicalThemeIfNeeded() }
        self.viewportOffset = snapshot.viewportOffset
        self.viewportScale = snapshot.viewportScale
    }
    
    /// A reference to the system UndoManager, injected by the view layer.
    public var undoManager: UndoManager? = nil {
        didSet { mutationEngine.undoManager = undoManager }
    }
    
    /// Incremented whenever the undo stack changes to force UI updates.
    public var undoStackChanged: Int = 0
    
    /// Updates a specific node's position.
    /// - Parameters:
    ///   - id: The UUID of the node to update.
    ///   - position: The new position.
    ///   - persist: If true, triggers a debounced save to disk.
    public func updateNodePosition(id: UUID, position: CGPoint, persist: Bool = true) {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            let oldPosition = nodes[index].position
            
            // Register Undo
            // UndoManager always calls back on the main thread;
            // assumeIsolated bridges the nonisolated closure to @MainActor.
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.updateNodePosition(id: id, position: oldPosition, persist: persist)
                }
            }
            undoStackChanged += 1
            
            nodes[index].position = position
            if persist {
                requestSave()
            }
        }
    }

    /// Updates a specific node's agent profile.
    /// - Parameters:
    ///   - id: The UUID of the node to update.
    ///   - profile: The new agent profile.
    ///   - persist: If true, triggers a debounced save to disk.
    public func updateNodeAgentProfile(id: UUID, profile: AgentProfile, persist: Bool = true) {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            let oldProfile = nodes[index].agentProfile
            
            // Register Undo
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.updateNodeAgentProfile(id: id, profile: oldProfile, persist: persist)
                }
            }
            undoStackChanged += 1
            
            nodes[index].agentProfile = profile
            if persist {
                save()
            }
        }
    }

    /// Updates a specific node's theme.
    /// - Parameters:
    ///   - id: The UUID of the node to update.
    ///   - theme: The new theme.
    ///   - persist: If true, triggers a debounced save to disk.
    public func updateNodeTheme(id: UUID, theme: NodeTheme, persist: Bool = true) {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            let oldTheme = nodes[index].theme
            
            // Register Undo
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.updateNodeTheme(id: id, theme: oldTheme, persist: persist)
                }
            }
            undoStackChanged += 1
            
            nodes[index].theme = theme
            if persist {
                requestSave()
            }
        }
    }

    /// Changes a node's fundamental type.
    /// - Parameters:
    ///   - id: The UUID of the node to transform.
    ///   - type: The target NodeType.
    ///   - persist: If true, triggers a debounced save to disk.
    public func updateNodeType(id: UUID, type: NodeType, persist: Bool = true) {
        mutationEngine.updateNodeType(nodes: &nodes, id: id, type: type, persist: persist)
    }
    public func updateNodeTextContent(id: UUID, text: String, persist: Bool = true) {
        mutationEngine.updateNodeTextContent(nodes: &nodes, id: id, text: text, persist: persist)
    }
    public func updateMiniAppSRS(id: UUID, text: String, persist: Bool = true) {
        mutationEngine.updateMiniAppSRS(nodes: &nodes, id: id, text: text, persist: persist)
    }
    public func updateMiniAppCode(id: UUID, text: String, persist: Bool = true) {
        mutationEngine.updateMiniAppCode(nodes: &nodes, id: id, text: text, persist: persist)
    }
    public func updateNodeAgentState(id: UUID, agentState: NodeAgentState, persist: Bool = true) {
        mutationEngine.updateNodeAgentState(nodes: &nodes, id: id, agentState: agentState, persist: persist)
    }
    public func appendNodeAgentMessage(id: UUID, message: NodeAgentMessage, persist: Bool = true) {
        mutationEngine.appendNodeAgentMessage(nodes: &nodes, id: id, message: message, persist: persist)
    }
    public func clearNodeAgentMessages(id: UUID, persist: Bool = true) {
        mutationEngine.clearNodeAgentMessages(nodes: &nodes, id: id, persist: persist)
    }
    public func updateViewport(offset: CGSize, scale: CGFloat, persist: Bool = true) {
        self.viewportOffset = offset
        self.viewportScale = scale
        if persist {
            requestSave(showIndicator: false)
        }
    }
    
    /// Resets the viewport to the center (0,0) at 100% zoom.
    public func resetViewport() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            self.viewportOffset = .zero
            self.viewportScale = 1.0
        }
        requestSave()
    }

    /// Updates positions for multiple nodes at once, registering undo/redo.
    public func updateNodePositions(_ positions: [UUID: CGPoint], animated: Bool = true) {
        mutationEngine.updateNodePositions(nodes: &nodes, positions, animated: animated)
    }
    public func organizeNodes() {
        mutationEngine.organizeNodes(nodes: &nodes, )
    }
    public func addNode(type: NodeType = .miniApp) {
        mutationEngine.addNode(nodes: &nodes, type: type)
    }
    public func addShortcutNode(for appAction: AppActionID, definition: AppActionDefinition) {
        guard let nodeAction = appAction.pinableNodeAction else { return }
        let center = CGPoint(x: -viewportOffset.width, y: -viewportOffset.height)
        mutationEngine.addShortcutNode(
            nodes: &nodes,
            action: nodeAction,
            title: definition.title,
            icon: definition.icon,
            at: center
        )
    }

    /// Restores an app-owned node only when its stable identity is absent,
    /// preserving any existing user edits to that node.
    public func ensureNodeExists(_ node: SpatialNode) {
        guard !nodes.contains(where: { $0.id == node.id }) else { return }
        nodes.append(node)
        requestSave(showIndicator: false)
    }

    public func updateNodeTitle(id: UUID, title: String) {
        mutationEngine.updateNodeTitle(nodes: &nodes, id: id, title: title)
    }
    public func updateNodeSubtitle(id: UUID, subtitle: String?) {
        mutationEngine.updateNodeSubtitle(nodes: &nodes, id: id, subtitle: subtitle)
    }
    public func updateNodeIcon(id: UUID, icon: String?) {
        mutationEngine.updateNodeIcon(nodes: &nodes, id: id, icon: icon)
    }
    public func deleteNode(id: UUID, persist: Bool = true) {
        mutationEngine.deleteNode(nodes: &nodes, id: id, persist: persist)
    }

    private func compileLivePreviewsAndEvaluateChallenges(nodes: inout [SpatialNode]) {
        _ = livePreviewOrchestrator.compile(nodes: &nodes)
        let htmlSamples = nodes.compactMap { node -> String? in
            guard node.type == .miniApp else { return nil }
            return node.miniApp?.compiledHTML
        }
        let newlyCompleted = GamificationStore.shared.evaluateMiniApps(htmlSamples: htmlSamples)
        if !newlyCompleted.isEmpty {
            onChallengesCompleted?(newlyCompleted)
        }
    }

}
