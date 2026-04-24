import Foundation
import CoreGraphics

public struct HomeProvider {
    public static var homeNodes: [SpatialNode] {
        return [
            SpatialNode(
                id: UUID(),
                position: CGPoint(x: -200, y: -200),
                title: String(localized: "Profile"),
                subtitle: String(localized: "Manage your account and preferences."),
                icon: "person.crop.circle.fill",
                theme: .blue,
                action: .openProfile
            ),
            SpatialNode(
                id: UUID(),
                position: CGPoint(x: 200, y: -200),
                title: String(localized: "Projects"),
                subtitle: String(localized: "View and organize your work."),
                icon: "folder.fill",
                theme: .purple,
                action: .openProjectExplorer
            ),
            SpatialNode(
                id: UUID(),
                position: CGPoint(x: -200, y: 200),
                title: String(localized: "Settings"),
                subtitle: String(localized: "App configuration and tools."),
                icon: "gearshape.fill",
                theme: .orange,
                action: .openSettings
            ),
            SpatialNode(
                id: UUID(),
                position: CGPoint(x: 200, y: 200),
                title: String(localized: "New Project"),
                subtitle: String(localized: "Start a fresh spatial journey."),
                icon: "plus.circle.fill",
                theme: .green,
                action: .createNewProject
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
