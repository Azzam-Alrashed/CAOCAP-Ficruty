import Foundation
import LiteRTLM
import Observation
import OSLog

enum LocalGemmaModelError: LocalizedError {
    case unsupportedDevice
    case insufficientStorage(required: String)
    case invalidServerResponse
    case incompleteDownload
    case modelNotDownloaded

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice:
            return String(
                localized: "Gemma 4 requires an iPhone 15 Pro or newer iPhone, or an iPad with an M-series chip."
            )
        case .insufficientStorage(let required):
            return String(
                format: String(localized: "Free at least %@ of device storage, then try again."),
                required
            )
        case .invalidServerResponse:
            return String(
                localized: "The Gemma model server did not return the expected file. Please try again later."
            )
        case .incompleteDownload:
            return String(
                localized: "The Gemma model download was incomplete. Please retry the download."
            )
        case .modelNotDownloaded:
            return String(localized: "Download Gemma 4 in Settings before using it offline.")
        }
    }
}

struct LocalGemmaModelStore: Sendable {
    static let modelFileName = "gemma-4-E2B-it.litertlm"
    static let minimumValidModelBytes: Int64 = 2_588_147_712
    static let requiredAvailableCapacity: Int64 = 3_500_000_000

    let directory: URL
    let minimumValidModelBytes: Int64

    init(
        directory: URL = Self.defaultDirectory,
        minimumValidModelBytes: Int64 = Self.minimumValidModelBytes
    ) {
        self.directory = directory
        self.minimumValidModelBytes = minimumValidModelBytes
    }

    var modelURL: URL {
        directory.appendingPathComponent(Self.modelFileName, isDirectory: false)
    }

    var partialDownloadURL: URL {
        directory.appendingPathComponent("\(Self.modelFileName).partial", isDirectory: false)
    }

    func inspect() -> (isReady: Bool, size: Int64) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: modelURL.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return (size >= minimumValidModelBytes, size)
    }

    func availableCapacity() -> Int64? {
        let fileManager = FileManager.default
        var existingAncestor = directory
        while !fileManager.fileExists(atPath: existingAncestor.path),
              existingAncestor.path != "/" {
            existingAncestor.deleteLastPathComponent()
        }
        let values = try? existingAncestor.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage
    }

    func removeModel() throws {
        let fileManager = FileManager.default
        for url in [modelURL, partialDownloadURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    static var defaultDirectory: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appendingPathComponent("LocalModels", isDirectory: true)
            .appendingPathComponent("Gemma4E2B", isDirectory: true)
    }

    static var legacyMLXDirectory: URL {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documents.appendingPathComponent("huggingface", isDirectory: true)
    }
}

protocol LocalGemmaModelDownloading: Sendable {
    func download(
        from sourceURL: URL,
        to store: LocalGemmaModelStore,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

struct URLSessionGemmaModelDownloader: LocalGemmaModelDownloading {
    func download(
        from sourceURL: URL,
        to store: LocalGemmaModelStore,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let operation = GemmaDownloadOperation(
            sourceURL: sourceURL,
            store: store,
            progress: progress
        )
        try await withTaskCancellationHandler {
            try await operation.start()
        } onCancel: {
            operation.cancel()
        }
    }
}

private final class GemmaDownloadOperation: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let sourceURL: URL
    private let store: LocalGemmaModelStore
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()

    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var isFinished = false
    private var isCancelled = false

    init(
        sourceURL: URL,
        store: LocalGemmaModelStore,
        progress: @escaping @Sendable (Double) -> Void
    ) {
        self.sourceURL = sourceURL
        self.store = store
        self.progress = progress
    }

    func start() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock {
                guard !isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation

                var request = URLRequest(url: sourceURL)
                request.timeoutInterval = 120
                request.setValue("CAOCAP/1.0", forHTTPHeaderField: "User-Agent")

                let configuration = URLSessionConfiguration.default
                configuration.timeoutIntervalForResource = 60 * 60 * 6
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.downloadTask(with: request)
                self.task = task
                task.resume()
            }
        }
    }

    func cancel() {
        lock.withLock {
            isCancelled = true
            task?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw LocalGemmaModelError.invalidServerResponse
            }

            let fileManager = FileManager.default
            try fileManager.createDirectory(at: store.directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: store.partialDownloadURL.path) {
                try fileManager.removeItem(at: store.partialDownloadURL)
            }
            try fileManager.moveItem(at: location, to: store.partialDownloadURL)

            let attributes = try fileManager.attributesOfItem(atPath: store.partialDownloadURL.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard size >= store.minimumValidModelBytes else {
                try? fileManager.removeItem(at: store.partialDownloadURL)
                throw LocalGemmaModelError.incompleteDownload
            }

            if fileManager.fileExists(atPath: store.modelURL.path) {
                try fileManager.removeItem(at: store.modelURL)
            }
            try fileManager.moveItem(at: store.partialDownloadURL, to: store.modelURL)
            var modelURL = store.modelURL
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try modelURL.setResourceValues(resourceValues)
            progress(1)
            finish(with: .success(()))
        } catch {
            finish(with: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(with: .failure(error))
        }
    }

    private func finish(with result: Result<Void, Error>) {
        let continuation: CheckedContinuation<Void, Error>? = lock.withLock {
            guard !isFinished else { return nil }
            isFinished = true
            let continuation = self.continuation
            self.continuation = nil
            task = nil
            session?.finishTasksAndInvalidate()
            session = nil
            return continuation
        }

        switch result {
        case .success:
            continuation?.resume()
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}

@Observable @MainActor
public final class LocalGemmaModelManager {
    public static let shared = LocalGemmaModelManager(purgesLegacyArtifacts: true)

    private static let sourceURL = URL(
        string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/9262660a1676eed6d0c477ab1a86344430854664/gemma-4-E2B-it.litertlm"
    )!

    private let logger = Logger(subsystem: "com.caocap.app", category: "LocalGemmaModelManager")
    private let store: LocalGemmaModelStore
    private let downloader: any LocalGemmaModelDownloading
    private let eligibility: LocalModelDeviceEligibility
    private let availableCapacityProvider: @Sendable () -> Int64?
    private let engineCacheDirectory: URL
    private let streamProvider: (@MainActor @Sendable (String, CoCaptainAgentScope) -> AsyncThrowingStream<String, Error>)?
    @ObservationIgnored
    private var legacyCleanupTask: Task<Void, Never>?
    @ObservationIgnored
    private var generationTasks: [CoCaptainAgentScope: (id: UUID, task: Task<Void, Never>)] = [:]
    private var downloadTask: Task<Void, Never>?
    private var engine: Engine?
    private var conversations: [CoCaptainAgentScope: Conversation] = [:]

    public private(set) var isDownloadingLocalModel = false
    public private(set) var localModelDownloadProgress = 0.0
    public private(set) var localModelError: String?
    public private(set) var isLocalModelCached = false
    public private(set) var localModelCacheSizeFormatted = "0 MB"

    init(
        store: LocalGemmaModelStore = LocalGemmaModelStore(),
        downloader: any LocalGemmaModelDownloading = URLSessionGemmaModelDownloader(),
        eligibility: LocalModelDeviceEligibility = .current,
        purgesLegacyArtifacts: Bool = false,
        availableCapacityProvider: (@Sendable () -> Int64?)? = nil,
        engineCacheDirectory: URL? = nil,
        streamProvider: (@MainActor @Sendable (String, CoCaptainAgentScope) -> AsyncThrowingStream<String, Error>)? = nil
    ) {
        self.store = store
        self.downloader = downloader
        self.eligibility = eligibility
        self.availableCapacityProvider = availableCapacityProvider ?? {
            store.availableCapacity()
        }
        self.engineCacheDirectory = engineCacheDirectory ?? Self.defaultEngineCacheDirectory
        self.streamProvider = streamProvider

        if purgesLegacyArtifacts {
            UserDefaults.standard.removeObject(forKey: "cocaptain.hfToken")
            let legacyDirectory = LocalGemmaModelStore.legacyMLXDirectory
            let logger = logger
            legacyCleanupTask = Task {
                await Task.detached(priority: .utility) {
                    let fileManager = FileManager.default
                    guard fileManager.fileExists(atPath: legacyDirectory.path) else { return }
                    do {
                        try fileManager.removeItem(at: legacyDirectory)
                        logger.info("Removed legacy MLX model artifacts.")
                    } catch {
                        logger.error(
                            "Failed to remove legacy MLX artifacts: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }.value
            }
        }

        refreshCacheSize()
    }

    public func refreshCacheSize() {
        let store = store
        Task {
            let inspection = await Task.detached(priority: .utility) {
                store.inspect()
            }.value
            isLocalModelCached = inspection.isReady
            localModelCacheSizeFormatted = Self.formattedSize(inspection.size)
        }
    }

    public func downloadLocalModel() {
        guard downloadTask == nil else { return }
        guard eligibility.isSupported else {
            localModelError = LocalGemmaModelError.unsupportedDevice.localizedDescription
            return
        }

        isDownloadingLocalModel = true
        localModelDownloadProgress = 0
        localModelError = nil

        let store = store
        let downloader = downloader
        downloadTask = Task {
            defer {
                isDownloadingLocalModel = false
                downloadTask = nil
                refreshCacheSize()
            }

            await legacyCleanupTask?.value
            let availableCapacityProvider = availableCapacityProvider
            let availableCapacity = await Task.detached(priority: .utility) {
                availableCapacityProvider()
            }.value
            if let availableCapacity,
               availableCapacity < LocalGemmaModelStore.requiredAvailableCapacity {
                localModelError = LocalGemmaModelError.insufficientStorage(
                    required: "3.5 GB"
                ).localizedDescription
                return
            }
            guard !Task.isCancelled else { return }

            do {
                try await downloader.download(from: Self.sourceURL, to: store) { progress in
                    Task { @MainActor [weak self] in
                        self?.localModelDownloadProgress = progress
                    }
                }
                logger.info("Gemma 4 LiteRT model downloaded successfully.")
            } catch is CancellationError {
                logger.info("Gemma 4 LiteRT model download cancelled.")
            } catch let error as URLError where error.code == .cancelled {
                logger.info("Gemma 4 LiteRT model download cancelled.")
            } catch {
                logger.error("Gemma 4 LiteRT model download failed: \(error.localizedDescription, privacy: .public)")
                localModelError = error.localizedDescription
            }
        }
    }

    public func cancelDownload() {
        downloadTask?.cancel()
    }

    public func clearLocalModelCache() {
        cancelDownload()
        for activeGeneration in generationTasks.values {
            activeGeneration.task.cancel()
        }
        generationTasks.removeAll()
        for conversation in conversations.values {
            try? conversation.cancel()
        }
        conversations.removeAll()
        engine = nil
        let store = store
        let engineCacheDirectory = engineCacheDirectory
        Task {
            do {
                try await Task.detached(priority: .utility) {
                    try store.removeModel()
                    let fileManager = FileManager.default
                    if fileManager.fileExists(atPath: engineCacheDirectory.path) {
                        try fileManager.removeItem(at: engineCacheDirectory)
                    }
                }.value
                localModelError = nil
            } catch {
                logger.error("Failed to remove Gemma 4 LiteRT model: \(error.localizedDescription, privacy: .public)")
                localModelError = error.localizedDescription
            }
            refreshCacheSize()
        }
    }

    public func preloadLocalModelIfNeeded() {
        guard eligibility.isSupported,
              CoCaptainModelSelectionPolicy.resolvedModelName(
                UserDefaults.standard.string(forKey: "cocaptain.modelName"),
                eligibility: eligibility
              ) == CoCaptainModelSelectionPolicy.localModelName else {
            return
        }

        let store = store
        Task {
            let isReady = await Task.detached(priority: .utility) {
                store.inspect().isReady
            }.value
            guard isReady else { return }

            do {
                _ = try await conversation(for: .project)
                logger.info("Gemma 4 LiteRT model preloaded successfully.")
            } catch {
                logger.error("Gemma 4 LiteRT preload failed: \(error.localizedDescription, privacy: .public)")
                localModelError = error.localizedDescription
            }
        }
    }

    public func resetChat(scope: CoCaptainAgentScope) {
        generationTasks[scope]?.task.cancel()
        generationTasks[scope] = nil
        try? conversations[scope]?.cancel()
        conversations[scope] = nil
    }

    public func streamResponse(
        to prompt: String,
        scope: CoCaptainAgentScope
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            if generationTasks[scope] != nil {
                resetChat(scope: scope)
            }
            let generationID = UUID()
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish(throwing: CancellationError())
                    return
                }

                do {
                    try Task.checkCancellation()
                    if let streamProvider {
                        for try await chunk in streamProvider(prompt, scope) {
                            try Task.checkCancellation()
                            continuation.yield(chunk)
                        }
                    } else {
                        let conversation = try await conversation(for: scope)
                        try await withTaskCancellationHandler {
                            for try await message in conversation.sendMessageStream(Message(prompt)) {
                                try Task.checkCancellation()
                                let text = message.toString
                                if !text.isEmpty {
                                    continuation.yield(text)
                                }
                            }
                        } onCancel: {
                            try? conversation.cancel()
                        }
                    }
                    continuation.finish()
                } catch {
                    if generationTasks[scope]?.id == generationID {
                        conversations[scope] = nil
                    }
                    continuation.finish(throwing: error)
                }

                if generationTasks[scope]?.id == generationID {
                    generationTasks[scope] = nil
                }
            }
            generationTasks[scope] = (generationID, task)

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func conversation(for scope: CoCaptainAgentScope) async throws -> Conversation {
        if let conversation = conversations[scope], conversation.isAlive {
            return conversation
        }

        let engine = try await initializedEngine()
        let sampler = try SamplerConfig(topK: 40, topP: 0.95, temperature: 0.7)
        let config = ConversationConfig(
            systemMessage: Message(Self.systemInstructionText, role: .system),
            samplerConfig: sampler
        )
        let conversation = try await engine.createConversation(with: config)
        conversations[scope] = conversation
        return conversation
    }

    private func initializedEngine() async throws -> Engine {
        guard eligibility.isSupported else {
            throw LocalGemmaModelError.unsupportedDevice
        }
        let store = store
        let isReady = await Task.detached(priority: .utility) {
            store.inspect().isReady
        }.value
        guard isReady else {
            throw LocalGemmaModelError.modelNotDownloaded
        }
        if let engine, await engine.isInitialized() {
            return engine
        }

        let engineCacheDirectory = engineCacheDirectory
        let cacheDirectory = try await Task.detached(priority: .utility) {
            let cacheDirectory = engineCacheDirectory
            try FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            return cacheDirectory
        }.value

        let config = try EngineConfig(
            modelPath: store.modelURL.path,
            backend: .gpu,
            maxNumTokens: 8_192,
            cacheDir: cacheDirectory.path
        )
        let engine = Engine(engineConfig: config)
        try await engine.initialize()
        self.engine = engine
        return engine
    }

    private static func formattedSize(_ size: Int64) -> String {
        guard size > 0 else { return "0 MB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private static var defaultEngineCacheDirectory: URL {
        FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("LiteRTLM", isDirectory: true)
    }

    private static let systemInstructionText = """
        You are CoCaptain, a spatial programming assistant for CAOCAP.
        Answer ordinary questions conversationally and concisely.
        Only propose app actions when the user explicitly asks to navigate, use a tool, or otherwise change app state.
        Never apply workspace changes yourself. CAOCAP validates every proposal and requires user review before running pending actions.
        When proposing app actions, follow the cocaptain_actions contract included in the user prompt exactly and place the XML block at the end of the response.
        """
}
