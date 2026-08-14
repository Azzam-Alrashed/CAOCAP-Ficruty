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
                activityTab
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
        .tint(tabTint)
        .onChange(of: selectedTab) { _, newTab in
            guard newTab != .search else { return }
            searchContext = newTab
            searchText = ""
        }
    }

    private var sessionsTab: some View {
        @Bindable var session = session

        return NavigationStack(path: $session.sessionPath) {
            ZStack {
                pageBackground(color: Color(uiColor: .systemBlue))

                ScrollView {
                    LazyVStack(spacing: 12) {
                        Button {
                            session.createSession()
                        } label: {
                            NewSessionRow()
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Starts a new session with CoCaptain")

                        if session.sessionLibrary.sessions.isEmpty {
                            ContentUnavailableView(
                                "No Sessions Yet",
                                systemImage: "bubble.left.and.bubble.right",
                                description: Text("Your conversations will appear here.")
                            )
                            .padding(.top, 48)
                        } else {
                            ForEach(session.sessionLibrary.sessions) { summary in
                                Button {
                                    session.openSession(id: summary.id)
                                } label: {
                                    SessionRow(session: summary)
                                        .padding(16)
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens this session")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Home")
            .navigationDestination(for: UUID.self) { sessionID in
                SessionChatView(session: session, sessionID: sessionID)
                    .toolbar(.hidden, for: .tabBar)
            }
            .onChange(of: session.sessionPath) { _, path in
                session.handleSessionPathChange(path)
            }
        }
    }

    private var activityTab: some View {
        NavigationStack {
            ZStack {
                pageBackground(color: Color(uiColor: .systemGreen))

                ScrollView {
                    FreeTierUsageView {
                        session.requestPurchaseSheet()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Activity")
        }
    }

    @ViewBuilder
    private func pageBackground(color: Color) -> some View {
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()

        Circle()
            .fill(color.opacity(0.16))
            .frame(width: 400, height: 400)
            .blur(radius: 60)
            .offset(x: 150, y: -200)
            .allowsHitTesting(false)
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

    private var tabTint: Color {
        let activeContext = selectedTab == .search ? searchContext : selectedTab

        switch activeContext {
        case .sessions, .search:
            return Color(uiColor: .systemBlue)
        case .activity:
            return Color(uiColor: .systemGreen)
        case .settings:
            return .orange
        }
    }
}

private struct NewSessionRow: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(.white.opacity(0.18), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("New Session")
                    .font(.headline)

                Text("Start something new")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white)
        .padding(18)
        .background {
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBlue),
                    Color(uiColor: .systemIndigo)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(uiColor: .systemBlue).opacity(0.28), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("New Session, Start something new")
    }
}

private enum HomeTab: Hashable {
    case sessions
    case activity
    case settings
    case search
}

private struct SessionRow: View {
    let session: SessionSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color(uiColor: .systemBlue))
                .frame(width: 48, height: 48)
                .background(Color(uiColor: .systemBlue).opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(session.previewText.isEmpty ? "No messages yet" : session.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(compactTimestamp)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .fixedSize()
        }
        .contentShape(Rectangle())
    }

    private var compactTimestamp: String {
        let now = Date()
        let elapsed = max(0, now.timeIntervalSince(session.updatedAt))

        if elapsed < 60 {
            return "Now"
        }
        if elapsed < 3_600 {
            return "\(Int(elapsed / 60))m"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3_600))h"
        }
        if elapsed < 604_800 {
            return session.updatedAt.formatted(.dateTime.weekday(.abbreviated))
        }
        if Calendar.current.isDate(session.updatedAt, equalTo: now, toGranularity: .year) {
            return session.updatedAt.formatted(.dateTime.day().month(.abbreviated))
        }
        return session.updatedAt.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
    }
}

private struct SessionChatView: View {
    let session: AppSessionCoordinator
    let sessionID: UUID

    var body: some View {
        CoCaptainView(
            viewModel: session.coCaptain,
            presentationStyle: .session,
            sessionTitle: session.sessionLibrary.session(id: sessionID)?.title ?? "New Session",
            focusComposerOnAppear: session.shouldFocusSessionComposer,
            onOpenCanvas: {
                session.presentCanvas()
            }
        )
    }
}

#Preview {
    HomeView(session: AppSessionCoordinator())
        .environment(AuthenticationManager())
}
