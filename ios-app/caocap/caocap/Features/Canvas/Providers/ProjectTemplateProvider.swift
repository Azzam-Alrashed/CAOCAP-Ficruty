import Foundation
import CoreGraphics

/// Available templates for populating a new or empty project.
public enum ProjectTemplate: String, CaseIterable, Identifiable, Codable {
    /// A starter workspace placeholder (canvas stays empty by default).
    case helloWorld = "hello_world"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .helloWorld: return "Hello World"
        }
    }
    
    public var description: String {
        switch self {
        case .helloWorld: return "A clean canvas ready for workflow nodes."
        }
    }
    
    public var icon: String {
        switch self {
        case .helloWorld: return "play.circle.fill"
        }
    }
    
    public var theme: NodeTheme {
        switch self {
        case .helloWorld: return .blue
        }
    }
}

public struct ProjectTemplateProvider {

    /// Returns the initial array of nodes for the given template.
    public static func nodes(for template: ProjectTemplate) -> [SpatialNode] {
        switch template {
        case .helloWorld:
            return defaultNodes
        }
    }

    /// The default canvas starts clean; users add nodes when they are ready.
    public static var defaultNodes: [SpatialNode] {
        []
    }

    /// Placeholder Mini-App body. Kept empty now that the on-device HTML runtime is gone;
    /// `codeText` remains for Codable compatibility and CoCaptain code-section patches.
    public static let defaultCode = ""
}
