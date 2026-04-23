import SwiftUI
import Observation

@MainActor
@Observable
public class CoCaptainViewModel {
    public var isPresented: Bool = false
    public var messages: [ChatMessage] = [
        ChatMessage(text: "Hello! I'm your Co-Captain. How can I help you build today?", isUser: false)
    ]
    
    public var store: ProjectStore?
    
    public init() {}
    
    public func setPresented(_ presented: Bool) {
        if !presented {
            // Cancel any in-flight stream when the sheet is dismissed
            streamingTask?.cancel()
            streamingTask = nil
            isThinking = false
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPresented = presented
        }
    }
    
    /// Holds the active streaming task so it can be cancelled on dismiss.
    private var streamingTask: Task<Void, Never>?
    
    public var isThinking: Bool = false
    
    public func sendMessage(_ text: String) {
        let userMessage = ChatMessage(text: text, isUser: true)
        messages.append(userMessage)
        
        isThinking = true

        // Placeholder message updated in real-time as tokens arrive
        let aiMessageId = UUID()
        messages.append(ChatMessage(id: aiMessageId, text: "", isUser: false))

        streamingTask = Task {
            do {
                var fullResponse = ""
                for try await chunk in LLMService.shared.streamResponse(for: text) {
                    fullResponse += chunk
                    if let index = messages.firstIndex(where: { $0.id == aiMessageId }) {
                        messages[index] = ChatMessage(id: aiMessageId, text: fullResponse, isUser: false)
                    }
                }
            } catch {
                if let index = messages.firstIndex(where: { $0.id == aiMessageId }) {
                    messages[index] = ChatMessage(
                        id: aiMessageId,
                        text: "Sorry, I hit an error: \(error.localizedDescription)",
                        isUser: false
                    )
                }
            }
            isThinking = false
        }
    }
    
}

public struct ChatMessage: Identifiable, Hashable {
    public let id: UUID
    public let text: String
    public let isUser: Bool
    
    public init(id: UUID = UUID(), text: String, isUser: Bool) {
        self.id = id
        self.text = text
        self.isUser = isUser
    }
    
    /// Returns the text as an AttributedString with markdown support.
    public var attributedText: AttributedString {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        } else {
            return AttributedString(text)
        }
    }
}

extension AttributedString {
    init(_ text: String) {
        self = AttributedString(stringLiteral: text)
    }
}
