import SwiftUI
import UIKit

enum CoCaptainPresentationStyle {
    case legacySheet
    case session
}

struct CoCaptainView: View {
    @Bindable var viewModel: CoCaptainViewModel
    var onRequestExpandedPresentation: (() -> Void)?
    var presentationStyle: CoCaptainPresentationStyle = .legacySheet
    var sessionTitle: String?
    var focusComposerOnAppear = false
    var onOpenCanvas: (() -> Void)?
    @State private var text: String = ""
    @State private var mentions: [CoCaptainNodeMention] = []
    @State private var attachments: [CoCaptainAttachment] = []
    @State private var isConversationListPresented = false
    @FocusState private var isFocused: Bool
    @AppStorage(CoCaptainChatMode.storageKey) private var chatModeRawValue = CoCaptainChatMode.agent.rawValue
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var chatModeBinding: Binding<CoCaptainChatMode> {
        Binding(
            get: {
                CoCaptainChatMode(rawValue: chatModeRawValue) ?? .agent
            },
            set: { newValue in
                chatModeRawValue = newValue.rawValue
                viewModel.chatMode = newValue
            }
        )
    }

    var body: some View {
        Group {
            if presentationStyle == .legacySheet {
                NavigationStack { chatContent }
            } else {
                chatContent
            }
        }
        .sheet(isPresented: $isConversationListPresented) {
            CoCaptainConversationListView(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: isFocused) { _, isFocused in
            if isFocused {
                onRequestExpandedPresentation?()
            }
        }
        .onAppear {
            syncChatModeFromStorage()
            guard focusComposerOnAppear else { return }
            Task { @MainActor in
                await Task.yield()
                isFocused = true
            }
        }
        .onChange(of: chatModeRawValue) { _, _ in
            syncChatModeFromStorage()
        }
        .onChange(of: viewModel.composerDraftRequest) { _, draft in
            guard let draft else { return }
            text = draft.text
            mentions = draft.mentions
            attachments = draft.attachments
            viewModel.composerDraftRequest = nil
            isFocused = draft.shouldFocus
        }
        .onChange(of: viewModel.progressPhase) { oldPhase, newPhase in
            if let newPhase {
                announceForAccessibility(newPhase.localizedTitle)
            } else if oldPhase != nil {
                announceForAccessibility(
                    LocalizationManager.shared.localizedString(
                        "CoCaptain response ready."
                    )
                )
            }
        }
        .onChange(of: viewModel.pendingReviewCount) { oldCount, newCount in
            guard newCount > oldCount else { return }
            onRequestExpandedPresentation?()
            announceForAccessibility(
                LocalizationManager.shared.localizedString(
                    "Changes are ready for review."
                )
            )
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            CoCaptainTimelineListView(
                viewModel: viewModel,
                lastScrollPosition: $viewModel.lastScrollPosition,
                isFocused: $isFocused
            )

            CoCaptainInputComposer(
                text: $text,
                chatMode: chatModeBinding,
                mentions: $mentions,
                attachments: $attachments,
                isFocused: $isFocused,
                allowsContextPinning: true,
                pinnableNodes: viewModel.pinnableContextNodes,
                isThinking: viewModel.isThinking,
                isConversationArchiveLoading: viewModel.isConversationArchiveLoading,
                analysisItems: viewModel.analysisItems,
                pendingReviewCount: viewModel.pendingReviewCount,
                onSend: sendCurrentMessage,
                onStop: viewModel.stopStreaming,
                onFocusPendingReviews: {
                    onRequestExpandedPresentation?()
                    viewModel.focusPendingReviews()
                },
                onApplySuggestion: viewModel.applySuggestion,
                onDismissSuggestion: viewModel.dismissSuggestion
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentationStyle == .legacySheet {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isFocused = false
                        isConversationListPresented = true
                    } label: {
                        Image(
                            systemName: horizontalSizeClass == .regular
                                ? "sidebar.left"
                                : "bubble.left.and.bubble.right"
                        )
                            .overlay(alignment: .topTrailing) {
                                if viewModel.pendingReviewCount > 0 {
                                    Text("\(viewModel.pendingReviewCount)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(3)
                                        .background(Color.orange, in: Circle())
                                        .offset(x: 7, y: -7)
                                }
                            }
                    }
                    .accessibilityLabel(
                        LocalizationManager.shared.localizedString("Open conversations")
                    )
                }

                ToolbarItem(placement: .principal) {
                    Button {
                        isFocused = false
                        isConversationListPresented = true
                    } label: {
                        HStack(spacing: 6) {
                            VStack(spacing: 1) {
                                Text(viewModel.activeConversationTitle)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("CoCaptain")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }

                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        LocalizationManager.shared.localizedString(
                            "Open conversations"
                        )
                    )
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        isFocused = false
                        viewModel.createConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(viewModel.isThinking || viewModel.isConversationArchiveLoading)
                    .accessibilityLabel(
                        LocalizationManager.shared.localizedString("New conversation")
                    )
                }
            } else {
                ToolbarItem(placement: .principal) {
                    Text(sessionTitle ?? viewModel.activeConversationTitle)
                        .font(.headline)
                        .lineLimit(1)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isFocused = false
                        onOpenCanvas?()
                    } label: {
                        Image(systemName: "square.on.square")
                    }
                    .accessibilityLabel("Open canvas")
                }
            }
        }
    }

    /// Keeps the view model aligned with the persisted composer mode.
    private func syncChatModeFromStorage() {
        viewModel.chatMode = CoCaptainChatMode(rawValue: chatModeRawValue) ?? .agent
    }

    private func announceForAccessibility(_ message: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func sendCurrentMessage() {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!prompt.isEmpty || !attachments.isEmpty), !viewModel.isThinking else { return }
        let submittedPrompt = prompt.isEmpty ? "Review the attached files." : prompt

        guard viewModel.sendMessage(
            submittedPrompt,
            mentions: mentions,
            attachments: attachments,
            purpose: .standard
        ) else { return }
        HapticsManager.shared.trigger(.soft)
        text = ""
        mentions = []
        attachments = []
        isFocused = false
    }
}

#Preview {
    CoCaptainView(viewModel: CoCaptainViewModel())
}
