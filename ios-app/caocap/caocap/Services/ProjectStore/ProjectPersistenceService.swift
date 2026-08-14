import Foundation

/// The complete serialisable state of one canvas project.
/// Written to disk as JSON by `ProjectPersistenceService` and restored on load.
public struct ProjectSnapshot: Codable, Equatable {
    /// The schema version this snapshot was written with. Used to reject incompatible files.
    public let schemaVersion: Int
    /// Human-readable project name, or `nil` when the name has not been set yet.
    public let projectName: String?
    /// All spatial nodes that live on the canvas at the time of the snapshot.
    public let nodes: [SpatialNode]
    /// Canvas pan offset (in canvas-space points) at the time of the snapshot.
    public let viewportOffset: CGSize
    /// Canvas zoom level at the time of the snapshot (1.0 = 100%).
    public let viewportScale: CGFloat
    /// Optional label attached when the snapshot was saved as a named checkpoint.
    public var checkpointLabel: String?

    public init(
        schemaVersion: Int = ProjectPersistenceService.currentSchemaVersion,
        projectName: String?,
        nodes: [SpatialNode],
        viewportOffset: CGSize,
        viewportScale: CGFloat,
        checkpointLabel: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.projectName = projectName
        self.nodes = nodes
        self.viewportOffset = viewportOffset
        self.viewportScale = viewportScale
        self.checkpointLabel = checkpointLabel
    }
}

/// Lightweight descriptor for a saved checkpoint — stored in the history list
/// without loading the full snapshot into memory.
public struct SnapshotMetadata: Codable, Equatable, Identifiable {
    /// Stable identity that doubles as the checkpoint's JSON file name stem.
    public let id: UUID
    /// Wall-clock time the checkpoint was created.
    public let date: Date
    /// Human-readable label shown in the history UI.
    public let label: String
    /// The file name of the checkpoint JSON (relative to the snapshots directory).
    public let fileName: String

    public init(id: UUID = UUID(), date: Date = Date(), label: String, fileName: String) {
        self.id = id
        self.date = date
        self.label = label
        self.fileName = fileName
    }
}

/// Errors surfaced by `ProjectPersistenceService` during load.
public enum ProjectPersistenceError: LocalizedError, Equatable {
    /// The file on disk carries a schema version that differs from `currentSchemaVersion`.
    /// The associated value is `nil` when the file is missing the version field entirely.
    case unsupportedSchemaVersion(Int?, current: Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version, let current):
            if let version {
                return "Project schema version \(version) is not supported. Expected version \(current)."
            }
            return "Project is missing schema version. Expected version \(current)."
        }
    }
}

/// Encapsulates project file layout, schema decoding, and atomic JSON writes so
/// ProjectStore can stay focused on observable project state.
public struct ProjectPersistenceService: Sendable {
    /// The schema version that this build of the app can read and write.
    /// Increment this whenever a structural, non-backwards-compatible change is
    /// made to `ProjectSnapshot` or `SpatialNode`.
    public static let currentSchemaVersion = 4

    /// Minimal decodable used to peek at a file's schema version before fully
    /// decoding it, so we can reject incompatible files cheaply.
    private struct VersionCheck: Codable {
        let schemaVersion: Int?
    }

    /// Override used in tests to sandbox I/O to a temporary directory.
    private let baseDirectory: URL?

    /// - Parameter baseDirectory: If non-nil, all project files are read from and
    ///   written to this directory. Defaults to `Application Support/com.ficruty.caocap`.
    public init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
    }

    /// The root workspace directory where all project JSON files are stored.
    public func workspaceDirectory() -> URL {
        projectDirectory()
    }

    /// Full URL on disk for the given project file name.
    public func fileURL(for fileName: String) -> URL {
        projectDirectory().appendingPathComponent(fileName)
    }

    /// Returns `true` when a project file with the given name already exists on disk.
    public func projectExists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: fileName).path)
    }

    /// Removes an abandoned session workspace and its checkpoints.
    public func deleteProject(fileName: String) throws {
        let projectURL = fileURL(for: fileName)
        if FileManager.default.fileExists(atPath: projectURL.path) {
            try FileManager.default.removeItem(at: projectURL)
        }

        let snapshotsURL = snapshotsDirectory(for: fileName)
        if FileManager.default.fileExists(atPath: snapshotsURL.path) {
            try FileManager.default.removeItem(at: snapshotsURL)
        }
    }

    /// Lists top-level project/canvas JSON file names in the workspace directory.
    /// Does not include checkpoint snapshots under `snapshots/`.
    public func listProjectFileNames() -> [String] {
        let directory = projectDirectory()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .map(\.lastPathComponent)
            .sorted()
    }

    /// Loads and fully decodes a project snapshot from disk.
    /// - Throws: `ProjectPersistenceError.unsupportedSchemaVersion` if the file's
    ///   schema version does not match `currentSchemaVersion`.
    public func load(fileName: String) throws -> ProjectSnapshot {
        let data = try Data(contentsOf: fileURL(for: fileName))
        let decoder = JSONDecoder()
        let versionCheck = try? decoder.decode(VersionCheck.self, from: data)
        try requireCurrentSchema(versionCheck?.schemaVersion)
        return try decoder.decode(ProjectSnapshot.self, from: data)
    }

    /// Writes a project snapshot atomically: the new JSON is written to a temp file
    /// first, then swapped in via `replaceItemAt(_:withItemAt:)` so an interrupted
    /// write can never corrupt the live file.
    public func save(_ snapshot: ProjectSnapshot, fileName: String) throws {
        let url = fileURL(for: fileName)
        let tempURL = url.appendingPathExtension("\(UUID().uuidString).tmp")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(snapshot)

        try data.write(to: tempURL)

        if FileManager.default.fileExists(atPath: url.path) {
            // Atomic replacement keeps the destination inode stable.
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: url)
        }

        // Clean up the temp file in case replaceItemAt left it behind.
        try? FileManager.default.removeItem(at: tempURL)
    }

    /// Saves a named checkpoint snapshot to the per-project snapshots directory.
    /// - Returns: A `SnapshotMetadata` record that can be stored in the history list.
    public func saveSnapshot(_ snapshot: ProjectSnapshot, fileName: String, label: String) throws -> SnapshotMetadata {
        let id = UUID()
        let snapshotFileName = "\(id.uuidString).json"
        let directory = snapshotsDirectory(for: fileName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        var mutableSnapshot = snapshot
        mutableSnapshot.checkpointLabel = label
        
        let url = directory.appendingPathComponent(snapshotFileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(mutableSnapshot)
        try data.write(to: url)
        
        return SnapshotMetadata(id: id, date: Date(), label: label, fileName: snapshotFileName)
    }

    /// Loads the full snapshot referenced by a `SnapshotMetadata` record.
    /// - Throws: `ProjectPersistenceError` if the schema is stale or the file is missing.
    public func loadSnapshot(metadata: SnapshotMetadata, for projectFileName: String) throws -> ProjectSnapshot {
        let url = snapshotsDirectory(for: projectFileName)
            .appendingPathComponent(metadata.fileName)
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let versionCheck = try? decoder.decode(VersionCheck.self, from: data)
        try requireCurrentSchema(versionCheck?.schemaVersion)
        return try decoder.decode(ProjectSnapshot.self, from: data)
    }

    /// Permanently removes a checkpoint file from disk.
    /// Silently no-ops if the file no longer exists (e.g. already deleted).
    public func deleteSnapshot(metadata: SnapshotMetadata, for projectFileName: String) throws {
        let url = snapshotsDirectory(for: projectFileName)
            .appendingPathComponent(metadata.fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Returns all valid checkpoints for a project, sorted newest-first.
    /// Snapshots that have a different schema version are silently skipped so
    /// stale checkpoints from older builds don't surface in the history UI.
    public func listSnapshots(for fileName: String) -> [SnapshotMetadata] {
        let directory = snapshotsDirectory(for: fileName)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }
        
        let decoder = JSONDecoder()
        return files.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let versionCheck = try? decoder.decode(VersionCheck.self, from: data),
                  // Skip snapshots from a different schema version.
                  versionCheck.schemaVersion == Self.currentSchemaVersion,
                  let snapshot = try? decoder.decode(ProjectSnapshot.self, from: data),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let date = attributes[.creationDate] as? Date else {
                return nil
            }
            
            return SnapshotMetadata(
                // The UUID stem of the file name is the stable checkpoint ID.
                id: UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID(),
                date: date,
                label: snapshot.checkpointLabel ?? "Manual Checkpoint",
                fileName: url.lastPathComponent
            )
        }.sorted { $0.date > $1.date }
    }

    /// The directory that holds checkpoint snapshots for a given project file.
    /// Structured as `<workspaceDirectory>/snapshots/<projectNameStem>/`.
    public func snapshotsDirectory(for fileName: String) -> URL {
        projectDirectory()
            .appendingPathComponent("snapshots")
            .appendingPathComponent(fileName.replacingOccurrences(of: ".json", with: ""))
    }

    /// Returns the directory where project files live, creating it if necessary.
    /// Falls back to `Application Support/com.ficruty.caocap` when no override is set.
    private func projectDirectory() -> URL {
        if let baseDirectory {
            try? FileManager.default.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true
            )
            return baseDirectory
        }

        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("com.ficruty.caocap", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    /// Throws if the file's schema version doesn't match the current one.
    /// Passing `nil` means the version field was absent — also rejected.
    private func requireCurrentSchema(_ version: Int?) throws {
        guard version == Self.currentSchemaVersion else {
            throw ProjectPersistenceError.unsupportedSchemaVersion(version, current: Self.currentSchemaVersion)
        }
    }
}

/// Actor wrapper around `ProjectPersistenceService.save(_:fileName:)` so disk
/// writes can be dispatched from a background `Task` without data races.
public actor ProjectPersistenceWriter {
    private let persistence: ProjectPersistenceService

    public init(persistence: ProjectPersistenceService = ProjectPersistenceService()) {
        self.persistence = persistence
    }

    /// Writes `snapshot` to the given file name, isolated to this actor's executor.
    public func save(_ snapshot: ProjectSnapshot, fileName: String) throws {
        try persistence.save(snapshot, fileName: fileName)
    }
}
