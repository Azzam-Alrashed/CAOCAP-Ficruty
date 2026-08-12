//
//  caocapApp.swift
//  caocap
//
//  Created by الشيخ عزام on 20/04/2026.
//

import SwiftUI

// MARK: - App Delegate

/// Thin delegate whose only responsibility is forwarding launch
/// events to `AppConfiguration`. Never add SDK calls directly here.
final class AppDelegate: NSObject, UIApplicationDelegate {

    /// Owned here so it is guaranteed to exist before `didFinishLaunchingWithOptions` fires.
    let authManager = AuthenticationManager()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PerformanceSignposts.beginLaunch()
        AppConfiguration.shared.configure(authManager: authManager)
        AppIconService.applySavedIcon()
        return true
    }
}


// MARK: - App Entry Point

/// The root `App` entry point.
///
/// Wires together the `AppDelegate`, persisted theme/language preferences,
/// and the `WindowGroup` scene that hosts `ContentView`. All third-party SDK
/// setup is delegated to `AppConfiguration` via `AppDelegate`.
@main
struct caocapApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    /// User-selected color scheme preference stored in `UserDefaults`.
    /// Accepted values: `"Light"`, `"Dark"`, or `"System"` (default).
    @AppStorage("app_theme") private var selectedTheme = "System"
    /// User-selected UI language stored in `UserDefaults`.
    /// Accepted values: `"Arabic"` or `"English"` (default).
    @AppStorage("app_language") private var selectedLanguage = "English"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(delegate.authManager)
                .preferredColorScheme(colorScheme)
                .environment(\.locale, appLocale)
                .environment(\.layoutDirection, appLayoutDirection)
        }
        // Commands bridge hardware keyboard shortcuts on iPad/Mac to the
        // notification-based action bus consumed by ContentView.
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    NotificationCenter.default.post(name: .performUndo, object: nil)
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo") {
                    NotificationCenter.default.post(name: .performRedo, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandMenu("Commands") {
                Button("Command Line") {
                    NotificationCenter.default.post(name: .openCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Summon CoCaptain") {
                    NotificationCenter.default.post(name: .summonCoCaptain, object: nil)
                }
                .keyboardShortcut("j", modifiers: .command)
            }
        }
    }
    
    /// Maps the persisted theme string to a SwiftUI `ColorScheme`.
    /// Returns `nil` for `"System"` so the OS controls light/dark automatically.
    private var colorScheme: ColorScheme? {
        switch selectedTheme {
        case "Light": return .light
        case "Dark": return .dark
        default: return nil
        }
    }

    /// Resolves the persisted language string to a `Locale` injected into the environment.
    private var appLocale: Locale {
        switch selectedLanguage {
        case "Arabic":
            return Locale(identifier: "ar")
        default:
            return Locale(identifier: "en")
        }
    }

    /// Resolves the persisted language to an explicit `LayoutDirection` so Arabic
    /// UI mirrors correctly regardless of the device's system language.
    private var appLayoutDirection: LayoutDirection {
        switch selectedLanguage {
        case "Arabic":
            return .rightToLeft
        default:
            return .leftToRight
        }
    }
}
