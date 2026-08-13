import SwiftUI

/// Root view that switches between launch, onboarding, and the signed-in app shell.
///
/// Session orchestration lives in `AppSessionCoordinator`; this view wires UI only.
/// FAB, call chrome, confetti, and force-update live in a passthrough `UIWindow` above system sheets.
struct ContentView: View {
    @State private var session = AppSessionCoordinator()
    @Namespace private var sessionTransitionNamespace
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        GeometryReader { geometry in
            rootContent
            .background(Color.black.ignoresSafeArea())
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

    /// These roots are mutually exclusive. The app shell is not mounted beneath onboarding.
    @ViewBuilder
    private var rootContent: some View {
        if session.isLaunching {
            LaunchScreenView()
        } else if session.intro.shouldPresent {
            IntroView(coordinator: session.intro) {
                session.finishIntroFlow()
            }
        } else if session.personalization.shouldPresent {
            PersonalizationOnboardingView(
                coordinator: session.personalization,
                onBackToIntro: {
                    session.returnToIntroFromPersonalization()
                },
                onFinish: {
                    session.finishPersonalizationFlow()
                }
            )
        } else {
            appContent
        }
    }

    private var appContent: some View {
        destinationContent
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
            .modifier(AppSheetsModifier(session: session))
    }

    private var destinationContent: some View {
        NavigationStack(path: destinationPath) {
            HomeView(
                sessionPreview: SessionCanvasPreview(viewport: session.viewport),
                onOpenSession: session.openSession,
                transitionNamespace: sessionTransitionNamespace
            )
            .navigationDestination(for: AppDestination.self) { destination in
                if destination == .workspace {
                    workspaceContent
                        .navigationTransition(
                            .zoom(
                                sourceID: SessionTransitionID.latest,
                                in: sessionTransitionNamespace
                            )
                        )
                        .toolbarVisibility(.hidden, for: .navigationBar, .tabBar)
                        .background(InteractivePopGestureDisabler())
                }
            }
        }
    }

    private var destinationPath: Binding<[AppDestination]> {
        Binding(
            get: {
                session.destination == .workspace ? [.workspace] : []
            },
            set: { path in
                if path.last == .workspace {
                    session.openSession()
                } else {
                    session.returnHome()
                }
            }
        )
    }

    private var workspaceContent: some View {
        ZStack {
            workspaceCanvas

            CommandPaletteView(viewModel: session.commandPalette)

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
                canvasID: "project_canvas_\(fileName)",
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

#Preview {
    ContentView()
        .environment(AuthenticationManager())
}
