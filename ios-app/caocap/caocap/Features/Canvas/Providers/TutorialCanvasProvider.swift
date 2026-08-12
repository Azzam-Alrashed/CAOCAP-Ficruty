import CoreGraphics
import Foundation

/// The tutorial workspace hosts a seeded Hello World Mini-App used by interactive
/// lessons that teach opening nodes and canvas organization.
public enum TutorialCanvasProvider {
    public static let miniAppNodeID = UUID(uuidString: "CA0CA003-0000-4000-8000-000000000001")!

    public static var snapshot: ProjectSnapshot {
        ProjectSnapshot(
            projectName: "Tutorial",
            nodes: [practiceMiniAppNode],
            viewportOffset: .zero,
            viewportScale: 0.5
        )
    }

    public static var practiceMiniAppNode: SpatialNode {
        SpatialNode(
            id: miniAppNodeID,
            type: .miniApp,
            position: .zero,
            title: "Hello World",
            subtitle: "Tap to open",
            icon: "play.circle.fill",
            theme: .blue,
            miniApp: MiniAppState(
                codeText: ProjectTemplateProvider.defaultCode
            )
        )
    }
}
