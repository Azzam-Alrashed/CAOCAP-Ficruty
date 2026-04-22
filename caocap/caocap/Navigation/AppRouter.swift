import Foundation
import Observation

public enum WorkspaceState: Equatable {
    case onboarding
    case home
}

@MainActor
@Observable
public class AppRouter {
    public var currentWorkspace: WorkspaceState
    
    public let onboardingStore = ProjectStore(fileName: "onboarding_v2.json", projectName: "Onboarding")
    public let homeStore = ProjectStore(fileName: "home_v2.json", projectName: "Home", initialNodes: HomeProvider.homeNodes)
    
    public var activeStore: ProjectStore {
        switch currentWorkspace {
        case .onboarding: return onboardingStore
        case .home: return homeStore
        }
    }
    
    public init() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.currentWorkspace = hasCompletedOnboarding ? .home : .onboarding
    }
    
    public func navigate(to workspace: WorkspaceState) {
        currentWorkspace = workspace
        
        // Update UserDefaults if we navigate to home from onboarding
        if workspace == .home {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
    }
}
