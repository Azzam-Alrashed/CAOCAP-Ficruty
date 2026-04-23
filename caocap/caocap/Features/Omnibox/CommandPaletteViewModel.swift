import SwiftUI
import Observation

@Observable
public class CommandPaletteViewModel {
    public var query: String = "" {
        didSet {
            // Reset selection when search changes
            selectedIndex = 0
        }
    }
    public var isPresented: Bool = false
    public var selectedIndex: Int = 0
    public var commands: [Command] = Command.allCases
    
    public var filteredCommands: [Command] {
        if query.isEmpty { return commands }
        return commands.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
    
    public var onExecute: ((Command) -> Void)?
    
    public init() {}
    
    public func setPresented(_ presented: Bool) {
        isPresented = presented
        if !presented {
            query = ""
            selectedIndex = 0
        }
    }
    
    public func moveSelection(direction: Direction) {
        let count = filteredCommands.count
        guard count > 0 else { return }
        
        switch direction {
        case .up:
            selectedIndex = (selectedIndex - 1 + count) % count
        case .down:
            selectedIndex = (selectedIndex + 1) % count
        }
    }
    
    public func confirmSelection() {
        let filtered = filteredCommands
        if selectedIndex >= 0 && selectedIndex < filtered.count {
            let command = filtered[selectedIndex]
            executeCommand(command)
        }
    }
    
    public func executeCommand(_ command: Command) {
        print("Executing command: \(command.title)")
        onExecute?(command)
        setPresented(false)
    }
    
    public enum Direction {
        case up, down
    }
}

public enum Command: String, CaseIterable, Equatable, Identifiable {
    case openFile = "Open File"
    case createNode = "Create New Node"
    case summonCoCaptain = "Summon Co-Captain"
    case newProject = "New Project"
    case goHome = "Go to Home"
    case goBack = "Go Back"
    case toggleGrid = "Toggle Grid"
    case shareProject = "Share Project"
    case proSubscription = "Pro Subscription"
    case signIn = "Sign In / Save Work"
    case help = "Help & Documentation"
    
    public var id: String { self.rawValue }
    
    public var title: String { self.rawValue }
    
    public var icon: String {
        switch self {
        case .openFile: return "doc.text.magnifyingglass"
        case .createNode: return "plus.square"
        case .summonCoCaptain: return "sparkles"
        case .newProject: return "plus.circle.fill"
        case .goHome: return "house.fill"
        case .goBack: return "arrow.left.circle"
        case .toggleGrid: return "grid"
        case .shareProject: return "square.and.arrow.up"
        case .proSubscription: return "crown"
        case .signIn: return "person.crop.circle.badge.checkmark"
        case .help: return "questionmark.circle"
        }
    }
}
