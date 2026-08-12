import Foundation
import Observation

/// Reusable, content-driven tutorial coordinator. The production catalog is empty
/// until the pivot defines its new lessons.
@MainActor
@Observable
public final class OnboardingCoordinator {
    public typealias Step = OnboardingStepID

    public var currentStep: Step?
    public var activeLessonID: OnboardingLessonID?
    public var showPopover = false

    @ObservationIgnored private var popoverTask: Task<Void, Never>?
    @ObservationIgnored private var advancesThroughLessons = false
    @ObservationIgnored public var onLessonWillStart: ((OnboardingLessonID) -> Void)?
    @ObservationIgnored public var onTutorialCompleted: (() -> Void)?
    @ObservationIgnored private let analytics: any AnalyticsTracking
    @ObservationIgnored private let catalog: OnboardingCatalog

    private static let completedKey = "onboarding_completed"
    private static let lessonCompletedKeyPrefix = "onboarding_lesson_completed_"

    public var isCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: Self.completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.completedKey) }
    }

    public var completedLessonIDs: Set<OnboardingLessonID> {
        Set(catalog.lessons.map(\.id).filter {
            UserDefaults.standard.bool(forKey: Self.lessonCompletionKey(for: $0))
        })
    }

    public convenience init() {
        self.init(catalog: .empty, analytics: AnalyticsService.shared)
    }

    init(catalog: OnboardingCatalog, analytics: any AnalyticsTracking) {
        self.catalog = catalog
        self.analytics = analytics
    }

    public func isLessonCompleted(_ lessonID: OnboardingLessonID) -> Bool {
        completedLessonIDs.contains(lessonID)
    }

    /// An empty catalog is deliberately dormant and produces no side effects.
    public func startIfNeeded() {
        guard !catalog.mainLessonIDs.isEmpty, !isCompleted else { return }
        guard let lessonID = catalog.firstIncompleteLesson(completedLessonIDs: completedLessonIDs) else {
            markComplete()
            return
        }
        startLesson(lessonID, advancesThroughLessons: true)
    }

    public func startLesson(_ lessonID: OnboardingLessonID, advancesThroughLessons: Bool) {
        guard let lesson = catalog.lesson(for: lessonID), let firstStep = lesson.steps.first else { return }
        onLessonWillStart?(lessonID)
        log(OnboardingAnalytics.lessonStarted, lessonID: lessonID)
        self.advancesThroughLessons = advancesThroughLessons
        activeLessonID = lessonID
        currentStep = firstStep
        schedulePopover(after: 1.5)
    }

    public func completeCurrentStep() {
        guard let step = currentStep,
              let lessonID = activeLessonID,
              let lesson = catalog.lesson(for: lessonID) else { return }
        showPopover = false
        analytics.logEvent(OnboardingAnalytics.stepCompleted, parameters: [
            OnboardingAnalytics.lessonID: lessonID.rawValue,
            OnboardingAnalytics.stepID: step.rawValue
        ])

        if let next = catalog.nextStep(after: step, in: lesson) {
            currentStep = next
            schedulePopover(after: 0.8)
            return
        }

        markLessonComplete(lessonID)
        log(OnboardingAnalytics.lessonCompleted, lessonID: lessonID)
        finishLesson(lessonID)
    }

    public func hidePopoverForCurrentStep() {
        popoverTask?.cancel()
        showPopover = false
    }

    public func skip() {
        popoverTask?.cancel()
        showPopover = false
        guard let lessonID = activeLessonID else { return }
        log(OnboardingAnalytics.lessonSkipped, lessonID: lessonID)
        markLessonComplete(lessonID)
        finishLesson(lessonID)
    }

    public func reset() {
        UserDefaults.standard.removeObject(forKey: Self.completedKey)
        for lesson in catalog.lessons {
            UserDefaults.standard.removeObject(forKey: Self.lessonCompletionKey(for: lesson.id))
        }
        activeLessonID = nil
        currentStep = nil
        showPopover = false
        advancesThroughLessons = false
        popoverTask?.cancel()
    }

    func lesson(for id: OnboardingLessonID) -> OnboardingLesson? { catalog.lesson(for: id) }
    func content(for step: Step) -> OnboardingStepContent? { catalog.content(for: step) }

    private func finishLesson(_ lessonID: OnboardingLessonID) {
        if advancesThroughLessons,
           let next = catalog.nextMainLesson(after: lessonID),
           !isLessonCompleted(next) {
            startLesson(next, advancesThroughLessons: true)
        } else if catalog.mainLessonIDs.allSatisfy({ isLessonCompleted($0) }) {
            markComplete()
        } else {
            activeLessonID = nil
            currentStep = nil
            advancesThroughLessons = false
        }
    }

    private func schedulePopover(after delay: TimeInterval) {
        popoverTask?.cancel()
        popoverTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            showPopover = true
        }
    }

    private func markLessonComplete(_ id: OnboardingLessonID) {
        UserDefaults.standard.set(true, forKey: Self.lessonCompletionKey(for: id))
    }

    private func markComplete() {
        popoverTask?.cancel()
        activeLessonID = nil
        currentStep = nil
        advancesThroughLessons = false
        isCompleted = true
        onTutorialCompleted?()
    }

    private func log(_ event: String, lessonID: OnboardingLessonID) {
        analytics.logEvent(event, parameters: [OnboardingAnalytics.lessonID: lessonID.rawValue])
    }

    private static func lessonCompletionKey(for id: OnboardingLessonID) -> String {
        lessonCompletedKeyPrefix + id.rawValue
    }
}
