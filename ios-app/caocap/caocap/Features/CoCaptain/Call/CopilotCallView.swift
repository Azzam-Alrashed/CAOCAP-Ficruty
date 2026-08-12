import SwiftUI

/// Compact, draggable call chrome for Gemini Live screen-share sessions.
/// Starts at the top of the canvas and can be dragged out of the way.
struct CopilotCallView: View {
    @Bindable var viewModel: CopilotCallViewModel
    var onFrameChange: ((CGRect) -> Void)? = nil

    @State private var position: CGPoint = .zero
    @State private var dragStart: CGPoint = .zero
    @State private var isDragging = false
    @State private var appeared = false
    @State private var statusPulse = false

    static let cardSize = CGSize(width: 268, height: 64)
    static let videoCardSize = CGSize(width: 310, height: 64)
    static let quotaCardSize = CGSize(width: 300, height: 92)
    private let edgePadding: CGFloat = 16

    private var cardSize: CGSize {
        if viewModel.isQuotaExceeded { return Self.quotaCardSize }
        if viewModel.showsScreenShareControl { return Self.videoCardSize }
        return Self.cardSize
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let currentPos = position == .zero ? defaultPosition(in: size) : position

            callCard
                .frame(width: cardSize.width, height: cardSize.height)
                .scaleEffect(isDragging ? 1.04 : (appeared ? 1 : 0.86))
                .opacity(appeared ? 1 : 0)
                .shadow(
                    color: .black.opacity(isDragging ? 0.28 : 0.16),
                    radius: isDragging ? 18 : 10,
                    y: isDragging ? 10 : 5
                )
                .position(currentPos)
                .gesture(dragGesture(in: size, currentPos: currentPos))
                .onAppear {
                    if position == .zero {
                        position = defaultPosition(in: size)
                    }
                    reportFrame(at: position == .zero ? defaultPosition(in: size) : position)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                        appeared = true
                    }
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        statusPulse = true
                    }
                    viewModel.start()
                }
                .onDisappear {
                    onFrameChange?(.null)
                }
                .onChange(of: geometry.size) { _, newSize in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        position = clamped(position, in: newSize)
                    }
                    reportFrame(at: clamped(position, in: newSize))
                }
                .onChange(of: viewModel.isQuotaExceeded) { _, exceeded in
                    guard exceeded else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        position = clamped(position, in: size)
                    }
                    reportFrame(at: clamped(position, in: size))
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: viewModel.isMuted)
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: viewModel.isScreenSharing)
                .animation(.easeInOut(duration: 0.25), value: viewModel.connectionState)
                .animation(.spring(response: 0.32, dampingFraction: 0.84), value: viewModel.isQuotaExceeded)
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    private var callCard: some View {
        HStack(spacing: 10) {
            avatar

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 6, height: 6)
                        .scaleEffect(statusPulse && isLive ? 1.35 : 1)
                        .opacity(statusPulse && isLive ? 1 : 0.7)

                    Text(modeLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(viewModel.persona.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(viewModel.statusText)
                    .font(.caption2)
                    .foregroundStyle(viewModel.isQuotaExceeded ? .orange : .secondary)
                    .lineLimit(viewModel.isQuotaExceeded ? 2 : 1)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 4)

            if viewModel.isQuotaExceeded {
                upgradeButton
            } else {
                muteButton
                if viewModel.showsScreenShareControl {
                    screenShareButton
                }
            }
            endButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: viewModel.persona.accentHex).opacity(0.22), lineWidth: 1)
        )
    }

    private var avatar: some View {
        Image(viewModel.persona.avatarImageName)
            .resizable()
            .scaledToFit()
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color(hex: viewModel.persona.accentHex).opacity(0.5), lineWidth: 1.5)
            )
    }

    private var muteButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                viewModel.toggleMute()
            }
        } label: {
            Image(systemName: viewModel.isMuted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(viewModel.isMuted ? Color.orange : Color.primary)
                .frame(width: 32, height: 32)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            viewModel.isMuted
                ? LocalizationManager.shared.localizedString("copilot.call.unmute")
                : LocalizationManager.shared.localizedString("copilot.call.mute")
        )
    }

    private var screenShareButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                viewModel.toggleScreenShare()
            }
        } label: {
            Image(systemName: "rectangle.dashed.badge.record")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(viewModel.isScreenSharing ? Color.red : Color.primary)
                .frame(width: 32, height: 32)
                .background(.thinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(viewModel.isScreenSharing ? Color.red.opacity(0.45) : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            viewModel.isScreenSharing
                ? LocalizationManager.shared.localizedString("copilot.call.stopSharing")
                : LocalizationManager.shared.localizedString("copilot.call.shareScreen")
        )
    }

    private var upgradeButton: some View {
        Button {
            viewModel.upgradeToPro()
        } label: {
            Text(LocalizationManager.shared.localizedString("copilot.call.upgrade"))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Color.orange, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LocalizationManager.shared.localizedString("copilot.call.upgrade"))
    }

    private var endButton: some View {
        Button {
            viewModel.endCall()
        } label: {
            Image(systemName: "phone.down.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.red, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LocalizationManager.shared.localizedString("copilot.call.end"))
    }

    private var modeLabel: String {
        LocalizationManager.shared.localizedString(
            viewModel.isScreenSharing
                ? "copilot.call.recording"
                : viewModel.mode.localizedTitleKey
        )
    }

    private var statusDotColor: Color {
        switch viewModel.connectionState {
        case .connected:
            return viewModel.isScreenSharing ? .red : Color(hex: viewModel.persona.accentHex)
        case .connecting:
            return .orange
        case .failed:
            return .red
        case .ended, .idle:
            return .secondary
        }
    }

    private var isLive: Bool {
        if case .connected = viewModel.connectionState { return true }
        if case .connecting = viewModel.connectionState { return true }
        return false
    }

    private func dragGesture(in size: CGSize, currentPos: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !isDragging {
                    dragStart = currentPos
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isDragging = true
                    }
                }
                let next = clamped(
                    CGPoint(
                        x: dragStart.x + value.translation.width,
                        y: dragStart.y + value.translation.height
                    ),
                    in: size
                )
                position = next
                reportFrame(at: next)
            }
            .onEnded { _ in
                let snapped = snapToNearestPoint(position, in: size)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    isDragging = false
                    position = snapped
                }
                reportFrame(at: snapped)
                triggerHapticFeedback(.rigid)
            }
    }

    private func reportFrame(at center: CGPoint) {
        onFrameChange?(
            CGRect(
                x: center.x - cardSize.width / 2,
                y: center.y - cardSize.height / 2,
                width: cardSize.width,
                height: cardSize.height
            )
        )
    }

    /// Same edge/corner dock points as the FAB (3×3 without the screen center).
    private func snapPoints(in size: CGSize) -> [CGPoint] {
        let minX = edgePadding + cardSize.width / 2
        let maxX = size.width - edgePadding - cardSize.width / 2
        let minY = edgePadding + cardSize.height / 2 + 44
        let maxY = size.height - edgePadding - cardSize.height / 2
        let centerX = size.width / 2
        let centerY = size.height / 2
        return [
            CGPoint(x: minX, y: minY), CGPoint(x: centerX, y: minY), CGPoint(x: maxX, y: minY),
            CGPoint(x: minX, y: centerY), CGPoint(x: maxX, y: centerY),
            CGPoint(x: minX, y: maxY), CGPoint(x: centerX, y: maxY), CGPoint(x: maxX, y: maxY)
        ]
    }

    /// Top-center dock, clear of the bottom-trailing FAB.
    private func defaultPosition(in size: CGSize) -> CGPoint {
        snapPoints(in: size)[1]
    }

    private func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let points = snapPoints(in: size)
        let minX = points.map(\.x).min() ?? point.x
        let maxX = points.map(\.x).max() ?? point.x
        let minY = points.map(\.y).min() ?? point.y
        let maxY = points.map(\.y).max() ?? point.y
        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }

    private func snapToNearestPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let points = snapPoints(in: size)
        return points.min(by: {
            hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y)
        }) ?? points[1]
    }

    private func triggerHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}
