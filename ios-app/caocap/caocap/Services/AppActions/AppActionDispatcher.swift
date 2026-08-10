import Foundation

/// Top-level grouping for app actions surfaced in the command palette and agent.
public enum AppActionCategory: String, Hashable {
    /// Actions that navigate between workspaces or canvas levels.
    case navigation
    /// Actions that mutate project structure (nodes, canvas, files).
    case project
    /// Actions related to the AI assistant or the user's account.
    case assistant
}

public enum AppActionID: String, CaseIterable, Identifiable, Codable, Hashable {
    case goRoot = "go_root"
    case goBack = "go_back"
    case createNode = "create_node"
    case summonCoCaptain = "summon_cocaptain"
    case summonCopilotVoice = "summon_copilot_voice"
    case summonCopilotVideo = "summon_copilot_video"
    case undo = "undo"
    case redo = "redo"
    case openFile = "open_file"
    case toggleGrid = "toggle_grid"
    case shareCanvas = "share_canvas"
    case proSubscription = "pro_subscription"
    case signIn = "sign_in"
    case openSettings = "open_settings"
    case openProfile = "open_profile"
    case moveNode = "move_node"
    case themeNode = "theme_node"
    case transformNode = "transform_node"
    case help = "help"
    case organizeNodes = "organize_nodes"
    case openSnapshotBrowser = "open_snapshot_browser"
    case toggleHUD = "toggle_hud"
    case showActionsList = "show_actions_list"
    case createSubCanvas = "create_sub_canvas"
    case openActivity = "open_activity"
    case openDaily = "open_daily"
    case openWhatsApp = "open_whatsapp"
    case openAppIcon = "open_app_icon"
    case changeCopilot = "change_copilot"
    case openUsage = "open_usage"

    public var id: String { rawValue }

    /// Maps pin-able app actions to their canvas shortcut `NodeAction`.
    public var pinableNodeAction: NodeAction? {
        switch self {
        case .goRoot: return .navigateRoot
        case .openSettings: return .openSettings
        case .openProfile: return .openProfile
        case .summonCoCaptain: return .summonCoCaptain
        case .proSubscription: return .proSubscription
        case .openActivity: return .openActivity
        case .openDaily: return .openDaily
        case .openWhatsApp: return .openWhatsApp
        case .help: return .openHelp
        case .openAppIcon: return .openAppIcon
        default: return nil
        }
    }
}

public struct AppActionDefinition: Identifiable, Hashable {
    public let id: AppActionID
    public let title: String
    public let icon: String
    public let category: AppActionCategory
    /// Mutating actions change user data or project structure. Most require
    /// review, but small reversible workspace actions may opt into autonomous
    /// execution through `allowsAutonomousExecution`.
    public let isMutating: Bool
    /// Indicates whether trusted non-user callers, such as CoCaptain, may run
    /// this action without an explicit review item.
    public let allowsAutonomousExecution: Bool
    /// When true, the omnibox can place a shortcut node on the active canvas.
    public let canPinToCanvas: Bool

    public init(
        id: AppActionID,
        title: String,
        icon: String,
        category: AppActionCategory,
        isMutating: Bool,
        allowsAutonomousExecution: Bool,
        canPinToCanvas: Bool = false
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.category = category
        self.isMutating = isMutating
        self.allowsAutonomousExecution = allowsAutonomousExecution
        self.canPinToCanvas = canPinToCanvas
    }

    /// The stable, localised title of the action, resolved via `LocalizationManager`.
    public var localizedTitle: String {
        LocalizationManager.shared.localizedString(title)
    }
}

/// Distinguishes who is requesting an action, which controls whether
/// autonomous-execution restrictions are enforced.
public enum AppActionSource: Hashable {
    /// The user triggered the action directly (e.g. tapped a button).
    case user
    /// The agent triggered the action autonomously without user review.
    case agentAutomatic
    /// The agent proposed the action and the user approved it.
    case agentApproved
}

/// The result of attempting to execute an action, including whether it ran
/// and any message to surface to the agent or the UI.
public struct AppActionResult: Hashable {
    public let actionID: AppActionID
    public let title: String
    /// `true` when the handler was found and ran; `false` on any failure.
    public let executed: Bool
    /// Human-readable outcome message, either from the handler or a default.
    public let message: String

    public init(actionID: AppActionID, title: String, executed: Bool, message: String) {
        self.actionID = actionID
        self.title = title
        self.executed = executed
        self.message = message
    }
}

@MainActor
public protocol AppActionPerforming: AnyObject {
    var availableActions: [AppActionDefinition] { get }
    func definition(for id: AppActionID) -> AppActionDefinition?
    @discardableResult
    func perform(_ id: AppActionID, source: AppActionSource, arguments: [String: String]?) -> AppActionResult
}

/// Central registry and execution boundary for commands. UI surfaces and agents
/// request actions by ID; this dispatcher owns whether they are configured and
/// safe to execute from the given source.
@MainActor
public final class AppActionDispatcher: AppActionPerforming {
    public private(set) var availableActions: [AppActionDefinition] = [
        AppActionDefinition(
            id: .goRoot,
            title: "Go to Root",
            icon: "house.fill",
            category: .navigation,
            isMutating: false,
            allowsAutonomousExecution: true,
            canPinToCanvas: true
        ),
        AppActionDefinition(
            id: .goBack,
            title: "Go Back",
            icon: "arrow.left.circle",
            category: .navigation,
            isMutating: false,
            allowsAutonomousExecution: true
        ),
        AppActionDefinition(
            id: .createNode,
            title: "Create Mini-App",
            icon: "plus.square",
            category: .project,
            isMutating: true,
            allowsAutonomousExecution: false
        ),
        AppActionDefinition(
            id: .summonCoCaptain,
            title: "Summon Co-Captain",
            icon: "sparkles",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: true,
            canPinToCanvas: true
        ),
        AppActionDefinition(
            id: .summonCopilotVoice,
            title: "Voice Call Copilot",
            icon: "mic.fill",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: false
        ),
        AppActionDefinition(
            id: .summonCopilotVideo,
            title: "Screen Share with Copilot",
            icon: "video.fill",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: false
        ),
        AppActionDefinition(
            id: .undo,
            title: "Undo",
            icon: "arrow.uturn.backward",
            category: .project,
            isMutating: true,
            allowsAutonomousExecution: true
        ),
        AppActionDefinition(
            id: .redo,
            title: "Redo",
            icon: "arrow.uturn.forward",
            category: .project,
            isMutating: true,
            allowsAutonomousExecution: true
        ),
        AppActionDefinition(
            id: .openFile,
            title: "Open File",
            icon: "doc.text.magnifyingglass",
            category: .project,
            isMutating: false,
            allowsAutonomousExecution: false
        ),
        AppActionDefinition(
            id: .toggleGrid,
            title: "Toggle Grid",
            icon: "grid",
            category: .navigation,
            isMutating: false,
            allowsAutonomousExecution: true
        ),
        AppActionDefinition(
            id: .shareCanvas,
            title: "Share Canvas",
            icon: "square.and.arrow.up",
            category: .project,
            isMutating: false,
            allowsAutonomousExecution: false
        ),
        AppActionDefinition(
            id: .proSubscription,
            title: "Pro Subscription",
            icon: "crown",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: false,
            canPinToCanvas: true
        ),
        AppActionDefinition(
            id: .signIn,
            title: "Sign In",
            icon: "person.crop.circle.badge.checkmark",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: false
        ),
        AppActionDefinition(
            id: .openSettings,
            title: "Open Settings",
            icon: "gearshape.fill",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: true,
            canPinToCanvas: true
        ),
        AppActionDefinition(
            id: .openProfile,
            title: "Open Profile",
            icon: "person.fill",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: true,
            canPinToCanvas: true
        ),
        AppActionDefinition(
            id: .moveNode,
            title: "Move Node",
            icon: "arrow.up.and.down.and.arrow.left.and.right",
            category: .project,
            isMutating: true,
            allowsAutonomousExecution: true
        ),
        AppActionDefinition(
            id: .themeNode,
            title: "Change Node Theme",
            icon: "paintbrush.fill",
            category: .project,
            isMutating: true,
            allowsAutonomousExecution: false
        ),
        AppActionDefinition(
            id: .transformNode,
            title: "Transform Node Type",
            icon: "arrow.triangle.2.circlepath",
            category: .project,
            isMutating: true,
            allowsAutonomousExecution: false
        ),
        AppActionDefinition(
            id: .help,
            title: "Help & Documentation",
            icon: "questionmark.circle",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: false,
            canPinToCanvas: true
        ),
        AppActionDefinition(
            id: .organizeNodes,
            title: "Organize Nodes",
            icon: "wand.and.stars",
            category: .project,
            isMutating: true,
            allowsAutonomousExecution: true
        ),
        AppActionDefinition(
            id: .openSnapshotBrowser,
            title: "Browse Checkpoints",
            icon: "clock.arrow.circlepath",
            category: .project,
            isMutating: false,
            allowsAutonomousExecution: true
        ),
        AppActionDefinition(
            id: .toggleHUD,
            title: "Toggle HUD",
            icon: "menubar.rectangle",
            category: .navigation,
            isMutating: false,
            allowsAutonomousExecution: true
        ),
        AppActionDefinition(
            id: .showActionsList,
            title: "Show Actions List",
            icon: "list.bullet.rectangle.portrait",
            category: .navigation,
            isMutating: false,
            allowsAutonomousExecution: true
        ),
        AppActionDefinition(
            id: .createSubCanvas,
            title: "New Canvas",
            icon: "folder.fill.badge.plus",
            category: .project,
            isMutating: true,
            allowsAutonomousExecution: false
        ),
        AppActionDefinition(
            id: .openActivity,
            title: "Activity",
            icon: "chart.bar.xaxis",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: false,
            canPinToCanvas: true
        ),
        AppActionDefinition(
            id: .openDaily,
            title: "Daily",
            icon: "rosette",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: false,
            canPinToCanvas: true
        ),
        AppActionDefinition(
            id: .openWhatsApp,
            title: "WhatsApp",
            icon: "message.fill",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: false,
            canPinToCanvas: true
        ),
        AppActionDefinition(
            id: .openAppIcon,
            title: "App Icon",
            icon: "app.fill",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: false,
            canPinToCanvas: true
        ),
        AppActionDefinition(
            id: .changeCopilot,
            title: "Change Copilot",
            icon: "person.crop.circle.badge.questionmark",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: false
        ),
        AppActionDefinition(
            id: .openUsage,
            title: "View Usage",
            icon: "gauge.with.dots.needle.67percent",
            category: .assistant,
            isMutating: false,
            allowsAutonomousExecution: true
        )
    ]

    private var handlers: [AppActionID: ([String: String]?) -> String?] = [:]

    public init() {
        refreshCopilotActionTitle()
    }

    public func refreshCopilotActionTitle() {
        let copilot = UserProfileStore().loadSelectedCopilot()
        if let index = availableActions.firstIndex(where: { $0.id == .summonCoCaptain }) {
            availableActions[index] = AppActionDefinition(
                id: .summonCoCaptain,
                title: "Summon \(copilot.displayName)",
                icon: "sparkles",
                category: .assistant,
                isMutating: false,
                allowsAutonomousExecution: true,
                canPinToCanvas: true
            )
        }
    }

    /// Registers a simple parameter-free handler.
    public func register(_ id: AppActionID, handler: @escaping () -> Void) {
        handlers[id] = { _ in
            handler()
            return nil
        }
    }

    /// Registers a handler that accepts arguments.
    public func register(_ id: AppActionID, handler: @escaping ([String: String]?) -> Void) {
        handlers[id] = { arguments in
            handler(arguments)
            return nil
        }
    }

    /// Registers a handler that accepts arguments and returns a custom status message.
    public func register(_ id: AppActionID, handler: @escaping ([String: String]?) -> String?) {
        handlers[id] = handler
    }

    public func definition(for id: AppActionID) -> AppActionDefinition? {
        availableActions.first(where: { $0.id == id })
    }

    /// Executes an action if configured. Automatic agent calls are blocked
    /// unless the action has explicitly opted into autonomous execution.
    @discardableResult
    public func perform(_ id: AppActionID, source: AppActionSource, arguments: [String: String]? = nil) -> AppActionResult {
        guard let definition = definition(for: id) else {
            return AppActionResult(
                actionID: id,
                title: id.rawValue,
                executed: false,
                message: LocalizationManager.shared.localizedString("Action unavailable.")
            )
        }

        if source == .agentAutomatic {
            guard definition.allowsAutonomousExecution else {
                return AppActionResult(
                    actionID: definition.id,
                    title: definition.localizedTitle,
                    executed: false,
                    message: LocalizationManager.shared.localizedString("Action requires approval.")
                )
            }
        }

        guard let handler = handlers[id] else {
            return AppActionResult(
                actionID: definition.id,
                title: definition.localizedTitle,
                executed: false,
                message: LocalizationManager.shared.localizedString("Action is not configured.")
            )
        }

        let customMessage = handler(arguments)
        let defaultMessage = LocalizationManager.shared.localizedString("appAction.executedMessage", arguments: [definition.localizedTitle])
        
        return AppActionResult(
            actionID: definition.id,
            title: definition.localizedTitle,
            executed: true,
            message: customMessage ?? defaultMessage
        )
    }
}
