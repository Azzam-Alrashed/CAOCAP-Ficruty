import SwiftUI

/// Shared free-tier / Pro usage summary for Settings and the Omnibox Usage sheet.
struct FreeTierUsageView: View {
    var showsSectionChrome: Bool = true
    var onUpgrade: (() -> Void)? = nil

    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var tokenStatus = TokenUsageLimiter.shared.status()

    private let tokenLimit = TokenUsageLimiter.freeMonthlyTokenLimit

    var body: some View {
        Group {
            if showsSectionChrome {
                SettingsSection(LocalizedStringKey("settings.usage.title")) {
                    content
                }
            } else {
                content
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )
            }
        }
        .task {
            await refresh()
        }
        .onAppear {
            tokenStatus = TokenUsageLimiter.shared.status()
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if subscriptionManager.isSubscribed {
                proBanner
            } else {
                usageRow(
                    icon: "sparkles",
                    color: Color(hex: "A855F7"),
                    title: LocalizationManager.shared.localizedString("settings.usage.cocaptain.title"),
                    subtitle: LocalizationManager.shared.localizedString(
                        "settings.usage.cocaptain.subtitle",
                        arguments: [tokenStatus.periodKey]
                    ),
                    valueText: "\(formatted(tokenStatus.usedTokens)) / \(formatted(tokenLimit))",
                    progress: progress(
                        used: tokenStatus.usedTokens,
                        limit: tokenLimit
                    )
                )

                if let onUpgrade {
                    Divider().padding(.leading, 56).opacity(0.3)

                    SettingsRow(
                        icon: "crown.fill",
                        title: LocalizedStringKey("View Pro"),
                        subtitle: LocalizedStringKey("settings.usage.upgrade.subtitle"),
                        color: .orange,
                        action: onUpgrade
                    )
                }
            }
        }
    }

    private var proBanner: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: "crown.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.yellow)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey("settings.usage.pro.title"))
                    .font(.system(size: 16, weight: .medium))
                Text(LocalizedStringKey("settings.usage.pro.subtitle"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func usageRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        valueText: String,
        progress: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)

                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(valueText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            ProgressView(value: progress)
                .tint(progress >= 1 ? .orange : color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func progress(used: Int, limit: Int) -> Double {
        guard limit > 0 else { return 0 }
        return min(1, Double(used) / Double(limit))
    }

    private func formatted(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private func refresh() async {
        await subscriptionManager.refreshEntitlements()
        tokenStatus = TokenUsageLimiter.shared.status()
    }
}

/// Standalone sheet opened from the Omnibox Usage command.
struct UsageSheetView: View {
    var onUpgrade: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                FreeTierUsageView(
                    showsSectionChrome: false,
                    onUpgrade: onUpgrade
                )
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(LocalizedStringKey("settings.usage.title"))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.6))
                            .padding(8)
                            .background(.primary.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
        }
    }
}
