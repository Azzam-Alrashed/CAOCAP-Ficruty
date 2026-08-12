import CoreGraphics
import Foundation
import Testing
@testable import caocap

struct CommandPaletteNavigationPriorityTests {
    @Test func queriedNavigationActionsArePrioritized() {
        let viewModel = CommandPaletteViewModel()
        viewModel.actions = [
            action(.openSettings, title: "Open Settings"),
            action(.goRoot, title: "Go to Root"),
            action(.goBack, title: "Go Back")
        ]
        viewModel.query = "go"

        #expect(viewModel.filteredActions.map(\.id) == [.goBack, .goRoot])
        #expect(viewModel.prioritizedNavigationActionCount == 2)
        #expect(viewModel.selectionIndex(forActionAt: 0) == 0)
        #expect(viewModel.selectionIndex(forActionAt: 1) == 1)
    }

    @Test func confirmingFirstQueriedResultExecutesNavigation() {
        let viewModel = CommandPaletteViewModel()
        viewModel.actions = [
            action(.goBack, title: "Go Back")
        ]
        viewModel.query = "back"

        var executedAction: AppActionID?
        viewModel.onExecute = { executedAction = $0 }

        viewModel.confirmSelection()

        #expect(executedAction == .goBack)
    }

    private func action(_ id: AppActionID, title: String) -> AppActionDefinition {
        AppActionDefinition(
            id: id,
            title: title,
            icon: "circle",
            category: .navigation,
            isMutating: false,
            allowsAutonomousExecution: true
        )
    }
}
