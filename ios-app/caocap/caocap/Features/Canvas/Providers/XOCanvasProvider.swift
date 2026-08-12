import CoreGraphics
import Foundation

/// A placeholder XO Mini-App node used as a ready-to-open canvas example.
public enum XOCanvasProvider {
    public static let miniAppNodeID = UUID(uuidString: "CA0CA002-0000-4000-8000-000000000002")!

    public static var snapshot: ProjectSnapshot {
        ProjectSnapshot(
            projectName: "XO",
            nodes: [
                SpatialNode(
                    id: miniAppNodeID,
                    type: .miniApp,
                    position: .zero,
                    title: "XO",
                    subtitle: "Tap to open",
                    icon: "square.grid.3x3.fill",
                    theme: .secondary,
                    miniApp: MiniAppState(
                        codeText: code
                    )
                )
            ],
            viewportOffset: .zero,
            viewportScale: 0.8
        )
    }

    /// Empty placeholder; HTML runtime removed.
    public static let code = ""
}
