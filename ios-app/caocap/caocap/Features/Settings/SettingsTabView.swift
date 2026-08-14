import SwiftUI

/// Adapts the shared settings screen to the app's persistent tab bar.
struct SettingsTabView: View {
    @Bindable var session: AppSessionCoordinator
    @Environment(AuthenticationManager.self) private var authManager

    var body: some View {
        SettingsView(
            selectedCopilot: Binding(
                get: { session.selectedCopilot },
                set: { session.updateSelectedCopilot($0) }
            ),
            presentation: .tab,
            onOpenAccount: {
                session.requestProfileSheet()
            },
            onOpenAppIcon: {
                session.requestAppIconPickerSheet()
            },
            onEraseEverything: {
                try await session.eraseEverything(authManager: authManager)
            }
        )
    }
}

#Preview {
    SettingsTabView(session: AppSessionCoordinator())
        .environment(AuthenticationManager())
}
