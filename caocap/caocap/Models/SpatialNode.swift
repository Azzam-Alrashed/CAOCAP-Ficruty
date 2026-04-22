import Foundation
import CoreGraphics

public enum NodeAction: String, Codable, Equatable {
    case navigateHome
    case retryOnboarding
}

public struct SpatialNode: Identifiable, Codable, Equatable {
    public let id: UUID
    public var position: CGPoint
    public var title: String
    public var subtitle: String?
    public var icon: String?
    public var theme: NodeTheme
    public var nextNodeId: UUID?
    public var action: NodeAction?
    
    public init(id: UUID = UUID(), position: CGPoint, title: String, subtitle: String? = nil, icon: String? = nil, theme: NodeTheme = .blue, nextNodeId: UUID? = nil, action: NodeAction? = nil) {
        self.id = id
        self.position = position
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.theme = theme
        self.nextNodeId = nextNodeId
        self.action = action
    }
}
