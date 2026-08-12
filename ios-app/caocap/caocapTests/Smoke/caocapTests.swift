//
//  caocapTests.swift
//  caocapTests
//
//  Created by الشيخ عزام on 20/04/2026.
//

import CoreGraphics
import Foundation
import Testing
@testable import caocap

struct caocapTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func introCatalogResolvesArabic() {
        let title = LocalizationManager.shared.localizedString("intro.step0.title", language: "Arabic")
        #expect(title == "العد التنازلي للإطلاق.")

        let message = LocalizationManager.shared.localizedString("intro.step0.message", language: "Arabic")
        #expect(message.contains("كل مهمة"))
    }

    @Test func viewportDragTranslationUsesPhysicalDirections() {
        let viewport = ViewportState(offset: CGSize(width: 10, height: -20), scale: 1.0)

        viewport.handleDragTranslation(CGSize(width: 35, height: -15))
        #expect(viewport.offset == CGSize(width: 45, height: -35))

        viewport.handleDragEnded()
        viewport.handleDragTranslation(CGSize(width: -25, height: 40))
        #expect(viewport.offset == CGSize(width: 20, height: 5))
    }

    @Test func viewportDragEndedCommitsOffsetForNextGesture() {
        let viewport = ViewportState(offset: .zero, scale: 1.0)

        viewport.handleDragTranslation(CGSize(width: 50, height: 12))
        viewport.handleDragEnded()
        viewport.handleDragTranslation(CGSize(width: 10, height: -2))

        #expect(viewport.offset == CGSize(width: 60, height: 10))
        #expect(viewport.lastOffset == CGSize(width: 50, height: 12))
    }

    @Test func defaultProjectStartsWithCleanCanvas() {
        #expect(ProjectTemplateProvider.defaultNodes.isEmpty)
    }

    @Test func defaultMiniAppCodeIsEmptyPlaceholder() {
        #expect(ProjectTemplateProvider.defaultCode.isEmpty)
    }

    @MainActor
    @Test func onboardingCoordinatorResetAndStart() async throws {
        let onboarding = OnboardingCoordinator()
        onboarding.isCompleted = true
        #expect(onboarding.isCompleted)
        
        onboarding.reset()
        #expect(!onboarding.isCompleted)
        #expect(onboarding.currentStep == nil)
        
        onboarding.startIfNeeded()
        #expect(onboarding.currentStep == nil)
        #expect(!onboarding.showPopover)
    }

    @MainActor
    @Test func llmServiceLocalStreamingRequiresDownloadedLiteRTModel() async throws {
        guard LocalModelDeviceEligibility.current.isSupported else { return }

        let originalModelName = UserDefaults.standard.string(forKey: "cocaptain.modelName")
        UserDefaults.standard.set(
            CoCaptainModelSelectionPolicy.localModelName,
            forKey: "cocaptain.modelName"
        )
        defer { UserDefaults.standard.set(originalModelName, forKey: "cocaptain.modelName") }
        
        let llmService = LLMService.shared
        
        let events = llmService.streamAgentEvents(for: "test", context: nil, expectsStructuredResponse: false, availableActions: [])
        
        var threwExpectedError = false
        do {
            for try await _ in events {
                // Expect an error because the LiteRT model fixture is not installed.
            }
        } catch {
            let errorDescription = error.localizedDescription
            if errorDescription.contains("Download Gemma 4") || errorDescription.contains("not ready") {
                threwExpectedError = true
            }
        }
        
        #expect(threwExpectedError)
    }
}
