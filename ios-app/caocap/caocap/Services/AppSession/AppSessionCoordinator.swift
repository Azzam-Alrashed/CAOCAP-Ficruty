import Foundation
import Observation
import OSLog
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Orchestrates root-session state: routing, actions, palette binding, sheets, and onboarding hooks.
@MainActor
@Observable
final class AppSessionCoordinator {
    var sessionLibrary: SessionLibrary
    var selectedHomeTab: HomeTab = .home
    var sessionPath: [UUID] = []
    private(set) var activeSessionID: UUID?
    private(set) var shouldFocusSessionComposer = false
    var router: AppRouter
    var commandPalette = CommandPaletteViewModel()
    var coCaptain: CoCaptainViewModel
    private(set) var actionDispatcher = AppActionDispatcher()

    var showingPurchaseSheet = false
    var showingUsage = false
    var showingSignIn = false
    var showingSettings = false
    var showingSnapshotBrowser = false
    var showingProfile = false
    var showingHelp = false
    var showingAppIconPicker = false
    var showConfetti = false
    /// Graduation copy shown with tutorial-completion confetti only.
    var showTutorialGraduationBanner = false
    var showingCopilotCall = false
    var showingCopilotPicker = false
    var activeCopilotCallMode: CopilotInteractionMode = .video
    var selectedCopilot: CopilotPersona = UserProfileStore().loadSelectedCopilot()
    @ObservationIgnored var copilotCallViewModel: CopilotCallViewModel?

    var currentScale: CGFloat = 1.0
    var isLaunching = true
    var appUpdateService = AppUpdateService.shared
    var viewport = ViewportState()
    var containerSize: CGSize = .zero
    /// Matches `LaunchScreenView` entrance length so the brand animation can land.
    /// Tests may shorten this to avoid sleeping for the full brand dwell.
    var launchMinimumVisibleDuration: Duration = .milliseconds(1_200)
    /// Hard cap so splash never blocks interaction longer than the old fixed delay.
    var launchMaximumVisibleDuration: Duration = .seconds(2.5)
    @ObservationIgnored private var launchDismissTask: Task<Void, Never>?
    @ObservationIgnored private let projectPersistence: ProjectPersistenceService


    var intro = IntroCoordinator()
    var personalization = PersonalizationOnboardingCoordinator()
    var onboarding = OnboardingCoordinator()

    var coCaptainDetent: PresentationDetent = .large
    var coCaptainAllowsMediumDetent = false

    private var actionsConfigured = false
    @ObservationIgnored private var activeUndoManager: UndoManager?
    

    init(
        sessionLibrary: SessionLibrary? = nil,
        projectPersistence: ProjectPersistenceService = ProjectPersistenceService(),
        coCaptain: CoCaptainViewModel? = nil
    ) {
        self.sessionLibrary = sessionLibrary ?? SessionLibrary()
        self.projectPersistence = projectPersistence
        self.coCaptain = coCaptain ?? CoCaptainViewModel()
        self.router = AppRouter(projectPersistence: projectPersistence)
        onboarding.onTutorialCompleted = { [weak self] in
            self?.celebrateTutorialGraduation()
        }
    }

    private enum StorageKey {
        static let gridOpacity = "grid_opacity"
        static let lastGridOpacity = "last_grid_opacity"
    }

    var gridOpacity: Double {
        get {
            if UserDefaults.standard.object(forKey: StorageKey.gridOpacity) == nil {
                return 0.1
            }
            return UserDefaults.standard.double(forKey: StorageKey.gridOpacity)
        }
        set { UserDefaults.standard.set(newValue, forKey: StorageKey.gridOpacity) }
    }

    private var lastGridOpacity: Double {
        get {
            if UserDefaults.standard.object(forKey: StorageKey.lastGridOpacity) == nil {
                return 0.1
            }
            return UserDefaults.standard.double(forKey: StorageKey.lastGridOpacity)
        }
        set { UserDefaults.standard.set(newValue, forKey: StorageKey.lastGridOpacity) }
    }

    var coCaptainAvailableDetents: Set<PresentationDetent> {
        coCaptainAllowsMediumDetent ? [.medium, .large] : [.large]
    }

    // MARK: - Lifecycle

    func bootstrap(undoManager: UndoManager?) {
        activeUndoManager = undoManager
        selectedCopilot = UserProfileStore().loadSelectedCopilot()
        bindCommandPalette()
        configureActionsIfNeeded()
        actionDispatcher.refreshCopilotActionTitle()
        syncViewportWithActiveStore()
        attachUndoManager(undoManager)
        coCaptain.configureProjectSession(store: router.rootStore, dispatcher: actionDispatcher)

        scheduleLaunchOverlayDismissal()
    }

    /// Dismisses the launch overlay when the session is ready, after a short brand
    /// minimum and before a hard maximum — not a fixed cosmetic sleep.
    private func scheduleLaunchOverlayDismissal() {
        launchDismissTask?.cancel()
        launchDismissTask = Task { @MainActor [weak self] in
            await self?.dismissLaunchOverlayWhenReady()
        }
    }

    private func dismissLaunchOverlayWhenReady() async {
        let clock = ContinuousClock()
        let started = clock.now

        await waitForLaunchReadiness()
        guard !Task.isCancelled else { return }

        let readyAt = clock.now
        let minAt = started + launchMinimumVisibleDuration
        let maxAt = started + launchMaximumVisibleDuration
        let dismissAt = min(max(readyAt, minAt), maxAt)
        let remaining = dismissAt - clock.now
        if remaining > .zero {
            try? await Task.sleep(for: remaining)
        }
        guard !Task.isCancelled else { return }

        finishLaunchOverlayDismissal()
    }

    /// Yield so SwiftUI can commit the launch root's first frame before transitioning.
    private func waitForLaunchReadiness() async {
        await Task.yield()
    }

    private func finishLaunchOverlayDismissal() {
        guard isLaunching else { return }
        withAnimation(.easeInOut(duration: 0.5)) {
            isLaunching = false
        }
        PerformanceSignposts.endLaunch()
        if !intro.shouldPresent {
            startInteractiveOnboardingIfNeeded()
        }
    }

    func handleWorkspaceChange(undoManager: UndoManager?) {
        activeUndoManager = undoManager
        bindCommandPalette()
        attachUndoManager(undoManager)
        coCaptain.configureProjectSession(store: router.rootStore, dispatcher: actionDispatcher)
        syncCommandPaletteActions()
        syncViewportWithActiveStore()
    }

    func updateContainerSize(_ size: CGSize) {
        containerSize = size
    }

    /// Called when the motivational intro tour finishes. Presents personalization if needed.
    func finishIntroFlow() {
        startInteractiveOnboardingIfNeeded()
    }

    /// Called when the personalization survey finishes or is skipped.
    func finishPersonalizationFlow() {
        selectedCopilot = UserProfileStore().loadSelectedCopilot()
        actionDispatcher.refreshCopilotActionTitle()
        startInteractiveOnboardingIfNeeded()
    }

    func updateSelectedCopilot(_ persona: CopilotPersona) {
        UserProfileStore().saveSelectedCopilot(persona)
        selectedCopilot = persona
        actionDispatcher.refreshCopilotActionTitle()
    }

    /// Re-opens the intro tour while personalization remains in progress.
    func returnToIntroFromPersonalization() {
        intro.reset()
    }

    /// Starts the gesture tutorial only when intro and personalization are both complete.
    func startInteractiveOnboardingIfNeeded() {
        guard !intro.shouldPresent, !personalization.shouldPresent else { return }
        onboarding.startIfNeeded()
    }

    private func celebrateTutorialGraduation() {
        HapticsManager.shared.notification(.success)
        presentConfetti(showGraduationBanner: true)
    }

    /// Plays confetti in the top chrome window so it sits above sheets and chrome.
    func presentConfetti(duration: TimeInterval = 2.5, showGraduationBanner: Bool = false) {
        showTutorialGraduationBanner = showGraduationBanner
        showConfetti = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self else { return }
            self.showConfetti = false
            self.showTutorialGraduationBanner = false
        }
    }

    func eraseEverything(authManager: AuthenticationManager) async throws {
        guard !LocalGemmaModelManager.shared.isDownloadingLocalModel else {
            throw AppDataResetError.localModelDownloadInProgress
        }

        coCaptain.stopStreaming()
        onboarding.reset()

        let stores = [router.rootStore] + Array(router.projects.values)
        for store in stores {
            await store.prepareForDataReset()
        }

        authManager.signOut()
        LocalGemmaModelManager.shared.clearLocalModelCache()
        try await AppDataResetService.eraseLocalData()

        router = AppRouter(projectPersistence: projectPersistence)
        commandPalette = CommandPaletteViewModel()
        coCaptain = CoCaptainViewModel()
        sessionLibrary = SessionLibrary()
        actionDispatcher = AppActionDispatcher()
        intro = IntroCoordinator()
        personalization = PersonalizationOnboardingCoordinator()
        onboarding = OnboardingCoordinator()
        onboarding.onTutorialCompleted = { [weak self] in
            self?.celebrateTutorialGraduation()
        }
        viewport = ViewportState()
        currentScale = 1
        sessionPath = []
        activeSessionID = nil
        shouldFocusSessionComposer = false
        selectedHomeTab = .home
        actionsConfigured = false

        bindCommandPalette()
        configureActionsIfNeeded()
        attachUndoManager(activeUndoManager)
        coCaptain.configureProjectSession(store: router.rootStore, dispatcher: actionDispatcher)
        syncViewportWithActiveStore()
        launchDismissTask?.cancel()
        launchDismissTask = nil
        isLaunching = false
        PerformanceSignposts.endLaunch()
    }

    // MARK: - Undo

    func performUndo(undoManager: UndoManager?) {
        undoManager?.undo()
        router.activeStore.undoStackChanged += 1
    }

    func performRedo(undoManager: UndoManager?) {
        undoManager?.redo()
        router.activeStore.undoStackChanged += 1
    }

    var canUndo: Bool {
        _ = router.activeStore.undoStackChanged
        return activeUndoManager?.canUndo == true
    }

    func handleUndoStackChanged() {
        router.activeStore.undoStackChanged += 1
    }

    // MARK: - Onboarding + CoCaptain Presentation

    func handleCoCaptainPresentationChange(isPresented: Bool) {
        if isPresented {
            Task {
                await SubscriptionManager.shared.refreshEntitlements()
            }
        }
    }

    func requestCoCaptainExpandedPresentation() {
        coCaptainAllowsMediumDetent = false
        coCaptainDetent = .large
    }

    /// Dismisses session sheets that cover the canvas. Returns true if anything closed.
    @discardableResult
    func dismissPresentedSheets() -> Bool {
        var dismissed = false

        if coCaptain.isPresented {
            coCaptain.setPresented(false)
            dismissed = true
        }
        if commandPalette.isPresented {
            commandPalette.setPresented(false)
            dismissed = true
        }
        if showingSignIn {
            showingSignIn = false
            dismissed = true
        }
        if showingPurchaseSheet {
            showingPurchaseSheet = false
            dismissed = true
        }
        if showingSettings {
            showingSettings = false
            dismissed = true
        }
        if showingUsage {
            showingUsage = false
            dismissed = true
        }
        if showingSnapshotBrowser {
            showingSnapshotBrowser = false
            dismissed = true
        }
        if showingProfile {
            showingProfile = false
            dismissed = true
        }
        if showingHelp {
            showingHelp = false
            dismissed = true
        }
        if showingAppIconPicker {
            showingAppIconPicker = false
            dismissed = true
        }
        if showingCopilotPicker {
            showingCopilotPicker = false
            dismissed = true
        }
        return dismissed
    }

    /// Opens the Command Line from the FAB's middle long-press action.
    func openCommandLine() {
        coCaptain.setPresented(false)
        commandPalette.setPresented(true)
    }

    /// Creates a transient session. It becomes durable only after the first user message.
    @discardableResult
    func createSession() -> SessionSummary {
        let draft = sessionLibrary.createDraft()
        openSession(id: draft.id)
        return draft
    }

    /// Pushes a real session using Home's native navigation stack.
    func openSession(id: UUID, focusComposer: Bool = false) {
        guard let summary = sessionLibrary.session(id: id) else { return }
        selectedHomeTab = .chat
        activeSessionID = id
        shouldFocusSessionComposer = focusComposer
        sessionPath = [id]
        configureSession(summary)
    }

    /// Called when native back navigation (including edge swipe) changes the path.
    func handleSessionPathChange(_ path: [UUID]) {
        guard path.isEmpty, activeSessionID != nil else { return }
        closeActiveSession()
    }

    /// Pops the session using the same native path as the back button.
    func returnHome() {
        commandPalette.setPresented(false)
        coCaptain.setPresented(false)
        sessionPath = []
        closeActiveSession()
        router.goRoot()
        selectedHomeTab = .home
    }

    func openChatTab() {
        if selectedHomeTab != .chat {
            sessionPath = []
            closeActiveSession()
        }
        selectedHomeTab = .chat
    }

    /// Makes the Home surface active before presenting its canvas-local Command Line.
    func openHomeCommandLine() {
        dismissPresentedSheets()
        selectedHomeTab = .home
        openCommandLine()
    }

    /// Makes the Home canvas active before applying a viewport command from global chrome.
    func openHomeAndCenterCanvas() {
        dismissPresentedSheets()
        selectedHomeTab = .home
        centerActiveCanvas()
    }

    /// Resets Chat's navigation so returning to the tab always shows its session list.
    func leaveChatTab() {
        commandPalette.setPresented(false)
        sessionPath = []
        closeActiveSession()
    }

    // MARK: - Command Line

    func bindCommandPalette() {
        syncCommandPaletteActions()
        commandPalette.onExecute = { [weak self] actionID in
            guard let self else { return }
            _ = self.actionDispatcher.perform(actionID, source: .user)
        }
        commandPalette.onSubmitPrompt = { [weak self] prompt in
            self?.submitCoCaptainPrompt(prompt)
        }
    }

    func syncCommandPaletteActions() {
        let isRoot = router.currentWorkspace == .root
        commandPalette.actions = actionDispatcher.availableActions.filter { action in
            if isRoot && action.id == .goRoot { return false }
            if isRoot && action.id == .goBack { return false }
            return true
        }
    }

    func filteredPaletteActionIDs(at workspace: WorkspaceState) -> [AppActionID] {
        let isRoot = workspace == .root
        return actionDispatcher.availableActions.compactMap { action in
            if isRoot && action.id == .goRoot { return nil }
            if isRoot && action.id == .goBack { return nil }
            return action.id
        }
    }

    // MARK: - Private

    private func attachUndoManager(_ undoManager: UndoManager?) {
        router.activeStore.undoManager = undoManager
        router.rootStore.undoManager = undoManager
    }

    private func configureSession(_ summary: SessionSummary) {
        let store = router.rootStore
        attachUndoManager(activeUndoManager)
        coCaptain.onConversationMetadataChange = { [weak self] metadata in
            self?.handleConversationMetadata(metadata, sessionID: summary.id)
        }
        coCaptain.configureProjectSession(store: store, dispatcher: actionDispatcher)
        coCaptain.selectConversation(for: summary.id)
    }

    private func handleConversationMetadata(
        _ metadata: CoCaptainConversationMetadata,
        sessionID: UUID
    ) {
        guard activeSessionID == sessionID else { return }
        let sessionTitle = metadata.hasUserMessages ? metadata.title : "New Session"
        if metadata.hasUserMessages, sessionLibrary.isDraft(id: sessionID) {
            sessionLibrary.commit(
                id: sessionID,
                title: sessionTitle,
                previewText: metadata.previewText,
                updatedAt: metadata.updatedAt
            )
        } else {
            sessionLibrary.update(
                id: sessionID,
                title: sessionTitle,
                previewText: metadata.previewText,
                updatedAt: metadata.updatedAt
            )
        }
    }

    private func closeActiveSession() {
        guard let id = activeSessionID else { return }
        activeSessionID = nil
        shouldFocusSessionComposer = false
        coCaptain.onConversationMetadataChange = nil

        guard sessionLibrary.discardDraft(id: id) != nil else { return }
        coCaptain.deleteConversation(id: id)
    }

    func waitForDraftCleanup() async {
        await Task.yield()
    }

    private func syncViewportWithActiveStore() {
        viewport = ViewportState(
            offset: router.activeStore.viewportOffset,
            scale: router.activeStore.viewportScale
        )
        currentScale = viewport.scale
    }

    func centerActiveCanvas() {
        let fitScale = viewport.scaleToFitSpaceSketch(in: containerSize)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            viewport.flyTo(
                nodePosition: .zero,
                containerSize: containerSize,
                targetScale: fitScale
            )
            currentScale = fitScale
        }
        router.activeStore.updateViewport(offset: .zero, scale: fitScale)
    }

    func ensureActionsConfigured() {
        configureActionsIfNeeded()
    }

    private func configureActionsIfNeeded() {
        guard !actionsConfigured else { return }
        actionsConfigured = true
        configureActions()
    }

    private func configureActions() {
        actionDispatcher.register(.goHome) { [weak self] in
            self?.returnHome()
        }
        actionDispatcher.register(.goRoot) { [weak self] in
            guard let self else { return }
            self.router.goRoot()
            self.currentScale = 1.0
        }
        actionDispatcher.register(.goBack) { [weak self] in
            guard let self else { return }
            self.router.goBack()
        }
        actionDispatcher.register(.summonCoCaptain) { [weak self] in
            guard let self else { return }
            self.openChatTab()
        }
        actionDispatcher.register(.summonCopilotVideo) { [weak self] in
            self?.presentCopilotCall(mode: .video)
        }
        actionDispatcher.register(.undo) { [weak self] in
            guard let self else { return }
            self.performUndo(undoManager: self.activeUndoManager)
        }
        actionDispatcher.register(.redo) { [weak self] in
            guard let self else { return }
            self.performRedo(undoManager: self.activeUndoManager)
        }
        actionDispatcher.register(.toggleGrid) { [weak self] in
            self?.toggleGrid()
        }
        actionDispatcher.register(.proSubscription) { [weak self] in
            self?.presentPurchaseSheet()
        }
        actionDispatcher.register(.signIn) { [weak self] in
            self?.showingSignIn = true
        }
        actionDispatcher.register(.openSettings) { [weak self] in
            self?.showingSettings = true
        }
        actionDispatcher.register(.openUsage) { [weak self] in
            self?.showingUsage = true
        }
        actionDispatcher.register(.openProfile) { [weak self] in
            self?.showingProfile = true
        }
        actionDispatcher.register(.openWhatsApp) {
            if let url = SupportContact.whatsAppURL {
                UIApplication.shared.open(url)
            }
        }
        actionDispatcher.register(.help) { [weak self] in
            self?.showingHelp = true
        }
        actionDispatcher.register(.openAppIcon) { [weak self] in
            self?.showingAppIconPicker = true
        }
        actionDispatcher.register(.changeCopilot) { [weak self] in
            self?.commandPalette.setPresented(false)
            self?.showingCopilotPicker = true
        }
        actionDispatcher.register(.openSnapshotBrowser) { [weak self] in
            self?.showingSnapshotBrowser = true
        }
    }

    private func toggleGrid() {
        if gridOpacity > 0.0 {
            lastGridOpacity = gridOpacity
            gridOpacity = 0.0
        } else {
            gridOpacity = lastGridOpacity > 0.0 ? lastGridOpacity : 0.1
        }
    }

    private func presentPurchaseSheet() {
        if coCaptain.isPresented {
            coCaptain.setPresented(false)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(0.3))
                self?.showingPurchaseSheet = true
            }
        } else if showingProfile {
            showingProfile = false
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(0.3))
                self?.showingPurchaseSheet = true
            }
        } else if showingSettings {
            showingSettings = false
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(0.3))
                self?.showingPurchaseSheet = true
            }
        } else if showingUsage {
            showingUsage = false
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(0.3))
                self?.showingPurchaseSheet = true
            }
        } else {
            showingPurchaseSheet = true
        }
    }

    /// Opens the purchase sheet, dismissing any covering sheet first when needed.
    func requestPurchaseSheet() {
        presentPurchaseSheet()
    }

    /// Opens Account, dismissing the Command Line Settings sheet first when needed.
    func requestProfileSheet() {
        if showingSettings {
            showingSettings = false
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(0.3))
                self?.showingProfile = true
            }
        } else {
            showingProfile = true
        }
    }

    /// Opens the app icon picker, dismissing the Command Line Settings sheet first when needed.
    func requestAppIconPickerSheet() {
        if showingSettings {
            showingSettings = false
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(0.3))
                self?.showingAppIconPicker = true
            }
        } else {
            showingAppIconPicker = true
        }
    }

    private func submitCoCaptainPrompt(_ prompt: String) {
        if let step = onboarding.currentStep,
           onboarding.content(for: step)?.blocksCoCaptainPrompt == true {
            return
        }
        coCaptain.configureProjectSession(store: router.rootStore, dispatcher: actionDispatcher)
        if activeSessionID == nil {
            let draft = createSession()
            coCaptain.selectConversation(for: draft.id)
        }
        selectedHomeTab = .chat
        coCaptain.sendMessage(prompt, purpose: .standard)
    }

    private func prepareCoCaptainPresentation() {
        coCaptainAllowsMediumDetent = false
        coCaptainDetent = .large
    }

    private func presentCoCaptain() {
        prepareCoCaptainPresentation()
        coCaptain.setPresented(true)
    }

    func presentCopilotCall(mode: CopilotInteractionMode) {
        if coCaptain.isPresented {
            coCaptain.setPresented(false)
        }
        commandPalette.setPresented(false)

        let persona = selectedCopilot
        let context = copilotCallProjectContext()
        let viewModel = CopilotCallViewModel(
            mode: mode,
            persona: persona,
            projectContext: context
        )
        viewModel.onDismiss = { [weak self] in
            self?.dismissCopilotCall()
        }
        viewModel.onUpgrade = { [weak self] in
            self?.presentPurchaseSheet()
        }
        copilotCallViewModel = viewModel
        activeCopilotCallMode = mode
        showingCopilotCall = true
    }

    func dismissCopilotCall() {
        showingCopilotCall = false
        let viewModel = copilotCallViewModel
        copilotCallViewModel = nil
        Task {
            await viewModel?.liveService.stop()
        }
    }

    private func copilotCallProjectContext() -> String {
        let store = router.activeStore
        let workspaceLabel: String
        switch router.currentWorkspace {
        case .root:
            workspaceLabel = "root"
        case .project(let fileName):
            workspaceLabel = fileName
        }
        let nodeSummary = store.nodes
            .prefix(12)
            .map { "- \($0.title) (\($0.type.rawValue))" }
            .joined(separator: "\n")
        return """
        Workspace: \(workspaceLabel)
        Node count: \(store.nodes.count)
        Nodes:
        \(nodeSummary)
        """
    }
}
