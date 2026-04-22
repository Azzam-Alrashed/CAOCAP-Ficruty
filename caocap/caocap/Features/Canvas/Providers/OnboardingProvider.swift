import Foundation
import CoreGraphics

public struct OnboardingProvider {
    public static var manifestoNodes: [SpatialNode] {
        let node1Id = UUID()
        let node2Id = UUID()
        let node3Id = UUID()
        let node4Id = UUID()
        let node5Id = UUID()
        let node6Id = UUID()
        
        return [
            SpatialNode(
                id: node1Id,
                position: .zero,
                title: "Hello, world!",
                subtitle: "Welcome to CAOCAP. Follow the arrow to begin your journey.",
                icon: "hand.wave.fill",
                theme: .purple,
                nextNodeId: node2Id
            ),
            SpatialNode(
                id: node2Id,
                position: CGPoint(x: 500, y: 100),
                title: "Navigation",
                subtitle: "Pan with one finger and zoom with two to move around this space.",
                icon: "map.fill",
                theme: .blue,
                nextNodeId: node3Id
            ),
            SpatialNode(
                id: node3Id,
                position: CGPoint(x: 1000, y: -200),
                title: "Direct Manipulation",
                subtitle: "Try dragging me! You can organize nodes anywhere on the canvas.",
                icon: "hand.point.up.left.fill",
                theme: .orange,
                nextNodeId: node4Id
            ),
            SpatialNode(
                id: node4Id,
                position: CGPoint(x: 1500, y: 300),
                title: "Agentic Flow",
                subtitle: "Each node represents an intent, a snippet of code, or an app module.",
                icon: "sparkles",
                theme: .pink,
                nextNodeId: node5Id
            ),
            SpatialNode(
                id: node5Id,
                position: CGPoint(x: 1000, y: 800),
                title: "Summon the Command Palette",
                subtitle: "Tap the command button to create new nodes and interact with the AI.",
                icon: "command",
                theme: .green,
                nextNodeId: node6Id
            ),
            SpatialNode(
                id: node6Id,
                position: CGPoint(x: 0, y: 1000),
                title: "Go to the Home workspace",
                subtitle: "Click me to enter the Home workspace and start building.",
                icon: "rocket.fill",
                theme: .purple,
                action: .navigateHome
            )
        ]
    }
}
