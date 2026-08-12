import Foundation

struct HelpShortcutItem: Identifiable, Hashable {
    let id: String
    let titleKey: String
    let examplePhraseKey: String
}

struct HelpArticle: Identifiable, Hashable {
    let id: String
    let titleKey: String
    let subtitleKey: String
    let icon: String
    let bodyParagraphKeys: [String]
}

/// Static catalogue for the in-app help center.
enum HelpManifest {
    static let supportURL = URL(string: "https://www.azzam.ai/caocap/support")!

    static let omniboxShortcuts: [HelpShortcutItem] = [
        HelpShortcutItem(id: "settings", titleKey: "Settings", examplePhraseKey: "help.shortcut.settings"),
        HelpShortcutItem(id: "profile", titleKey: "Profile", examplePhraseKey: "help.shortcut.profile"),
        HelpShortcutItem(id: "cocaptain", titleKey: "Summon Co-Captain", examplePhraseKey: "help.shortcut.cocaptain"),
        HelpShortcutItem(id: "help", titleKey: "Help & Documentation", examplePhraseKey: "help.shortcut.help"),
        HelpShortcutItem(id: "activity", titleKey: "Activity", examplePhraseKey: "help.shortcut.activity"),
        HelpShortcutItem(id: "daily", titleKey: "Daily", examplePhraseKey: "help.shortcut.daily"),
        HelpShortcutItem(id: "grid", titleKey: "Toggle Grid", examplePhraseKey: "help.shortcut.grid"),
        HelpShortcutItem(id: "organize", titleKey: "Organize Nodes", examplePhraseKey: "help.shortcut.organize"),
        HelpShortcutItem(id: "pendingReviews", titleKey: "Pending CoCaptain Reviews", examplePhraseKey: "help.shortcut.pendingReviews")
    ]

    static let articles: [HelpArticle] = [
        HelpArticle(
            id: "canvas",
            titleKey: "help.article.canvas.title",
            subtitleKey: "help.article.canvas.subtitle",
            icon: "square.grid.2x2",
            bodyParagraphKeys: [
                "help.article.canvas.body1",
                "help.article.canvas.body2"
            ]
        ),
        HelpArticle(
            id: "miniapps",
            titleKey: "help.article.miniapps.title",
            subtitleKey: "help.article.miniapps.subtitle",
            icon: "app.connected.to.app.below.fill",
            bodyParagraphKeys: [
                "help.article.miniapps.body1",
                "help.article.miniapps.body2"
            ]
        ),
        HelpArticle(
            id: "cocaptain",
            titleKey: "help.article.cocaptain.title",
            subtitleKey: "help.article.cocaptain.subtitle",
            icon: "sparkles",
            bodyParagraphKeys: [
                "help.article.cocaptain.body1",
                "help.article.cocaptain.body2",
                "help.article.cocaptain.body3"
            ]
        ),
        HelpArticle(
            id: "omnibox",
            titleKey: "help.article.omnibox.title",
            subtitleKey: "help.article.omnibox.subtitle",
            icon: "command",
            bodyParagraphKeys: [
                "help.article.omnibox.body1",
                "help.article.omnibox.body2"
            ]
        ),
        HelpArticle(
            id: "videoCall",
            titleKey: "help.article.videoCall.title",
            subtitleKey: "help.article.videoCall.subtitle",
            icon: "video.fill",
            bodyParagraphKeys: [
                "help.article.videoCall.body1",
                "help.article.videoCall.body2",
                "help.article.videoCall.body3"
            ]
        )
    ]
}
