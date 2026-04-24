import Foundation
import OSLog

public struct ProjectMetadata: Identifiable {
    public let id: String // filename
    public let name: String
    public let lastModified: Date
}

public class ProjectManager {
    public static let shared = ProjectManager()
    private let logger = Logger(subsystem: "com.ficruty.caocap", category: "ProjectManager")
    
    private var baseDir: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("com.ficruty.caocap", isDirectory: true)
        return appSupport
    }
    
    public func listProjects() -> [ProjectMetadata] {
        let fileManager = FileManager.default
        do {
            let files = try fileManager.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
            
            return files.compactMap { url in
                let fileName = url.lastPathComponent
                guard fileName.hasPrefix("project_") && fileName.hasSuffix(".json") else { return nil }
                
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                let modificationDate = attributes?[.modificationDate] as? Date ?? Date()
                
                // We could read the JSON to get the actual project name, but for speed we'll use the ID for now
                // or do a quick peek at the first few bytes.
                let name = getProjectName(from: url) ?? "Untitled Project"
                
                return ProjectMetadata(id: fileName, name: name, lastModified: modificationDate)
            }.sorted { $0.lastModified > $1.lastModified }
            
        } catch {
            logger.error("Failed to list projects: \(error.localizedDescription)")
            return []
        }
    }
    
    public func deleteProject(fileName: String) {
        let url = baseDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }
    
    private func getProjectName(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["projectName"] as? String else {
            return nil
        }
        return name
    }
}
