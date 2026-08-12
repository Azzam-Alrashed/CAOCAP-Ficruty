import AVFoundation
import FirebaseAILogic
import Foundation
import OSLog
import Observation

/// Manages a Gemini Live session for copilot screen-share calls.
@MainActor
@Observable
final class GeminiLiveSessionService {
    enum ConnectionState: Equatable {
        case idle
        case connecting
        case connected
        case ended
        case failed(String)
    }

    private(set) var connectionState: ConnectionState = .idle
    private(set) var inputTranscript: String = ""
    private(set) var outputTranscript: String = ""
    private(set) var isMuted = false
    /// Whether ReplayKit screen frames are currently being sent to the live session.
    private(set) var isScreenSharing = false
    /// True when the free-tier monthly CoCaptain budget blocked or ended the call.
    private(set) var isQuotaExceeded = false

    private let logger = Logger(subsystem: "CAOCAP", category: "GeminiLive")
    private let audioEngine = CopilotCallAudioEngine()
    private let screenCapture = ScreenCaptureController()
    private let tokenUsageLimiter = TokenUsageLimiter.shared
    private let subscriptionManager = SubscriptionManager.shared

    private var liveSession: LiveSession?
    private var receiveTask: Task<Void, Never>?
    private var quotaWatchTask: Task<Void, Never>?
    private var mode: CopilotInteractionMode = .video
    private var sessionContextPrompt = ""
    private var accumulatedInputTranscript = ""
    private var accumulatedOutputTranscript = ""
    private var sessionStartedAt: Date?
    private var didRecordUsage = false
    private var didUseScreenShare = false

    static let liveModelName = "gemini-3.1-flash-live-preview"

    func start(
        mode: CopilotInteractionMode,
        persona: CopilotPersona,
        projectContext: String?
    ) async {
        await stop(recordUsage: false)
        self.mode = mode
        connectionState = .connecting
        isQuotaExceeded = false
        isScreenSharing = false
        didUseScreenShare = false
        inputTranscript = ""
        outputTranscript = ""
        accumulatedInputTranscript = ""
        accumulatedOutputTranscript = ""
        didRecordUsage = false
        sessionStartedAt = nil

        do {
            guard await requestMicrophoneAuthorization() else {
                connectionState = .failed(
                    LocalizationManager.shared.localizedString("copilot.call.micPermissionDenied")
                )
                return
            }

            let systemText = Self.systemInstruction(persona: persona, projectContext: projectContext, mode: mode)
            sessionContextPrompt = systemText

            await subscriptionManager.refreshEntitlements()
            if case .failure(let error) = tokenUsageLimiter.preflightLiveSession(
                contextPrompt: systemText,
                isSubscribed: subscriptionManager.isSubscribed
            ) {
                isQuotaExceeded = true
                connectionState = .failed(error.localizedDescription)
                return
            }

            let liveModel = FirebaseAI.firebaseAI(backend: .googleAI()).liveModel(
                modelName: Self.liveModelName,
                generationConfig: LiveGenerationConfig(
                    responseModalities: [.audio],
                    speech: SpeechConfig(voiceName: persona.liveVoiceName),
                    inputAudioTranscription: AudioTranscriptionConfig(),
                    outputAudioTranscription: AudioTranscriptionConfig()
                ),
                systemInstruction: ModelContent(role: "system", parts: systemText)
            )

            let session = try await liveModel.connect()
            liveSession = session
            sessionStartedAt = Date()

            audioEngine.onPCMChunk = { [weak self] data in
                Task { @MainActor in
                    await self?.liveSession?.sendAudioRealtime(data)
                }
            }
            try audioEngine.start()

            if mode == .video {
                startScreenShare()
            }

            connectionState = .connected
            receiveTask = Task { [weak self] in
                await self?.consumeResponses(from: session)
            }
            quotaWatchTask = Task { [weak self] in
                await self?.watchFreeTierQuota()
            }

            await session.sendTextRealtime(
                LocalizationManager.shared.localizedString(
                    "copilot.call.greetingPrompt",
                    arguments: [persona.displayName]
                )
            )
        } catch {
            logger.error("Live connect failed: \(error.localizedDescription, privacy: .public)")
            connectionState = .failed(error.localizedDescription)
            await stop(recordUsage: false)
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        audioEngine.setMuted(muted)
    }

    func setScreenSharing(_ enabled: Bool) {
        guard case .connected = connectionState else { return }
        if enabled {
            startScreenShare()
        } else {
            stopScreenShare()
        }
    }

    func stop() async {
        await stop(recordUsage: true)
    }

    private func startScreenShare() {
        guard !isScreenSharing else { return }

        screenCapture.onJPEGFrame = { [weak self] jpeg in
            Task { @MainActor in
                await self?.liveSession?.sendVideoRealtime(jpeg, mimeType: "image/jpeg")
            }
        }
        screenCapture.onStarted = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isScreenSharing = true
                self.didUseScreenShare = true
            }
        }
        screenCapture.onError = { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.logger.error("Screen capture error: \(error.localizedDescription, privacy: .public)")
                self.stopScreenShare()
            }
        }

        screenCapture.start()
    }

    private func stopScreenShare() {
        screenCapture.stop()
        screenCapture.onJPEGFrame = nil
        screenCapture.onStarted = nil
        screenCapture.onError = nil
        isScreenSharing = false
    }

    private func stop(recordUsage: Bool) async {
        quotaWatchTask?.cancel()
        quotaWatchTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        stopScreenShare()
        audioEngine.stop()
        if let liveSession {
            await liveSession.close()
        }
        liveSession = nil

        if recordUsage {
            recordLiveUsageIfNeeded()
        }

        if case .failed = connectionState {
            // keep failure message
        } else if connectionState != .idle {
            connectionState = .ended
        }
    }

    private func consumeResponses(from session: LiveSession) async {
        do {
            for try await message in session.responses {
                if Task.isCancelled { break }
                switch message.payload {
                case .content(let content):
                    if content.wasInterrupted {
                        audioEngine.clearPlayback()
                    }
                    if let input = content.inputAudioTranscription?.text, !input.isEmpty {
                        inputTranscript = input
                        appendUniqueTranscript(&accumulatedInputTranscript, input)
                    }
                    if let output = content.outputAudioTranscription?.text, !output.isEmpty {
                        outputTranscript = output
                        appendUniqueTranscript(&accumulatedOutputTranscript, output)
                    }
                    content.modelTurn?.parts.forEach { part in
                        if let inline = part as? InlineDataPart,
                           inline.mimeType.starts(with: "audio/pcm") {
                            audioEngine.enqueuePlaybackPCM16(inline.data)
                        }
                    }
                case .toolCall, .toolCallCancellation, .goingAwayNotice:
                    break
                @unknown default:
                    break
                }
            }
        } catch {
            if !Task.isCancelled {
                logger.error("Live receive failed: \(error.localizedDescription, privacy: .public)")
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    private func watchFreeTierQuota() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { break }
            guard case .connected = connectionState else { break }

            await subscriptionManager.refreshEntitlements()
            let duration = sessionStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            if tokenUsageLimiter.shouldEndLiveSession(
                contextPrompt: sessionContextPrompt,
                inputTranscript: accumulatedInputTranscript,
                outputTranscript: accumulatedOutputTranscript,
                duration: duration,
                includesScreenShare: didUseScreenShare,
                isSubscribed: subscriptionManager.isSubscribed
            ) {
                isQuotaExceeded = true
                connectionState = .failed(
                    TokenUsageLimitError(
                        limitTokens: TokenUsageLimiter.freeMonthlyTokenLimit,
                        usedTokens: tokenUsageLimiter.status().usedTokens,
                        requestedTokens: 0
                    ).localizedDescription
                )
                await stop(recordUsage: true)
                break
            }
        }
    }

    private func recordLiveUsageIfNeeded() {
        guard !didRecordUsage else { return }
        guard let startedAt = sessionStartedAt else { return }
        didRecordUsage = true

        let duration = Date().timeIntervalSince(startedAt)
        tokenUsageLimiter.recordLiveSession(
            contextPrompt: sessionContextPrompt,
            inputTranscript: accumulatedInputTranscript,
            outputTranscript: accumulatedOutputTranscript,
            duration: duration,
            includesScreenShare: didUseScreenShare,
            isSubscribed: subscriptionManager.isSubscribed
        )
    }

    private func appendUniqueTranscript(_ store: inout String, _ snippet: String) {
        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if store.isEmpty {
            store = trimmed
        } else if !store.contains(trimmed) {
            store += "\n" + trimmed
        } else if trimmed.count > store.count {
            store = trimmed
        }
    }

    private static func systemInstruction(
        persona: CopilotPersona,
        projectContext: String?,
        mode: CopilotInteractionMode
    ) -> String {
        var lines = [
            "You are \(persona.displayName), the user's copilot in CAOCAP.",
            LocalizationManager.shared.localizedString(persona.roleKey),
            persona.mantra,
            "Keep spoken replies concise and helpful for building on an infinite canvas."
        ]
        if mode == .video {
            lines.append(
                "The user is sharing their app screen. Use the screen frames to understand their canvas and guide them."
            )
        }
        if let projectContext, !projectContext.isEmpty {
            lines.append("Project context:\n\(projectContext)")
        }
        return lines.joined(separator: "\n")
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
