import CoreGraphics
import Foundation

/// Canonical empty root canvas used after first-run personalization.
public enum RootCanvasProvider {
    public static let defaultViewportScale: CGFloat = 1

    public static var nodes: [SpatialNode] { [] }

    public static var snapshot: ProjectSnapshot {
        ProjectSnapshot(
            projectName: "Root",
            nodes: nodes,
            viewportOffset: .zero,
            viewportScale: defaultViewportScale
        )
    }
}
