import SwiftUI

/// A draggable, long-press-expandable floating action button that anchors at the
/// bottom-trailing corner of the canvas and snaps to a 3×3 edge grid on release.
///
/// **Interaction modes:**
/// - **Tap** – toggles the AI chat.
/// - **Long-press** – expands a radial menu for Center Canvas / Command Line / Video.
/// - **Drag** – repositions the button; on release it snaps to the nearest grid point.
/// - **Drag while expanded** – gestures toward a bubble to highlight and select it.
struct FloatingCommandButton: View {
    @State private var position: CGPoint = .zero
    @State private var startPosition: CGPoint = .zero
    @State private var isDragging: Bool = false
    @State private var isExpanded: Bool = false
    @State private var activeAction: CommandAction? = nil

    enum CommandAction {
        case centerCanvas
        case commandLine
        case video
    }

    @Environment(\.colorScheme) var colorScheme

    var onTap: () -> Void
    /// Restores the active canvas to its origin at 100% zoom.
    var onCenterCanvas: () -> Void
    var onOpenCommandLine: () -> Void
    var onSelectMode: (CopilotInteractionMode) -> Void
    var copilot: CopilotPersona = UserProfileStore().loadSelectedCopilot()

    var tooltipAnchor: OnboardingTooltipAnchor = .floatingCommandButton
    /// Additional clearance reserved beneath the snap grid (for global tab chrome).
    var bottomInset: CGFloat = 0
    /// When non-null and overlapping the FAB, the button relocates to another snap point.
    var obstacleFrame: CGRect = .null
    /// Hit-test region for the overlay window (full screen while the radial menu is open).
    var onInteractiveFrameChange: ((CGRect) -> Void)? = nil
    /// Compact FAB rect used for onboarding tooltip anchoring in ContentView.
    var onAnchorFrameChange: ((CGRect) -> Void)? = nil

    @State private var containerSize: CGSize = .zero

    private let padding: CGFloat = 35
    private let buttonSize: CGFloat = 64
    private let avoidancePadding: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let currentPos = position == .zero ? initialPosition(in: size) : position

            let buttonScale: CGFloat = {
                if isDragging {
                    return 1.15
                } else if isExpanded {
                    return 0.9
                } else {
                    return 1.0
                }
            }()

            let shadowRadius: CGFloat = (isDragging || isExpanded) ? 15 : 10

            let shadowColor: Color = (isDragging || isExpanded)
                ? Color.black.opacity(0.35)
                : Color.black.opacity(0.2)

            ZStack {
                if isExpanded {
                    Color.black.opacity(0.01)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isExpanded = false
                            }
                        }
                }

                quickActionBubbles(around: currentPos, in: size)

                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(Color(hex: copilot.accentHex).opacity(0.4), lineWidth: 1.5)
                        )
                        .shadow(
                            color: shadowColor,
                            radius: shadowRadius,
                            x: 0,
                            y: (isDragging || isExpanded) ? 8 : 5
                        )

                    if isExpanded {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.primary)
                            .rotationEffect(.degrees(90))
                    } else {
                        Image(copilot.avatarImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: buttonSize * 0.72, height: buttonSize * 0.72)
                            .clipShape(Circle())
                    }
                }
                .frame(width: buttonSize, height: buttonSize)
                .scaleEffect(buttonScale)
                .onboardingTooltipAnchor(tooltipAnchor)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .onEnded { _ in
                            if !isDragging {
                                triggerHapticFeedback(.heavy)
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                    isExpanded = true
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("floatingLayer"))
                        .onChanged { value in
                            if isExpanded {
                                updateActiveAction(at: value.location, center: currentPos, size: size)
                            } else {
                                let dragThreshold: CGFloat = 10
                                let dragDistance = sqrt(
                                    pow(value.translation.width, 2) + pow(value.translation.height, 2)
                                )

                                if dragDistance > dragThreshold {
                                    if !isDragging {
                                        startPosition = currentPos
                                        withAnimation(.interactiveSpring()) {
                                            isDragging = true
                                        }
                                        triggerHapticFeedback(.light)
                                    }

                                    position = CGPoint(
                                        x: startPosition.x + value.translation.width,
                                        y: startPosition.y + value.translation.height
                                    )
                                }
                            }
                        }
                        .onEnded { _ in
                            if isExpanded {
                                if let action = activeAction {
                                    executeAction(action)
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    isExpanded = false
                                    activeAction = nil
                                }
                            } else if isDragging {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    isDragging = false
                                    snapToNearestPoint(in: size)
                                }
                            } else {
                                triggerHapticFeedback(.medium)
                                onTap()
                            }
                        }
                )
                .position(currentPos)
            }
            .coordinateSpace(name: "floatingLayer")
            .onAppear {
                containerSize = size
                if position == .zero {
                    position = initialPosition(in: size)
                }
                avoidObstacleIfNeeded(in: size)
                reportFrames(center: position == .zero ? initialPosition(in: size) : position, in: size)
            }
            .onChange(of: geometry.size) { _, newSize in
                containerSize = newSize
                withAnimation(.spring()) {
                    snapToNearestPoint(in: newSize)
                }
            }
            .onChange(of: obstacleFrame) { _, _ in
                avoidObstacleIfNeeded(in: containerSize == .zero ? size : containerSize)
            }
            .onChange(of: position) { _, _ in
                reportFrames(center: currentPos, in: size)
            }
            .onChange(of: isExpanded) { _, _ in
                reportFrames(center: currentPos, in: size)
            }
            .onChange(of: isDragging) { _, _ in
                reportFrames(center: currentPos, in: size)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func quickActionBubbles(around pos: CGPoint, in size: CGSize) -> some View {
        let direction = sproutDirection(for: pos, in: size)
        let distance: CGFloat = 75
        let angle: CGFloat = 45

        ZStack {
            // Center: Command Line
            QuickActionBubble(
                icon: "command",
                color: .green,
                isExpanded: isExpanded,
                isHighlighted: activeAction == .commandLine,
                size: 48,
                delay: 0.05
            ) {
                triggerHapticFeedback(.medium)
                withAnimation(.spring()) { isExpanded = false }
                onOpenCommandLine()
            }
            .offset(
                x: isExpanded ? direction.x * distance : 0,
                y: isExpanded ? direction.y * distance : 0
            )

            // Left: Center Canvas
            QuickActionBubble(
                icon: "scope",
                color: .primary,
                isExpanded: isExpanded,
                isHighlighted: activeAction == .centerCanvas,
                size: 40,
                delay: 0.0
            ) {
                triggerHapticFeedback(.medium)
                withAnimation(.spring()) { isExpanded = false }
                onCenterCanvas()
            }
            .offset(
                x: isExpanded ? direction.rotated(by: -angle).x * distance : 0,
                y: isExpanded ? direction.rotated(by: -angle).y * distance : 0
            )

            // Right: Video (screen share)
            QuickActionBubble(
                icon: CopilotInteractionMode.video.systemImageName,
                color: .red,
                isExpanded: isExpanded,
                isHighlighted: activeAction == .video,
                size: 40,
                delay: 0.1
            ) {
                triggerHapticFeedback(.medium)
                withAnimation(.spring()) { isExpanded = false }
                onSelectMode(.video)
            }
            .offset(
                x: isExpanded ? direction.rotated(by: angle).x * distance : 0,
                y: isExpanded ? direction.rotated(by: angle).y * distance : 0
            )
        }
        .position(pos)
    }

    private func updateActiveAction(at location: CGPoint, center: CGPoint, size: CGSize) {
        let direction = sproutDirection(for: center, in: size)
        let distance: CGFloat = 75
        let angle: CGFloat = 45
        let threshold: CGFloat = 40

        let centerCanvasPos = CGPoint(
            x: center.x + direction.rotated(by: -angle).x * distance,
            y: center.y + direction.rotated(by: -angle).y * distance
        )
        let commandLinePos = CGPoint(
            x: center.x + direction.x * distance,
            y: center.y + direction.y * distance
        )
        let videoPos = CGPoint(
            x: center.x + direction.rotated(by: angle).x * distance,
            y: center.y + direction.rotated(by: angle).y * distance
        )

        let dCenterCanvas = hypot(location.x - centerCanvasPos.x, location.y - centerCanvasPos.y)
        let dCommandLine = hypot(location.x - commandLinePos.x, location.y - commandLinePos.y)
        let dVideo = hypot(location.x - videoPos.x, location.y - videoPos.y)

        let previousAction = activeAction
        let nearest = [
            (CommandAction.centerCanvas, dCenterCanvas, true),
            (.commandLine, dCommandLine, true),
            (.video, dVideo, true)
        ]
            .filter { $0.1 < threshold && $0.2 }
            .min(by: { $0.1 < $1.1 })

        activeAction = nearest?.0

        if activeAction != previousAction && activeAction != nil {
            triggerHapticFeedback(.light)
        }
    }

    private func executeAction(_ action: CommandAction) {
        triggerHapticFeedback(.medium)
        switch action {
        case .centerCanvas:
            onCenterCanvas()
        case .commandLine:
            onOpenCommandLine()
        case .video:
            onSelectMode(.video)
        }
    }

    private func sproutDirection(for pos: CGPoint, in size: CGSize) -> CGPoint {
        let dx = size.width / 2 - pos.x
        let dy = size.height / 2 - pos.y
        let len = sqrt(dx * dx + dy * dy)
        return len > 0 ? CGPoint(x: dx / len, y: dy / len) : CGPoint(x: 0, y: -1)
    }

    private func initialPosition(in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width - padding - buttonSize / 2,
            y: size.height - bottomInset - padding - buttonSize / 2
        )
    }

    private func fabFrame(at center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - buttonSize / 2,
            y: center.y - buttonSize / 2,
            width: buttonSize,
            height: buttonSize
        )
    }

    private func reportFrames(center: CGPoint, in size: CGSize) {
        let anchor = fabFrame(at: center)
        onAnchorFrameChange?(anchor)
        if isExpanded {
            // Allow tap-outside dismissal while the radial menu is open.
            onInteractiveFrameChange?(CGRect(origin: .zero, size: size))
        } else {
            onInteractiveFrameChange?(anchor.insetBy(dx: -10, dy: -10))
        }
    }

    private func snapPoints(in size: CGSize) -> [CGPoint] {
        let minX = padding + buttonSize / 2
        let maxX = size.width - padding - buttonSize / 2
        let minY = 60 + buttonSize / 2
        let maxY = size.height - bottomInset - padding - buttonSize / 2
        let centerX = size.width / 2
        let centerY = size.height / 2
        return [
            CGPoint(x: minX, y: minY), CGPoint(x: centerX, y: minY), CGPoint(x: maxX, y: minY),
            CGPoint(x: minX, y: centerY), CGPoint(x: maxX, y: centerY),
            CGPoint(x: minX, y: maxY), CGPoint(x: centerX, y: maxY), CGPoint(x: maxX, y: maxY)
        ]
    }

    private func snapToNearestPoint(in size: CGSize) {
        let points = snapPoints(in: size)
        let preferred = points.min(by: { distance(from: $0, to: position) < distance(from: $1, to: position) }) ?? points[7]
        position = bestPoint(near: preferred, in: size) ?? preferred
        reportFrames(center: position, in: size)
        triggerHapticFeedback(.rigid)
    }

    private func avoidObstacleIfNeeded(in size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        guard !obstacleFrame.isNull, !obstacleFrame.isEmpty else { return }
        let current = position == .zero ? initialPosition(in: size) : position
        let inflatedObstacle = obstacleFrame.insetBy(dx: -avoidancePadding, dy: -avoidancePadding)
        guard fabFrame(at: current).intersects(inflatedObstacle) else { return }

        if let next = bestPoint(near: current, in: size) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                position = next
            }
            reportFrames(center: next, in: size)
            triggerHapticFeedback(.light)
        }
    }

    /// Picks the closest snap point that does not intersect the obstacle frame.
    private func bestPoint(near target: CGPoint, in size: CGSize) -> CGPoint? {
        let inflatedObstacle = obstacleFrame.isNull
            ? CGRect.null
            : obstacleFrame.insetBy(dx: -avoidancePadding, dy: -avoidancePadding)
        let candidates = snapPoints(in: size)
            .filter { !fabFrame(at: $0).intersects(inflatedObstacle) }
            .sorted { distance(from: $0, to: target) < distance(from: $1, to: target) }
        return candidates.first
    }

    private func distance(from: CGPoint, to: CGPoint) -> CGFloat {
        hypot(from.x - to.x, from.y - to.y)
    }

    private func triggerHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}

struct QuickActionBubble: View {
    let icon: String
    let color: Color
    let isExpanded: Bool
    var isEnabled: Bool = true
    var isHighlighted: Bool = false
    var size: CGFloat = 48
    let delay: Double
    let action: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(isHighlighted ? color : color.opacity(isEnabled ? 0.3 : 0.1), lineWidth: isHighlighted ? 2 : 1))
                .shadow(color: color.opacity(isHighlighted ? 0.5 : (isEnabled ? 0.2 : 0)), radius: isHighlighted ? 12 : 8)

            Image(systemName: icon)
                .font(.system(size: size * 0.375, weight: .bold))
                .foregroundColor(color)
                .opacity(isEnabled ? 1.0 : 0.3)
        }
        .frame(width: size, height: size)
        .scaleEffect(isExpanded ? (isHighlighted ? 1.25 : 1.0) : 0.01)
        .opacity(isExpanded ? (isEnabled ? 1 : 0.5) : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHighlighted)
        .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(isExpanded ? delay : 0), value: isExpanded)
        .animation(.spring(), value: isEnabled)
        .onTapGesture {
            if isEnabled && isExpanded {
                action()
            }
        }
    }
}

extension CGPoint {
    func rotated(by degrees: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        let sinTheta = sin(radians)
        let cosTheta = cos(radians)
        return CGPoint(
            x: x * cosTheta - y * sinTheta,
            y: x * sinTheta + y * cosTheta
        )
    }
}
