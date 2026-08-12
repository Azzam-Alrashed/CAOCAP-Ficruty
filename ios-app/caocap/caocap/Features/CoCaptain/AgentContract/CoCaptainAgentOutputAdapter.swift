import Foundation

/// Identifies which wire format the model used to deliver its structured
/// output in a given turn. Used for diagnostics and telemetry.
public enum CoCaptainAgentOutputSource: String, Hashable {
    /// The model wrapped actions in a `<cocaptain_actions>` XML block in text.
    case xml = "xml"
    /// The model used Gemini function-calling to invoke `request_app_action`.
    case functionCall = "function_call"
    /// The model delivered a clarifying question through `ask_clarifying_question`.
    case clarifyingQuestionFunctionCall = "clarifying_question_function_call"
    /// Both mechanisms fired in the same turn and were merged.
    case combined = "combined"
}

/// The normalised, adapter-independent output of one model turn, ready for
/// the coordinator to validate and route into the review pipeline.
public struct CoCaptainAgentDirective: Hashable {
    /// The conversational text that precedes the structured action block.
    public let preamble: String
    /// The chat-visible text, equal to `preamble` for XML responses or the
    /// function-call visible text when no XML block is present.
    public let visibleText: String
    /// The decoded, actionable payload, or `nil` when the model produced no
    /// structured output for this turn.
    public let payload: CoCaptainAgentPayload?
    /// Validation or parsing errors discovered while processing the response.
    /// A non-empty array causes the coordinator to attempt an agentic retry.
    public let diagnostics: [String]
    /// Which adapter produced this directive.
    public let source: CoCaptainAgentOutputSource

    public init(
        preamble: String,
        visibleText: String,
        payload: CoCaptainAgentPayload?,
        diagnostics: [String] = [],
        source: CoCaptainAgentOutputSource
    ) {
        self.preamble = preamble
        self.visibleText = visibleText
        self.payload = payload
        self.diagnostics = diagnostics
        self.source = source
    }
}

/// Converts raw model output into a directive the coordinator can validate and
/// execute. Future Gemini function-call or structured-output adapters should
/// produce this same directive so orchestration stays independent of wire shape.
public protocol CoCaptainAgentOutputAdapting {
    /// Extracts the conversational visible text from a raw response string.
    /// - Parameter response: The raw text returned by the model.
    /// - Returns: The text content intended for display.
    func visibleText(from response: String) -> String
    /// Converts a raw response and optional function calls into a directive.
    /// - Parameters:
    ///   - response: The raw text returned by the model.
    ///   - functionCalls: A list of function calls triggered by the model.
    /// - Returns: A fully formed `CoCaptainAgentDirective`.
    func directive(from response: String, functionCalls: [CoCaptainAgentFunctionCall]) -> CoCaptainAgentDirective
}

public extension CoCaptainAgentOutputAdapting {
    /// Convenience overload for callers that have no function-call events,
    /// defaulting to an empty array so they don't need to pass it explicitly.
    func directive(from response: String) -> CoCaptainAgentDirective {
        directive(from: response, functionCalls: [])
    }
}

/// Adapter that decodes the `<cocaptain_actions>` XML fenced format.
///
/// Delegates all XML parsing to `CoCaptainAgentParser` and wraps the result
/// in a `CoCaptainAgentDirective`. Function calls are ignored by this adapter;
/// use `CoCaptainCompositeAgentAdapter` to handle both formats.
public struct CoCaptainXMLAgentAdapter: CoCaptainAgentOutputAdapting {
    private let parser: CoCaptainAgentParser

    public init(parser: CoCaptainAgentParser = CoCaptainAgentParser()) {
        self.parser = parser
    }

    public func visibleText(from response: String) -> String {
        parser.visibleText(from: response)
    }

    public func directive(from response: String, functionCalls: [CoCaptainAgentFunctionCall]) -> CoCaptainAgentDirective {
        let parsed = parser.parse(response)
        return CoCaptainAgentDirective(
            preamble: parsed.preamble,
            visibleText: parsed.visibleText,
            payload: parsed.payload,
            // Wrap single diagnostic in an array for uniform handling downstream.
            diagnostics: parsed.diagnostic.map { [$0] } ?? [],
            source: .xml
        )
    }
}

/// Adapter that converts Gemini native function-call events into a directive.
///
/// Only `request_app_action` calls are understood. Each call must carry an
/// `actionId` argument and an optional `executionMode` of `"safe"` or
/// `"pending"` (defaults to `"pending"` when absent).
public struct CoCaptainFunctionCallAgentAdapter {
    /// The Gemini tool name the model must invoke for app actions.
    public static let requestAppActionName = "request_app_action"

    public init() {}

    /// Converts an array of raw function-call events into a directive.
    ///
    /// Unknown function names and malformed arguments are collected as
    /// diagnostics rather than silently dropped, so the validator can
    /// feed them back to the model via an agentic retry.
    public func directive(
        from functionCalls: [CoCaptainAgentFunctionCall],
        visibleText: String = ""
    ) -> CoCaptainAgentDirective {
        var safeActions: [CoCaptainAgentAction] = []
        var pendingActions: [CoCaptainAgentAction] = []
        var diagnostics: [String] = []

        for functionCall in functionCalls {
            guard functionCall.name == Self.requestAppActionName else {
                diagnostics.append("Unknown function call `\(functionCall.name)`.")
                continue
            }

            guard let actionID = nonEmptyArgument("actionId", in: functionCall)
                ?? nonEmptyArgument("action_id", in: functionCall) else {
                diagnostics.append("Function call `\(functionCall.name)` is missing `actionId`.")
                continue
            }

            // Default to pending so unknown modes don't silently auto-execute.
            let executionMode = (nonEmptyArgument("executionMode", in: functionCall) ?? "pending")
                .lowercased()
            let action = CoCaptainAgentAction(
                actionID: actionID,
                args: supplementalArguments(from: functionCall)
            )

            switch executionMode {
            case "safe":
                safeActions.append(action)
            case "pending":
                pendingActions.append(action)
            default:
                diagnostics.append("Function call `\(functionCall.name)` has invalid `executionMode` `\(executionMode)`.")
            }
        }

        // Only build a payload when at least one valid action was decoded;
        // an empty payload is represented as nil so the coordinator knows
        // the model produced no executable intent.
        let payload = safeActions.isEmpty && pendingActions.isEmpty
            ? nil
            : CoCaptainAgentPayload(
                assistantMessage: visibleText,
                safeActions: safeActions,
                pendingActions: pendingActions
            )

        return CoCaptainAgentDirective(
            preamble: visibleText,
            visibleText: visibleText,
            payload: payload,
            diagnostics: diagnostics,
            source: .functionCall
        )
    }

    /// Returns a trimmed, non-empty argument value, or `nil` if the key is
    /// absent or the value is blank after trimming whitespace.
    private func nonEmptyArgument(_ key: String, in functionCall: CoCaptainAgentFunctionCall) -> String? {
        functionCall.stringArgument(key)
    }

    private func supplementalArguments(from functionCall: CoCaptainAgentFunctionCall) -> [String: String]? {
        let reservedKeys = Set(["actionId", "action_id", "executionMode"])
        var args: [String: String] = [:]
        for (key, value) in functionCall.arguments where !reservedKeys.contains(key) {
            guard let scalar = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !scalar.isEmpty else {
                continue
            }
            args[key] = scalar
        }
        return args.isEmpty ? nil : args
    }
}

/// Adapter that converts `ask_clarifying_question` function calls into the
/// existing `CoCaptainClarifyingQuestion` payload shape.
///
/// Legacy `propose_node_edit` calls are ignored (dropped with a diagnostic).
public struct CoCaptainClarifyingQuestionFunctionAdapter {
    /// The tool names this adapter understands. The composite adapter uses
    /// this set to partition calls between adapters.
    public static let handledFunctionNames: Set<String> = [
        CoCaptainClarifyingQuestionTools.askClarifyingQuestionName,
        // Legacy name kept only so the composite adapter can drop it cleanly.
        "propose_node_edit"
    ]

    public init() {}

    /// Converts clarifying-question tool calls into a directive. Malformed
    /// arguments become diagnostics so the agentic retry can feed them back.
    public func directive(
        from functionCalls: [CoCaptainAgentFunctionCall],
        visibleText: String = ""
    ) -> CoCaptainAgentDirective {
        var clarifyingQuestion: CoCaptainClarifyingQuestion?
        var diagnostics: [String] = []

        for functionCall in functionCalls {
            switch functionCall.name {
            case CoCaptainClarifyingQuestionTools.askClarifyingQuestionName:
                if let question = question(from: functionCall) {
                    // Keep the first well-formed question; the contract allows one.
                    clarifyingQuestion = clarifyingQuestion ?? question
                } else {
                    diagnostics.append(
                        "Function call `\(functionCall.name)` needs a non-empty `prompt` and \(CoCaptainClarifyingQuestion.minimumOptions)-\(CoCaptainClarifyingQuestion.maximumOptions) non-empty `options`."
                    )
                }
            case "propose_node_edit":
                diagnostics.append(
                    "Function call `propose_node_edit` is no longer supported; use `request_app_action` or `ask_clarifying_question`."
                )
            default:
                diagnostics.append("Unknown function call `\(functionCall.name)`.")
            }
        }

        let payload = clarifyingQuestion.map {
            CoCaptainAgentPayload(
                assistantMessage: visibleText,
                clarifyingQuestion: $0
            )
        }

        return CoCaptainAgentDirective(
            preamble: visibleText,
            visibleText: visibleText,
            payload: payload,
            diagnostics: diagnostics,
            source: .clarifyingQuestionFunctionCall
        )
    }

    private func question(from functionCall: CoCaptainAgentFunctionCall) -> CoCaptainClarifyingQuestion? {
        guard let prompt = functionCall.stringArgument("prompt") else { return nil }
        let options = (functionCall.arguments["options"]?.arrayValue ?? [])
            .compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard options.count >= CoCaptainClarifyingQuestion.minimumOptions else { return nil }
        return CoCaptainClarifyingQuestion(
            prompt: prompt,
            options: Array(options.prefix(CoCaptainClarifyingQuestion.maximumOptions))
        )
    }
}

/// Merges XML-fenced and Gemini function-call output into a single directive.
///
/// When the model produces both an XML block and native function calls in the
/// same turn, their actions are combined: function calls supply `safeActions`
/// and `pendingActions`; clarifying questions may come from tools or XML.
/// Diagnostics from both adapters are concatenated.
public struct CoCaptainCompositeAgentAdapter: CoCaptainAgentOutputAdapting {
    private let xmlAdapter: CoCaptainXMLAgentAdapter
    private let functionCallAdapter: CoCaptainFunctionCallAgentAdapter
    private let clarifyingQuestionAdapter: CoCaptainClarifyingQuestionFunctionAdapter

    public init(
        xmlAdapter: CoCaptainXMLAgentAdapter = CoCaptainXMLAgentAdapter(),
        functionCallAdapter: CoCaptainFunctionCallAgentAdapter = CoCaptainFunctionCallAgentAdapter(),
        clarifyingQuestionAdapter: CoCaptainClarifyingQuestionFunctionAdapter = CoCaptainClarifyingQuestionFunctionAdapter()
    ) {
        self.xmlAdapter = xmlAdapter
        self.functionCallAdapter = functionCallAdapter
        self.clarifyingQuestionAdapter = clarifyingQuestionAdapter
    }

    public func visibleText(from response: String) -> String {
        xmlAdapter.visibleText(from: response)
    }

    public func directive(from response: String, functionCalls: [CoCaptainAgentFunctionCall]) -> CoCaptainAgentDirective {
        let fencedDirective = xmlAdapter.directive(from: response, functionCalls: [])
        // If there are no function calls, return the XML directive directly to
        // avoid building a redundant combined payload.
        guard !functionCalls.isEmpty else { return fencedDirective }

        // Partition calls between the clarifying-question adapter and the
        // app-action adapter so neither flags the other's tools as unknown.
        let clarifyingCalls = functionCalls.filter {
            CoCaptainClarifyingQuestionFunctionAdapter.handledFunctionNames.contains($0.name)
        }
        let actionCalls = functionCalls.filter {
            !CoCaptainClarifyingQuestionFunctionAdapter.handledFunctionNames.contains($0.name)
        }

        let functionDirective = actionCalls.isEmpty
            ? nil
            : functionCallAdapter.directive(from: actionCalls, visibleText: fencedDirective.visibleText)
        let clarifyingDirective = clarifyingCalls.isEmpty
            ? nil
            : clarifyingQuestionAdapter.directive(from: clarifyingCalls, visibleText: fencedDirective.visibleText)

        let payload = combine(
            functionDirective?.payload,
            clarifyingDirective?.payload,
            fencedDirective.payload
        )
        return CoCaptainAgentDirective(
            preamble: fencedDirective.preamble,
            visibleText: fencedDirective.visibleText,
            payload: payload,
            diagnostics: (functionDirective?.diagnostics ?? [])
                + (clarifyingDirective?.diagnostics ?? [])
                + fencedDirective.diagnostics,
            source: mergedSource(
                hasActionPayload: functionDirective?.payload != nil,
                hasClarifyingPayload: clarifyingDirective?.payload != nil,
                hasFencedPayload: fencedDirective.payload != nil
            )
        )
    }

    /// Merges the three optional payload sources.
    ///
    /// - Safe/pending actions come from the `request_app_action` side.
    /// - Clarifying question prefers the function-call tool; XML is fallback.
    /// - `assistantMessage` comes from the XML payload (richer prose) if
    ///   present; falls back to the function-call visible text.
    private func combine(
        _ functionPayload: CoCaptainAgentPayload?,
        _ clarifyingPayload: CoCaptainAgentPayload?,
        _ fencedPayload: CoCaptainAgentPayload?
    ) -> CoCaptainAgentPayload? {
        guard functionPayload != nil || clarifyingPayload != nil || fencedPayload != nil else {
            return nil
        }

        return CoCaptainAgentPayload(
            assistantMessage: fencedPayload?.assistantMessage
                ?? clarifyingPayload?.assistantMessage
                ?? functionPayload?.assistantMessage
                ?? "",
            safeActions: functionPayload?.safeActions ?? [],
            pendingActions: functionPayload?.pendingActions ?? [],
            clarifyingQuestion: clarifyingPayload?.clarifyingQuestion ?? fencedPayload?.clarifyingQuestion
        )
    }

    private func mergedSource(
        hasActionPayload: Bool,
        hasClarifyingPayload: Bool,
        hasFencedPayload: Bool
    ) -> CoCaptainAgentOutputSource {
        let contributions = [hasActionPayload, hasClarifyingPayload, hasFencedPayload]
            .filter { $0 }
            .count
        if contributions > 1 { return .combined }
        if hasClarifyingPayload { return .clarifyingQuestionFunctionCall }
        if hasActionPayload { return .functionCall }
        return .xml
    }
}
