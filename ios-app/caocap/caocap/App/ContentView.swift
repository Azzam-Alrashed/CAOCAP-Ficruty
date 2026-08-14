import SwiftUI

/// Root view that switches between launch, onboarding, and the signed-in app shell.
///
/// Session orchestration lives in `AppSessionCoordinator`; this view wires UI only.
/// Call chrome, confetti, and force-update live in a passthrough `UIWindow` above system sheets.
struct ContentView: View {
    @State private var session = AppSessionCoordinator()
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
        HomeView(session: session)
            .onboardingTooltipOverlay(
                isCommandPalettePresented: session.commandPalette.isPresented,
                // Canvas-local anchors, including its FAB, render inside the canvas sheet.
                rendersAnchor: {
                    !$0.isCanvasLocal
                        && !$0.isPreviewShellLocal
                        && !$0.isCoCaptainLocal
                        && $0 != .floatingCommandButton
                }
            )
            .modifier(AppSheetsModifier(session: session))
    }

}

#Preview {
    ContentView()
        .environment(AuthenticationManager())
}
