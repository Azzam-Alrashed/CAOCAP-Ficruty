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
    var router = AppRouter()
    var commandPalette = CommandPaletteViewModel()
    var coCaptain = CoCaptainViewModel()
    private(set) var actionDispatcher = AppActionDispatcher()

    var showingFileImporter = false
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
    /// Fullscreen mini-app preview sheet opened by tapping a mini-app node.
    var presentedMiniApp: SpatialNode?
    /// Non-mini-app node inspector sheet opened from the canvas.
    var selectedNodeDetail: SpatialNode?
    var activeCopilotCallMode: CopilotInteractionMode = .video
    var selectedCopilot: CopilotPersona = UserProfileStore().loadSelectedCopilot()
    @ObservationIgnored var copilotCallViewModel: CopilotCallViewModel?

    var currentScale: CGFloat = 1.0
    var isLaunching = true
    var appUpdateService = AppUpdateService.shared
    var viewport = ViewportState()
    var nodeSizes: [UUID: CGSize] = [:]
    var containerSize: CGSize = .zero
    /// Briefly highlights a node after fly-to navigation from CoCaptain or the command palette.
    var canvasFocusNodeID: UUID?
    @ObservationIgnored private var canvasFocusClearTask: Task<Void, Never>?
    /// Matches `LaunchScreenView` entrance length so the brand animation can land.
    /// Tests may shorten this to avoid sleeping for the full brand dwell.
    var launchMinimumVisibleDuration: Duration = .milliseconds(1_200)
    /// Hard cap so splash never blocks interaction longer than the old fixed delay.
    var launchMaximumVisibleDuration: Duration = .seconds(2.5)
    @ObservationIgnored private var launchDismissTask: Task<Void, Never>?

    var exportURL: URL?
    var showExportSheet = false

    var intro = IntroCoordinator()
    var personalization = PersonalizationOnboardingCoordinator()
    var onboarding = OnboardingCoordinator()

    var coCaptainDetent: PresentationDetent = .large
    var coCaptainAllowsMediumDetent = false

    private var actionsConfigured = false
    @ObservationIgnored private var activeUndoManager: UndoManager?
    

    init() {
        onboarding.onTutorialCompleted = { [weak self] in
            self?.celebrateTutorialGraduation()
        }
    }

    private enum StorageKey {
        static let gridOpacity = "grid_opacity"
        static let lastGridOpacity = "last_grid_opacity"
        static let showingHUD = "showing_hud"
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

    var showingHUD: Bool {
        get { UserDefaults.standard.bool(forKey: StorageKey.showingHUD) }
        set { UserDefaults.standard.set(newValue, forKey: StorageKey.showingHUD) }
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
        coCaptain.configureProjectSession(store: router.activeStore, dispatcher: actionDispatcher)

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

    /// Root `ProjectStore` loads synchronously in `AppRouter` before UI appears.
    /// Yield so SwiftUI can commit the first canvas frame under the overlay.
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
        coCaptain.configureProjectSession(store: router.activeStore, dispatcher: actionDispatcher)
        syncCommandPaletteActions()
        commandPalette.nodes = router.activeStore.nodes
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
        onboarding.startIfNeeded()
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
        guard !personalization.shouldPresent else { return }
        onboarding.startIfNeeded()
    }

    func restartPersonalization() {
        personalization.reset()
        router.navigate(to: .root, addToStack: false, animated: false)
        syncViewportWithActiveStore()
    }

    func restartOnboarding() {
        intro.reset()
        personalization.reset()
        onboarding.reset()
        router.navigate(to: .root, addToStack: false, animated: false)
        syncViewportWithActiveStore()
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

        router = AppRouter()
        commandPalette = CommandPaletteViewModel()
        coCaptain = CoCaptainViewModel()
        actionDispatcher = AppActionDispatcher()
        intro = IntroCoordinator()
        personalization = PersonalizationOnboardingCoordinator()
        onboarding = OnboardingCoordinator()
        onboarding.onTutorialCompleted = { [weak self] in
            self?.celebrateTutorialGraduation()
        }
        viewport = ViewportState()
        currentScale = 1
        nodeSizes = [:]
        actionsConfigured = false

        bindCommandPalette()
        configureActionsIfNeeded()
        attachUndoManager(activeUndoManager)
        coCaptain.configureProjectSession(store: router.activeStore, dispatcher: actionDispatcher)
        syncViewportWithActiveStore()
        launchDismissTask?.cancel()
        launchDismissTask = nil
        isLaunching = false
        PerformanceSignposts.endLaunch()
    }

    func updateNodeSizes(_ sizes: [UUID: CGSize]) {
        nodeSizes = sizes
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

    // MARK: - Node Actions

    func handleNodeAction(_ action: NodeAction) {
        guard let actionID = action.appActionID else { return }
        _ = actionDispatcher.perform(actionID, source: .user)
    }

    func handleSubCanvasNavigation(fileName: String) {
        presentedMiniApp = nil
        selectedNodeDetail = nil
        router.navigateToSubCanvas(fileName: fileName)
    }

    // MARK: - Onboarding + CoCaptain Presentation

    func handleCommandPalettePresentationChange(isPresented: Bool) {
        if isPresented {
            commandPalette.nodes = router.activeStore.nodes
        }
    }

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

        if presentedMiniApp != nil {
            presentedMiniApp = nil
            dismissed = true
        }
        if selectedNodeDetail != nil {
            selectedNodeDetail = nil
            dismissed = true
        }
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
        if showExportSheet {
            showExportSheet = false
            dismissed = true
        }

        return dismissed
    }

    /// FAB tap: dismiss any open sheet, otherwise open the omnibox.
    func handleFloatingCommandButtonTap() {
        if dismissPresentedSheets() { return }
        commandPalette.setPresented(true)
    }

    // MARK: - File Import

    func importProject(from result: Result<[URL], Error>) {
        let logger = Logger(subsystem: "com.caocap.app", category: "FileImport")
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }

            guard selectedURL.startAccessingSecurityScopedResource() else {
                logger.error("Failed to start accessing security scoped resource.")
                return
            }

            Task { @MainActor [weak self] in
                defer {
                    selectedURL.stopAccessingSecurityScopedResource()
                }

                do {
                    let newFileName = try await Task.detached(priority: .userInitiated) { () -> String in
                        let data = try Data(contentsOf: selectedURL)
                        let decoder = JSONDecoder()
                        _ = try decoder.decode(ProjectSnapshot.self, from: data)

                        let persistence = ProjectPersistenceService()
                        let newFileName = CanvasFileNaming.newCanvasFileName()
                        let targetURL = persistence.fileURL(for: newFileName)
                        try data.write(to: targetURL, options: .atomic)
                        return newFileName
                    }.value

                    logger.info("Successfully imported project to: \(newFileName)")

                    guard let self else { return }
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        self.router.navigate(to: .project(newFileName))
                    }
                } catch {
                    logger.error("Import failed: \(error.localizedDescription)")
                }
            }

        case .failure(let error):
            logger.error("Document picker failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Command Palette

    func bindCommandPalette() {
        syncCommandPaletteActions()
        commandPalette.nodes = router.activeStore.nodes
        commandPalette.onExecute = { [weak self] actionID in
            guard let self else { return }
            _ = self.actionDispatcher.perform(actionID, source: .user)
        }
        commandPalette.onPinAction = { [weak self] actionID in
            guard let self,
                  let definition = self.actionDispatcher.definition(for: actionID) else { return }
            self.router.activeStore.addShortcutNode(for: actionID, definition: definition)
            self.commandPalette.nodes = self.router.activeStore.nodes
        }
        commandPalette.onCreateNode = { [weak self] type in
            guard let self else { return }
            self.createNode(type: type)
            self.commandPalette.nodes = self.router.activeStore.nodes
        }
        commandPalette.onFlyToNode = { [weak self] nodeId in
            self?.focusCanvasNode(nodeId)
        }
        coCaptain.onFlyToNode = { [weak self] nodeId in
            self?.focusCanvasNode(nodeId)
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

    func flyToTargetScale(for node: SpatialNode, nodeId: UUID) -> CGFloat {
        guard containerSize != .zero else { return 1.0 }

        let size: CGSize
        if let measuredSize = nodeSizes[nodeId] {
            size = measuredSize
        } else {
            switch node.type {
            case .miniApp:
                size = CGSize(width: 375, height: 667)
            default:
                size = CGSize(width: 280, height: 180)
            }
        }

        let paddingFactor: CGFloat = 0.8
        let scaleX = (containerSize.width * paddingFactor) / size.width
        let scaleY = (containerSize.height * paddingFactor) / size.height
        return min(min(scaleX, scaleY), 1.2)
    }

    // MARK: - Private

    private func attachUndoManager(_ undoManager: UndoManager?) {
        router.activeStore.undoManager = undoManager
        router.rootStore.undoManager = undoManager
    }

    private func syncViewportWithActiveStore() {
        viewport = ViewportState(
            offset: router.activeStore.viewportOffset,
            scale: router.activeStore.viewportScale
        )
        currentScale = viewport.scale
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
        actionDispatcher.register(.goRoot) { [weak self] in
            guard let self else { return }
            self.presentedMiniApp = nil
            self.selectedNodeDetail = nil
            self.router.goRoot()
            self.currentScale = 1.0
        }
        actionDispatcher.register(.goBack) { [weak self] in
            guard let self else { return }
            self.presentedMiniApp = nil
            self.selectedNodeDetail = nil
            self.router.goBack()
        }
        actionDispatcher.register(.createNode) { [weak self] args in
            self?.createNode(arguments: args)
        }
        actionDispatcher.register(.deleteNode) { [weak self] args in
            self?.deleteNode(arguments: args)
        }
        actionDispatcher.register(.renameNode) { [weak self] args in
            self?.renameNode(arguments: args)
        }
        actionDispatcher.register(.updateNodeSubtitle) { [weak self] args in
            self?.updateNodeSubtitle(arguments: args)
        }
        actionDispatcher.register(.updateNodeIcon) { [weak self] args in
            self?.updateNodeIcon(arguments: args)
        }
        actionDispatcher.register(.connectNodes) { [weak self] args in
            self?.connectNodes(arguments: args)
        }
        actionDispatcher.register(.disconnectNodes) { [weak self] args in
            self?.disconnectNodes(arguments: args)
        }
        actionDispatcher.register(.summonCoCaptain) { [weak self] in
            guard let self else { return }
            self.coCaptain.configureProjectSession(store: self.router.activeStore, dispatcher: self.actionDispatcher)
            self.presentCoCaptain()
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
        actionDispatcher.register(.openFile) { [weak self] in
            self?.showingFileImporter = true
        }
        actionDispatcher.register(.toggleGrid) { [weak self] in
            self?.toggleGrid()
        }
        actionDispatcher.register(.shareCanvas) { [weak self] in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let url = await ExportService.export(from: self.router.activeStore, format: .caocap) {
                    self.exportURL = url
                    self.showExportSheet = true
                }
            }
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
        actionDispatcher.register(.moveNode) { [weak self] args in
            self?.moveNode(arguments: args)
        }
        actionDispatcher.register(.themeNode) { [weak self] args in
            self?.themeNode(arguments: args)
        }
        actionDispatcher.register(.transformNode) { [weak self] args in
            self?.transformNode(arguments: args)
        }
        actionDispatcher.register(.organizeNodes) { [weak self] in
            guard let self else { return }
            self.router.activeStore.organizeNodes()
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) {
                self.viewport.fitTo(nodes: self.router.activeStore.nodes, containerSize: self.containerSize)
            }
        }
        actionDispatcher.register(.toggleHUD) { [weak self] in
            guard let self else { return }
            self.showingHUD.toggle()
        }
        actionDispatcher.register(.showActionsList) { [weak self] in
            self?.commandPalette.setPresented(true, mode: .actionsList)
        }
        actionDispatcher.register(.createSubCanvas) { [weak self] in
            self?.router.activeStore.addNode(type: .subCanvas)
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

    private func moveNode(arguments args: [String: String]?) {
        guard let args,
              let idString = args["nodeId"], let uuid = UUID(uuidString: idString),
              let xStr = args["x"], let x = Double(xStr),
              let yStr = args["y"], let y = Double(yStr) else { return }
        router.activeStore.updateNodePosition(id: uuid, position: CGPoint(x: x, y: y))
    }

    private func themeNode(arguments args: [String: String]?) {
        guard let args,
              let idString = args["nodeId"], let uuid = UUID(uuidString: idString),
              let themeStr = args["theme"], let theme = NodeTheme(rawValue: themeStr) else { return }
        router.activeStore.updateNodeTheme(id: uuid, theme: theme)
    }

    private func transformNode(arguments args: [String: String]?) {
        guard let args,
              let idString = args["nodeId"], let uuid = UUID(uuidString: idString),
              let typeStr = args["type"], let type = NodeType(rawValue: typeStr) else { return }

        router.activeStore.updateNodeType(id: uuid, type: type)
    }

    private func createNode(arguments args: [String: String]?) {
        let type = args?["type"].flatMap(NodeType.init(rawValue:)) ?? .miniApp
        let title = args?["title"]
        let position: CGPoint?
        if let xStr = args?["x"], let yStr = args?["y"],
           let x = Double(xStr), let y = Double(yStr) {
            position = CGPoint(x: x, y: y)
        } else {
            position = nil
        }
        router.activeStore.addNode(type: type, title: title, position: position)
    }

    private func deleteNode(arguments args: [String: String]?) {
        guard let idString = args?["nodeId"], let uuid = UUID(uuidString: idString) else { return }
        router.activeStore.deleteNode(id: uuid)
    }

    private func renameNode(arguments args: [String: String]?) {
        guard let idString = args?["nodeId"], let uuid = UUID(uuidString: idString),
              let title = args?["title"] else { return }
        router.activeStore.updateNodeTitle(id: uuid, title: title)
    }

    private func updateNodeSubtitle(arguments args: [String: String]?) {
        guard let idString = args?["nodeId"], let uuid = UUID(uuidString: idString) else { return }
        router.activeStore.updateNodeSubtitle(id: uuid, subtitle: args?["subtitle"])
    }

    private func updateNodeIcon(arguments args: [String: String]?) {
        guard let idString = args?["nodeId"], let uuid = UUID(uuidString: idString) else { return }
        router.activeStore.updateNodeIcon(id: uuid, icon: args?["icon"])
    }

    private func connectNodes(arguments args: [String: String]?) {
        guard let fromString = args?["fromNodeId"], let fromID = UUID(uuidString: fromString),
              let toString = args?["toNodeId"], let toID = UUID(uuidString: toString) else { return }
        let kind = args?["kind"]
            .flatMap(NodeConnectionKind.init(rawValue:)) ?? .next
        router.activeStore.connectNodes(fromID: fromID, toID: toID, kind: kind)
    }

    private func disconnectNodes(arguments args: [String: String]?) {
        guard let fromString = args?["fromNodeId"], let fromID = UUID(uuidString: fromString),
              let toString = args?["toNodeId"], let toID = UUID(uuidString: toString) else { return }
        let kind = args?["kind"].flatMap(NodeConnectionKind.init(rawValue:))
        router.activeStore.disconnectNodes(fromID: fromID, toID: toID, kind: kind)
    }

    private func createNode(type: NodeType) {
        router.activeStore.addNode(type: type)
    }

    func focusCanvasNode(_ nodeId: UUID) {
        guard let node = router.activeStore.nodes.first(where: { $0.id == nodeId }) else { return }
        let targetScale = flyToTargetScale(for: node, nodeId: nodeId)
        HapticsManager.shared.trigger(.light)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
            viewport.flyTo(nodePosition: node.position, containerSize: containerSize, targetScale: targetScale)
        }
        canvasFocusNodeID = nodeId
        canvasFocusClearTask?.cancel()
        canvasFocusClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, !Task.isCancelled else { return }
            if self.canvasFocusNodeID == nodeId {
                self.canvasFocusNodeID = nil
            }
        }
    }

    private func submitCoCaptainPrompt(_ prompt: String) {
        if let step = onboarding.currentStep,
           onboarding.content(for: step)?.blocksCoCaptainPrompt == true {
            return
        }
        coCaptain.configureProjectSession(store: router.activeStore, dispatcher: actionDispatcher)
        presentCoCaptain()
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
