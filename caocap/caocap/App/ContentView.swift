import SwiftUI

struct ContentView: View {
    @StateObject var commandPalette = CommandPaletteViewModel()
    @StateObject var coCaptain = CoCaptainViewModel()
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @State private var isHomeActive = false
    @State private var projectStore = ProjectStore(fileName: "onboarding_v2.json", projectName: "Onboarding")
    @State private var homeProjectStore = ProjectStore(fileName: "home_v2.json", projectName: "Main Workspace", initialNodes: HomeProvider.homeNodes)
    @State private var showingPurchaseSheet = false
    @State private var currentScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            if isHomeActive {
                // The Home Canvas (Main Navigation Hub)
                InfiniteCanvasView(store: homeProjectStore, currentScale: $currentScale, onNodeAction: { action in
                    if action == "Retry Onboarding" {
                        withAnimation(.spring()) {
                            isHomeActive = false
                            currentScale = 1.0
                        }
                    }
                })
                .id("home_canvas")
            } else {
                InfiniteCanvasView(store: projectStore, currentScale: $currentScale, onNodeAction: { action in
                    if action == "Go to the Home workspace" {
                        withAnimation(.spring()) {
                            isHomeActive = true
                            hasCompletedOnboarding = true
                            currentScale = 1.0
                        }
                    }
                })
                .id("onboarding_canvas")
            }
            
            // HUD Overlay
            CanvasHUDView(store: isHomeActive ? homeProjectStore : projectStore, viewportScale: currentScale)
            
            FloatingCommandButton(onTap: {
                commandPalette.setPresented(true)
            })
            
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
        .sheet(isPresented: $showingPurchaseSheet) {
            PurchaseView()
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color(hex: "050505"))
        }
        .onAppear {
            setupCommandHandlers()
            
            // Determine initial view based on onboarding status
            isHomeActive = hasCompletedOnboarding
            
            // Sync initial scale
            currentScale = (isHomeActive ? homeProjectStore : projectStore).viewportScale
        }
    }
    
    private func setupCommandHandlers() {
        commandPalette.onExecute = { command in
            switch command {
            case .summonCoCaptain:
                coCaptain.setPresented(true)
            case .proSubscription:
                showingPurchaseSheet = true
            default:
                break
            }
        }
    }
}

#Preview {
    ContentView()
}
