import SwiftUI

struct ContentView: View {
    @State var commandPalette = CommandPaletteViewModel()
    @State var coCaptain = CoCaptainViewModel()
    @State private var router = AppRouter()
    @State private var showingPurchaseSheet = false
    @State private var currentScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            switch router.currentWorkspace {
            case .home:
                // The Home Canvas (Main Navigation Hub)
                InfiniteCanvasView(store: router.homeStore, currentScale: $currentScale, onNodeAction: { action in
                    if action == "Retry Onboarding" {
                        withAnimation(.spring()) {
                            router.navigate(to: .onboarding)
                            currentScale = 1.0
                        }
                    }
                })
                .id("home_canvas")
            case .onboarding:
                InfiniteCanvasView(store: router.onboardingStore, currentScale: $currentScale, onNodeAction: { action in
                    if action == "Go to the Home workspace" {
                        withAnimation(.spring()) {
                            router.navigate(to: .home)
                            currentScale = 1.0
                        }
                    }
                })
                .id("onboarding_canvas")
            }
            
            // HUD Overlay
            CanvasHUDView(store: router.activeStore, viewportScale: currentScale)
            
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
            
            // Sync initial scale
            currentScale = router.activeStore.viewportScale
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
