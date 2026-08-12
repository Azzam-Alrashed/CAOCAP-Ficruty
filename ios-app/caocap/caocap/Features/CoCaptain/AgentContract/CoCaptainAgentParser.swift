import Foundation

/// Splits model responses into user-visible text and an optional trailing
/// `cocaptain_actions` XML payload.
public struct CoCaptainAgentParser {
    private static let startTag = "<cocaptain_actions>"
    private static let endTag = "</cocaptain_actions>"

    public init() {}

    /// Parses the structured XML block in the response.
    public func parse(_ response: String) -> CoCaptainParsedResponse {
        if let blockRange = lastCompleteActionsBlock(in: response) {
            let preamble = String(response[..<blockRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return parseActionsBlock(
                xml: String(response[blockRange]),
                preamble: preamble
            )
        }

        if let startRange = response.range(of: Self.startTag) {
            return CoCaptainParsedResponse(
                preamble: String(response[..<startRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines),
                payload: nil
            )
        }
        if let loosePayload = parseLoosePayload(response) {
            return loosePayload
        }
        return CoCaptainParsedResponse(
            preamble: response.trimmingCharacters(in: .whitespacesAndNewlines),
            payload: nil
        )
    }

    private func parseActionsBlock(xml: String, preamble: String) -> CoCaptainParsedResponse {

        let assistantMessage = extractTag(name: "assistant_message", from: xml) ?? ""
        
        let safeActions = extractTags(name: "safe_actions", from: xml).flatMap { 
            extractSelfClosingTags(name: "action", from: $0) 
        }.compactMap { attrs -> CoCaptainAgentAction? in
            guard let id = attrs["id"] else { return nil }
            return CoCaptainAgentAction(actionID: id, args: actionArgs(from: attrs))
        }
        
        let pendingActions = extractTags(name: "pending_actions", from: xml).flatMap { 
            extractSelfClosingTags(name: "action", from: $0) 
        }.compactMap { attrs -> CoCaptainAgentAction? in
            guard let id = attrs["id"] else { return nil }
            return CoCaptainAgentAction(actionID: id, args: actionArgs(from: attrs))
        }

        // Legacy `node_edit` elements are ignored; Mini-App code edits are retired.
        let payload = CoCaptainAgentPayload(
            assistantMessage: assistantMessage,
            safeActions: safeActions,
            pendingActions: pendingActions,
            clarifyingQuestion: extractClarifyingQuestion(from: xml)
        )

        return CoCaptainParsedResponse(preamble: preamble, payload: payload)
    }

    /// Extracts the first well-formed `clarifying_question` element. Malformed
    /// questions (empty prompt or fewer than two options) degrade gracefully to
    /// `nil` so the turn falls back to prose instead of failing validation.
    private func extractClarifyingQuestion(from xml: String) -> CoCaptainClarifyingQuestion? {
        guard let match = extractTagMatches(name: "clarifying_question", from: xml).first else {
            return nil
        }

        let prompt = (match.attributes["prompt"] ?? extractTag(name: "prompt", from: match.content) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let options = extractTags(name: "option", from: match.content)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !prompt.isEmpty,
              options.count >= CoCaptainClarifyingQuestion.minimumOptions else {
            return nil
        }

        return CoCaptainClarifyingQuestion(
            prompt: prompt,
            options: Array(options.prefix(CoCaptainClarifyingQuestion.maximumOptions))
        )
    }

    /// Returns the range of the last fully closed `cocaptain_actions` block.
    /// Earlier complete blocks are ignored so a repaired trailing payload wins.
    private func lastCompleteActionsBlock(in response: String) -> Range<String.Index>? {
        var searchStart = response.startIndex
        var lastComplete: Range<String.Index>?

        while let start = response.range(of: Self.startTag, range: searchStart..<response.endIndex) {
            guard let end = response.range(of: Self.endTag, range: start.upperBound..<response.endIndex) else {
                break
            }
            lastComplete = start.lowerBound..<end.upperBound
            searchStart = end.upperBound
        }

        return lastComplete
    }

    /// Returns the text that is safe to stream into the chat bubble.
    public func visibleText(from response: String) -> String {
        if let range = response.range(of: Self.startTag) {
            return response[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - XML Extraction Helpers

    /// Extracts the inner content of the first matching XML tag.
    /// - Parameters:
    ///   - name: The name of the XML tag to find.
    ///   - text: The raw text containing XML.
    /// - Returns: The trimmed inner content, or `nil` if the tag is not found.
    private func extractTag(name: String, from text: String) -> String? {
        let pattern = "<\(name)\\s*>(.*?)</\(name)\\s*>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex?.firstMatch(in: text, options: [], range: nsRange) {
            if let range = Range(match.range(at: 1), in: text) {
                return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    /// Represents a matched XML tag including its inner content and parsed attributes.
    private struct TagMatch {
        /// The inner text content of the tag.
        let content: String
        /// Dictionary of all key-value attributes parsed from the opening tag.
        let attributes: [String: String]
    }

    /// Extracts the inner content of all occurrences of a specified XML tag.
    /// - Returns: An array of trimmed strings for every matching tag.
    private func extractTags(name: String, from text: String) -> [String] {
        let pattern = "<\(name)(?:\\s[^>]*)?>(.*?)</\(name)\\s*>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex?.matches(in: text, options: [], range: nsRange) ?? []
        return matches.compactMap { match in
            if let range = Range(match.range(at: 1), in: text) {
                return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }
    }

    /// Extracts all occurrences of a specified XML tag, parsing both attributes and inner content.
    /// - Returns: An array of `TagMatch` objects containing the parsed data.
    private func extractTagMatches(name: String, from text: String) -> [TagMatch] {
        let pattern = "<\(name)(\\s[^>]*)?>(.*?)</\(name)\\s*>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex?.matches(in: text, options: [], range: nsRange) ?? []
        return matches.compactMap { match in
            guard let contentRange = Range(match.range(at: 2), in: text) else { return nil }
            
            let attrString = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
            let content = String(text[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let attributes = parseAttributes(attrString)
            
            return TagMatch(content: content, attributes: attributes)
        }
    }

    /// Extracts the attributes from all self-closing occurrences of a specified XML tag.
    /// - Returns: An array of attribute dictionaries for each matching tag.
    private func extractSelfClosingTags(name: String, from text: String) -> [[String: String]] {
        let pattern = "<\(name)\\s+([^>]*?)/\\s*>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex?.matches(in: text, options: [], range: nsRange) ?? []
        return matches.compactMap { match in
            if let range = Range(match.range(at: 1), in: text) {
                return parseAttributes(String(text[range]))
            }
            return nil
        }
    }

    /// Parses raw attribute strings (e.g. `key="value" key='value' key=value`) into a dictionary.
    private func parseAttributes(_ attrString: String) -> [String: String] {
        var attributes: [String: String] = [:]
        // Robust attribute parsing: handles key="val", key='val', or key=val (unquoted)
        // and allows optional whitespace around the equals sign.
        let pattern = "(\\w+)\\s*=\\s*(?:[\"']([^\"']*)[\"']|([^\\s>]+))"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsRange = NSRange(attrString.startIndex..<attrString.endIndex, in: attrString)
        let matches = regex?.matches(in: attrString, options: [], range: nsRange) ?? []
        for match in matches {
            if let keyRange = Range(match.range(at: 1), in: attrString) {
                let key = String(attrString[keyRange])
                if let valRange = Range(match.range(at: 2), in: attrString) {
                    attributes[key] = String(attrString[valRange])
                } else if let valRange = Range(match.range(at: 3), in: attrString) {
                    attributes[key] = String(attrString[valRange])
                }
            }
        }
        return attributes
    }

    private func actionArgs(from attributes: [String: String]) -> [String: String]? {
        let args = attributes.filter { $0.key != "id" }
        return args.isEmpty ? nil : args
    }

    private func parseLoosePayload(_ response: String) -> CoCaptainParsedResponse? {
        guard let objectStart = response.lastIndex(of: "{") else { return nil }
        let objectText = String(response[objectStart...])
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
        guard let data = objectText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assistantMessage = object["assistantMessage"] as? String else {
            return nil
        }

        let preamble = String(response[..<objectStart])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CoCaptainParsedResponse(
            preamble: preamble,
            payload: CoCaptainAgentPayload(assistantMessage: assistantMessage)
        )
    }
}
