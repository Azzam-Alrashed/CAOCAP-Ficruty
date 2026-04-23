import Foundation
import AuthenticationServices
import CryptoKit
import FirebaseAuth

// MARK: - AppleSignInCoordinator

/// Handles the ASAuthorizationController flow and produces a Firebase OAuthCredential.
///
/// Usage:
/// ```swift
/// let coordinator = AppleSignInCoordinator()
/// let credential = try await coordinator.signIn()
/// try await authManager.signInWithApple(credential: credential)
/// ```
@MainActor
final class AppleSignInCoordinator: NSObject {

    private var continuation: CheckedContinuation<OAuthCredential, Error>?

    /// A random nonce used to prevent replay attacks. Must be sent to Apple
    /// and verified against the returned identity token.
    private var currentNonce: String?

    // MARK: - Public

    func signIn() async throws -> OAuthCredential {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let nonce = randomNonce()
            self.currentNonce = nonce

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(nonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - Nonce Helpers

    private func randomNonce(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        return randomBytes.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard
                let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let nonce = self.currentNonce,
                let appleIDToken = appleIDCredential.identityToken,
                let idTokenString = String(data: appleIDToken, encoding: .utf8)
            else {
                self.continuation?.resume(throwing: AuthError.invalidAppleCredential)
                self.continuation = nil
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )
            self.continuation?.resume(returning: credential)
            self.continuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            self.continuation?.resume(throwing: error)
            self.continuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // ASAuthorizationController always calls this on the main thread.
        // assumeIsolated bridges the nonisolated protocol requirement to @MainActor.
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.windows.first { $0.isKeyWindow } ?? UIWindow()
        }
    }
}

// MARK: - AuthError

enum AuthError: LocalizedError {
    case invalidAppleCredential
    case missingPresentingViewController

    var errorDescription: String? {
        switch self {
        case .invalidAppleCredential:
            return "Could not validate Apple ID credential. Please try again."
        case .missingPresentingViewController:
            return "No view controller available to present sign-in flow."
        }
    }
}
