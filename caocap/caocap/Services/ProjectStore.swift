import Foundation
import Observation
import OSLog
import SwiftUI

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
    public var isSaving: Bool = false
    
    private let logger = Logger(subsystem: "com.ficruty.caocap", category: "Persistence")
    
    /// A reference to the pending save task used for debouncing disk writes.
    private var saveTask: Task<Void, Never>? = nil
    
    /// The internal structure used for JSON serialization of the project state.
    private struct ProjectData: Codable {
        let projectName: String?
        let nodes: [SpatialNode]
        let viewportOffset: CGSize
        let viewportScale: CGFloat
    }
    
    /// Returns the local file URL where project data is stored.
    /// This property also ensures the parent directory exists.
    public let fileName: String
    
    private var fileURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("com.ficruty.caocap", isDirectory: true)
        
        // Create the directory if it doesn't exist (e.g., on first run)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        
        return appSupport.appendingPathComponent(self.fileName)
    }
    
    public init(fileName: String = "project_v1.json", projectName: String = "Untitled Project", initialNodes: [SpatialNode]? = nil, initialViewportScale: CGFloat = 1.0) {
        self.fileName = fileName
        self.projectName = projectName
        self.viewportScale = initialViewportScale
        load(initialNodes: initialNodes, initialViewportScale: initialViewportScale)
    }
    
    /// Loads the project data from disk. If no file is found, initializes with default nodes.
    public func load(initialNodes: [SpatialNode]? = nil, initialViewportScale: CGFloat = 1.0) {
        let url = fileURL
        
        if !FileManager.default.fileExists(atPath: url.path) {
            logger.info("No saved project found for \(self.fileName). Initializing with defaults.")
            self.nodes = initialNodes ?? OnboardingProvider.manifestoNodes
            self.viewportScale = initialViewportScale
            
            // Ensure Live Preview is compiled immediately for new projects
            compileLivePreview()
            
            // Only perform an initial save for permanent project files.
            if !self.fileName.contains("onboarding") {
                save()
            }
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(ProjectData.self, from: data)
            
            var migratedNodes = decoded.nodes
            
            // Migrate old nodes that lack the action property
            for i in 0..<migratedNodes.count {
                if migratedNodes[i].action == nil {
                    if migratedNodes[i].title == "Retry Onboarding" {
                        migratedNodes[i].action = .retryOnboarding
                    } else if migratedNodes[i].title == "Go to the Home workspace" {
                        migratedNodes[i].action = .navigateHome
                    } else if migratedNodes[i].title == "New Project" {
                        migratedNodes[i].action = .createNewProject
                    } else if migratedNodes[i].title == "Settings" {
                        migratedNodes[i].action = .openSettings
                    } else if migratedNodes[i].title == "Profile" {
                        migratedNodes[i].action = .openProfile
                    } else if migratedNodes[i].title == "Projects" {
                        migratedNodes[i].action = .openProjectExplorer
                    }
                }
            }
            
            // Update the live state with the decoded data
            self.projectName = decoded.projectName ?? self.projectName
            self.nodes = migratedNodes
            self.viewportOffset = decoded.viewportOffset
            self.viewportScale = decoded.viewportScale
            
            logger.info("Successfully loaded project from disk.")
        } catch {
            logger.error("Failed to load project: \(error.localizedDescription)")
            // Fallback to initial nodes if data is corrupted or missing
            self.nodes = initialNodes ?? OnboardingProvider.manifestoNodes
        }
        
        // Ensure the Live Preview is synced with the code nodes on startup
        compileLivePreview()
    }
    
    public func save() {
        let url = fileURL
        let tempURL = url.appendingPathExtension("\(UUID().uuidString).tmp")
        
        let projectData = ProjectData(
            projectName: projectName,
            nodes: nodes,
            viewportOffset: viewportOffset,
            viewportScale: viewportScale
        )
        
        let log = logger
        
        Task.detached(priority: .background) {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(projectData)
                
                // 1. Write to a temporary file first
                try data.write(to: tempURL, options: .atomic)
                
                // 2. Perform an atomic swap to prevent data corruption during write
                if FileManager.default.fileExists(atPath: url.path) {
                    _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
                } else {
                    try FileManager.default.moveItem(at: tempURL, to: url)
                }
                
                log.info("Successfully saved project to disk.")
            } catch {
                log.error("Failed to save project: \(error.localizedDescription)")
            }
            
            // Clean up the temp file if the atomic swap failed or it wasn't consumed
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Reset isSaving only if no other task is pending
        if saveTask == nil {
            isSaving = false
        }
    }
    
    /// Schedules a save operation to run after a short delay (500ms).
    /// If another save is requested before the delay expires, the previous request is cancelled.
    public func requestSave() {
        saveTask?.cancel()
        isSaving = true
        
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            if !Task.isCancelled {
                compileLivePreview()
                save()
                saveTask = nil
                isSaving = false
            }
        }
    }
    
    /// Combines HTML, CSS, and JS node contents and updates the Live Preview node.
    private func compileLivePreview() {
        guard let webViewIndex = nodes.firstIndex(where: { $0.type == .webView }),
              let htmlNode = nodes.first(where: { $0.title.lowercased() == "html" }) else {
            return
        }
        
        var compiledHTML = htmlNode.textContent ?? ""
        
        // Inject CSS
        if let cssNode = nodes.first(where: { $0.title.lowercased() == "css" }),
           let cssContent = cssNode.textContent, !cssContent.isEmpty {
            let styleTag = "\n<style>\n\(cssContent)\n</style>\n"
            if let headRange = compiledHTML.range(of: "</head>", options: .caseInsensitive) {
                compiledHTML.insert(contentsOf: styleTag, at: headRange.lowerBound)
            } else if let htmlRange = compiledHTML.range(of: "<html>", options: .caseInsensitive) {
                compiledHTML.insert(contentsOf: "<head>\n\(styleTag)\n</head>\n", at: htmlRange.upperBound)
            } else {
                compiledHTML = styleTag + compiledHTML
            }
        }
        
        // Inject JS
        if let jsNode = nodes.first(where: { $0.title.lowercased() == "javascript" }),
           let jsContent = jsNode.textContent, !jsContent.isEmpty {
            let scriptTag = "\n<script>\n\(jsContent)\n</script>\n"
            if let bodyRange = compiledHTML.range(of: "</body>", options: .caseInsensitive) {
                compiledHTML.insert(contentsOf: scriptTag, at: bodyRange.lowerBound)
            } else if let htmlRange = compiledHTML.range(of: "</html>", options: .caseInsensitive) {
                compiledHTML.insert(contentsOf: scriptTag, at: htmlRange.lowerBound)
            } else {
                compiledHTML += scriptTag
            }
        }
        
        // Update the WebView node if the content changed
        if nodes[webViewIndex].htmlContent != compiledHTML {
            nodes[webViewIndex].htmlContent = compiledHTML
        }
    }
    
    /// A reference to the system UndoManager, injected by the view layer.
    public var undoManager: UndoManager? = nil
    
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
    
    /// Updates a specific node's text content.
    /// - Parameters:
    ///   - id: The UUID of the node to update.
    ///   - text: The new text content.
    ///   - persist: If true, triggers a debounced save to disk.
    public func updateNodeTextContent(id: UUID, text: String, persist: Bool = true) {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            let oldText = nodes[index].textContent ?? ""
            
            // Register Undo
            // UndoManager always calls back on the main thread;
            // assumeIsolated bridges the nonisolated closure to @MainActor.
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.updateNodeTextContent(id: id, text: oldText, persist: persist)
                }
            }
            undoStackChanged += 1
            
            nodes[index].textContent = text
            if persist {
                requestSave()
            }
        }
    }
    
    /// Updates the viewport state.
    /// - Parameters:
    ///   - offset: The new offset.
    ///   - scale: The new scale.
    ///   - persist: If true, triggers a debounced save to disk.
    public func updateViewport(offset: CGSize, scale: CGFloat, persist: Bool = true) {
        self.viewportOffset = offset
        self.viewportScale = scale
        if persist {
            requestSave()
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
    
    /// Adds a new code node to the project at the current viewport center.
    public func addNode() {
        let newNode = SpatialNode(
            id: UUID(),
            type: .code,
            position: CGPoint(x: -viewportOffset.width / viewportScale, y: -viewportOffset.height / viewportScale),
            title: "New Logic",
            subtitle: "Write your intent here.",
            icon: "plus.square.fill",
            theme: .blue,
            textContent: "// Start coding here..."
        )
        
        withAnimation(.spring()) {
            nodes.append(newNode)
        }
        requestSave()
    }
}
