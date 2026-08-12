import Foundation
import Testing
@testable import caocap

struct NodeActionAppActionTests {
    @Test func everyNodeActionResolvesToAppActionID() {
        let mappings: [(NodeAction, AppActionID)] = [
            (.navigateRoot, .goRoot),
            (.openSettings, .openSettings),
            (.openProfile, .openProfile),
            (.summonCoCaptain, .summonCoCaptain),
            (.proSubscription, .proSubscription),
            (.openWhatsApp, .openWhatsApp),
            (.openHelp, .help),
            (.openAppIcon, .openAppIcon)
        ]

        for (nodeAction, expectedID) in mappings {
            #expect(nodeAction.appActionID == expectedID)
        }
    }

    @Test func pinableAppActionsRoundTripToNodeAction() throws {
        let pinableIDs: [AppActionID] = [
            .goRoot,
            .openSettings,
            .openProfile,
            .summonCoCaptain,
            .proSubscription,
            .openWhatsApp,
            .help,
            .openAppIcon
        ]

        for actionID in pinableIDs {
            let nodeAction = try #require(actionID.pinableNodeAction)
            #expect(nodeAction.appActionID == actionID)
        }
    }

    @MainActor
    @Test func dispatcherExposesRootShortcutActions() throws {
        let dispatcher = AppActionDispatcher()
        let shortcutIDs: [AppActionID] = [.openWhatsApp, .help, .openAppIcon]

        for id in shortcutIDs {
            let definition = try #require(dispatcher.definition(for: id))
            #expect(!definition.isMutating)
            #expect(!definition.allowsAutonomousExecution)
            #expect(definition.canPinToCanvas)
            #expect(id.pinableNodeAction != nil)
        }
    }

    @MainActor
    @Test func dispatcherExposesGraphMutationActionsAsPendingOnly() throws {
        let dispatcher = AppActionDispatcher()
        let graphIDs: [AppActionID] = [
            .createNode,
            .deleteNode,
            .renameNode,
            .updateNodeSubtitle,
            .updateNodeIcon,
            .connectNodes,
            .disconnectNodes
        ]

        for id in graphIDs {
            let definition = try #require(dispatcher.definition(for: id))
            #expect(definition.isMutating)
            #expect(!definition.allowsAutonomousExecution)
            #expect(definition.canPinToCanvas == false)
        }
    }
}
