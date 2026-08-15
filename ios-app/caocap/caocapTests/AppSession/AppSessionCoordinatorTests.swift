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

    @Test func goHomeActionCollapsesWorkspaceAndDismissesCommandLine() {
        let fixture = makeSessionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = fixture.session
        session.ensureActionsConfigured()
        let draft = session.createSession()
        session.openCommandLine()

        _ = session.actionDispatcher.perform(.goHome, source: .user)

        #expect(session.sessionPath.isEmpty)
        #expect(session.activeSessionID == nil)
        #expect(session.sessionLibrary.session(id: draft.id) == nil)
        #expect(!session.commandPalette.isPresented)
    }

    @Test func goRootKeepsSessionOpen() {
        let fixture = makeSessionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = fixture.session
        session.ensureActionsConfigured()
        let draft = session.createSession()

        _ = session.actionDispatcher.perform(.goRoot, source: .user)

        #expect(session.sessionPath == [draft.id])
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

    @Test func globalFABNavigationSelectsChatTab() {
        let session = AppSessionCoordinator()
        session.selectedHomeTab = .home

        session.openChatTab()

        #expect(session.selectedHomeTab == .chat)
        #expect(session.sessionPath.isEmpty)
    }

    @Test func globalFABCommandActionReturnsHomeBeforeOpeningCommandLine() {
        let session = AppSessionCoordinator()
        session.selectedHomeTab = .chat

        session.openHomeCommandLine()

        #expect(session.selectedHomeTab == .home)
        #expect(session.commandPalette.isPresented)
    }

    @Test func middleFABActionOpensCommandLine() {
        let session = AppSessionCoordinator()

        session.openCommandLine()

        #expect(session.commandPalette.isPresented)
        #expect(!session.coCaptain.isPresented)
    }

    @Test func newSessionIsTransientUnfocusedAndUsesSharedRootCanvas() async {
        let fixture = makeSessionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let draft = fixture.session.createSession()
        while fixture.session.coCaptain.isConversationArchiveLoading {
            await Task.yield()
        }

        #expect(fixture.session.sessionPath == [draft.id])
        #expect(fixture.session.activeSessionID == draft.id)
        #expect(!fixture.session.shouldFocusSessionComposer)
        #expect(fixture.session.sessionLibrary.sessions.isEmpty)
        #expect(fixture.session.router.currentWorkspace == .root)
        #expect(fixture.session.coCaptain.store === fixture.session.router.rootStore)
        #expect(fixture.session.coCaptain.activeConversationID == draft.id)
    }

    @Test func firstUserMessageCommitsAndTitlesDraft() throws {
        let fixture = makeSessionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let draft = fixture.session.createSession()

        fixture.session.coCaptain.onConversationMetadataChange?(
            CoCaptainConversationMetadata(
                title: "Plan the launch",
                previewText: "Plan the launch with me",
                updatedAt: Date(),
                hasUserMessages: true
            )
        )

        let committed = try #require(fixture.session.sessionLibrary.session(id: draft.id))
        #expect(committed.title == "Plan the launch")
        #expect(committed.previewText == "Plan the launch with me")
        #expect(!fixture.session.sessionLibrary.isDraft(id: draft.id))
    }

    @Test func openingPreviousSessionUsesRootCanvasWithoutFocusingComposer() async {
        let fixture = makeSessionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let summary = fixture.session.sessionLibrary.createDraft()
        fixture.session.sessionLibrary.commit(
            id: summary.id,
            title: "Existing mission",
            previewText: "Continue where we stopped"
        )

        fixture.session.openSession(id: summary.id)
        while fixture.session.coCaptain.isConversationArchiveLoading {
            await Task.yield()
        }

        #expect(fixture.session.sessionPath == [summary.id])
        #expect(fixture.session.activeSessionID == summary.id)
        #expect(!fixture.session.shouldFocusSessionComposer)
        #expect(fixture.session.router.currentWorkspace == .root)
        #expect(fixture.session.coCaptain.store === fixture.session.router.rootStore)
        #expect(fixture.session.coCaptain.activeConversationID == summary.id)
    }

    @Test func nativeBackPreservesCommittedSession() {
        let fixture = makeSessionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let summary = fixture.session.sessionLibrary.createDraft()
        fixture.session.sessionLibrary.commit(
            id: summary.id,
            title: "Saved mission",
            previewText: "A durable conversation"
        )
        fixture.session.openSession(id: summary.id)

        fixture.session.sessionPath = []
        fixture.session.handleSessionPathChange([])

        #expect(fixture.session.activeSessionID == nil)
        #expect(fixture.session.sessionLibrary.session(id: summary.id) != nil)
    }

    @Test func nativeBackDiscardsUntouchedDraftWithoutDeletingRootCanvas() async {
        let fixture = makeSessionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let draft = fixture.session.createSession()
        fixture.session.sessionPath = []
        fixture.session.handleSessionPathChange([])
        await fixture.session.waitForDraftCleanup()

        #expect(fixture.session.sessionLibrary.session(id: draft.id) == nil)
        #expect(fixture.session.router.currentWorkspace == .root)
        #expect(fixture.session.router.projects.isEmpty)
    }

    private func makeSessionFixture() -> (
        root: URL,
        session: AppSessionCoordinator
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSessionCoordinatorTests-\(UUID().uuidString)")
        let sessionPersistence = SessionPersistenceService(
            baseDirectory: root.appendingPathComponent("sessions")
        )
        let library = SessionLibrary(persistence: sessionPersistence)
        let projectPersistence = ProjectPersistenceService(baseDirectory: root)
        let coCaptain = CoCaptainViewModel(
            conversationStore: CoCaptainConversationStore(
                baseDirectory: root.appendingPathComponent("conversations")
            )
        )
        return (
            root,
            AppSessionCoordinator(
                sessionLibrary: library,
                projectPersistence: projectPersistence,
                coCaptain: coCaptain
            )
        )
    }
}
