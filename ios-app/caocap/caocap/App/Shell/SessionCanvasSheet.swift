import SwiftUI

/// The active session's spatial workspace, presented above its primary chat.
struct SessionCanvasSheet: View {
    @Bindable var session: AppSessionCoordinator
    @State private var fabAnchorFrame: CGRect = .null

    var body: some View {
        ZStack {
            workspaceCanvas

            CommandPaletteView(viewModel: session.commandPalette)

            KeyboardShortcutBridge(
                onOpenCommandPalette: {
                    session.commandPalette.setPresented(true)
                },
                onSummonCoCaptain: {
                    session.dismissCanvas()
                },
                onUndo: {
                    _ = session.actionDispatcher.perform(.undo, source: .user)
                },
                onRedo: {
                    _ = session.actionDispatcher.perform(.redo, source: .user)
                }
            )

            FloatingCommandButton(
                onTap: {
                    session.handleFloatingCommandButtonTap()
                },
                onCenterCanvas: {
                    session.centerActiveCanvas()
                },
                onOpenCommandLine: {
                    session.openCommandLine()
                },
                onSelectMode: { mode in
                    switch mode {
                    case .chat:
                        session.dismissCanvas()
                    case .video:
                        _ = session.actionDispatcher.perform(
                            .summonCopilotVideo,
                            source: .user
                        )
                    }
                },
                copilot: session.selectedCopilot,
                onAnchorFrameChange: { frame in
                    fabAnchorFrame = frame
                }
            )
            .environment(\.layoutDirection, .leftToRight)
            .environment(session.onboarding)
        }
        .background(Color(uiColor: .systemBackground))
        .onboardingExplicitAnchorFrames(fabExplicitAnchorFrames)
        .onboardingTooltipOverlay(
            isCommandPalettePresented: session.commandPalette.isPresented,
            rendersAnchor: { anchor in
                anchor.isCanvasLocal || anchor == .floatingCommandButton
            }
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

    private var fabExplicitAnchorFrames: [OnboardingTooltipAnchor: CGRect] {
        guard !fabAnchorFrame.isNull, !fabAnchorFrame.isEmpty else { return [:] }
        return [.floatingCommandButton: fabAnchorFrame]
    }

    private func dismissCommandLine() {
        if session.commandPalette.isPresented {
            session.commandPalette.setPresented(false)
        }
    }
}
