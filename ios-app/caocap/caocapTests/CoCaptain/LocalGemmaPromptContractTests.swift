import Testing
@testable import caocap

struct LocalGemmaPromptContractTests {
    @MainActor
    @Test func localStructuredTurnUsesXMLWithoutCloudTools() {
        let prompt = LLMService.shared.buildPrompt(
            userMessage: "rename the cafe node",
            context: "Node Graph:\n- Cafe [miniApp]",
            expectsStructuredResponse: true,
            availableActions: [],
            scope: .project,
            purpose: .standard,
            chatMode: .agent,
            modelSupportsFunctionCalling: false
        )

        #expect(prompt.contains("XML schema for `cocaptain_actions`") || prompt.contains("cocaptain_actions") || prompt.contains("request_app_action"))
        #expect(!prompt.contains("propose_node_edit"))
        #expect(!prompt.contains("read_node_section"))
        #expect(!prompt.contains("node_edits"))
    }
}
