import SwiftUI

struct CanvasHUDView: View {
    let store: ProjectStore
    let viewportScale: CGFloat
    var onSignInTapped: (() -> Void)? = nil

    @Environment(AuthenticationManager.self) private var authManager
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            HStack(spacing: 0) {
                // Info pill (non-interactive)
                HStack(spacing: 16) {
                    // Project Name
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text(store.projectName.uppercased())
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .kerning(1)
                    }

                    Divider().frame(height: 16)

                    // Node Count
                    HStack(spacing: 4) {
                        Text("\(store.nodes.count)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        Text("nodes")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Divider().frame(height: 16)

                    // Zoom Level
                    HStack(spacing: 4) {
                        Text("\(Int(viewportScale * 100))%")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Divider().frame(height: 16)

                    // Save Status
                    HStack(spacing: 6) {
                        if store.isSaving {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                                .shadow(color: .orange.opacity(0.5), radius: 3)
                            Text("SAVING")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.orange)
                        } else {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                                .shadow(color: .green.opacity(0.5), radius: 3)
                            Text("LIVE")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.green)
                        }
                    }
                    .animation(.spring(), value: store.isSaving)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .allowsHitTesting(false)

                // Profile Button (interactive)
                if authManager.isAnonymous {
                    Button(action: { onSignInTapped?() }) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.trailing, 16)
                            .padding(.leading, 8)
                    }
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "5E5CE6"), Color(hex: "BF5AF2")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(.trailing, 16)
                        .padding(.leading, 8)
                        .allowsHitTesting(false)
                }
            }
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)

            Spacer()
        }
        .padding(.top, 60)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        CanvasHUDView(store: ProjectStore(), viewportScale: 1.0)
            .environment(AuthenticationManager())
    }
}

