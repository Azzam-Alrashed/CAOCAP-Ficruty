import CoreGraphics
import Foundation
import Testing
@testable import caocap

@MainActor
struct AppSessionCoordinatorTests {

    @Test func toggleGridActionPersistsOpacity() {
        let session = AppSessionCoordinator()
        session.ensureActionsConfigured()
        session.gridOpacity = 0.5

        _ = session.actionDispatcher.perform(.toggleGrid, source: .user)

        #expect(session.gridOpacity == 0.0)

        _ = session.actionDispatcher.perform(.toggleGrid, source: .user)

        #expect(session.gridOpacity == 0.5)
    }

    @Test func goRootActionResetsScale() {
        let session = AppSessionCoordinator()
        session.ensureActionsConfigured()
        session.currentScale = 2.0

        _ = session.actionDispatcher.perform(.goRoot, source: .user)

        #expect(session.currentScale == 1.0)
        #expect(session.router.currentWorkspace == .root)
    }

    @Test func filteredPaletteActionsHideRootNavigationAtRoot() {
        let session = AppSessionCoordinator()
        session.router.currentWorkspace = .root

        let actionIDs = session.filteredPaletteActionIDs(at: .root)

        #expect(!actionIDs.contains(.goRoot))
        #expect(!actionIDs.contains(.goBack))
    }

    @Test func whatsAppActionIsConfiguredInDispatcher() {
        let session = AppSessionCoordinator()
        session.ensureActionsConfigured()

        let result = session.actionDispatcher.perform(.openWhatsApp, source: .user)

        #expect(result.executed)
        #expect(SupportContact.whatsAppURL?.absoluteString == "https://wa.me/966559279486")
    }

    @Test func helpAppActionPresentsHelpSheet() {
        let session = AppSessionCoordinator()
        session.ensureActionsConfigured()

        _ = session.actionDispatcher.perform(.help, source: .user)

        #expect(session.showingHelp)
    }

    @Test func bootstrapDismissesLaunchAfterReadyMinimumNotFixedTwoPointFiveSeconds() async {
        let session = AppSessionCoordinator()
        session.launchMinimumVisibleDuration = .milliseconds(20)
        session.launchMaximumVisibleDuration = .milliseconds(200)
        #expect(session.isLaunching)

        session.bootstrap(undoManager: nil)

        try? await Task.sleep(for: .milliseconds(80))
        #expect(!session.isLaunching)
    }

    @Test func bootstrapHonorsLaunchMaximumVisibleDuration() async {
        let session = AppSessionCoordinator()
        session.launchMinimumVisibleDuration = .seconds(10)
        session.launchMaximumVisibleDuration = .milliseconds(30)
        #expect(session.isLaunching)

        session.bootstrap(undoManager: nil)

        try? await Task.sleep(for: .milliseconds(100))
        #expect(!session.isLaunching)
    }

    @Test func floatingCommandTapOpensOmniboxWhenIdle() {
        let session = AppSessionCoordinator()

        session.handleFloatingCommandButtonTap()

        #expect(session.commandPalette.isPresented)
    }
}
