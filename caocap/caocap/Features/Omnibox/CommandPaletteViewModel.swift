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
    public var actions: [AppActionDefinition] = []
    
    public var filteredActions: [AppActionDefinition] {
        if query.isEmpty { return actions }
        return actions.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
    
    public var onExecute: ((AppActionID) -> Void)?
    
    public init() {}
    
    public func setPresented(_ presented: Bool) {
        isPresented = presented
        if !presented {
            query = ""
            selectedIndex = 0
        }
    }
    
    public func moveSelection(direction: Direction) {
        let count = filteredActions.count
        guard count > 0 else { return }
        
        switch direction {
        case .up:
            selectedIndex = (selectedIndex - 1 + count) % count
        case .down:
            selectedIndex = (selectedIndex + 1) % count
        }
    }
    
    public func confirmSelection() {
        let filtered = filteredActions
        if selectedIndex >= 0 && selectedIndex < filtered.count {
            let action = filtered[selectedIndex]
            executeAction(action)
        }
    }
    
    public func executeAction(_ action: AppActionDefinition) {
        print("Executing action: \(action.title)")
        onExecute?(action.id)
        setPresented(false)
    }
    
    public enum Direction {
        case up, down
    }
}
