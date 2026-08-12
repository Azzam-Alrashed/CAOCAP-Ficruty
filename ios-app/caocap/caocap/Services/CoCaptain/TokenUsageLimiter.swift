import Foundation

/// A snapshot of token consumption for the current billing period.
public struct TokenUsageStatus: Equatable {
    /// A `"YYYY-MM"` key identifying the calendar month this status covers.
    public let periodKey: String
    /// Estimated tokens consumed so far this month.
    public let usedTokens: Int
    /// The maximum tokens allowed this month for the current tier.
    public let limitTokens: Int

    /// How many more tokens the user can spend before hitting the monthly cap.
    public var remainingTokens: Int {
        max(0, limitTokens - usedTokens)
    }
}

/// Thrown by `TokenUsageLimiter.preflight` when the incoming request
/// would push usage past the monthly free-tier cap.
public struct TokenUsageLimitError: LocalizedError, Equatable {
    /// The configured monthly token ceiling.
    public let limitTokens: Int
    /// Tokens already consumed this period before this request.
    public let usedTokens: Int
    /// Estimated cost of the incoming prompt plus the response reserve.
    public let requestedTokens: Int

    public var errorDescription: String? {
        "You've reached this month's free CoCaptain usage for chat and screen-share. Upgrade to Pro to continue, or try again next month."
    }
}

/// Tracks local estimated LLM token usage for the free tier.
///
/// Firebase AI Logic does not currently flow exact usage accounting through
/// CAOCAP's app boundary, so this service uses a conservative character-based
/// estimate and resets usage by calendar month.
public final class TokenUsageLimiter {
    public static let shared = TokenUsageLimiter()

    public static let freeMonthlyTokenLimit = 50_000
    public static let minimumResponseTokenReserve = 1_000
    /// Minimum remaining budget required to start a Gemini Live screen-share call.
    public static let liveSessionMinimumReserve = 2_500
    /// Conservative estimated tokens burned per minute of Live audio.
    public static let liveAudioTokensPerMinute = 1_200
    /// Conservative estimated tokens burned per minute of Live screen-share (audio + frames).
    public static let liveVideoTokensPerMinute = 1_800

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let periodKeyStorageKey = "cocaptain.tokenUsage.period"
    private let usedTokensStorageKey = "cocaptain.tokenUsage.usedTokens"

    public init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    /// Returns the current usage snapshot, resetting the counter automatically
    /// when the calendar month has rolled over.
    public func status(
        limitTokens: Int = TokenUsageLimiter.freeMonthlyTokenLimit,
        now: Date = Date()
    ) -> TokenUsageStatus {
        resetIfNeeded(now: now)
        return TokenUsageStatus(
            periodKey: periodKey(for: now),
            usedTokens: defaults.integer(forKey: usedTokensStorageKey),
            limitTokens: limitTokens
        )
    }

    /// Guards a pending LLM call against the monthly cap before the request is sent.
    ///
    /// Subscribers bypass the check entirely. For free-tier users the prompt's estimated
    /// token cost plus `responseReserveTokens` is added to current usage; if the sum
    /// exceeds the limit, a `TokenUsageLimitError` is returned so the caller can surface
    /// an upgrade prompt instead of sending the request.
    ///
    /// - Parameters:
    ///   - prompt: The full prompt string that will be sent to the model.
    ///   - isSubscribed: Skip enforcement when the user holds an active Pro subscription.
    ///   - limitTokens: Monthly cap; defaults to `freeMonthlyTokenLimit`.
    ///   - responseReserveTokens: Extra tokens reserved for the expected model reply.
    ///   - now: Injection point for the current date (useful in tests).
    public func preflight(
        prompt: String,
        isSubscribed: Bool,
        limitTokens: Int = TokenUsageLimiter.freeMonthlyTokenLimit,
        responseReserveTokens: Int = TokenUsageLimiter.minimumResponseTokenReserve,
        now: Date = Date()
    ) -> Result<Void, TokenUsageLimitError> {
        guard !isSubscribed else { return .success(()) }

        let current = status(limitTokens: limitTokens, now: now)
        let requestedTokens = estimateTokens(in: prompt) + responseReserveTokens

        guard current.usedTokens + requestedTokens <= limitTokens else {
            return .failure(
                TokenUsageLimitError(
                    limitTokens: limitTokens,
                    usedTokens: current.usedTokens,
                    requestedTokens: requestedTokens
                )
            )
        }

        return .success(())
    }

    /// Guards starting a Gemini Live screen-share session against the free-tier monthly cap.
    ///
    /// Uses the session context prompt plus `liveSessionMinimumReserve` so a call cannot
    /// start when the remaining budget is too small for a meaningful Live turn.
    public func preflightLiveSession(
        contextPrompt: String,
        isSubscribed: Bool,
        limitTokens: Int = TokenUsageLimiter.freeMonthlyTokenLimit,
        minimumReserveTokens: Int = TokenUsageLimiter.liveSessionMinimumReserve,
        now: Date = Date()
    ) -> Result<Void, TokenUsageLimitError> {
        preflight(
            prompt: contextPrompt,
            isSubscribed: isSubscribed,
            limitTokens: limitTokens,
            responseReserveTokens: minimumReserveTokens,
            now: now
        )
    }

    /// Records token usage after a completed LLM exchange.
    ///
    /// Call this once the full model response has been streamed so both
    /// the prompt and the actual response length are known. Subscribers
    /// are exempt from tracking.
    public func record(
        prompt: String,
        response: String,
        isSubscribed: Bool,
        now: Date = Date()
    ) {
        guard !isSubscribed else { return }

        resetIfNeeded(now: now)
        let usage = estimateTokens(in: prompt) + estimateTokens(in: response)
        let usedTokens = defaults.integer(forKey: usedTokensStorageKey)
        defaults.set(usedTokens + usage, forKey: usedTokensStorageKey)
    }

    /// Records estimated usage for a completed Gemini Live call.
    ///
    /// Combines context + transcripts with a duration-based surcharge so audio/video
    /// sessions that produce little transcript text still consume free-tier budget.
    public func recordLiveSession(
        contextPrompt: String,
        inputTranscript: String,
        outputTranscript: String,
        duration: TimeInterval,
        includesScreenShare: Bool,
        isSubscribed: Bool,
        now: Date = Date()
    ) {
        guard !isSubscribed else { return }

        resetIfNeeded(now: now)
        let usage = estimateLiveSessionTokens(
            contextPrompt: contextPrompt,
            inputTranscript: inputTranscript,
            outputTranscript: outputTranscript,
            duration: duration,
            includesScreenShare: includesScreenShare
        )
        let usedTokens = defaults.integer(forKey: usedTokensStorageKey)
        defaults.set(usedTokens + usage, forKey: usedTokensStorageKey)
    }

    /// Returns whether a free-tier Live session should end because projected usage
    /// would exhaust the monthly budget (or the budget is already empty).
    public func shouldEndLiveSession(
        contextPrompt: String,
        inputTranscript: String,
        outputTranscript: String,
        duration: TimeInterval,
        includesScreenShare: Bool,
        isSubscribed: Bool,
        limitTokens: Int = TokenUsageLimiter.freeMonthlyTokenLimit,
        now: Date = Date()
    ) -> Bool {
        guard !isSubscribed else { return false }
        let current = status(limitTokens: limitTokens, now: now)
        if current.remainingTokens <= 0 { return true }
        let projected = estimateLiveSessionTokens(
            contextPrompt: contextPrompt,
            inputTranscript: inputTranscript,
            outputTranscript: outputTranscript,
            duration: duration,
            includesScreenShare: includesScreenShare
        )
        return current.usedTokens + projected > limitTokens
    }

    /// Estimates tokens for a Live call from transcripts plus a per-minute audio/video surcharge.
    public func estimateLiveSessionTokens(
        contextPrompt: String,
        inputTranscript: String,
        outputTranscript: String,
        duration: TimeInterval,
        includesScreenShare: Bool
    ) -> Int {
        let transcriptUsage =
            estimateTokens(in: contextPrompt)
            + estimateTokens(in: inputTranscript)
            + estimateTokens(in: outputTranscript)
        let perMinute = includesScreenShare
            ? TokenUsageLimiter.liveVideoTokensPerMinute
            : TokenUsageLimiter.liveAudioTokensPerMinute
        let minutes = max(duration, 15) / 60.0
        let durationUsage = Int(ceil(minutes * Double(perMinute)))
        return transcriptUsage + durationUsage
    }

    /// Resets the usage counter for the given date's period and writes the new period key.
    /// Normally called automatically by `resetIfNeeded`; exposed publicly for testing.
    public func reset(now: Date = Date()) {
        defaults.set(periodKey(for: now), forKey: periodKeyStorageKey)
        defaults.set(0, forKey: usedTokensStorageKey)
    }

    /// Estimates the token count of `text` using a 4-characters-per-token heuristic.
    ///
    /// Firebase AI Logic doesn't expose exact usage through the CAOCAP app boundary,
    /// so a conservative approximation is used to stay within the free-tier envelope.
    public func estimateTokens(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return max(1, Int(ceil(Double(trimmed.count) / 4.0)))
    }

    private func resetIfNeeded(now: Date) {
        let currentPeriod = periodKey(for: now)
        guard defaults.string(forKey: periodKeyStorageKey) != currentPeriod else { return }
        reset(now: now)
    }

    private func periodKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }
}
