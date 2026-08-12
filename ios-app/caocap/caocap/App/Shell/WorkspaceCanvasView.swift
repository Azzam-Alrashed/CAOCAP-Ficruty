import SwiftUI

/// Shared blank canvas shell for root and project workspaces.
struct WorkspaceCanvasView: View {
    let store: ProjectStore
    let canvasID: String
    @Binding var viewport: ViewportState
    @Binding var currentScale: CGFloat
    var onEmptySpaceTap: () -> Void = {}

    var body: some View {
        InfiniteCanvasView(
            store: store,
            viewport: $viewport,
            currentScale: $currentScale,
            onEmptySpaceTap: onEmptySpaceTap
        )
        .environment(\.layoutDirection, .leftToRight)
        .id(canvasID)
    }
}
