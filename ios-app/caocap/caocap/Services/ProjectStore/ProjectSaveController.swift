import Foundation
import Observation
import OSLog

@Observable
@MainActor
public final class ProjectSaveController {
    public var isSaving: Bool = false
    private var activeVisualSavesCount: Int = 0
    private var activeWritesCount: Int = 0
    private var saveTask: Task<Void, Never>?
    
    private let persistence: ProjectPersistenceService
    private let persistenceWriter: ProjectPersistenceWriter
    private let logger = Logger(subsystem: "com.caocap.app", category: "Persistence")
    
    public init(
        persistence: ProjectPersistenceService
    ) {
        self.persistence = persistence
        self.persistenceWriter = ProjectPersistenceWriter(persistence: persistence)
    }
    
    public func save(snapshot: ProjectSnapshot, fileName: String, showIndicator: Bool = true) {
        activeWritesCount += 1
        if showIndicator {
            activeVisualSavesCount += 1
            isSaving = true
        }

        let writer = persistenceWriter
        let log = logger
        
        Task(priority: .background) {
            let saveState = PerformanceSignposts.begin(PerformanceSignposts.Name.save)
            do {
                try await writer.save(snapshot, fileName: fileName)
                log.info("Successfully saved project to disk.")
            } catch {
                log.error("Failed to save project: \(error.localizedDescription)")
            }
            PerformanceSignposts.end(PerformanceSignposts.Name.save, saveState)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.activeWritesCount = max(0, self.activeWritesCount - 1)
                if showIndicator {
                    self.activeVisualSavesCount = max(0, self.activeVisualSavesCount - 1)
                    if self.activeVisualSavesCount == 0 {
                        self.isSaving = false
                    }
                }
            }
        }
    }

    public func cancelPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        if activeVisualSavesCount == 0 {
            isSaving = false
        }
    }

    public func waitForActiveWrites() async {
        while activeWritesCount > 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
    
    public func requestSave(
        showIndicator: Bool = true,
        fileName: String,
        snapshotFactory: @escaping @MainActor () -> ProjectSnapshot,
        onDebounceComplete: (@MainActor () -> Void)? = nil
    ) {
        saveTask?.cancel()
        
        if showIndicator {
            isSaving = true
        }
        
        let shouldShowIndicatorOnSave = showIndicator || isSaving
        
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            if !Task.isCancelled {
                onDebounceComplete?()
                let snapshot = snapshotFactory()
                save(snapshot: snapshot, fileName: fileName, showIndicator: shouldShowIndicatorOnSave)
                saveTask = nil
            }
        }
    }
}
