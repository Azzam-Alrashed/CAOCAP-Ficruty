import SwiftUI

/// App-level navigation shell with a traditional list of conversation sessions.
struct HomeView: View {
    let session: AppSessionCoordinator

    @State private var selectedTab: HomeTab = .sessions
    @State private var searchContext: HomeTab = .sessions
    @State private var searchText = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: HomeTab.sessions) {
                sessionsTab
            } label: {
                Image("icons8-Home Plumpy")
                    .renderingMode(.template)
                    .accessibilityLabel("Home")
            }

            Tab(value: HomeTab.activity) {
                EmptyTabScreen()
            } label: {
                Image("icons8-Combo Chart Plumpy")
                    .renderingMode(.template)
                    .accessibilityLabel("Activity")
            }

            Tab(value: HomeTab.settings) {
                SettingsTabView(session: session)
            } label: {
                Image("icons8-Settings Plumpy")
                    .renderingMode(.template)
                    .accessibilityLabel("Settings")
            }

            Tab(value: HomeTab.search, role: .search) {
                contextualSearchTab
            }
        }
        .tint(Color(uiColor: .systemBlue))
        .onChange(of: selectedTab) { _, newTab in
            guard newTab != .search else { return }
            searchContext = newTab
            searchText = ""
        }
    }

    private var sessionsTab: some View {
        NavigationStack {
            List(PlaceholderSession.samples) { session in
                SessionRow(session: session)
                    .listRowInsets(
                        EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
                    )
                    .listRowSeparator(.visible)
            }
            .listStyle(.plain)
            .navigationTitle("Sessions")
        }
    }

    private var contextualSearchTab: some View {
        NavigationStack {
            ContentUnavailableView(
                searchTitle,
                systemImage: "magnifyingglass",
                description: Text(searchPrompt)
            )
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: Text(searchPrompt))
        }
    }

    private var searchTitle: String {
        switch searchContext {
        case .sessions:
            "Search Sessions"
        case .activity:
            "Search Activity"
        case .settings:
            "Search Settings"
        case .search:
            "Search"
        }
    }

    private var searchPrompt: String {
        switch searchContext {
        case .sessions:
            "Sessions and messages"
        case .activity:
            "Events and agent actions"
        case .settings:
            "Settings and preferences"
        case .search:
            "Search"
        }
    }
}

private enum HomeTab: Hashable {
    case sessions
    case activity
    case settings
    case search
}

private struct SessionRow: View {
    let session: PlaceholderSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(session.tint)
                .frame(width: 48, height: 48)
                .background(session.tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(session.latestMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 7) {
                Text(session.time)
                    .font(.caption)
                    .foregroundStyle(
                        session.unreadCount > 0
                            ? Color.accentColor
                            : Color(uiColor: .secondaryLabel)
                    )

                if session.unreadCount > 0 {
                    Text("\(session.unreadCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Color.accentColor, in: Circle())
                } else {
                    Color.clear
                        .frame(width: 20, height: 20)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

private struct PlaceholderSession: Identifiable {
    let id: Int
    let title: String
    let latestMessage: String
    let time: String
    let unreadCount: Int
    let tint: Color

    static let samples = [
        PlaceholderSession(
            id: 1,
            title: "Launch the new website",
            latestMessage: "The final accessibility review is ready.",
            time: "2:31 PM",
            unreadCount: 2,
            tint: .blue
        ),
        PlaceholderSession(
            id: 2,
            title: "Research competitors",
            latestMessage: "I found three products worth comparing.",
            time: "1:08 PM",
            unreadCount: 1,
            tint: .purple
        ),
        PlaceholderSession(
            id: 3,
            title: "Organize my Downloads",
            latestMessage: "Everything is grouped and ready for review.",
            time: "Yesterday",
            unreadCount: 0,
            tint: .green
        ),
        PlaceholderSession(
            id: 4,
            title: "Prepare the weekly report",
            latestMessage: "The draft is waiting for your feedback.",
            time: "Tuesday",
            unreadCount: 0,
            tint: .orange
        )
    ]
}

private struct EmptyTabScreen: View {
    var body: some View {
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()
    }
}

#Preview {
    HomeView(session: AppSessionCoordinator())
        .environment(AuthenticationManager())
}
