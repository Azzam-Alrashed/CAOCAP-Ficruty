import Foundation

/// Stable identifier for tutorial steps. New pivot content can define IDs without
/// changing the reusable coordinator.
public struct OnboardingStepID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Content and presentation metadata for one tutorial step.
struct OnboardingStepContent: Equatable {
    let id: OnboardingStepID
    let titleKey: String
    let messageKey: String
    let icon: String
    let tooltipAnchor: OnboardingTooltipAnchor
    let tooltipArrowPlacement: UnifiedBubbleWithArrowShape.ArrowPlacement
    let blocksCoCaptainPrompt: Bool
}
