import SwiftUI
import UIKit

/// Transparent window that sits above system sheets and only accepts hits inside
/// explicitly registered chrome frames, such as the call pill.
///
/// Must not become the key window — otherwise overlay taps steal first-responder
/// ownership from the main app window and the Command Line keyboard never appears.
@MainActor
final class PassthroughChromeWindow: UIWindow {
    /// Screen-space rects that should receive touches. Everything else passes through.
    var interactiveFrames: [CGRect] = []
    /// When true, the window captures all hits (force-update and similar blocking overlays).
    var blocksAllPassthrough = false

    override var canBecomeKey: Bool { false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if blocksAllPassthrough {
            return super.hitTest(point, with: event)
        }
        let allowed = interactiveFrames.contains { frame in
            frame.insetBy(dx: -6, dy: -6).contains(point)
        }
        guard allowed else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// Shared closures + session pointer so the overlay hosting controller is created once.
@Observable
@MainActor
final class GlobalFloatingChromeBridge {
    var session: AppSessionCoordinator?
    var onInteractiveFramesChange: ([CGRect]) -> Void = { _ in }
    var onBlocksAllPassthroughChange: (Bool) -> Void = { _ in }
}

/// Owns the high-level chrome window and refreshes its SwiftUI root.
///
/// Uses a process-wide shared instance so SwiftUI recreating `ContentView` state
/// cannot leave an orphaned overlay window.
@MainActor
final class GlobalFloatingChromeController {
    static let shared = GlobalFloatingChromeController()

    private var window: PassthroughChromeWindow?
    private var hostingController: UIHostingController<GlobalFloatingChromeView>?
    private let bridge = GlobalFloatingChromeBridge()

    private init() {}

    func install(session: AppSessionCoordinator) {
        bridge.session = session
        bridge.onInteractiveFramesChange = { [weak self] frames in
            self?.window?.interactiveFrames = frames
        }
        bridge.onBlocksAllPassthroughChange = { [weak self] blocksAll in
            self?.window?.blocksAllPassthrough = blocksAll
        }

        removeOrphanedChromeWindows(keeping: window)

        if window != nil {
            return
        }

        guard let scene = activeWindowScene() else { return }

        let hosting = UIHostingController(rootView: GlobalFloatingChromeView(bridge: bridge))
        hosting.view.backgroundColor = .clear
        hostingController = hosting

        let overlay = PassthroughChromeWindow(windowScene: scene)
        overlay.windowLevel = .alert + 1
        overlay.backgroundColor = .clear
        overlay.rootViewController = hosting
        overlay.isHidden = false
        window = overlay
    }

    func uninstall() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        hostingController = nil
        bridge.session = nil
        removeOrphanedChromeWindows(keeping: nil)
    }

    /// Plays confetti above all app UI via the chrome overlay window.
    func presentConfetti(duration: TimeInterval = 2.5, showGraduationBanner: Bool = false) {
        bridge.session?.presentConfetti(duration: duration, showGraduationBanner: showGraduationBanner)
    }

    /// Returns keyboard/first-responder ownership to the primary app window.
    /// Needed after interactions that may have briefly key'd a different window.
    static func makeMainAppWindowKey() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard let scene else { return }

        let appWindow = scene.windows.first {
            !($0 is PassthroughChromeWindow)
                && $0.windowLevel == .normal
                && !$0.isHidden
                && $0.alpha > 0
        }
        appWindow?.makeKey()
    }

    private func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    }

    private func removeOrphanedChromeWindows(keeping kept: PassthroughChromeWindow?) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for case let chrome as PassthroughChromeWindow in scene.windows where chrome !== kept {
                chrome.isHidden = true
                chrome.rootViewController = nil
            }
        }
    }
}

/// Call chrome, confetti, and force-update rendered in the overlay window above sheets.
struct GlobalFloatingChromeView: View {
    @Bindable var bridge: GlobalFloatingChromeBridge

    @State private var callChromeFrame: CGRect = .null

    var body: some View {
        Group {
            if let session = bridge.session {
                chromeBody(session: session)
            } else {
                Color.clear
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func chromeBody(session: AppSessionCoordinator) -> some View {
        @Bindable var session = session
        let showsForceUpdate = shouldShowForceUpdate(session)

        ZStack {
            if shouldShowCallChrome(session), let callViewModel = session.copilotCallViewModel {
                CopilotCallView(
                    viewModel: callViewModel,
                    onFrameChange: { frame in
                        callChromeFrame = frame
                        publishInteractiveFrames(session: session)
                    }
                )
                .transition(.opacity)
            }

            if session.showConfetti {
                confettiOverlay(showGraduationBanner: session.showTutorialGraduationBanner)
                    .transition(.opacity)
                    .zIndex(1_000)
            }

            if showsForceUpdate, let update = session.appUpdateService.availableUpdate {
                AppUpdatePromptView(update: update, onUpdate: {})
                    .transition(.opacity)
                    .zIndex(2_000)
            }
        }
        .onAppear {
            publishInteractiveFrames(session: session)
            bridge.onBlocksAllPassthroughChange(showsForceUpdate)
        }
        .onChange(of: showsForceUpdate) { _, blocksAll in
            bridge.onBlocksAllPassthroughChange(blocksAll)
            publishInteractiveFrames(session: session)
        }
        .onChange(of: session.showingCopilotCall) { _, showing in
            if !showing {
                callChromeFrame = .null
                publishInteractiveFrames(session: session)
            }
        }
        .onChange(of: session.isLaunching) { _, _ in
            refreshChromeVisibility(session: session)
        }
        .onChange(of: session.intro.shouldPresent) { _, _ in
            refreshChromeVisibility(session: session)
        }
        .onChange(of: session.personalization.shouldPresent) { _, _ in
            refreshChromeVisibility(session: session)
        }
        .onChange(of: session.appUpdateService.availableUpdate) { _, _ in
            refreshChromeVisibility(session: session)
        }
    }

    @ViewBuilder
    private func confettiOverlay(showGraduationBanner: Bool) -> some View {
        ZStack {
            ConfettiCelebrationView()
            if showGraduationBanner {
                VStack {
                    Spacer()
                    TutorialGraduationBanner()
                        .padding(.horizontal, 24)
                        .padding(.bottom, 48)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func shouldShowForceUpdate(_ session: AppSessionCoordinator) -> Bool {
        !session.isLaunching
            && session.appUpdateService.shouldPresentUpdatePrompt
            && session.appUpdateService.availableUpdate != nil
    }

    private func shouldShowCallChrome(_ session: AppSessionCoordinator) -> Bool {
        session.showingCopilotCall
            && !session.isLaunching
            && !session.intro.shouldPresent
            && !session.personalization.shouldPresent
            && !shouldShowForceUpdate(session)
    }

    private func refreshChromeVisibility(session: AppSessionCoordinator) {
        if !shouldShowCallChrome(session) {
            callChromeFrame = .null
        }
        bridge.onBlocksAllPassthroughChange(shouldShowForceUpdate(session))
        publishInteractiveFrames(session: session)
    }

    private func publishInteractiveFrames(session: AppSessionCoordinator) {
        guard shouldShowCallChrome(session) else {
            bridge.onInteractiveFramesChange([])
            return
        }
        var frames: [CGRect] = []
        if session.showingCopilotCall, !callChromeFrame.isNull, !callChromeFrame.isEmpty {
            frames.append(callChromeFrame)
        }
        bridge.onInteractiveFramesChange(frames)
    }
}
