import SwiftUI

/// App-level navigation shell shown before entering a CoPilot session.
struct HomeView<SessionPreview: View>: View {
    let sessionPreview: SessionPreview
    let onOpenSession: () -> Void
    let transitionNamespace: Namespace.ID

    var body: some View {
        TabView {
            homeTab
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

    private var homeTab: some View {
        VStack(spacing: 0) {
            Button(action: onOpenSession) {
                sessionPreview
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .matchedTransitionSource(id: SessionTransitionID.latest, in: transitionNamespace) { source in
                source
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .accessibilityLabel("Open latest session")
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer(minLength: 0)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
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
    HomeViewPreview()
}

private struct HomeViewPreview: View {
    @Namespace private var namespace

    var body: some View {
        HomeView(
            sessionPreview: Color(uiColor: .secondarySystemBackground),
            onOpenSession: {},
            transitionNamespace: namespace
        )
    }
}

enum SessionTransitionID: Hashable {
    case latest
}
