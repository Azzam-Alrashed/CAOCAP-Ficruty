import Foundation
import Observation
import SwiftUI

/// Identifies the currently active workspace in the navigation hierarchy.
///
/// - `root`: The home canvas containing the user's project nodes.
/// - `project(String)`: A named project canvas identified by its filename.
public enum WorkspaceState: Equatable {
    case root
    case project(String) // filename
}

/// Coordinates top-level workspace navigation and owns the active stores for
/// home and user-created projects.
@MainActor
@Observable
public class AppRouter {
    /// The currently active workspace. SwiftUI views observe this via `@Observable`.
    public var currentWorkspace: WorkspaceState
    /// Cache of `ProjectStore` instances keyed by filename. Stores are created lazily
    /// on first access and retained for the lifetime of the router.
    public var projects: [String: ProjectStore] = [:]
    /// Stack of previously visited workspaces, supporting `goBack()` navigation.
    private var navigationStack: [WorkspaceState] = []
    
    public let rootStore: ProjectStore
    private let projectPersistence: ProjectPersistenceService
    
    /// Returns the store for the current workspace, lazily creating project
    /// stores on cold boot when navigation restores a project filename.
    public var activeStore: ProjectStore {
        switch currentWorkspace {
        case .root: return rootStore
        case .project(let fileName):
            if let store = projects[fileName] {
                return store
            }
            
            // COLD BOOT FIX: Initialize and cache synchronously to prevent race conditions
            let newStore = ProjectStore(
                fileName: fileName,
                persistence: projectPersistence
            )
            projects[fileName] = newStore
            return newStore
        }
    }
    
    /// Initializes the router and creates an empty root canvas.
    public init(projectPersistence: ProjectPersistenceService = ProjectPersistenceService()) {
        CanvasWorkspaceMigration.runIfNeeded()
        self.projectPersistence = projectPersistence
        self.currentWorkspace = .root
        self.rootStore = ProjectStore(
            fileName: CanvasFileNaming.rootFileName,
            projectName: "Root",
            initialNodes: RootCanvasProvider.nodes,
            initialViewportScale: RootCanvasProvider.defaultViewportScale,
            persistence: projectPersistence
        )
    }
    
    /// Moves between workspaces and records onboarding completion when the user
    /// reaches Home, which makes Home the default workspace on the next launch.
    public func navigate(to workspace: WorkspaceState, addToStack: Bool = true, animated: Bool = true) {
        let updateState = {
            if addToStack && self.currentWorkspace != workspace {
                self.navigationStack.append(self.currentWorkspace)
                // Prevent infinite stack growth
                if self.navigationStack.count > 50 {
                    self.navigationStack.removeFirst()
                }
            }
            self.currentWorkspace = workspace
            
            if case .project(let fileName) = workspace {
                UserDefaults.standard.set(fileName, forKey: "lastCanvasFileName")
            }
        }
        
        if animated {
            withAnimation(.spring()) {
                updateState()
            }
        } else {
            updateState()
        }
    }
    
    /// Pops the navigation stack and returns to the previous workspace.
    /// No-ops if the stack is empty (i.e., already at the first visited workspace).
    public func goBack() {
        guard let previous = navigationStack.popLast() else { return }
        navigate(to: previous, addToStack: false, animated: true)
    }
    
    /// Navigates to the root workspace without recording the transition in the back stack.
    public func goRoot() {
        navigate(to: .root, animated: true)
    }
    
    /// Resolves an existing canvas filename and navigates into the corresponding project.
    /// `CanvasFileNaming.resolveExistingFileName` normalises legacy filename formats.
    public func navigateToSubCanvas(fileName: String) {
        let resolved = CanvasFileNaming.resolveExistingFileName(fileName)
        navigate(to: .project(resolved), animated: true)
    }

    /// Detaches a session workspace so its pending writes can be drained before
    /// an untouched draft is deleted from disk.
    public func detachProject(fileName: String) -> ProjectStore? {
        projects.removeValue(forKey: fileName)
    }

    /// Creates a brand-new project canvas with the default node template and immediately
    /// navigates to it. Used as a recovery path when an imported or linked canvas cannot
    /// be loaded.
    public func createFreshMiniAppCanvas() {
        let fileName = CanvasFileNaming.newCanvasFileName()
        let store = ProjectStore(
            fileName: fileName,
            projectName: "Mini-App Canvas",
            initialNodes: ProjectTemplateProvider.defaultNodes,
            persistence: projectPersistence
        )
        projects[fileName] = store
        navigate(to: .project(fileName), animated: true)
    }

    /// In-memory node arrays keyed by canvas file name, including root.
    /// Prefer these over disk when counting Mini-Apps so unsaved edits count.
    public func liveNodesByFileName() -> [String: [SpatialNode]] {
        var map: [String: [SpatialNode]] = [
            CanvasFileNaming.rootFileName: rootStore.nodes
        ]
        for (fileName, store) in projects {
            map[fileName] = store.nodes
        }
        switch currentWorkspace {
        case .root:
            break
        case .project(let fileName):
            map[fileName] = activeStore.nodes
        }
        return map
    }
}
