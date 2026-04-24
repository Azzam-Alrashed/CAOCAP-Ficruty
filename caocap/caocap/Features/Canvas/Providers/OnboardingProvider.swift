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
        let node7Id = UUID()
        
        return [
            SpatialNode(
                id: node1Id,
                position: .zero,
                title: String(localized: "Welcome to CAOCAP"),
                subtitle: String(localized: "The spatial landscape for agentic software design."),
                icon: "sparkles",
                theme: .purple,
                nextNodeId: node2Id
            ),
            SpatialNode(
                id: node2Id,
                position: CGPoint(x: 600, y: 150),
                title: String(localized: "The Infinite Canvas"),
                subtitle: String(localized: "Break free from the file tree. Pan and zoom to navigate your architecture."),
                icon: "map.fill",
                theme: .blue,
                nextNodeId: node3Id
            ),
            SpatialNode(
                id: node3Id,
                position: CGPoint(x: 1200, y: -100),
                title: String(localized: "Nodes of Intent"),
                subtitle: String(localized: "Each node represents a component, a logic block, or a vision. Drag them to organize your mind."),
                icon: "square.grid.3x3.fill",
                theme: .orange,
                nextNodeId: node4Id
            ),
            SpatialNode(
                id: node4Id,
                position: CGPoint(x: 1800, y: 300),
                title: String(localized: "Agentic Design"),
                subtitle: String(localized: "You define the 'What'. Your Co-Captain handles the 'How'. Spatial programming starts here."),
                icon: "brain.head.profile",
                theme: .pink,
                nextNodeId: node5Id
            ),
            SpatialNode(
                id: node5Id,
                type: .webView,
                position: CGPoint(x: 1500, y: 900),
                title: String(localized: "Live Preview"),
                subtitle: String(localized: "See your creations come to life in real-time. This node is a live browser engine."),
                icon: "safari.fill",
                theme: .green,
                nextNodeId: node6Id,
                htmlContent: """
                <html>
                <body style="background: linear-gradient(135deg, #7C3AED, #3B82F6); color: white; display: flex; align-items: center; justify-content: center; height: 100vh; font-family: system-ui, sans-serif; margin: 0; text-align: center;">
                    <div>
                        <h1 style="font-size: 3rem; margin-bottom: 0.5rem;">\(String(localized: "Hello, CAOCAP"))</h1>
                        <p style="font-size: 1.2rem; opacity: 0.8;">\(String(localized: "Live Spatial Preview"))</p>
                    </div>
                </body>
                </html>
                """
            ),
            SpatialNode(
                id: node6Id,
                position: CGPoint(x: 600, y: 1200),
                title: String(localized: "The Command Palette"),
                subtitle: String(localized: "Press the Floating Action Button to summon tools, create nodes, or talk to the AI."),
                icon: "command",
                theme: .blue,
                nextNodeId: node7Id
            ),
            SpatialNode(
                id: node7Id,
                position: CGPoint(x: -400, y: 800),
                title: String(localized: "Your Journey Begins"),
                subtitle: String(localized: "Enter your Home workspace to start building your first spatial project."),
                icon: "rocket.fill",
                theme: .purple,
                action: .navigateHome
            )
        ]
    }
}
