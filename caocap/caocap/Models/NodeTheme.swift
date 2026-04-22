import SwiftUI

public enum NodeTheme: String, Codable, CaseIterable {
    case purple, blue, pink, orange, green, secondary
    
    public var color: Color {
        switch self {
        case .purple: return .purple
        case .blue: return .blue
        case .pink: return .pink
        case .orange: return .orange
        case .green: return .green
        case .secondary: return .secondary
        }
    }
    
    public var glowOpacity: Double {
        switch self {
        case .secondary: return 0.05
        default: return 0.15
        }
    }
}
