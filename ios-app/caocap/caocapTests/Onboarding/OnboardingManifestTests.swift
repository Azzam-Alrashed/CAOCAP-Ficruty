import Testing
@testable import caocap

@MainActor
struct OnboardingManifestTests {
    private let lessonID = OnboardingLessonID(rawValue: "fixture.lesson")
    private let firstStep = OnboardingStepID(rawValue: "fixture.first")
    private let secondStep = OnboardingStepID(rawValue: "fixture.second")

    @Test func productionCatalogIsDormant() {
        let onboarding = OnboardingCoordinator(catalog: .empty, analytics: NoOpAnalyticsService())
        onboarding.reset()

        onboarding.startIfNeeded()

        #expect(OnboardingLessonsManifest.lessons.isEmpty)
        #expect(OnboardingLessonsManifest.mainLessonIDs.isEmpty)
        #expect(onboarding.currentStep == nil)
        #expect(onboarding.activeLessonID == nil)
        #expect(!onboarding.showPopover)
        #expect(!onboarding.isCompleted)
    }

    @Test func injectedCatalogAdvancesAndCompletes() {
        let onboarding = makeFixtureCoordinator()
        onboarding.reset()
        var completed = false
        onboarding.onTutorialCompleted = { completed = true }

        onboarding.startIfNeeded()
        #expect(onboarding.currentStep == firstStep)

        onboarding.completeCurrentStep()
        #expect(onboarding.currentStep == secondStep)

        onboarding.completeCurrentStep()
        #expect(onboarding.currentStep == nil)
        #expect(onboarding.isLessonCompleted(lessonID))
        #expect(onboarding.isCompleted)
        #expect(completed)
    }

    @Test func injectedCatalogCanSkip() {
        let onboarding = makeFixtureCoordinator()
        onboarding.reset()
        onboarding.startIfNeeded()

        onboarding.skip()

        #expect(onboarding.currentStep == nil)
        #expect(onboarding.isLessonCompleted(lessonID))
        #expect(onboarding.isCompleted)
    }

    private func makeFixtureCoordinator() -> OnboardingCoordinator {
        let lesson = OnboardingLesson(
            id: lessonID,
            titleKey: "fixture.lesson.title",
            subtitleKey: "fixture.lesson.subtitle",
            icon: "sparkles",
            accentHex: "00B894",
            steps: [firstStep, secondStep]
        )
        let content = [firstStep, secondStep].map {
            OnboardingStepContent(
                id: $0,
                titleKey: "fixture.step.title",
                messageKey: "fixture.step.message",
                icon: "arrow.right.circle.fill",
                tooltipAnchor: .canvas,
                tooltipArrowPlacement: .bottom,
                blocksCoCaptainPrompt: false
            )
        }
        return OnboardingCoordinator(
            catalog: OnboardingCatalog(
                mainLessonIDs: [lessonID],
                lessons: [lesson],
                stepContent: Dictionary(uniqueKeysWithValues: content.map { ($0.id, $0) })
            ),
            analytics: NoOpAnalyticsService()
        )
    }
}
