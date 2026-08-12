import XCTest
@testable import caocap

@MainActor
final class ProjectSaveControllerTests: XCTestCase {
    var persistence: ProjectPersistenceService!
    var sut: ProjectSaveController!
    
    override func setUp() async throws {
        persistence = ProjectPersistenceService()
        sut = ProjectSaveController(persistence: persistence)
    }
    
    func testSaveTriggersIndicatorAndFinishes() async throws {
        let snapshot = ProjectSnapshot(
            schemaVersion: ProjectStore.currentSchemaVersion,
            projectName: "Test",
            nodes: [],
            viewportOffset: .zero,
            viewportScale: 1.0
        )
        
        XCTAssertFalse(sut.isSaving)
        
        sut.save(snapshot: snapshot, fileName: "test_save.json", showIndicator: true)
        
        XCTAssertTrue(sut.isSaving)
        
        await sut.waitForActiveWrites()
        
        // Back on MainActor it should be false
        XCTAssertFalse(sut.isSaving)
    }
    
    func testSaveWithoutIndicatorDoesNotTriggerIsSaving() async throws {
        let snapshot = ProjectSnapshot(
            schemaVersion: ProjectStore.currentSchemaVersion,
            projectName: "Test",
            nodes: [],
            viewportOffset: .zero,
            viewportScale: 1.0
        )
        
        XCTAssertFalse(sut.isSaving)
        
        sut.save(snapshot: snapshot, fileName: "test_save.json", showIndicator: false)
        
        XCTAssertFalse(sut.isSaving)
        
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    
    func testRequestSaveDebounces() async throws {
        XCTAssertFalse(sut.isSaving)
        
        var factoryCalledCount = 0
        var debounceCalledCount = 0
        
        let factory: @MainActor () -> ProjectSnapshot = {
            factoryCalledCount += 1
            return ProjectSnapshot(
                schemaVersion: ProjectStore.currentSchemaVersion,
                projectName: "Test",
                nodes: [],
                viewportOffset: .zero,
                viewportScale: 1.0
            )
        }
        
        let onDebounceComplete: @MainActor () -> Void = {
            debounceCalledCount += 1
        }
        
        sut.requestSave(showIndicator: true, fileName: "test_debounce.json", snapshotFactory: factory, onDebounceComplete: onDebounceComplete)
        
        XCTAssertTrue(sut.isSaving)
        XCTAssertEqual(factoryCalledCount, 0)
        XCTAssertEqual(debounceCalledCount, 0)
        
        // Trigger another request save within the 500ms window
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        sut.requestSave(showIndicator: true, fileName: "test_debounce.json", snapshotFactory: factory, onDebounceComplete: onDebounceComplete)
        
        // Wait for the full 500ms debounce
        try await Task.sleep(nanoseconds: 600_000_000)
        
        // Both factory and debounce should be called only once
        XCTAssertEqual(factoryCalledCount, 1)
        XCTAssertEqual(debounceCalledCount, 1)
        
        // Wait for the actual save background task
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(sut.isSaving)
    }

    func testCancelledDebouncedSaveDoesNotWrite() async throws {
        sut.requestSave(
            fileName: "save_cancelled.json",
            snapshotFactory: { self.makeSnapshot() }
        )
        sut.cancelPendingSave()
        try await Task.sleep(for: .milliseconds(550))
        await sut.waitForActiveWrites()

        XCTAssertFalse(persistence.projectExists(fileName: "save_cancelled.json"))
    }

    func testFailedSaveCompletesWithoutCrash() async throws {
        let invalidDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("save-file-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: invalidDirectory)
        defer { try? FileManager.default.removeItem(at: invalidDirectory) }
        let controller = ProjectSaveController(
            persistence: ProjectPersistenceService(baseDirectory: invalidDirectory)
        )

        controller.save(
            snapshot: makeSnapshot(),
            fileName: "cannot-save.json",
            showIndicator: false
        )
        await controller.waitForActiveWrites()
    }

    private func makeSnapshot() -> ProjectSnapshot {
        ProjectSnapshot(
            schemaVersion: ProjectStore.currentSchemaVersion,
            projectName: "Test",
            nodes: [],
            viewportOffset: .zero,
            viewportScale: 1.0
        )
    }
}
