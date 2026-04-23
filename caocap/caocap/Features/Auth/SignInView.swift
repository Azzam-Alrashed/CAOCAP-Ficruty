import SwiftUI
import FirebaseAuth

// MARK: - SignInView

/// A premium glassmorphic sign-in sheet.
/// Shown when the user wants to save their work across devices.
/// Links the current anonymous session to a real identity — no data is lost.
struct SignInView: View {
    @Environment(AuthenticationManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var appleCoordinator = AppleSignInCoordinator()
    @State private var googleCoordinator = GoogleSignInCoordinator()
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Ambient glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "5E5CE6").opacity(0.25), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 280
                    )
                )
                .frame(width: 560)
                .offset(y: -120)
                .blur(radius: 20)

            VStack(spacing: 0) {
                // Handle
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)

                Spacer().frame(height: 40)

                // Header
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "5E5CE6"), Color(hex: "BF5AF2")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("Save Your Work")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Sign in to sync your projects across\nall your devices. Your current work is preserved.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 32)

                Spacer().frame(height: 48)

                // Sign-In Buttons
                VStack(spacing: 14) {
                    SignInButton(
                        icon: "apple.logo",
                        label: "Continue with Apple",
                        foreground: .black,
                        background: .white
                    ) {
                        await handleAppleSignIn()
                    }

                    SignInButton(
                        icon: "g.circle.fill",
                        label: "Continue with Google",
                        foreground: .white,
                        background: Color(hex: "1A1A1A"),
                        stroke: Color.white.opacity(0.12)
                    ) {
                        await handleGoogleSignIn()
                    }

                    SignInButton(
                        icon: "chevron.left.forwardslash.chevron.right",
                        label: "Continue with GitHub",
                        foreground: .white,
                        background: Color(hex: "1A1A1A"),
                        stroke: Color.white.opacity(0.12)
                    ) {
                        await handleGitHubSignIn()
                    }
                }
                .padding(.horizontal, 28)

                // Error message
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "FF6B6B"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer().frame(height: 32)

                // Privacy note
                Text("By continuing, you agree to our Terms of Service\nand Privacy Policy.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 36)
            }

            // Loading overlay
            if isLoading {
                Color.black.opacity(0.5).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.4)
            }
        }
    }

    // MARK: - Actions

    private func handleAppleSignIn() async {
        await perform {
            let credential = try await appleCoordinator.signIn()
            try await authManager.signInWithApple(credential: credential)
            dismiss()
        }
    }

    private func handleGoogleSignIn() async {
        await perform {
            let credential = try await googleCoordinator.signIn()
            try await authManager.signInWithGoogle(credential: credential)
            dismiss()
        }
    }

    private func handleGitHubSignIn() async {
        await perform {
            try await authManager.signInWithGitHub()
            dismiss()
        }
    }

    /// Shared error-handling wrapper for all sign-in actions.
    private func perform(_ action: () async throws -> Void) async {
        withAnimation { isLoading = true; errorMessage = nil }
        do {
            try await action()
        } catch {
            withAnimation {
                errorMessage = error.localizedDescription
            }
        }
        withAnimation { isLoading = false }
    }

}

// MARK: - SignInButton

private struct SignInButton: View {
    let icon: String
    let label: String
    let foreground: Color
    let background: Color
    var stroke: Color = .clear
    let action: () async -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(PressableButtonStyle(isPressed: $isPressed))
    }
}

// MARK: - PressableButtonStyle

private struct PressableButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

#Preview {
    SignInView()
        .environment(AuthenticationManager())
}
