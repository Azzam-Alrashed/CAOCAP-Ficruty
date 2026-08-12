import SwiftUI

/// Presents global sheets driven by `AppSessionCoordinator` presentation flags.
struct AppSheetsModifier: ViewModifier {
    @Bindable var session: AppSessionCoordinator
    @Environment(AuthenticationManager.self) private var authManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        coCaptainPresentation(content)
            .sheet(isPresented: $session.showingSignIn) {
                SignInView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground {
                        Color.black.opacity(0.95)
                            .background(.ultraThinMaterial)
                    }
            }
            .sheet(isPresented: $session.showingPurchaseSheet) {
                PurchaseView()
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(Color(hex: "050505"))
            }
            .sheet(isPresented: $session.showingSettings) {
                SettingsView(
                    selectedCopilot: Binding(
                        get: { session.selectedCopilot },
                        set: { session.updateSelectedCopilot($0) }
                    ),
                    onUpgrade: {
                        session.requestPurchaseSheet()
                    },
                    onRestartPersonalization: {
                        session.restartPersonalization()
                    },
                    onRestartOnboarding: {
                        session.restartOnboarding()
                    },
                    onEraseEverything: {
                        try await session.eraseEverything(authManager: authManager)
                    }
                )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $session.showingUsage) {
                UsageSheetView(
                    onUpgrade: {
                        session.requestPurchaseSheet()
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $session.showingSnapshotBrowser) {
                SnapshotBrowserView(store: session.router.activeStore)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $session.showingProfile) {
                ProfileView(onSignIn: {
                    session.showingSignIn = true
                }, onPro: {
                    session.showingPurchaseSheet = true
                })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $session.showingHelp) {
                HelpView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $session.showingAppIconPicker) {
                AppIconPickerView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $session.showingCopilotPicker) {
                CopilotPersonaPickerSheet(
                    selection: session.selectedCopilot,
                    onSelect: { session.updateSelectedCopilot($0) }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
    }

    @ViewBuilder
    private func coCaptainPresentation<Content: View>(_ content: Content) -> some View {
        let isPresented = Binding(
            get: { session.coCaptain.isPresented },
            set: { session.coCaptain.setPresented($0) }
        )

        if horizontalSizeClass == .regular {
            content
                .inspector(isPresented: isPresented) {
                    CoCaptainView(viewModel: session.coCaptain)
                        .inspectorColumnWidth(min: 360, ideal: 420, max: 520)
                }
        } else {
            content
                .sheet(isPresented: isPresented) {
                    CoCaptainView(
                        viewModel: session.coCaptain,
                        onRequestExpandedPresentation: {
                            session.requestCoCaptainExpandedPresentation()
                        }
                    )
                        .presentationDetents(
                            session.coCaptainAvailableDetents,
                            selection: $session.coCaptainDetent
                        )
                        .presentationDragIndicator(.visible)
                        .presentationBackground(.ultraThinMaterial)
                        .presentationBackgroundInteraction(.enabled)
                }
        }
    }
}
