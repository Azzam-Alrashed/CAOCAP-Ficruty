import Foundation

/// The outcome of a payload validation pass.
public struct CoCaptainAgentValidationResult: Hashable {
    /// A list of descriptive errors explaining why the payload cannot be safely executed.
    public let issues: [String]

    /// `true` if the payload has no structural or semantic errors.
    public var isValid: Bool {
        issues.isEmpty
    }
}

/// Validates model-produced agent payloads before any app action can execute.
/// The dispatcher remains the final execution boundary; this layer gives the
/// model deterministic feedback when it emits an unsafe or unusable contract.
public struct CoCaptainAgentValidator {
    public init() {}

    /// Validates the extracted model payload against the live capabilities of the application.
    /// Ensures requested actions exist and are correctly classified.
    @MainActor
    public func validate(
        payload: CoCaptainAgentPayload,
        dispatcher: (any AppActionPerforming)?,
        requiresAgenticWork: Bool
    ) -> CoCaptainAgentValidationResult {
        var issues: [String] = []

        issues.append(contentsOf: duplicateActionIssues(
            safeActions: payload.safeActions,
            pendingActions: payload.pendingActions
        ))

        for action in payload.safeActions {
            guard let id = AppActionID(rawValue: action.actionID) else {
                issues.append("Unknown safe action id `\(action.actionID)`.")
                continue
            }

            guard let definition = dispatcher?.definition(for: id) else {
                issues.append("Safe action `\(id.rawValue)` is not currently available.")
                continue
            }

            if !definition.allowsAutonomousExecution {
                issues.append("Safe action `\(id.rawValue)` is not autonomous; move it to `pendingActions`.")
            }
        }

        for action in payload.pendingActions {
            guard let id = AppActionID(rawValue: action.actionID) else {
                issues.append("Unknown pending action id `\(action.actionID)`.")
                continue
            }

            if dispatcher?.definition(for: id) == nil {
                issues.append("Pending action `\(id.rawValue)` is not currently available.")
            }
        }

        // A clarifying question is valid agentic work on its own: asking the
        // user which change they meant is preferable to guessing or refusing.
        if requiresAgenticWork,
           payload.safeActions.isEmpty,
           payload.pendingActions.isEmpty,
           payload.clarifyingQuestion == nil {
            issues.append("Build/edit requests must include at least one safe action, pending action, or clarifying question.")
        }

        return CoCaptainAgentValidationResult(issues: issues)
    }

    private func duplicateActionIssues(
        safeActions: [CoCaptainAgentAction],
        pendingActions: [CoCaptainAgentAction]
    ) -> [String] {
        var issues: [String] = []
        var seenSafe = Set<String>()
        var seenPending = Set<String>()

        for action in safeActions {
            if !seenSafe.insert(action.actionID).inserted {
                issues.append("Safe action `\(action.actionID)` is duplicated.")
            }
        }

        for action in pendingActions {
            if !seenPending.insert(action.actionID).inserted {
                issues.append("Pending action `\(action.actionID)` is duplicated.")
            }
        }

        for actionID in seenSafe.intersection(seenPending) {
            issues.append("Action `\(actionID)` cannot appear in both `safeActions` and `pendingActions`.")
        }

        return issues
    }
}
