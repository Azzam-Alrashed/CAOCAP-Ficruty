import Foundation
import CoreGraphics

public struct HomeProvider {
    public static var homeNodes: [SpatialNode] {
        return [
            SpatialNode(
                id: UUID(),
                position: CGPoint(x: -200, y: -200),
                title: "Profile",
                subtitle: "Manage your account and preferences.",
                icon: "person.crop.circle.fill",
                theme: .blue
            ),
            SpatialNode(
                id: UUID(),
                position: CGPoint(x: 200, y: -200),
                title: "Projects",
                subtitle: "View and organize your work.",
                icon: "folder.fill",
                theme: .purple
            ),
            SpatialNode(
                id: UUID(),
                position: CGPoint(x: -200, y: 200),
                title: "Settings",
                subtitle: "App configuration and tools.",
                icon: "gearshape.fill",
                theme: .orange
            ),
            SpatialNode(
                id: UUID(),
                position: CGPoint(x: 200, y: 200),
                title: "New Project",
                subtitle: "Start a fresh spatial journey.",
                icon: "plus.circle.fill",
                theme: .green
            ),
            SpatialNode(
                id: UUID(),
                position: CGPoint(x: 0, y: 500),
                title: "Retry Onboarding",
                subtitle: "Revisit the guided tour and app manifesto.",
                icon: "graduationcap.fill",
                theme: .blue,
                action: .retryOnboarding
            )
        ]
    }
}
