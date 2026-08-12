import SwiftUI

/// Stable identifier for a reusable tutorial lesson.
public struct OnboardingLessonID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct OnboardingLesson: Identifiable, Hashable {
    let id: OnboardingLessonID
    let titleKey: String
    let subtitleKey: String
    let icon: String
    let accentHex: String
    let steps: [OnboardingStepID]

    var accentColor: Color { Color(hex: accentHex) }
}

/// Injectable tutorial content. Production intentionally ships with no lessons
/// until the pivot's new onboarding journey is defined.
struct OnboardingCatalog {
    let mainLessonIDs: [OnboardingLessonID]
    let lessons: [OnboardingLesson]
    let stepContent: [OnboardingStepID: OnboardingStepContent]

    static let empty = OnboardingCatalog(
        mainLessonIDs: [],
        lessons: [],
        stepContent: [:]
    )

    func lesson(for id: OnboardingLessonID) -> OnboardingLesson? {
        lessons.first { $0.id == id }
    }

    func content(for id: OnboardingStepID) -> OnboardingStepContent? {
        stepContent[id]
    }

    func firstIncompleteLesson(completedLessonIDs: Set<OnboardingLessonID>) -> OnboardingLessonID? {
        mainLessonIDs.first { !completedLessonIDs.contains($0) }
    }

    func nextMainLesson(after id: OnboardingLessonID) -> OnboardingLessonID? {
        guard let index = mainLessonIDs.firstIndex(of: id) else { return nil }
        let nextIndex = mainLessonIDs.index(after: index)
        return mainLessonIDs.indices.contains(nextIndex) ? mainLessonIDs[nextIndex] : nil
    }

    func nextStep(after step: OnboardingStepID, in lesson: OnboardingLesson) -> OnboardingStepID? {
        guard let index = lesson.steps.firstIndex(of: step) else { return nil }
        let nextIndex = lesson.steps.index(after: index)
        return lesson.steps.indices.contains(nextIndex) ? lesson.steps[nextIndex] : nil
    }
}

enum OnboardingLessonsManifest {
    static let catalog = OnboardingCatalog.empty
    static var mainLessonIDs: [OnboardingLessonID] { catalog.mainLessonIDs }
    static var lessons: [OnboardingLesson] { catalog.lessons }
}
