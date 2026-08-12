import Foundation
import Testing
@testable import caocap

struct CommandPalettePreviewContextTests {
    @Test func previewContextExposesFilteredTools() {
        let viewModel = CommandPaletteViewModel()
        #expect(viewModel.filteredPreviewTools.isEmpty)

        viewModel.miniAppPreviewContext = MiniAppPreviewPaletteContext(
            nodeID: UUID(),
            onSelectTool: { _ in }
        )

        #expect(viewModel.filteredPreviewTools.count == MiniAppPreviewTool.allCases.count)
        #expect(viewModel.previewToolCount == MiniAppPreviewTool.allCases.count)
        #expect(viewModel.filteredPreviewTools == [.agent, .settings, .backToCanvas])
    }

    @Test func previewToolSelectionInvokesCallbackAndDismissesPalette() {
        let viewModel = CommandPaletteViewModel()
        var selectedTool: MiniAppPreviewTool?
        let nodeID = UUID()

        viewModel.miniAppPreviewContext = MiniAppPreviewPaletteContext(
            nodeID: nodeID,
            onSelectTool: { selectedTool = $0 }
        )
        viewModel.setPresented(true)

        viewModel.selectPreviewTool(.agent)

        #expect(selectedTool == .agent)
        #expect(!viewModel.isPresented)
    }

    @Test func previewToolsFilterByQuery() {
        let viewModel = CommandPaletteViewModel()
        viewModel.miniAppPreviewContext = MiniAppPreviewPaletteContext(
            nodeID: UUID(),
            onSelectTool: { _ in }
        )
        viewModel.query = "agent"

        #expect(viewModel.filteredPreviewTools == [.agent])
    }

    @Test func previewToolsShiftSelectionIndices() {
        let viewModel = CommandPaletteViewModel()
        viewModel.miniAppPreviewContext = MiniAppPreviewPaletteContext(
            nodeID: UUID(),
            onSelectTool: { _ in }
        )

        #expect(viewModel.selectionIndex(forPreviewToolAt: 2) == 2)
        #expect(viewModel.selectionIndex(forActionAt: 0) == viewModel.previewToolCount)
    }
}
