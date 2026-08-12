import SwiftUI

/// Shared canvas shell for root and project workspaces.
struct WorkspaceCanvasView: View {
    let store: ProjectStore
    let canvasID: String
    @Binding var viewport: ViewportState
    @Binding var currentScale: CGFloat
    @Binding var presentedMiniApp: SpatialNode?
    @Binding var selectedNodeDetail: SpatialNode?
    var canvasFocusNodeID: UUID?
    var commandPalette: CommandPaletteViewModel?
    let onNavigateToSubCanvas: (String) -> Void
    let onRecoverUnsupportedProject: () -> Void
    var onFlyToNode: ((UUID) -> Void)?

    var body: some View {
        InfiniteCanvasView(
            store: store,
            viewport: $viewport,
            currentScale: $currentScale,
            presentedMiniApp: $presentedMiniApp,
            selectedNodeDetail: $selectedNodeDetail,
            canvasFocusNodeID: canvasFocusNodeID,
            commandPalette: commandPalette,
            onNavigateToSubCanvas: onNavigateToSubCanvas,
            onRecoverUnsupportedProject: onRecoverUnsupportedProject,
            onFlyToNode: onFlyToNode
        )
        // Spatial coordinates and pan/zoom gestures must stay LTR even when the app
        // locale is Arabic. Node cards opt back into RTL for their own text layout.
        .environment(\.layoutDirection, .leftToRight)
        .id(canvasID)
    }
}
