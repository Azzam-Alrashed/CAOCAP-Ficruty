import Foundation

/// How the user wants to interact with their selected copilot persona.
enum CopilotInteractionMode: String, CaseIterable, Identifiable, Hashable, Codable {
    /// Text CoCaptain sheet / inspector.
    case chat
    /// Gemini Live screen-share call (spoken audio plus in-app screen share).
    case video

    var id: String { rawValue }

    var systemImageName: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .video: return "video.fill"
        }
    }

    var localizedTitleKey: String {
        switch self {
        case .chat: return "copilot.mode.chat"
        case .video: return "copilot.mode.video"
        }
    }
}
