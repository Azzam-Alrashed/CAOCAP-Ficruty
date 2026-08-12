import SwiftUI

/// Attaches session lifecycle handlers: workspace sync, onboarding, undo bridge, and geometry.
struct AppSessionLifecycle: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var session: AppSessionCoordinator
    let geometry: GeometryProxy
    let undoManager: UndoManager?

    func body(content: Content) -> some View {
        content
            .onChange(of: session.router.currentWorkspace) {
                session.handleWorkspaceChange(undoManager: undoManager)
            }
            .onAppear {
                session.bootstrap(undoManager: undoManager)
                session.updateContainerSize(geometry.size)
            }
            .task {
                await session.appUpdateService.checkForUpdate()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task {
                    await SubscriptionManager.shared.refreshEntitlements()
                }
            }
            .onChange(of: session.coCaptain.isPresented) { _, isPresented in
                session.handleCoCaptainPresentationChange(isPresented: isPresented)
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in
                session.handleUndoStackChanged()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in
                session.handleUndoStackChanged()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCommandPalette)) { _ in
                session.commandPalette.setPresented(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .summonCoCaptain)) { _ in
                _ = session.actionDispatcher.perform(.summonCoCaptain, source: .user)
            }
            .onReceive(NotificationCenter.default.publisher(for: .performUndo)) { _ in
                session.performUndo(undoManager: undoManager)
            }
            .onReceive(NotificationCenter.default.publisher(for: .performRedo)) { _ in
                session.performRedo(undoManager: undoManager)
            }
            .onChange(of: geometry.size) { _, newSize in
                session.updateContainerSize(newSize)
            }
            .environment(session.onboarding)
    }
}
