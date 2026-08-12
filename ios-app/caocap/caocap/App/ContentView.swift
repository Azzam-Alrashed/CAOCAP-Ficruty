import SwiftUI

/// Root view that composes the active workspace canvas, global overlays, and session sheets.
///
/// Session orchestration lives in `AppSessionCoordinator`; this view wires UI only.
/// FAB, call chrome, confetti, and force-update live in a passthrough `UIWindow` above system sheets.
struct ContentView: View {
    @State private var session = AppSessionCoordinator()
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                workspaceCanvas

                if session.commandPalette.miniAppPreviewContext == nil {
                    CommandPaletteView(viewModel: session.commandPalette)
                }

                KeyboardShortcutBridge(
                    onOpenCommandPalette: {
                        session.commandPalette.setPresented(true)
                    },
                    onSummonCoCaptain: {
                        _ = session.actionDispatcher.perform(.summonCoCaptain, source: .user)
                    },
                    onUndo: {
                        _ = session.actionDispatcher.perform(.undo, source: .user)
                    },
                    onRedo: {
                        _ = session.actionDispatcher.perform(.redo, source: .user)
                    }
                )
            }
            .onboardingTooltipOverlay(
                isCommandPalettePresented: session.commandPalette.isPresented,
                // FAB tooltips render in the chrome overlay window so they sit above the FAB.
                rendersAnchor: {
                    !$0.isCanvasLocal
                        && !$0.isPreviewShellLocal
                        && !$0.isCoCaptainLocal
                        && $0 != .floatingCommandButton
                }
            )
            .background(Color.black.ignoresSafeArea())
            .overlay { launchOverlay }
            .overlay { introOverlay }
            .overlay { personalizationOverlay }
            .modifier(AppSheetsModifier(session: session))
            .modifier(AppSessionLifecycle(
                session: session,
                geometry: geometry,
                undoManager: undoManager
            ))
            .onAppear {
                GlobalFloatingChromeController.shared.install(session: session)
            }
            .onDisappear {
                GlobalFloatingChromeController.shared.uninstall()
            }
        }
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
                presentedMiniApp: $session.presentedMiniApp,
                selectedNodeDetail: $session.selectedNodeDetail,
                canvasFocusNodeID: session.canvasFocusNodeID,
                commandPalette: session.commandPalette,
                onNavigateToSubCanvas: { fileName in
                    session.handleSubCanvasNavigation(fileName: fileName)
                },
                onRecoverUnsupportedProject: {
                    session.router.createFreshMiniAppCanvas()
                },
                onFlyToNode: { session.focusCanvasNode($0) }
            )
        case .project(let fileName):
            WorkspaceCanvasView(
                store: session.router.activeStore,
                canvasID: "project_canvas_\(fileName)",
                viewport: $session.viewport,
                currentScale: $session.currentScale,
                presentedMiniApp: $session.presentedMiniApp,
                selectedNodeDetail: $session.selectedNodeDetail,
                canvasFocusNodeID: session.canvasFocusNodeID,
                commandPalette: session.commandPalette,
                onNavigateToSubCanvas: { fileName in
                    session.handleSubCanvasNavigation(fileName: fileName)
                },
                onRecoverUnsupportedProject: {
                    session.router.createFreshMiniAppCanvas()
                },
                onFlyToNode: { session.focusCanvasNode($0) }
            )
        }
    }

    @ViewBuilder
    private var launchOverlay: some View {
        if session.isLaunching {
            LaunchScreenView()
                .transition(.opacity)
                .zIndex(100)
        }
    }

    @ViewBuilder
    private var introOverlay: some View {
        if !session.isLaunching && session.intro.shouldPresent {
            IntroView(coordinator: session.intro) {
                session.finishIntroFlow()
            }
            .transition(.opacity)
            .zIndex(80)
        }
    }

    @ViewBuilder
    private var personalizationOverlay: some View {
        if !session.isLaunching
            && !session.intro.shouldPresent
            && session.personalization.shouldPresent {
            PersonalizationOnboardingView(
                coordinator: session.personalization,
                onBackToIntro: {
                    session.returnToIntroFromPersonalization()
                },
                onFinish: {
                    session.finishPersonalizationFlow()
                }
            )
            .transition(.opacity)
            .zIndex(75)
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthenticationManager())
}
