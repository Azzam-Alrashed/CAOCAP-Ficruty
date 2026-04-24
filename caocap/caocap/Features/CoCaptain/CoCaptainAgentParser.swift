import Foundation

public struct CoCaptainAgentParser {
    private static let fence = "```cocaptain-actions"

    public init() {}

    public func parse(_ response: String) -> CoCaptainParsedResponse {
        guard let startRange = response.range(of: Self.fence, options: .backwards) else {
            return CoCaptainParsedResponse(visibleText: response.trimmingCharacters(in: .whitespacesAndNewlines), payload: nil)
        }

        guard let jsonStart = response[startRange.upperBound...].firstIndex(of: "\n"),
              let endRange = response.range(of: "\n```", range: jsonStart..<response.endIndex) else {
            return CoCaptainParsedResponse(visibleText: response.trimmingCharacters(in: .whitespacesAndNewlines), payload: nil)
        }

        let visibleText = String(response[..<startRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonRange = response.index(after: jsonStart)..<endRange.lowerBound
        let json = String(response[jsonRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(CoCaptainAgentPayload.self, from: data) else {
            return CoCaptainParsedResponse(visibleText: visibleText.isEmpty ? response.trimmingCharacters(in: .whitespacesAndNewlines) : visibleText, payload: nil)
        }

        let resolvedVisibleText = visibleText.isEmpty ? payload.assistantMessage : visibleText
        return CoCaptainParsedResponse(visibleText: resolvedVisibleText, payload: payload)
    }

    public func visibleText(from response: String) -> String {
        if let range = response.range(of: Self.fence) {
            return String(response[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
