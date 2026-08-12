import Foundation
import Observation
import OSLog

/// UI state for the command palette. The legacy node search and creation paths
/// are intentionally absent while the orchestration workflow editor is rebuilt.
@Observable
public final class CommandPaletteViewModel {
    public enum CommandPaletteMode {
        case search
        case actionsList
    }

    private let logger = Logger(subsystem: "CAOCAP", category: "CommandPalette")

    public var query = "" {
        didSet {
            guard query != oldValue else { return }
            selectedIndex = 0
        }
    }
    public var isPresented = false
    public var selectedIndex = 0
    public var actions: [AppActionDefinition] = []
    public var mode: CommandPaletteMode = .search

    public var onExecute: ((AppActionID) -> Void)?
    public var onSubmitPrompt: ((String) -> Void)?

    public init() {}

    public var filteredActions: [AppActionDefinition] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return actions }
        return actions.filter {
            $0.localizedTitle.localizedCaseInsensitiveContains(trimmed)
                || $0.title.localizedCaseInsensitiveContains(trimmed)
        }
        .enumerated()
        .sorted { lhs, rhs in
            let lhsPriority = Self.navigationPriority(lhs.element.id)
            let rhsPriority = Self.navigationPriority(rhs.element.id)
            return lhsPriority == rhsPriority ? lhs.offset < rhs.offset : lhsPriority < rhsPriority
        }
        .map(\.element)
    }

    public var prioritizedNavigationActionCount: Int {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        return filteredActions.prefix { $0.id == .goBack || $0.id == .goRoot }.count
    }

    public var canSubmitPrompt: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var promptSelectionIndex: Int { filteredActions.count }

    public func setPresented(_ presented: Bool, mode: CommandPaletteMode = .search) {
        self.mode = mode
        isPresented = presented
        if !presented {
            query = ""
            selectedIndex = 0
        }
    }

    public func moveSelection(direction: Direction) {
        let count = filteredActions.count + (canSubmitPrompt ? 1 : 0)
        guard count > 0 else { return }
        switch direction {
        case .up: selectedIndex = (selectedIndex - 1 + count) % count
        case .down: selectedIndex = (selectedIndex + 1) % count
        }
    }

    public func confirmSelection() {
        let actions = filteredActions
        if selectedIndex < actions.count {
            executeAction(actions[selectedIndex])
        } else if canSubmitPrompt && selectedIndex == promptSelectionIndex {
            submitPromptIfNeeded()
        }
    }

    public func executeAction(_ action: AppActionDefinition) {
        logger.info("Executing action: \(action.title)")
        onExecute?(action.id)
        if action.id == .showActionsList {
            query = ""
            selectedIndex = 0
            setPresented(true, mode: .actionsList)
        } else {
            setPresented(false)
        }
    }

    public func selectionIndex(forActionAt index: Int) -> Int { index }

    public func selectGoBackActionIfAvailable() {
        guard let index = filteredActions.firstIndex(where: { $0.id == .goBack }) else { return }
        selectedIndex = index
    }

    public func selectHelpActionIfAvailable() {
        guard let index = filteredActions.firstIndex(where: { $0.id == .help }) else { return }
        selectedIndex = index
    }

    public var showsGoBackAction: Bool { filteredActions.contains { $0.id == .goBack } }
    public var showsHelpAction: Bool { filteredActions.contains { $0.id == .help } }

    public func selectPromptRowIfAvailable() {
        guard canSubmitPrompt else { return }
        selectedIndex = promptSelectionIndex
    }

    public func submitPromptIfNeeded() {
        let prompt = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        logger.info("Submitting unmatched command palette query to CoCaptain")
        onSubmitPrompt?(prompt)
        setPresented(false)
    }

    private static func navigationPriority(_ id: AppActionID) -> Int {
        switch id {
        case .goBack: return 0
        case .goRoot: return 1
        default: return 2
        }
    }

    public enum Direction { case up, down }
}
