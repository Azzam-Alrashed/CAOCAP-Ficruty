import Foundation
import FirebaseAILogic
import OSLog

/// A singleton service that manages the interaction with the Gemini LLM via Firebase AI Logic.
///
/// Uses `FirebaseAI.firebaseAI(backend: .googleAI())` — the correct Firebase AI Logic
/// Swift API as of the `FirebaseAILogic` SDK.
///
/// Provides a streaming interface and maintains chat history for multi-turn conversations.
@MainActor
public final class LLMService {

    public static let shared = LLMService()

    private let logger = Logger(subsystem: "com.ficruty.caocap", category: "LLMService")

    // MARK: - Model & Session

    /// Lazily initialised so Firebase is guaranteed to be configured before first use.
    private lazy var model: GenerativeModel = {
        FirebaseAI.firebaseAI(backend: .googleAI()).generativeModel(
            modelName: "gemini-3-flash-preview",
            systemInstruction: ModelContent(
                role: "system",
                parts: """
                You are Co-Captain, a spatial programming assistant for the Ficruty platform.
                Your goal is to help users build web applications using a node-based spatial canvas.

                Personality:
                - Encouraging, technical, and concise.
                - You embrace "vibe coding" — thinking in terms of intents, nodes, and flows.
                - Your primary languages are HTML, CSS, and JavaScript.

                Instructions:
                - When providing code, always wrap it in Markdown code blocks with the language identifier.
                - If a user describes a feature, suggest how they could break it into spatial nodes.
                - Never reveal that you are an AI; simply act as the Co-Captain.
                """
            )
        )
    }()

    /// The active chat session that maintains history.
    private var chat: Chat?

    private init() {}

    // MARK: - API

    /// Resets the current chat session, clearing all history.
    public func resetChat() {
        chat = nil
        logger.info("Chat session reset.")
    }

    /// Generates a streaming response for the given user prompt, maintaining conversation history.
    ///
    /// - Parameter prompt: The raw user message.
    /// - Returns: An `AsyncThrowingStream` of partial response strings.
    public func streamResponse(for prompt: String) -> AsyncThrowingStream<String, Error> {
        // Initialize chat session if it doesn't exist
        if chat == nil {
            chat = model.startChat()
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    logger.debug("Starting LLM stream with history.")
                    
                    // Use sendMessageStream to participate in the multi-turn session
                    let stream = try chat!.sendMessageStream(prompt)
                    
                    for try await chunk in stream {
                        if let text = chunk.text {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                    logger.info("LLM stream completed.")
                } catch {
                    logger.error("LLM stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
            // Support cooperative cancellation from the caller side
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
