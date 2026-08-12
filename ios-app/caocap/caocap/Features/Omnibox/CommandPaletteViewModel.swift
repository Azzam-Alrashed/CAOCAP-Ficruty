import Foundation
import Observation
import OSLog

/// UI state and submission routing for the Command Line.
@Observable
public final class CommandPaletteViewModel {
    private let logger = Logger(subsystem: "CAOCAP", category: "CommandLine")
    private let intentResolver = CommandIntentResolver()

    public var query = ""
    public var isPresented = false
    public var actions: [AppActionDefinition] = []

    public var onExecute: ((AppActionID) -> Void)?
    public var onSubmitPrompt: ((String) -> Void)?

    public init() {}

    public func setPresented(_ presented: Bool) {
        isPresented = presented
        if !presented {
            query = ""
        }
    }

    /// Executes recognized local commands and sends everything else to the CoPilot.
    public func submit() {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            setPresented(false)
            return
        }

        if let actionID = intentResolver.resolve(input, availableActions: actions) {
            logger.info("Executing Command Line action: \(actionID.rawValue)")
            onExecute?(actionID)
        } else {
            logger.info("Submitting Command Line request to CoPilot")
            onSubmitPrompt?(input)
        }
        setPresented(false)
    }
}
