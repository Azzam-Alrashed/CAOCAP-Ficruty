import SwiftUI

/// App-level navigation shell shown before entering a CoPilot session.
struct HomeView: View {
    var body: some View {
        TabView {
            EmptyTabScreen()
                .tabItem {
                    tabIcon("icons8-Home Plumpy", label: "Home")
                }

            EmptyTabScreen()
                .tabItem {
                    tabIcon("icons8-Combo Chart Plumpy", label: "Activity")
                }

            EmptyTabScreen()
                .tabItem {
                    tabIcon("icons8-Notification Plumpy", label: "Notifications")
                }

            EmptyTabScreen()
                .tabItem {
                    tabIcon("icons8-Settings Plumpy", label: "Settings")
                }
        }
    }

    private func tabIcon(_ name: String, label: String) -> some View {
        Label {
            Text(label)
        } icon: {
            Image(name)
                .renderingMode(.template)
        }
    }
}

private struct EmptyTabScreen: View {
    var body: some View {
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()
    }
}

#Preview {
    HomeView()
}
