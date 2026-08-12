import SwiftUI
import Observation
import OSLog

/// Mini-App detail tools surfaced in the omnibox while a large-sheet is open.
public enum MiniAppPreviewTool: String, CaseIterable, Identifiable {
    case agent
    case settings
    case backToCanvas

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .agent: return "Agent"
        case .settings: return "Settings"
        case .backToCanvas: return "Back to Canvas"
        }
    }

    var icon: String {
        switch self {
        case .agent: return "sparkles"
        case .settings: return "gearshape"
        case .backToCanvas: return "arrow.uturn.backward"
        }
    }
}

/// Active Mini-App preview session metadata used to render preview-only omnibox rows.
public struct MiniAppPreviewPaletteContext {
    public let nodeID: UUID
    public var onSelectTool: (MiniAppPreviewTool) -> Void

    public init(nodeID: UUID, onSelectTool: @escaping (MiniAppPreviewTool) -> Void) {
        self.nodeID = nodeID
        self.onSelectTool = onSelectTool
    }
}

/// UI state for the command palette. It deliberately emits only `AppActionID`
/// values so action execution remains centralized in `AppActionDispatcher`.
@Observable
public class CommandPaletteViewModel {
    public enum CommandPaletteMode {
        /// Standard mode: shows node results, action commands, and node-creation options.
        case search
        /// Dedicated actions-only list, entered via the "Show all actions" shortcut.
        case actionsList
    }
    
    private let logger = Logger(subsystem: "CAOCAP", category: "CommandPalette")
    
    /// Bound to the search field; resets keyboard selection whenever the value changes.
    public var query: String = "" {
        didSet {
            // Only reset keyboard selection when the query actually changed,
            // so that pressing Enter (which can re-trigger didSet with the
            // same value) doesn't clobber the arrow-key selection.
            guard query != oldValue else { return }
            selectedIndex = 0
        }
    }
    public var isPresented: Bool = false
    /// Flat index across all result sections (node results → actions → node creation → prompt row).
    public var selectedIndex: Int = 0
    /// Full list of registered app actions; filtered by `filteredActions` before display.
    public var actions: [AppActionDefinition] = []
    /// The current canvas nodes; searched by `nodeResults` when the query is non-empty.
    public var nodes: [SpatialNode] = []
    public var mode: CommandPaletteMode = .search
    /// When set, the palette renders Mini-App preview tool rows and hides the canvas overlay copy.
    public var miniAppPreviewContext: MiniAppPreviewPaletteContext?
    
    /// Filters against localized and canonical titles so command search works
    /// in the UI language while still matching stable English action names.
    public var filteredActions: [AppActionDefinition] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let paletteActions = actions.filter { !Self.hiddenCreationActionIDs.contains($0.id) }
        if trimmedQuery.isEmpty { return paletteActions }
        
        let matches = paletteActions.filter {
            $0.localizedTitle.localizedCaseInsensitiveContains(trimmedQuery) ||
            $0.title.localizedCaseInsensitiveContains(trimmedQuery)
        }
        return matches.enumerated()
            .sorted { lhs, rhs in
                let lhsPriority = Self.navigationPriority(for: lhs.element.id)
                let rhsPriority = Self.navigationPriority(for: rhs.element.id)
                return lhsPriority == rhsPriority ? lhs.offset < rhs.offset : lhsPriority < rhsPriority
            }
            .map(\.element)
    }

    public var nodeResults: [NodeSearchResult] {
        searchIndex.search(query: query, in: nodes)
    }

    public var nodeCreationResults: [NodeCreationOption] {
        creationCatalog.search(query: query)
    }

    public var filteredPreviewTools: [MiniAppPreviewTool] {
        guard miniAppPreviewContext != nil else { return [] }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty { return MiniAppPreviewTool.allCases }
        return MiniAppPreviewTool.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    public var previewToolCount: Int { filteredPreviewTools.count }

    private static let hiddenCreationActionIDs: Set<AppActionID> = [
        .createNode,
        .createSubCanvas
    ]

    private static func navigationPriority(for id: AppActionID) -> Int {
        switch id {
        case .goBack: return 0
        case .goRoot: return 1
        default: return 2
        }
    }

    private var nodeResultCount: Int { nodeResults.count }
    private var nodeCreationResultCount: Int { nodeCreationResults.count }
    private var actionResultCount: Int { filteredActions.count }
    public var prioritizedNavigationActionCount: Int {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        return filteredActions.prefix {
            $0.id == .goBack || $0.id == .goRoot
        }.count
    }

    private var nodeResultsStartIndex: Int { prioritizedNavigationActionCount }
    private var remainingActionsStartIndex: Int { prioritizedNavigationActionCount + nodeResultCount }
    private var nodeCreationResultsStartIndex: Int { nodeResultCount + actionResultCount }
    private var promptRowIndex: Int { nodeResultCount + actionResultCount + nodeCreationResultCount }

    public var promptSelectionIndex: Int { selectionOffset + promptRowIndex }
    
    /// Called by the host when an action should be executed; avoids duplicating dispatch logic here.
    public var onExecute: ((AppActionID) -> Void)?
    /// Called when the user requests to pin an action shortcut onto the canvas.
    public var onPinAction: ((AppActionID) -> Void)?
    /// Called when the user selects a node result, asking the canvas to fly to that node.
    public var onFlyToNode: ((UUID) -> Void)?
    /// Called when the user picks a node-creation option from the palette.
    public var onCreateNode: ((NodeType) -> Void)?
    /// Called when the user submits a free-text query that didn't match any command or node.
    public var onSubmitPrompt: ((String) -> Void)?
    
    @ObservationIgnored
    private let searchIndex = NodeSearchIndex()

    @ObservationIgnored
    private let creationCatalog = NodeCreationCatalog()

    private var totalResultCount: Int {
        var count = previewToolCount + nodeResultCount + nodeCreationResultCount + actionResultCount
        if canSubmitPrompt {
            count += 1
        }
        return count
    }

    public func selectionIndex(forPreviewToolAt index: Int) -> Int {
        index
    }

    public func selectPreviewBackToCanvasToolIfAvailable() {
        guard let index = filteredPreviewTools.firstIndex(of: .backToCanvas) else { return }
        selectedIndex = index
    }

    private var selectionOffset: Int { previewToolCount }
    
    public init() {}
    
    /// Closes back to a clean state so each palette open starts from the full
    /// command list.
    public func setPresented(_ presented: Bool, mode: CommandPaletteMode = .search) {
        self.mode = mode
        isPresented = presented
        if !presented {
            query = ""
            selectedIndex = 0
        }
    }
    
    public func moveSelection(direction: Direction) {
        let count = totalResultCount
        guard count > 0 else { return }
        
        switch direction {
        case .up:
            selectedIndex = (selectedIndex - 1 + count) % count
        case .down:
            selectedIndex = (selectedIndex + 1) % count
        }
    }

    public func selectGoBackActionIfAvailable() {
        guard let index = filteredActions.firstIndex(where: { $0.id == .goBack }) else { return }
        selectedIndex = selectionIndex(forActionAt: index)
    }

    public func selectHelpActionIfAvailable() {
        guard let index = filteredActions.firstIndex(where: { $0.id == .help }) else { return }
        selectedIndex = selectionIndex(forActionAt: index)
    }

    public var showsGoBackAction: Bool {
        filteredActions.contains { $0.id == .goBack }
    }

    public var showsHelpAction: Bool {
        filteredActions.contains { $0.id == .help }
    }

    public func selectPromptRowIfAvailable() {
        guard canSubmitPrompt else { return }
        selectedIndex = promptRowIndex
    }
    
    public func confirmSelection() {
        let previewTools = filteredPreviewTools
        if selectedIndex < previewTools.count {
            selectPreviewTool(previewTools[selectedIndex])
            return
        }

        let adjustedIndex = selectedIndex - selectionOffset
        let nodeResults = nodeResults
        let nodeCreationResults = nodeCreationResults
        let actions = filteredActions
        let prioritizedCount = prioritizedNavigationActionCount

        if adjustedIndex < prioritizedCount {
            executeAction(actions[adjustedIndex])
        } else if adjustedIndex >= nodeResultsStartIndex && adjustedIndex < remainingActionsStartIndex {
            flyToNode(nodeResults[adjustedIndex - nodeResultsStartIndex])
        } else if adjustedIndex >= remainingActionsStartIndex && adjustedIndex < nodeCreationResultsStartIndex {
            let actionIndex = prioritizedCount + adjustedIndex - remainingActionsStartIndex
            executeAction(actions[actionIndex])
        } else if adjustedIndex >= nodeCreationResultsStartIndex && adjustedIndex < promptRowIndex {
            createNode(nodeCreationResults[adjustedIndex - nodeCreationResultsStartIndex])
        } else if canSubmitPrompt && adjustedIndex == promptRowIndex {
            submitPromptIfNeeded()
        }
    }

    public func selectPreviewTool(_ tool: MiniAppPreviewTool) {
        logger.info("Selecting Mini-App preview tool: \(tool.title)")
        miniAppPreviewContext?.onSelectTool(tool)
        setPresented(false)
    }
    
    /// Emits the chosen action ID and dismisses. The view model does not perform
    /// side effects directly because the same action system is shared with agents.
    public func executeAction(_ action: AppActionDefinition) {
        logger.info("Executing action: \(action.title)")
        onExecute?(action.id)
        if action.id == .showActionsList {
            query = ""
            selectedIndex = 0
            setPresented(true, mode: .actionsList)
            return
        }
        setPresented(false)
    }

    public func pinAction(_ action: AppActionDefinition) {
        logger.info("Pinning action to canvas: \(action.title)")
        onPinAction?(action.id)
        setPresented(false)
    }

    public func flyToNode(_ result: NodeSearchResult) {
        logger.info("Flying to node: \(result.title)")
        onFlyToNode?(result.id)
        setPresented(false)
    }

    public func createNode(_ option: NodeCreationOption) {
        logger.info("Creating node from palette: \(option.title)")
        onCreateNode?(option.id)
        setPresented(false)
    }

    /// Maps a node-result list index into the unified `selectedIndex` space.
    public func selectionIndex(forNodeResultAt index: Int) -> Int {
        selectionOffset + nodeResultsStartIndex + index
    }

    /// Maps a node-creation list index into the unified `selectedIndex` space.
    public func selectionIndex(forNodeCreationResultAt index: Int) -> Int {
        selectionOffset + nodeCreationResultsStartIndex + index
    }

    /// Maps an action list index into the unified `selectedIndex` space.
    public func selectionIndex(forActionAt index: Int) -> Int {
        if index < prioritizedNavigationActionCount {
            return selectionOffset + index
        }
        return selectionOffset + remainingActionsStartIndex + index - prioritizedNavigationActionCount
    }

    public var canSubmitPrompt: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
    }

    /// Emits an unmatched palette query as a CoCaptain prompt. Listed commands
    /// continue through `onExecute`; this path is only for no-result queries.
    public func submitPromptIfNeeded() {
        let prompt = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        logger.info("Submitting unmatched command palette query to CoCaptain")
        onSubmitPrompt?(prompt)
        setPresented(false)
    }
    
    public enum Direction {
        /// Move the keyboard highlight upward through results, wrapping from the top.
        case up
        /// Move the keyboard highlight downward through results, wrapping from the bottom.
        case down
    }
}
