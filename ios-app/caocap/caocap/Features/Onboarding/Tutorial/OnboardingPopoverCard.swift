import SwiftUI

/// A shape that outlines a rounded rectangle bubble with a triangle arrow pointing down or up.
struct UnifiedBubbleWithArrowShape: Shape {
    enum ArrowPlacement {
        case top, bottom
    }
    
    var cornerRadius: CGFloat = 16
    var arrowSize: CGSize = CGSize(width: 16, height: 8)
    var arrowOffset: CGFloat = 0 // Offset from center
    var placement: ArrowPlacement = .bottom
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let bubbleHeight = rect.height - arrowSize.height
        let minX = rect.minX
        let maxX = rect.maxX
        
        let minY = placement == .top ? rect.minY + arrowSize.height : rect.minY
        let maxY = placement == .top ? rect.maxY : rect.minY + bubbleHeight
        
        // Calculate arrow center and clamp to keep it within bubble bounds
        let baseMidX = rect.midX + arrowOffset
        let minArrowX = minX + cornerRadius + arrowSize.width / 2
        let maxArrowX = maxX - cornerRadius - arrowSize.width / 2
        let midX = min(max(baseMidX, minArrowX), maxArrowX)
        
        // Start at top-left corner (after the radius)
        path.move(to: CGPoint(x: minX + cornerRadius, y: minY))
        
        // If arrow is at the top, draw it pointing up
        if placement == .top {
            path.addLine(to: CGPoint(x: midX - arrowSize.width / 2, y: minY))
            path.addLine(to: CGPoint(x: midX, y: rect.minY))
            path.addLine(to: CGPoint(x: midX + arrowSize.width / 2, y: minY))
        }
        
        // Top edge
        path.addLine(to: CGPoint(x: maxX - cornerRadius, y: minY))
        
        // Top-right corner
        path.addArc(
            center: CGPoint(x: maxX - cornerRadius, y: minY + cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: -90),
            endAngle: Angle(degrees: 0),
            clockwise: false
        )
        
        // Right edge
        path.addLine(to: CGPoint(x: maxX, y: maxY - cornerRadius))
        
        // Bottom-right corner
        path.addArc(
            center: CGPoint(x: maxX - cornerRadius, y: maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: 0),
            endAngle: Angle(degrees: 90),
            clockwise: false
        )
        
        // If arrow is at the bottom, draw it pointing down
        if placement == .bottom {
            path.addLine(to: CGPoint(x: midX + arrowSize.width / 2, y: maxY))
            path.addLine(to: CGPoint(x: midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: midX - arrowSize.width / 2, y: maxY))
        }
        
        // Bottom edge (left of bottom arrow)
        path.addLine(to: CGPoint(x: minX + cornerRadius, y: maxY))
        
        // Bottom-left corner
        path.addArc(
            center: CGPoint(x: minX + cornerRadius, y: maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: 90),
            endAngle: Angle(degrees: 180),
            clockwise: false
        )
        
        // Left edge
        path.addLine(to: CGPoint(x: minX, y: minY + cornerRadius))
        
        // Top-left corner
        path.addArc(
            center: CGPoint(x: minX + cornerRadius, y: minY + cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: 180),
            endAngle: Angle(degrees: 270),
            clockwise: false
        )
        
        path.closeSubpath()
        return path
    }
}

enum OnboardingTooltipAnchor: Hashable {
    /// Reusable anchor slots for future tutorial content.
    case canvas
    /// Anchored to the floating command button (FAB) at the bottom of the canvas.
    case floatingCommandButton
    case previewShell
    case previewOmnibox
    case coCaptain

    /// Whether this anchor is registered inside the canvas view hierarchy.
    var isCanvasLocal: Bool {
        self == .canvas
    }

    /// Whether this anchor is owned by the Mini-App preview shell or its tool sheets.
    var isPreviewShellLocal: Bool { self == .previewShell }

    /// Whether this anchor is rendered inside the preview omnibox list.
    var isPreviewOmniboxLocal: Bool { self == .previewOmnibox }

    /// Whether this anchor lives inside the CoCaptain sheet.
    var isCoCaptainLocal: Bool { self == .coCaptain }
}

/// Collects layout anchors for each named onboarding target so the tooltip overlay
/// can position itself relative to any annotated view in the hierarchy.
private struct OnboardingTooltipAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [OnboardingTooltipAnchor: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [OnboardingTooltipAnchor: Anchor<CGRect>],
        nextValue: () -> [OnboardingTooltipAnchor: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Canvas-local targets publish measured frames directly because `anchorPreference`
/// does not track `.position()`-placed overlays reliably in the infinite canvas.
private struct OnboardingExplicitAnchorFramePreferenceKey: PreferenceKey {
    static var defaultValue: [OnboardingTooltipAnchor: CGRect] = [:]

    static func reduce(
        value: inout [OnboardingTooltipAnchor: CGRect],
        nextValue: () -> [OnboardingTooltipAnchor: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Tracks the rendered size of the tooltip card so `tooltipCenter` can clamp position
/// correctly before the card is actually measured for the first time.
private struct OnboardingTooltipSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = CGSize(width: 290, height: 180)

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

extension View {
    /// Tags a view with an onboarding anchor so the tooltip overlay knows where to point.
    func onboardingTooltipAnchor(_ anchor: OnboardingTooltipAnchor) -> some View {
        anchorPreference(key: OnboardingTooltipAnchorPreferenceKey.self, value: .bounds) {
            [anchor: $0]
        }
    }

    /// Reads all accumulated anchors and renders the tooltip overlay in a single pass,
    /// avoiding multiple layout passes that could cause jitter.
    func onboardingExplicitAnchorFrames(_ frames: [OnboardingTooltipAnchor: CGRect]) -> some View {
        preference(key: OnboardingExplicitAnchorFramePreferenceKey.self, value: frames)
    }

    /// Publishes a measured frame for one onboarding anchor. Prefer this over
    /// `anchorPreference` for rows inside scroll views where layout anchors drift.
    func onboardingExplicitAnchorFrame(
        _ anchor: OnboardingTooltipAnchor,
        isEnabled: Bool,
        coordinateSpace: CoordinateSpace = .global
    ) -> some View {
        background {
            if isEnabled {
                GeometryReader { proxy in
                    Color.clear.onboardingExplicitAnchorFrames([
                        anchor: proxy.frame(in: coordinateSpace)
                    ])
                }
            }
        }
    }

    func onboardingTooltipOverlay(
        isCommandPalettePresented: Bool = false,
        rendersAnchor: @escaping (OnboardingTooltipAnchor) -> Bool = { _ in true },
        onCardFrameChange: ((CGRect) -> Void)? = nil
    ) -> some View {
        overlayPreferenceValue(OnboardingTooltipAnchorPreferenceKey.self) { anchors in
            overlayPreferenceValue(OnboardingExplicitAnchorFramePreferenceKey.self) { explicitFrames in
                OnboardingTooltipOverlay(
                    anchors: anchors,
                    explicitFrames: explicitFrames,
                    isCommandPalettePresented: isCommandPalettePresented,
                    rendersAnchor: rendersAnchor,
                    onCardFrameChange: onCardFrameChange
                )
            }
        }
    }

    /// Sheet-safe onboarding overlay for CoCaptain. Reads anchor preferences with
    /// `onPreferenceChange` instead of nested `overlayPreferenceValue`, which duplicates
    /// scroll content inside the CoCaptain sheet.
    func coCaptainOnboardingTooltipOverlay() -> some View {
        modifier(CoCaptainSheetTooltipOverlayModifier())
    }

    /// Chrome-window FAB tooltips. Avoids `overlayPreferenceValue`, which duplicated the FAB.
    func fabChromeOnboardingTooltipOverlay(
        isCommandPalettePresented: Bool,
        onCardFrameChange: ((CGRect) -> Void)? = nil
    ) -> some View {
        modifier(
            FABChromeOnboardingTooltipOverlayModifier(
                isCommandPalettePresented: isCommandPalettePresented,
                onCardFrameChange: onCardFrameChange
            )
        )
    }
}

/// Collects onboarding anchor preferences without `overlayPreferenceValue` so the
/// CoCaptain timeline is not laid out twice.
private struct CoCaptainSheetTooltipOverlayModifier: ViewModifier {
    @State private var layoutAnchors: [OnboardingTooltipAnchor: Anchor<CGRect>] = [:]
    @State private var explicitFrames: [OnboardingTooltipAnchor: CGRect] = [:]

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(OnboardingTooltipAnchorPreferenceKey.self) { layoutAnchors = $0 }
            .onPreferenceChange(OnboardingExplicitAnchorFramePreferenceKey.self) { explicitFrames = $0 }
            .overlay {
                OnboardingTooltipOverlay(
                    anchors: layoutAnchors,
                    explicitFrames: explicitFrames,
                    isCommandPalettePresented: false,
                    rendersAnchor: { $0.isCoCaptainLocal }
                )
            }
    }
}

/// Same preference pattern as CoCaptain — `overlayPreferenceValue` was drawing a second FAB.
private struct FABChromeOnboardingTooltipOverlayModifier: ViewModifier {
    let isCommandPalettePresented: Bool
    var onCardFrameChange: ((CGRect) -> Void)?

    @State private var layoutAnchors: [OnboardingTooltipAnchor: Anchor<CGRect>] = [:]
    @State private var explicitFrames: [OnboardingTooltipAnchor: CGRect] = [:]

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(OnboardingTooltipAnchorPreferenceKey.self) { layoutAnchors = $0 }
            .onPreferenceChange(OnboardingExplicitAnchorFramePreferenceKey.self) { explicitFrames = $0 }
            .overlay {
                OnboardingTooltipOverlay(
                    anchors: layoutAnchors,
                    explicitFrames: explicitFrames,
                    isCommandPalettePresented: isCommandPalettePresented,
                    rendersAnchor: { $0 == .floatingCommandButton },
                    onCardFrameChange: onCardFrameChange
                )
            }
    }
}

/// An overlay view that reads the registered anchor frames and positions a
/// `OnboardingPopoverCard` relative to the currently active step's target.
/// The tooltip is positioned to stay within safe area margins and transitions
/// with a spring scale-plus-fade animation.
private struct OnboardingTooltipOverlay: View {
    let anchors: [OnboardingTooltipAnchor: Anchor<CGRect>]
    let explicitFrames: [OnboardingTooltipAnchor: CGRect]
    let isCommandPalettePresented: Bool
    let rendersAnchor: (OnboardingTooltipAnchor) -> Bool
    var onCardFrameChange: ((CGRect) -> Void)? = nil

    @Environment(OnboardingCoordinator.self) private var onboarding: OnboardingCoordinator?
    @State private var cardSize = CGSize(width: 290, height: 180)

    var body: some View {
        GeometryReader { proxy in
            if let onboarding,
               let step = onboarding.currentStep,
               let stepContent = onboarding.content(for: step),
               onboarding.showPopover {
                let resolvedAnchor = stepContent.tooltipAnchor
                if rendersAnchor(resolvedAnchor),
                   let targetFrame = resolvedTargetFrame(for: resolvedAnchor, in: proxy) {
                let tooltipCenter = tooltipCenter(
                    for: targetFrame,
                    placement: stepContent.tooltipArrowPlacement,
                    cardSize: cardSize,
                    containerSize: proxy.size
                )
                let arrowOffset = targetFrame.midX - tooltipCenter.x

                OnboardingPopoverCard(
                    content: stepContent,
                    lesson: onboarding.activeLessonID.flatMap { onboarding.lesson(for: $0) },
                    arrowOffset: arrowOffset,
                    arrowPlacement: stepContent.tooltipArrowPlacement
                ) {
                    onboarding.skip()
                }
                .background(
                    GeometryReader { cardProxy in
                        Color.clear.preference(
                            key: OnboardingTooltipSizePreferenceKey.self,
                            value: cardProxy.size
                        )
                        .onAppear {
                            reportCardFrame(center: tooltipCenter, size: cardProxy.size)
                        }
                        .onChange(of: tooltipCenter.x) { _, _ in
                            reportCardFrame(center: tooltipCenter, size: cardSize)
                        }
                        .onChange(of: tooltipCenter.y) { _, _ in
                            reportCardFrame(center: tooltipCenter, size: cardSize)
                        }
                    }
                )
                .onPreferenceChange(OnboardingTooltipSizePreferenceKey.self) { newSize in
                    cardSize = newSize
                    reportCardFrame(center: tooltipCenter, size: newSize)
                }
                .position(tooltipCenter)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(1000)
                } else {
                    Color.clear.onAppear { onCardFrameChange?(.null) }
                }
            } else {
                Color.clear.onAppear { onCardFrameChange?(.null) }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: onboarding?.currentStep)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: onboarding?.showPopover)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isCommandPalettePresented)
        .onDisappear { onCardFrameChange?(.null) }
    }

    private func reportCardFrame(center: CGPoint, size: CGSize) {
        guard size.width > 1, size.height > 1 else {
            onCardFrameChange?(.null)
            return
        }
        onCardFrameChange?(
            CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            ).insetBy(dx: -8, dy: -8)
        )
    }

    private func resolvedTargetFrame(
        for anchor: OnboardingTooltipAnchor,
        in proxy: GeometryProxy
    ) -> CGRect? {
        if let explicit = explicitFrames[anchor] {
            return explicit
        }
        if let layoutAnchor = anchors[anchor] {
            return proxy[layoutAnchor]
        }
        return nil
    }

    /// Computes the center point for the tooltip card, keeping it inset from screen edges
    /// and on the correct side of the target frame based on arrow placement.
    private func tooltipCenter(
        for targetFrame: CGRect,
        placement: UnifiedBubbleWithArrowShape.ArrowPlacement,
        cardSize: CGSize,
        containerSize: CGSize
    ) -> CGPoint {
        let safetyMargin: CGFloat = 16
        let spacing: CGFloat = 8
        let halfWidth = cardSize.width / 2
        let halfHeight = cardSize.height / 2

        let x = min(
            max(targetFrame.midX, safetyMargin + halfWidth),
            max(safetyMargin + halfWidth, containerSize.width - safetyMargin - halfWidth)
        )

        let unclampedY: CGFloat
        switch placement {
        case .bottom:
            unclampedY = targetFrame.minY - spacing - halfHeight
        case .top:
            unclampedY = targetFrame.maxY + spacing + halfHeight
        }

        let y = min(
            max(unclampedY, safetyMargin + halfHeight),
            max(safetyMargin + halfHeight, containerSize.height - safetyMargin - halfHeight)
        )

        return CGPoint(x: x, y: y)
    }
}

/// A premium glassmorphic popover card used for onboarding tooltips.
/// Matches CAOCAP's dark, material-blurred visual language.
struct OnboardingPopoverCard: View {
    let content: OnboardingStepContent
    let lesson: OnboardingLesson?
    var arrowOffset: CGFloat = 0
    var arrowPlacement: UnifiedBubbleWithArrowShape.ArrowPlacement = .bottom
    let onSkip: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var accentColor: Color {
        lesson?.accentColor ?? Color(hex: "6C5CE7")
    }

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentColor, accentColor.opacity(0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: icon + title + step counter
            HStack(spacing: 10) {
                // Animated icon
                Image(systemName: content.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accentGradient)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(stringLiteral: content.titleKey))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)

                    OnboardingProgressBar(step: content.id, lesson: lesson)
                }

                Spacer()

                // Skip button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        onSkip()
                    }
                } label: {
                    Text(LocalizedStringKey("Skip"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }

            // Message body
            Text(LocalizedStringKey(stringLiteral: content.messageKey))
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.primary.opacity(0.85))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.top, arrowPlacement == .top ? 18 + 8 : 18)
        .padding(.bottom, arrowPlacement == .bottom ? 18 + 8 : 18)
        .frame(width: 290)
        .background(
            UnifiedBubbleWithArrowShape(arrowOffset: arrowOffset, placement: arrowPlacement)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            UnifiedBubbleWithArrowShape(arrowOffset: arrowOffset, placement: arrowPlacement)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.25 : 0.45),
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.15),
                            accentColor.opacity(colorScheme == .dark ? 0.2 : 0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
        .shadow(color: accentColor.opacity(0.08), radius: 30, x: 0, y: 5)
    }
}

/// A step-progress bar that fills from the left as the user advances through a lesson.
private struct OnboardingProgressBar: View {
    let step: OnboardingCoordinator.Step
    let lesson: OnboardingLesson?

    private var lessonSteps: [OnboardingCoordinator.Step] {
        lesson?.steps ?? []
    }

    private var currentIndex: Int {
        lessonSteps.firstIndex(of: step) ?? 0
    }

    private var accentColor: Color {
        lesson?.accentColor ?? .blue
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(lessonSteps.enumerated()), id: \.element.rawValue) { index, _ in
                Capsule()
                    .fill(index <= currentIndex ? accentColor.opacity(0.85) : Color.primary.opacity(0.12))
                    .frame(width: 16, height: 4)
            }
        }
        .accessibilityLabel(Text("Step \(currentIndex + 1) of \(lessonSteps.count)"))
    }
}
