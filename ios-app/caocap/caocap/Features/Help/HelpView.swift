import SwiftUI

/// In-app help center: tutorials, Command Line shortcuts, and getting-started guides.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header

                    SettingsSection("help.section.shortcuts") {
                        ForEach(HelpManifest.commandLineShortcuts) { shortcut in
                            shortcutRow(shortcut)
                        }
                    }

                    SettingsSection("help.section.guides") {
                        ForEach(HelpManifest.articles) { article in
                            NavigationLink {
                                HelpArticleView(article: article)
                            } label: {
                                articleRow(article)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        openURL(HelpManifest.supportURL)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "safari")
                                .font(.system(size: 16, weight: .semibold))
                            Text("help.footer.webDocs")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("help.header.title")
                .font(.system(size: 28, weight: .black, design: .rounded))
            Text("help.header.subtitle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func shortcutRow(_ shortcut: HelpShortcutItem) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.indigo.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "command")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.indigo)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(shortcut.titleKey))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                Text(LocalizationManager.shared.localizedString(shortcut.examplePhraseKey))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func articleRow(_ article: HelpArticle) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.cyan.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: article.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.cyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(article.titleKey))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                Text(LocalizedStringKey(article.subtitleKey))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.forward")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary.opacity(0.2))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func color(for name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "secondary": return .secondary
        default: return .indigo
        }
    }
}

#Preview {
    HelpView()
}
