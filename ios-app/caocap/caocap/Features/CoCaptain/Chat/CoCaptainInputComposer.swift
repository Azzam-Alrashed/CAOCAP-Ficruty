import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct CoCaptainInputComposer: View {
    @Binding var text: String
    @Binding var chatMode: CoCaptainChatMode
    @Binding var mentions: [CoCaptainNodeMention]
    @Binding var attachments: [CoCaptainAttachment]
    @FocusState.Binding var isFocused: Bool
    /// When false (node-scoped chat), inline cross-node @ suggestions are disabled.
    let allowsContextPinning: Bool
    let pinnableNodes: [SpatialNode]
    let isThinking: Bool
    let isConversationArchiveLoading: Bool
    let analysisItems: [ProjectSuggestion]
    let pendingReviewCount: Int
    let onSend: () -> Void
    let onStop: () -> Void
    let onFocusPendingReviews: () -> Void
    let onApplySuggestion: (ProjectSuggestion) -> Void
    let onDismissSuggestion: (ProjectSuggestion) -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("app.dictationLocale") private var dictationLocaleRawValue = DictationLocaleOption.auto.rawValue
    @State private var localModelManager = LocalGemmaModelManager.shared
    /// Dictation manager for streaming microphone input and converting it to query text.
    @State private var dictation = DictationController()
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isPhotoPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var attachmentError: String?
    @State private var isImportingAttachments = false
    @State private var lastAttachmentSource: AttachmentSource?

    private enum AttachmentSource {
        case photos
        case files
    }

    private var isInputValid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private var canSend: Bool {
        isInputValid
            && !isThinking
            && !isConversationArchiveLoading
            && !isImportingAttachments
    }

    /// Grows with wrapped/newline content; scrolls once the user exceeds this.
    private static let composerLineLimit = 1...6

    private var composerNewlineCount: Int {
        text.reduce(0) { partial, character in
            character.isNewline ? partial + 1 : partial
        }
    }

    /// Resolves the current user-selected or automatic dictation locale.
    private var dictationLocaleOption: DictationLocaleOption {
        DictationLocaleOption(rawValue: dictationLocaleRawValue) ?? .auto
    }

    var body: some View {
        VStack(spacing: 10) {
            if localModelManager.isDownloadingLocalModel {
                VStack(spacing: 6) {
                    HStack {
                        Label("Downloading Local Gemma 4 Model...", systemImage: "cpu")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                        Spacer()
                        Text("\(Int(localModelManager.localModelDownloadProgress * 100))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: localModelManager.localModelDownloadProgress)
                        .tint(.orange)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !analysisItems.isEmpty {
                CoCaptainAnalysisView(
                    suggestions: analysisItems,
                    onApply: onApplySuggestion,
                    onDismiss: onDismissSuggestion
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if pendingReviewCount > 0 {
                pendingReviewBanner
            }

            composerContent
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(.bar)
        .animation(.easeInOut(duration: 0.2), value: dictation.errorMessage)
        .onChange(of: dictation.transcript) { _, transcript in
            text = transcript
        }
        .onChange(of: text) { _, draft in
            mentions.removeAll { !draft.contains("@\($0.displayTitle)") }
        }
        .onDisappear {
            dictation.stop()
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: { result in
                Task { await importFiles(result) }
            }
        )
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotos,
            maxSelectionCount: 5,
            matching: .images
        )
        .onChange(of: selectedPhotos) { _, items in
            Task { await importPhotos(items) }
        }
    }

    @ViewBuilder
    private var attachmentErrorBanner: some View {
        if let attachmentError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .accessibilityHidden(true)
                Text(attachmentError)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let lastAttachmentSource {
                    Button(LocalizationManager.shared.localizedString("Choose again")) {
                        retryAttachmentSelection(from: lastAttachmentSource)
                    }
                    .font(.caption.weight(.semibold))
                }
                Button {
                    self.attachmentError = nil
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(
                    LocalizationManager.shared.localizedString("Dismiss error")
                )
            }
            .foregroundStyle(.red)
            .padding(.leading, CoCaptainChatStyle.compactSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var dictationErrorBanner: some View {
        if let errorMessage = dictation.errorMessage {
            Label(errorMessage, systemImage: "mic.slash")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, CoCaptainChatStyle.compactSpacing)
                .transition(.opacity)
        }
    }

    private var pendingReviewBanner: some View {
        Button {
            onFocusPendingReviews()
        } label: {
            HStack(spacing: CoCaptainChatStyle.smallSpacing) {
                Image(systemName: "tray.full.fill")
                    .foregroundStyle(CoCaptainChatStyle.pending)
                Text(
                    LocalizationManager.shared.localizedString(
                        "Review changes (%lld)",
                        arguments: [Int64(pendingReviewCount)]
                    )
                )
                .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, CoCaptainChatStyle.standardSpacing)
            .frame(minHeight: CoCaptainChatStyle.minimumHitSize)
            .coCaptainCardSurface(tint: CoCaptainChatStyle.pending)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, CoCaptainChatStyle.standardSpacing)
        .disabled(isThinking)
        .accessibilityHint(
            LocalizationManager.shared.localizedString(
                "Moves to the next change awaiting your review."
            )
        )
    }

    private func retryAttachmentSelection(from source: AttachmentSource) {
        attachmentError = nil
        switch source {
        case .photos:
            isPhotoPickerPresented = true
        case .files:
            isFileImporterPresented = true
        }
    }

    /// Secondary context stays above a compact, Messages-style input row.
    private var composerContent: some View {
        VStack(alignment: .leading, spacing: CoCaptainChatStyle.smallSpacing) {
            if !mentions.isEmpty { draftContextChips }
            if !attachments.isEmpty { attachmentPreview }
            if isImportingAttachments {
                HStack(spacing: CoCaptainChatStyle.smallSpacing) {
                    ProgressView()
                        .controlSize(.small)
                    Text(LocalizationManager.shared.localizedString("Preparing attachments"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)
            }
            attachmentErrorBanner
            dictationErrorBanner
            if !mentionSuggestions.isEmpty { mentionSuggestionList }
            composerInputRow
        }
        .animation(.easeInOut(duration: 0.2), value: chatMode)
        .animation(.easeInOut(duration: 0.2), value: mentions)
        .animation(.easeInOut(duration: 0.2), value: attachments)
    }

    private var composerInputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            attachmentMenu

            HStack(alignment: .bottom, spacing: 2) {
                composerTextField
                sendButton
            }
            .padding(.leading, 3)
            .padding(.trailing, 3)
            .padding(.vertical, 2)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 0.5)
            }

            Button(action: onSend) {
                EmptyView()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .disabled(!canSend)
            .accessibilityHidden(true)
        }
    }

    private var composerTextField: some View {
        TextField(chatMode.composerPlaceholder, text: $text, axis: .vertical)
            .lineLimit(Self.composerLineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .focused($isFocused)
            .submitLabel(.send)
            .accessibilityHint(
                LocalizationManager.shared.localizedString(
                    "Return sends. Shift-Return adds a new line."
                )
            )
            .onSubmit {
                if canSend {
                    onSend()
                }
            }
            .padding(.leading, 8)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
            .disabled(isConversationArchiveLoading || isImportingAttachments)
            .animation(.easeInOut(duration: 0.15), value: composerNewlineCount)
    }

    private var attachmentMenu: some View {
        Menu {
            Section {
                ForEach(CoCaptainChatMode.allCases) { mode in
                    Button {
                        chatMode = mode
                        HapticsManager.shared.selectionChanged()
                    } label: {
                        Label(
                            mode.displayName,
                            systemImage: mode == chatMode ? "checkmark" : mode.systemImageName
                        )
                    }
                }
            }

            Section {
                Button {
                    lastAttachmentSource = .photos
                    attachmentError = nil
                    isPhotoPickerPresented = true
                } label: {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }

                Button {
                    lastAttachmentSource = .files
                    attachmentError = nil
                    isFileImporterPresented = true
                } label: {
                    Label("Files", systemImage: "doc")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
                }
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(
            LocalizationManager.shared.localizedString("Add attachment")
        )
        .accessibilityValue(chatMode.displayName)
        .disabled(
            isThinking || isConversationArchiveLoading || isImportingAttachments
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                isFocused = false
            }
        )
    }

    private var activeMentionQuery: String? {
        guard allowsContextPinning,
              let atIndex = text.lastIndex(of: "@") else { return nil }
        let prefix = text[..<atIndex]
        if let last = prefix.last, !last.isWhitespace { return nil }
        let query = text[text.index(after: atIndex)...]
        guard !query.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        return String(query)
    }

    private var draftContextChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(mentions) { mention in
                    HStack(spacing: 5) {
                        Image(systemName: "scope")
                        Text(mention.displayTitle)
                            .lineLimit(1)
                        Button {
                            removeMention(mention)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            LocalizationManager.shared.localizedString(
                                "Remove %@ from context",
                                arguments: [mention.displayTitle]
                            )
                        )
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.blue)
                    .padding(.leading, 9)
                    .padding(.trailing, 3)
                    .frame(minHeight: 44)
                    .background(Color.blue.opacity(0.1), in: Capsule())
                }
            }
        }
    }

    private var mentionSuggestions: [SpatialNode] {
        guard let query = activeMentionQuery else { return [] }
        return pinnableNodes.filter {
            query.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(query)
        }.prefix(5).map { $0 }
    }

    private var mentionSuggestionList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(mentionSuggestions) { node in
                Button {
                    insertMention(node)
                } label: {
                    Label(node.displayTitle, systemImage: node.icon ?? node.type.defaultIcon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    LocalizationManager.shared.localizedString(
                        "Mention %@",
                        arguments: [node.displayTitle]
                    )
                )
            }
        }
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private var attachmentPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        HStack(spacing: 6) {
                            Image(systemName: attachment.isImage ? "photo" : "doc")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(attachment.fileName).lineLimit(1)
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(CoCaptainChatStyle.success)
                                    Text(LocalizationManager.shared.localizedString("Ready"))
                                    Text(verbatim: "·")
                                    Text(
                                        ByteCountFormatter.string(
                                            fromByteCount: Int64(attachment.data.count),
                                            countStyle: .file
                                        )
                                    )
                                }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                attachments.removeAll { $0.id == attachment.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                LocalizationManager.shared.localizedString(
                                    "Remove %@",
                                    arguments: [attachment.fileName]
                                )
                            )
                        }
                        .font(.caption)
                        .padding(.leading, 8)
                        .padding(.trailing, 3)
                        .padding(.vertical, 3)
                        .frame(minHeight: 44)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                    }
                }
            }
            Text(
                LocalizationManager.shared.localizedString(
                    "Up to 5 files, 10 MB each. Attachments require Gemini cloud."
                )
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.leading, 4)
        }
    }

    private func insertMention(_ node: SpatialNode) {
        guard let atIndex = text.lastIndex(of: "@") else { return }
        text.replaceSubrange(atIndex..<text.endIndex, with: "@\(node.displayTitle) ")
        if !mentions.contains(where: { $0.nodeID == node.id }) {
            mentions.append(CoCaptainNodeMention(nodeID: node.id, displayTitle: node.displayTitle))
        }
    }

    private func removeMention(_ mention: CoCaptainNodeMention) {
        mentions.removeAll { $0.id == mention.id }
        text = text.replacingOccurrences(
            of: "@\(mention.displayTitle)",
            with: ""
        )
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        text = text.trimmingCharacters(in: .whitespaces)
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        lastAttachmentSource = .photos
        attachmentError = nil
        isImportingAttachments = true
        defer {
            isImportingAttachments = false
            selectedPhotos = []
        }

        for item in items {
            guard attachments.count < 5 else {
                attachmentError = LocalizationManager.shared.localizedString(
                    "You can attach up to 5 files per message."
                )
                break
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                attachmentError = LocalizationManager.shared.localizedString(
                    "A selected photo couldn't be prepared. Choose it again."
                )
                continue
            }
            guard data.count <= 10 * 1_024 * 1_024 else {
                attachmentError = LocalizationManager.shared.localizedString(
                    "A selected photo is larger than 10 MB."
                )
                continue
            }
            let type = item.supportedContentTypes.first
            attachments.append(
                CoCaptainAttachment(
                    fileName: "Photo \(attachments.count + 1).\(type?.preferredFilenameExtension ?? "jpg")",
                    mimeType: type?.preferredMIMEType ?? "image/jpeg",
                    data: data
                )
            )
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) async {
        lastAttachmentSource = .files
        attachmentError = nil
        isImportingAttachments = true
        defer { isImportingAttachments = false }

        do {
            for url in try result.get() {
                guard attachments.count < 5 else {
                    attachmentError = LocalizationManager.shared.localizedString(
                        "You can attach up to 5 files per message."
                    )
                    break
                }
                let imported = try await Task.detached(priority: .userInitiated) {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
                    return (
                        data,
                        type?.preferredMIMEType ?? "application/octet-stream"
                    )
                }.value
                let data = imported.0
                guard data.count <= 10 * 1_024 * 1_024 else {
                    attachmentError = LocalizationManager.shared.localizedString(
                        "%@ is larger than 10 MB.",
                        arguments: [url.lastPathComponent]
                    )
                    continue
                }
                attachments.append(
                    CoCaptainAttachment(
                        fileName: url.lastPathComponent,
                        mimeType: imported.1,
                        data: data
                    )
                )
            }
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    private var sendButton: some View {
        Button(action: {
            if isConversationArchiveLoading || isImportingAttachments {
                return
            } else if isThinking {
                onStop()
            } else if dictation.isRecording {
                dictation.stop()
            } else if isInputValid {
                onSend()
            } else {
                isFocused = false
                Task {
                    await dictation.start(initialText: text, localeOption: dictationLocaleOption)
                }
            }
        }) {
            ZStack {
                Circle()
                    .fill(sendButtonBackground)
                    .frame(width: 30, height: 30)

                if isThinking {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                } else if dictation.isRecording {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .transition(.scale.combined(with: .opacity))
                } else if isInputValid {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 38, height: 40)
            .foregroundStyle(sendButtonForeground)
        }
        .accessibilityLabel(sendButtonAccessibilityLabel)
        .disabled(isConversationArchiveLoading || isImportingAttachments)
        .contextMenu {
            if !isInputValid || dictation.isRecording {
                dictationLocaleMenu
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
            value: isInputValid
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
            value: isThinking
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
            value: dictation.isRecording
        )
    }

    private var sendButtonBackground: Color {
        if isConversationArchiveLoading || isImportingAttachments {
            return Color.primary.opacity(0.05)
        }
        if dictation.isRecording {
            return .red.opacity(0.15)
        }
        if isThinking || isInputValid {
            return .blue
        }
        return Color.primary.opacity(0.08)
    }

    private var sendButtonForeground: Color {
        if dictation.isRecording {
            return .red
        }
        if isThinking || isInputValid {
            return .white
        }
        return .secondary
    }

    @ViewBuilder
    private var dictationLocaleMenu: some View {
        ForEach(DictationLocaleOption.allCases) { option in
            Button {
                if dictation.isRecording {
                    dictation.stop()
                }
                dictationLocaleRawValue = option.rawValue
            } label: {
                if option == dictationLocaleOption {
                    Label(option.displayName, systemImage: "checkmark")
                } else {
                    Label(option.displayName, systemImage: option.systemImageName)
                }
            }
        }
    }

    private var sendButtonAccessibilityLabel: String {
        if isConversationArchiveLoading {
            "Loading conversation"
        } else if isImportingAttachments {
            "Preparing attachments"
        } else if isThinking {
            "Stop CoCaptain"
        } else if dictation.isRecording {
            "Stop dictation"
        } else if isInputValid {
            "Send message"
        } else {
            "Start dictation"
        }
    }
}
