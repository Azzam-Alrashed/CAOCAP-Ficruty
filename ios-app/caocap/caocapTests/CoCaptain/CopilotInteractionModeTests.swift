import Testing
@testable import caocap

@Suite("Copilot interaction modes")
@MainActor
struct CopilotInteractionModeTests {
    @Test func modeIconsAreStable() {
        #expect(CopilotInteractionMode.chat.systemImageName == "bubble.left.and.bubble.right.fill")
        #expect(CopilotInteractionMode.video.systemImageName == "video.fill")
    }

    @Test func personasUseGenderedLiveVoices() {
        #expect(CopilotPersona.cocaptain.liveVoiceName == "Charon")
        #expect(CopilotPersona.costar.liveVoiceName == "Kore")
    }

    @Test func dispatcherIncludesUndoRedoAndCallActions() {
        let dispatcher = AppActionDispatcher()
        let ids = Set(dispatcher.availableActions.map(\.id))
        #expect(ids.contains(.undo))
        #expect(ids.contains(.redo))
        #expect(ids.contains(.summonCopilotVideo))
        #expect(ids.contains(.summonCoCaptain))
        #expect(ids.contains(.changeCopilot))
        #expect(ids.contains(.openUsage))
    }

    @Test func intentResolverMatchesUndoRedo() {
        let dispatcher = AppActionDispatcher()
        let resolver = CommandIntentResolver()
        #expect(resolver.resolve("undo", availableActions: dispatcher.availableActions) == .undo)
        #expect(resolver.resolve("redo", availableActions: dispatcher.availableActions) == .redo)
        #expect(resolver.resolve("voice call", availableActions: dispatcher.availableActions) == nil)
        #expect(resolver.resolve("screen share", availableActions: dispatcher.availableActions) == .summonCopilotVideo)
        #expect(resolver.resolve("change copilot", availableActions: dispatcher.availableActions) == .changeCopilot)
        #expect(resolver.resolve("switch copilot", availableActions: dispatcher.availableActions) == .changeCopilot)
        #expect(resolver.resolve("usage", availableActions: dispatcher.availableActions) == .openUsage)
        #expect(resolver.resolve("view usage", availableActions: dispatcher.availableActions) == .openUsage)
        #expect(resolver.resolve("token usage", availableActions: dispatcher.availableActions) == .openUsage)
    }

    @Test func intentResolverSeparatesAppHomeFromCanvasRoot() {
        let dispatcher = AppActionDispatcher()
        let resolver = CommandIntentResolver()

        #expect(resolver.resolve("home", availableActions: dispatcher.availableActions) == .goHome)
        #expect(resolver.resolve("go home", availableActions: dispatcher.availableActions) == .goHome)
        #expect(resolver.resolve("root", availableActions: dispatcher.availableActions) == .goRoot)
        #expect(resolver.resolve("go root", availableActions: dispatcher.availableActions) == .goRoot)
    }
}
