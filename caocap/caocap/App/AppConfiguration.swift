import Foundation
import OSLog
import FirebaseCore
import GoogleSignIn

/// Centralizes all third-party SDK configuration and app-launch bootstrap logic.
///
/// `AppConfiguration` is the single source of truth for startup initialization.
/// Adding a new SDK never requires touching `AppDelegate` — simply add a method here
/// and call it from `configure()`.
///
/// Usage:
/// ```swift
/// AppConfiguration.shared.configure(authManager: authManager)
/// ```
final class AppConfiguration {

    static let shared = AppConfiguration()

    private let logger = Logger(subsystem: "com.ficruty.caocap", category: "AppConfiguration")

    private init() {}

    // MARK: - Bootstrap

    /// Entry point for all app-level configuration.
    /// Call once from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    func configure(authManager: AuthenticationManager) {
        configureFirebase()
        configureGoogleSignIn()
        // `start()` is @MainActor-isolated. Firebase is configured synchronously above;
        // the auth listener starts on the next main actor run loop tick.
        Task { @MainActor in
            authManager.start()
        }
        logger.info("App bootstrap complete.")
    }

    // MARK: - Firebase

    private func configureFirebase() {
        guard FirebaseApp.app() == nil else {
            logger.warning("Firebase already configured — skipping duplicate call.")
            return
        }
        FirebaseApp.configure()
        logger.info("Firebase configured successfully.")
    }

    // MARK: - Google Sign-In

    private func configureGoogleSignIn() {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            logger.error("Google Sign-In: missing clientID in GoogleService-Info.plist.")
            return
        }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        logger.info("Google Sign-In configured successfully.")
    }
}

