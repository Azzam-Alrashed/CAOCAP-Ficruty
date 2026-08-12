import Foundation
import SwiftUI

/// Resolves localised strings and layout metadata for the app's two supported
/// languages (English and Arabic).
///
/// The manager reads the persisted language selection from `UserDefaults` and
/// vends the appropriate `.lproj` bundle for string lookup. Arabic switches the
/// SwiftUI layout to RTL via `layoutDirection(for:)`.
public class LocalizationManager {
    public static let shared = LocalizationManager()
    public static let supportedLanguages = ["English", "Arabic"]
    public static let languageStorageKey = "app_language"
    private let newProjectPrefix = "New Project "
    /// Titles of nodes whose content is shipped with the app and therefore
    /// needs to be translated rather than treated as user-supplied text.
    private let appOwnedNodeTitles: Set<String> = [
        "Welcome to CAOCAP",
        "The Infinite Canvas",
        "Nodes of Intent",
        "Agentic Design",
        "Mini-App",
        "The Command Palette",
        "Your Journey Begins",
        "Profile",
        "Projects",
        "Settings",
        "New Project",
        "Mini-App Code",
        "HTML",
        "CSS",
        "JavaScript",
        "New Logic",
        "Help",
        "WhatsApp"
    ]
    /// Subtitles of app-owned nodes. Only strings in this set are passed through
    /// the localization lookup; user-authored subtitles are returned verbatim.
    private let appOwnedNodeSubtitles: Set<String> = [
        "The spatial landscape for agentic software design.",
        "Break free from the file tree. Pan and zoom to navigate your architecture.",
        "Each node represents a component, a logic block, or a vision. Drag them to organize your mind.",
        "You define the 'What'. Your Co-Captain handles the 'How'. Spatial programming starts here.",
        "See your creations come to life in real-time inside the Mini-App preview.",
        "Press the Floating Action Button to summon tools, create nodes, or talk to the AI.",
        "Enter your Home workspace to start building your first spatial project.",
        "Manage your account and preferences.",
        "View and organize your work.",
        "App configuration and tools.",
        "Start a fresh spatial journey.",
        "Your mini-game will render here.",
        "Define the core logic and rules here.",
        "Document structure.",
        "Styling and layout.",
        "Interactivity and logic.",
        "HTML, CSS, and JavaScript in one file.",
        "Define intent, people, flow, and success.",
        "Your current build renders here.",
        "Write your intent here.",
        "Saved changes across all canvases",
        "Today's building challenges",
        "Tutorials, shortcuts, and guides",
        "Message Azzam directly"
    ]
    
    private init() {}

    /// The current in-app language resolved from `UserDefaults`.
    /// Automatically resets any saved Arabic preference to "English".
    public var currentLanguage: String {
        if UserDefaults.standard.string(forKey: Self.languageStorageKey) == "Arabic" {
            UserDefaults.standard.set("English", forKey: Self.languageStorageKey)
        }
        return "English"
    }

    private func localeIdentifier(for language: String) -> String {
        switch language {
        case "Arabic":
            return "ar"
        case "French":
            return "fr"
        case "German":
            return "de"
        case "Spanish":
            return "es"
        default:
            return "en"
        }
    }
    
    /// Returns a `Locale` suitable for number/date formatting in the given language.
    public func locale(for language: String) -> Locale {
        Locale(identifier: localeIdentifier(for: language))
    }

    /// Returns the SwiftUI `LayoutDirection` for the given language.
    /// Arabic uses RTL; all other languages default to LTR.
    public func layoutDirection(for language: String) -> LayoutDirection {
        switch language {
        case "Arabic":
            return .rightToLeft
        default:
            return .leftToRight
        }
    }

    /// Returns the `.lproj` bundle for `language`.
    /// Falls back to `Bundle.main` when no matching `.lproj` directory is found,
    /// which gracefully handles unsupported locales.
    public func bundle(for language: String? = nil) -> Bundle {
        let resolvedLanguage = language ?? currentLanguage
        let identifier = localeIdentifier(for: resolvedLanguage)
        guard let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    /// Returns the localised string for `key` in the given `language`.
    ///
    /// Resolves against the app's String Catalog (`Localizable.xcstrings`) using an
    /// explicit locale so runtime language changes honor `app_language` instead of
    /// the device system locale.
    public func localizedString(_ key: String, language: String? = nil) -> String {
        let resolvedLanguage = language ?? currentLanguage
        return String(
            localized: String.LocalizationValue(stringLiteral: key),
            table: "Localizable",
            bundle: bundle(for: resolvedLanguage),
            locale: locale(for: resolvedLanguage)
        )
    }

    /// Returns a formatted string by resolving `key` and applying `arguments`
    /// with the locale of `language` so that number/punctuation separators match.
    public func localizedString(_ key: String, arguments: [CVarArg], language: String? = nil) -> String {
        let resolvedLanguage = language ?? currentLanguage
        let format = localizedString(key, language: resolvedLanguage)
        return String(format: format, locale: locale(for: resolvedLanguage), arguments: arguments)
    }

    /// Returns the localised display name for a project.
    ///
    /// Handles three special cases:
    /// - The root/home workspace file is always translated as `"Root"`.
    /// - `"Untitled Project"` is translated via the strings table.
    /// - Projects named `"New Project <8-hex-char-suffix>"` use the
    ///   `"project.generatedName"` format string with the suffix as the argument.
    /// - All other names are returned verbatim (user-authored).
    public func localizedProjectName(_ name: String, fileName: String? = nil, language: String? = nil) -> String {
        if fileName == "root_v6.json" || fileName == "home_v6.json" || fileName == "home_v2.json" || name == "Root" || name == "Home" {
            return localizedString("Root", language: language)
        }



        if name == "Untitled Project" {
            return localizedString("Untitled Project", language: language)
        }

        if name.hasPrefix(newProjectPrefix) {
            let suffix = String(name.dropFirst(newProjectPrefix.count))
            if suffix.range(of: #"^[A-Fa-f0-9]{8}$"#, options: .regularExpression) != nil {
                return localizedString("project.generatedName", arguments: [suffix], language: language)
            }
        }

        return name
    }

    /// Returns a localised title for the node, but only when the title belongs
    /// to app-owned onboarding or system nodes. User-authored titles are returned
    /// unchanged to preserve intent.
    public func localizedNodeTitle(_ title: String, language: String? = nil) -> String {
        guard appOwnedNodeTitles.contains(title) else {
            return title
        }

        return localizedString(title, language: language)
    }

    /// Returns a localised subtitle for the node, guarded by the same
    /// app-owned-subtitle allowlist as `localizedNodeTitle`.
    public func localizedNodeSubtitle(_ subtitle: String, language: String? = nil) -> String {
        guard appOwnedNodeSubtitles.contains(subtitle) else {
            return subtitle
        }

        return localizedString(subtitle, language: language)
    }

    /// Returns a human-readable relative date string (e.g. `"2 hours ago"`).
    /// The string is formatted using the locale of the specified language.
    public func relativeDateString(for date: Date, relativeTo referenceDate: Date = Date(), language: String? = nil) -> String {
        let resolvedLanguage = language ?? currentLanguage
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale(for: resolvedLanguage)
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}
