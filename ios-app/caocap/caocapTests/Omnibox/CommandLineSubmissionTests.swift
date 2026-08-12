import Testing
@testable import caocap

struct CommandLineSubmissionTests {
    @Test func emptySubmissionDismissesCommandLine() {
        let viewModel = CommandPaletteViewModel()
        viewModel.setPresented(true)

        viewModel.submit()

        #expect(viewModel.isPresented == false)
        #expect(viewModel.query.isEmpty)
    }

    @Test func openSettingsCommandExecutesLocally() {
        let viewModel = CommandPaletteViewModel()
        viewModel.actions = [action(.openSettings, title: "Open Settings")]
        viewModel.query = "open settings"

        var executedAction: AppActionID?
        var submittedPrompt: String?
        viewModel.onExecute = { executedAction = $0 }
        viewModel.onSubmitPrompt = { submittedPrompt = $0 }

        viewModel.submit()

        #expect(executedAction == .openSettings)
        #expect(submittedPrompt == nil)
        #expect(viewModel.isPresented == false)
        #expect(viewModel.query.isEmpty)
    }

    @Test func unmatchedInputIsSentToCopilot() {
        let viewModel = CommandPaletteViewModel()
        viewModel.actions = [action(.openSettings, title: "Open Settings")]
        viewModel.query = "plan a launch mission"

        var executedAction: AppActionID?
        var submittedPrompt: String?
        viewModel.onExecute = { executedAction = $0 }
        viewModel.onSubmitPrompt = { submittedPrompt = $0 }

        viewModel.submit()

        #expect(executedAction == nil)
        #expect(submittedPrompt == "plan a launch mission")
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
