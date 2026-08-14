import Foundation
import Testing
@testable import caocap

@MainActor
struct SessionLibraryTests {
    @Test func draftDoesNotPersistUntilCommitted() throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let draft = fixture.library.createDraft()
        #expect(fixture.library.sessions.isEmpty)
        #expect(fixture.library.isDraft(id: draft.id))

        let reloaded = SessionLibrary(persistence: fixture.persistence)
        #expect(reloaded.sessions.isEmpty)
    }

    @Test func commitPersistsAndRestoresSession() throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let draft = fixture.library.createDraft()
        fixture.library.commit(
            id: draft.id,
            title: "Plan a launch",
            previewText: "Help me plan the launch"
        )

        let reloaded = SessionLibrary(persistence: fixture.persistence)
        let restored = try #require(reloaded.session(id: draft.id))
        #expect(restored.title == "Plan a launch")
        #expect(restored.previewText == "Help me plan the launch")
        #expect(!reloaded.isDraft(id: draft.id))
    }

    @Test func updatedSessionsSortNewestFirst() throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let start = Date(timeIntervalSince1970: 1_000)

        let first = fixture.library.createDraft(now: start)
        fixture.library.commit(
            id: first.id,
            title: "First",
            previewText: "First preview",
            updatedAt: start
        )
        let second = fixture.library.createDraft(now: start.addingTimeInterval(10))
        fixture.library.commit(
            id: second.id,
            title: "Second",
            previewText: "Second preview",
            updatedAt: start.addingTimeInterval(10)
        )

        #expect(fixture.library.sessions.map(\.id) == [second.id, first.id])
    }

    @Test func discardedDraftNeverAppearsInLibrary() {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let draft = fixture.library.createDraft()
        let discarded = fixture.library.discardDraft(id: draft.id)

        #expect(discarded?.id == draft.id)
        #expect(fixture.library.session(id: draft.id) == nil)
        #expect(fixture.library.sessions.isEmpty)
    }

    private func makeFixture() -> (
        root: URL,
        persistence: SessionPersistenceService,
        library: SessionLibrary
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionLibraryTests-\(UUID().uuidString)")
        let persistence = SessionPersistenceService(baseDirectory: root)
        return (root, persistence, SessionLibrary(persistence: persistence))
    }
}
