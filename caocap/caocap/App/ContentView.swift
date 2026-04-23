import SwiftUI

struct ContentView: View {
    @State var commandPalette = CommandPaletteViewModel()
    @State var coCaptain = CoCaptainViewModel()
    @State private var router = AppRouter()
    @State private var showingPurchaseSheet = false
    @State private var showingSignIn = false
    @State private var currentScale: CGFloat = 1.0
    @Environment(\.undoManager) var undoManager
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            switch router.currentWorkspace {
            case .home:
                // The Home Canvas (Main Navigation Hub)
                InfiniteCanvasView(store: router.homeStore, currentScale: $currentScale, onNodeAction: { action in
                    handleNodeAction(action)
                })
                .id("home_canvas")
            case .onboarding:
                InfiniteCanvasView(store: router.onboardingStore, currentScale: $currentScale, onNodeAction: { action in
                    handleNodeAction(action)
                })
                .id("onboarding_canvas")
            case .project(let fileName):
                InfiniteCanvasView(store: router.activeStore, currentScale: $currentScale, onNodeAction: { action in
                    handleNodeAction(action)
                })
                .id("project_canvas_\(fileName)")
            }
            
            // HUD Overlay
            CanvasHUDView(
                store: router.activeStore,
                viewportScale: currentScale,
                onSignInTapped: { showingSignIn = true }
            )
            
            FloatingCommandButton(
                onTap: {
                    commandPalette.setPresented(true)
                },
                onUndo: {
                    undoManager?.undo()
                    router.activeStore.undoStackChanged += 1
                },
                onSummonCoCaptain: {
                    coCaptain.store = router.activeStore
                    coCaptain.setPresented(true)
                },
                onRedo: {
                    undoManager?.redo()
                    router.activeStore.undoStackChanged += 1
                },
                canUndo: (router.activeStore.undoStackChanged >= 0) && (undoManager?.canUndo ?? false),
                canRedo: (router.activeStore.undoStackChanged >= 0) && (undoManager?.canRedo ?? false)
            )
            
            CommandPaletteView(viewModel: commandPalette)
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $coCaptain.isPresented) {
            CoCaptainView(viewModel: coCaptain)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground {
                    Color.white.opacity(0.4)
                        .background(.ultraThinMaterial)
                }
                .presentationBackgroundInteraction(.enabled)
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground {
                    Color.black.opacity(0.95)
                        .background(.ultraThinMaterial)
                }
        }
        .sheet(isPresented: $showingPurchaseSheet) {
            PurchaseView()
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color(hex: "050505"))
        }
        .onAppear {
            setupCommandHandlers()
            
            // Sync initial scale
            currentScale = router.activeStore.viewportScale
            
            // Inject UndoManager into the active store
            router.activeStore.undoManager = undoManager
            router.homeStore.undoManager = undoManager
            router.onboardingStore.undoManager = undoManager
        }
        .onChange(of: router.currentWorkspace) {
            // Update the undo manager reference when switching projects
            router.activeStore.undoManager = undoManager
        }
    }
    
    private func handleNodeAction(_ action: NodeAction) {
        switch action {
        case .navigateHome:
            router.navigate(to: .home, animated: true)
            currentScale = 1.0
        case .retryOnboarding:
            router.navigate(to: .onboarding, animated: true)
            currentScale = 1.0
        case .createNewProject:
            router.createNewProject()
        }
    }
    
    private func setupCommandHandlers() {
        commandPalette.onExecute = { command in
            switch command {
            case .summonCoCaptain:
                coCaptain.store = router.activeStore
                coCaptain.setPresented(true)
            case .newProject:
                router.createNewProject()
            case .goHome:
                router.goHome()
            case .goBack:
                router.goBack()
            case .proSubscription:
                showingPurchaseSheet = true
            case .signIn:
                showingSignIn = true
            default:
                break
            }
        }
    }
}

#Preview {
    ContentView()
}
