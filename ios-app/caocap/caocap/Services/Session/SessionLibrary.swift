import Foundation
import Observation
import OSLog

/// Lightweight Home-screen metadata for one isolated CAOCAP session.
struct SessionSummary: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var previewText: String
    let createdAt: Date
    var updatedAt: Date
    let workspaceFileName: String

    init(
        id: UUID = UUID(),
        title: String = "New Session",
        previewText: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        workspaceFileName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.previewText = previewText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.workspaceFileName = workspaceFileName ?? "session_\(id.uuidString).json"
    }
}

/// Atomic JSON persistence for the small session index shown on Home.
struct SessionPersistenceService: Sendable {
    private let directory: URL

    init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            directory = baseDirectory
        } else {
            directory = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            .appendingPathComponent("com.ficruty.caocap", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        }
    }

    func load() throws -> [SessionSummary] {
        let url = indexURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SessionSummary].self, from: data)
    }

    func save(_ sessions: [SessionSummary]) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let destination = indexURL
        let temporary = destination.appendingPathExtension("\(UUID().uuidString).tmp")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sessions)
        try data.write(to: temporary, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporary) }

        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    private var indexURL: URL {
        directory.appendingPathComponent("index.json")
    }
}

/// Owns committed Home sessions plus transient, unpersisted drafts.
@MainActor
@Observable
final class SessionLibrary {
    private(set) var sessions: [SessionSummary]
    private(set) var drafts: [UUID: SessionSummary] = [:]

    @ObservationIgnored private let persistence: SessionPersistenceService
    @ObservationIgnored private let logger = Logger(
        subsystem: "com.caocap.app",
        category: "SessionLibrary"
    )

    init(persistence: SessionPersistenceService = SessionPersistenceService()) {
        self.persistence = persistence
        do {
            sessions = try persistence.load()
            sortSessions()
        } catch {
            sessions = []
            logger.error(
                "Could not load sessions: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    @discardableResult
    func createDraft(now: Date = Date()) -> SessionSummary {
        let draft = SessionSummary(createdAt: now, updatedAt: now)
        drafts[draft.id] = draft
        return draft
    }

    func session(id: UUID) -> SessionSummary? {
        drafts[id] ?? sessions.first(where: { $0.id == id })
    }

    func isDraft(id: UUID) -> Bool {
        drafts[id] != nil
    }

    func commit(
        id: UUID,
        title: String,
        previewText: String,
        updatedAt: Date = Date()
    ) {
        guard var draft = drafts.removeValue(forKey: id) else {
            update(id: id, title: title, previewText: previewText, updatedAt: updatedAt)
            return
        }
        draft.title = normalizedTitle(title)
        draft.previewText = previewText
        draft.updatedAt = updatedAt
        sessions.append(draft)
        persistSortedSessions()
    }

    func update(
        id: UUID,
        title: String,
        previewText: String,
        updatedAt: Date = Date()
    ) {
        if var draft = drafts[id] {
            draft.title = normalizedTitle(title)
            draft.previewText = previewText
            draft.updatedAt = updatedAt
            drafts[id] = draft
            return
        }
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].title = normalizedTitle(title)
        sessions[index].previewText = previewText
        sessions[index].updatedAt = updatedAt
        persistSortedSessions()
    }

    @discardableResult
    func discardDraft(id: UUID) -> SessionSummary? {
        drafts.removeValue(forKey: id)
    }

    func removeAllInMemory() {
        sessions = []
        drafts = [:]
    }

    private func normalizedTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Session" : String(trimmed.prefix(80))
    }

    private func persistSortedSessions() {
        sortSessions()
        do {
            try persistence.save(sessions)
        } catch {
            logger.error(
                "Could not save sessions: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func sortSessions() {
        sessions.sort { $0.updatedAt > $1.updatedAt }
    }
}
