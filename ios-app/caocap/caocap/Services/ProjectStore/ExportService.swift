import Foundation
import OSLog
import SwiftUI
import UIKit

/// The output format for a project export.
public enum ExportFormat {
    /// A raw copy of the project's `.json` file renamed with the `.caocap` extension
    /// for sharing and re-importing in another CAOCAP installation.
    case caocap
}

/// Produces shareable export artefacts from a `ProjectStore`.
/// Heavy I/O is dispatched on a detached background task to avoid blocking the main actor.
public struct ExportService {
    private static let logger = Logger(subsystem: "com.caocap.app", category: "ExportService")

    /// Convenience entry point that pulls required state from a live `ProjectStore`
    /// on the main actor, then hands off to the background-safe overload.
    @MainActor
    public static func export(from store: ProjectStore, format: ExportFormat = .caocap) async -> URL? {
        let projectName = store.projectName
        let fileName = store.fileName

        return await export(
            projectName: projectName,
            fileName: fileName,
            format: format
        )
    }

    /// Performs the actual export work off the main actor.
    /// - Returns: A temporary-directory URL pointing to the exported file, or `nil` on failure.
    public static func export(
        projectName: String,
        fileName: String,
        format: ExportFormat = .caocap
    ) async -> URL? {
        return await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let safeName = projectName.replacingOccurrences(of: " ", with: "_").lowercased()

            switch format {
            case .caocap:
                let persistence = ProjectPersistenceService()
                let sourceURL = persistence.fileURL(for: fileName)
                let exportURL = fileManager.temporaryDirectory.appendingPathComponent("\(safeName).caocap")
                do {
                    if fileManager.fileExists(atPath: exportURL.path) {
                        try fileManager.removeItem(at: exportURL)
                    }
                    try fileManager.copyItem(at: sourceURL, to: exportURL)
                    return exportURL
                } catch {
                    logger.error("Failed to export .caocap: \(error.localizedDescription)")
                    return nil
                }
            }
        }.value
    }
}

/// System share sheet wrapper used by canvas export presentation.
public struct ActivityView: UIViewControllerRepresentable {
    public let activityItems: [Any]
    public let applicationActivities: [UIActivity]? = nil

    public init(activityItems: [Any]) {
        self.activityItems = activityItems
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
