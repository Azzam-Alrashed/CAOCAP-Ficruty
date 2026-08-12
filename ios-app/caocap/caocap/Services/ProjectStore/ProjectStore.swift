import Foundation
import Observation
import OSLog
import SwiftUI

/// Owns the mutable state for one spatial project, including nodes, viewport
/// position, persistence, and undo wiring.
@Observable
@MainActor
public class ProjectStore {
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
    /// The current version of the project file schema. Incremented when
    /// structural changes are made to nodes or the project envelope.
    public static let currentSchemaVersion = ProjectPersistenceService.currentSchemaVersion
    
    public let fileName: String
    
    public init(
        fileName: String = "canvas_v1.json",
        projectName: String = "Untitled Project",
        initialNodes: [SpatialNode]? = nil,
        initialViewportScale: CGFloat = 1.0,
        persistence: ProjectPersistenceService = ProjectPersistenceService()
    ) {
        self.fileName = fileName
        self.projectName = projectName
        self.viewportScale = initialViewportScale
        self.persistence = persistence
        self.saveController = ProjectSaveController(
            persistence: persistence
        )
        self.checkpointManager = CheckpointManager(persistence: persistence)
        load(initialNodes: initialNodes, initialViewportScale: initialViewportScale)
    }

    
    /// Loads the project data from disk. If no file is found, initializes with default nodes.
    public func load(initialNodes: [SpatialNode]? = nil, initialViewportScale: CGFloat = 1.0) {
        PerformanceSignposts.measure(PerformanceSignposts.Name.projectLoad) {
            if !persistence.projectExists(fileName: fileName) {
                logger.info("No saved project found for \(self.fileName). Initializing with defaults.")
                self.nodes = initialNodes ?? []
                self.viewportScale = initialViewportScale

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
            }
        )
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
    public var undoManager: UndoManager? = nil
    
    /// Incremented whenever the undo stack changes to force UI updates.
    public var undoStackChanged: Int = 0
    
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

}
