import Foundation

public enum NodeRole: String, CaseIterable, Codable, Hashable {
    case miniApp
    case subCanvas
    case custom

    public static let editableCanonicalRoles: [NodeRole] = [
        .miniApp
    ]

    public var displayName: String {
        switch self {
        case .miniApp: return "Mini-App"
        case .subCanvas: return "Sub-Canvas"
        case .custom: return "Custom"
        }
    }

    public var localizedDisplayName: String {
        LocalizationManager.shared.localizedString(displayName)
    }

    public var isEditableCanonicalRole: Bool {
        Self.editableCanonicalRoles.contains(self)
    }

    public func matches(node: SpatialNode) -> Bool {
        node.role == self
    }
}

public extension SpatialNode {
    var role: NodeRole {
        switch type {
        case .miniApp:
            return .miniApp
        case .subCanvas:
            return .subCanvas
        default:
            return .custom
        }
    }
}
