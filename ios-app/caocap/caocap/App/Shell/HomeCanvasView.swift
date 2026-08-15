import SwiftUI

/// The canvas-first Home tab, including its local command and FAB layers.
struct HomeCanvasView: View {
    @Bindable var session: AppSessionCoordinator
    var onOpenChat: () -> Void

    var body: some View {
        ZStack {
            workspaceCanvas
                .ignoresSafeArea(.container, edges: .bottom)

            CommandPaletteView(viewModel: session.commandPalette)

            KeyboardShortcutBridge(
                onOpenCommandPalette: {
                    session.commandPalette.setPresented(true)
                },
                onSummonCoCaptain: {
                    onOpenChat()
                },
                onUndo: {
                    _ = session.actionDispatcher.perform(.undo, source: .user)
                },
                onRedo: {
                    _ = session.actionDispatcher.perform(.redo, source: .user)
                }
            )

        }
        .background(Color(uiColor: .systemBackground))
        .onboardingTooltipOverlay(
            isCommandPalettePresented: session.commandPalette.isPresented,
            rendersAnchor: { $0.isCanvasLocal }
        )
        .environment(session.onboarding)
    }

    @ViewBuilder
    private var workspaceCanvas: some View {
        switch session.router.currentWorkspace {
        case .root:
            WorkspaceCanvasView(
                store: session.router.rootStore,
                canvasID: "root_canvas",
                viewport: $session.viewport,
                currentScale: $session.currentScale,
                onEmptySpaceTap: dismissCommandLine
            )
        case .project(let fileName):
            WorkspaceCanvasView(
                store: session.router.activeStore,
                canvasID: "session_canvas_\(fileName)",
                viewport: $session.viewport,
                currentScale: $session.currentScale,
                onEmptySpaceTap: dismissCommandLine
            )
        }
    }

    private func dismissCommandLine() {
        if session.commandPalette.isPresented {
            session.commandPalette.setPresented(false)
        }
    }
}
