import SwiftUI

/// Spotlight-style command surface. Rendering stays here while filtering,
/// selection, and execution callbacks live in `CommandPaletteViewModel`.
struct CommandPaletteView: View {
    @Bindable var viewModel: CommandPaletteViewModel
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    @AppStorage("app.dictationLocale") private var dictationLocaleRawValue = DictationLocaleOption.auto.rawValue
    /// When `true` (default), the results card lists options as soon as the omnibox opens.
    /// When `false`, options appear only after the user starts typing.
    @AppStorage("omnibox.showOptionsWhenEmpty") private var showOptionsWhenEmpty = false
    @State private var dictation = DictationController()
    
    private var dictationLocaleOption: DictationLocaleOption {
        DictationLocaleOption(rawValue: dictationLocaleRawValue) ?? .auto
    }
    
    struct ActionCategorySection {
        let category: AppActionCategory
        let title: String
        let items: [(index: Int, action: AppActionDefinition)]
    }

    var sections: [ActionCategorySection] {
        let actions = viewModel.filteredActions
        let categories: [(AppActionCategory, String)] = [
            (.navigation, "NAVIGATION"),
            (.project, "PROJECT"),
            (.assistant, "ASSISTANT")
        ]
        return categories.compactMap { cat, name in
            let filtered = actions.enumerated().filter { $0.element.category == cat }
            guard !filtered.isEmpty else { return nil }
            return ActionCategorySection(
                category: cat,
                title: name,
                items: filtered.map { ($0.offset, $0.element) }
            )
        }
    }

    var body: some View {
        ZStack {
            if viewModel.isPresented {
                // Backdrop
                Color.black.opacity(viewModel.mode == .actionsList ? 0.4 : 0.2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isFocused = false
                        viewModel.setPresented(false)
                    }
                    .transition(.opacity)
                
                if viewModel.mode == .actionsList {
                    // --- MODE 2: Original Spotlight Modal (Actions List) ---
                    VStack(spacing: 0) {
                        // Search Bar
                        HStack {
                            let currentCopilot = UserProfileStore().loadSelectedCopilot()
                            Image(currentCopilot.avatarImageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                                .clipShape(Circle())
                            
                            TextField("Ask \(currentCopilot.displayName) or type a command...", text: $viewModel.query)
                                .textFieldStyle(.plain)
                                .focused($isFocused)
                                .font(.system(size: 15, weight: .medium))
                                .frame(height: 24)
                                .submitLabel(.done)
                                .onSubmit {
                                    viewModel.confirmSelection()
                                }
                                .onKeyPress { press in
                                    if press.key == .upArrow {
                                        viewModel.moveSelection(direction: .up)
                                        return .handled
                                    } else if press.key == .downArrow {
                                        viewModel.moveSelection(direction: .down)
                                        return .handled
                                    }
                                    return .ignored
                                }

                            if dictation.isRecording || viewModel.query.isEmpty {
                                omniboxMicButton
                            } else {
                                clearQueryButton
                                    .font(.system(size: 18))
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        )

                        dictationErrorView
                        
                        Divider()
                            .background(Color.white.opacity(0.1))
                        
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 4) {
                                    if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        ForEach(sections, id: \.category) { section in
                                            Section(header:
                                                HStack {
                                                    Text(section.title)
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(.blue.opacity(0.8))
                                                    Spacer()
                                                }
                                                .padding(.horizontal, 16)
                                                .padding(.top, 12)
                                                .padding(.bottom, 4)
                                            ) {
                                                ForEach(section.items, id: \.action.id) { index, action in
                                                    AppActionRow(
                                                        item: action,
                                                        isSelected: index == viewModel.selectedIndex,
                                                        onSelect: { viewModel.executeAction(action) }
                                                    )
                                                    .id(action.id.rawValue)
                                                }
                                            }
                                        }
                                    } else {
                                        OmniboxSearchResultsView(
                                            viewModel: viewModel
                                        )
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .frame(maxHeight: 400)
                            .interactiveKeyboardDismiss()
                            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                                OmniboxSearchResultsView.scrollToSelection(
                                    newIndex: newIndex,
                                    viewModel: viewModel,
                                    proxy: proxy
                                )
                            }
                        }
                        
                        // Footer hint
                        HStack {
                            Text("Use arrows to navigate, Enter to select")
                                .font(.system(size: 10, weight: .light))
                                .opacity(0.5)
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.05))
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .shadow(color: Color.blue.opacity(colorScheme == .dark ? 0.15 : 0.05), radius: 20)
                    )
                    .frame(width: min(500, UIScreen.main.bounds.width - 40))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.25 : 0.4),
                                        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.1),
                                        Color.blue.opacity(colorScheme == .dark ? 0.2 : 0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                    .onAppear {
                        GlobalFloatingChromeController.makeMainAppWindowKey()
                        isFocused = true
                    }
                } else {
                    // --- MODE 1: iOS Search Bar Capsule (at Bottom) ---
                    VStack(spacing: 8) {
                        Spacer()
                        
                        // Floating Results Card — default: show options immediately; Settings can require typing first.
                        let hasPreviewTools = viewModel.previewToolCount > 0
                        let hasResults = !viewModel.filteredActions.isEmpty
                            || !viewModel.nodeResults.isEmpty
                            || !viewModel.nodeCreationResults.isEmpty
                            || viewModel.canSubmitPrompt
                        let trimmedQuery = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                        let showCard = hasPreviewTools
                            || (hasResults && (showOptionsWhenEmpty || !trimmedQuery.isEmpty))
                        
                        if showCard {
                            VStack(spacing: 0) {
                                ScrollViewReader { proxy in
                                    ScrollView {
                                        LazyVStack(spacing: 4) {
                                            OmniboxSearchResultsView(
                                                viewModel: viewModel
                                            )
                                        }
                                        .padding(.top, 12)
                                        .padding(.bottom, 8)
                                    }
                                    .frame(maxHeight: 250)
                                    .interactiveKeyboardDismiss()
                                    .onChange(of: viewModel.selectedIndex) { _, newIndex in
                                        OmniboxSearchResultsView.scrollToSelection(
                                            newIndex: newIndex,
                                            viewModel: viewModel,
                                            proxy: proxy
                                        )
                                    }
                                }
                            }
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(colorScheme == .dark ? 0.2 : 0.35),
                                                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: .black.opacity(0.3), radius: 15, y: 5)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.95).combined(with: .opacity),
                                removal: .scale(scale: 0.95).combined(with: .opacity)
                            ))
                        }
                        
                        // Search Bar Capsule (styled like iOS native search bar)
                        HStack(spacing: 12) {
                            let currentCopilot = UserProfileStore().loadSelectedCopilot()
                            Image(systemName: "command")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            TextField("Ask \(currentCopilot.displayName) or type a command...", text: $viewModel.query)
                                .textFieldStyle(.plain)
                                .focused($isFocused)
                                .font(.system(size: 15, weight: .medium))
                                .frame(height: 24)
                                .submitLabel(.done)
                                .onSubmit {
                                    viewModel.confirmSelection()
                                }
                                .onKeyPress { press in
                                    if press.key == .upArrow {
                                        viewModel.moveSelection(direction: .up)
                                        return .handled
                                    } else if press.key == .downArrow {
                                        viewModel.moveSelection(direction: .down)
                                        return .handled
                                    }
                                    return .ignored
                                }
                            
                            if dictation.isRecording || viewModel.query.isEmpty {
                                omniboxMicButton
                            } else {
                                clearQueryButton
                                    .font(.system(size: 18))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(colorScheme == .dark ? 0.2 : 0.35),
                                            Color.white.opacity(colorScheme == .dark ? 0.05 : 0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )

                        dictationErrorView
                    }
                    .frame(width: min(500, UIScreen.main.bounds.width - 32))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .onAppear {
                        GlobalFloatingChromeController.makeMainAppWindowKey()
                        isFocused = true
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isPresented)
        .animation(.easeInOut(duration: 0.2), value: dictation.errorMessage)
        .onChange(of: dictation.transcript) { _, transcript in
            viewModel.query = transcript
        }
        .onChange(of: viewModel.isPresented) { oldPresented, newPresented in
            if newPresented {
                Task { @MainActor in
                    GlobalFloatingChromeController.makeMainAppWindowKey()
                    try? await Task.sleep(for: .seconds(0.1))
                    GlobalFloatingChromeController.makeMainAppWindowKey()
                    isFocused = true
                }
            } else {
                dictation.stop()
            }
        }
        .onDisappear {
            dictation.stop()
        }
    }

    /// A button that clears the current query text in the Omnibox.
    private var clearQueryButton: some View {
        Button {
            viewModel.query = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear Omnibox query")
    }

    /// A button that toggles speech dictation (recording/stopping) for the Omnibox query.
    private var omniboxMicButton: some View {
        Button {
            if dictation.isRecording {
                dictation.stop()
            } else {
                // Remove focus from the keyboard search bar to avoid conflict with dictation input
                isFocused = false
                Task {
                    await dictation.start(
                        initialText: viewModel.query,
                        localeOption: dictationLocaleOption
                    )
                }
            }
        } label: {
            Image(systemName: dictation.isRecording ? "mic.circle.fill" : "mic.fill")
                .font(.system(size: dictation.isRecording ? 22 : 18))
                .foregroundColor(dictation.isRecording ? .red : .secondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Start dictation")
        .contextMenu {
            dictationLocaleMenu
        }
    }

    /// A context menu view listing the available localization languages for speech recognition.
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

    /// A label displaying dictation error messages when permissions are missing or service is unavailable.
    @ViewBuilder
    private var dictationErrorView: some View {
        if let errorMessage = dictation.errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.opacity)
        }
    }
}

// MARK: - Row Styling Modifier

struct OmniboxRowModifier: ViewModifier {
    let isSelected: Bool
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    if isSelected {
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.15),
                                Color.blue.opacity(0.08)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else if isHovered {
                        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.03)
                    }
                }
            )
            .scaleEffect(isSelected ? 1.015 : (isHovered ? 1.005 : 1.0))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? Color.blue.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
                    .shadow(color: Color.blue.opacity(0.3), radius: isSelected ? 4 : 0)
            )
            .cornerRadius(8)
            .padding(.horizontal, 8)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isSelected)
    }
}

extension View {
    func omniboxRowStyle(isSelected: Bool) -> some View {
        self.modifier(OmniboxRowModifier(isSelected: isSelected))
    }
}

// MARK: - Search Results

private struct OmniboxSearchResultsView: View {
    @Bindable var viewModel: CommandPaletteViewModel

    var body: some View {
        let actions = viewModel.filteredActions
        let prioritizedCount = viewModel.prioritizedNavigationActionCount
        let previewTools = viewModel.filteredPreviewTools

        if !previewTools.isEmpty {
            sectionHeader("MINI-APP")

            ForEach(Array(previewTools.enumerated()), id: \.element.id) { index, tool in
                MiniAppPreviewToolRow(
                    tool: tool,
                    isSelected: viewModel.selectionIndex(forPreviewToolAt: index) == viewModel.selectedIndex
                ) {
                    viewModel.selectPreviewTool(tool)
                }
                .id("preview-tool-\(tool.id)")
            }
        }

        ForEach(Array(actions.prefix(prioritizedCount).enumerated()), id: \.element.id) { index, action in
            actionRow(action, at: index)
        }

        if !viewModel.nodeResults.isEmpty {
            sectionHeader("CANVAS NODES")

            ForEach(Array(viewModel.nodeResults.enumerated()), id: \.element.id) { index, nodeResult in
                NodeSearchResultRow(
                    result: nodeResult,
                    isSelected: viewModel.selectionIndex(forNodeResultAt: index) == viewModel.selectedIndex
                ) {
                    viewModel.flyToNode(nodeResult)
                }
                .id(nodeResult.id.uuidString)
            }
        }

        ForEach(Array(actions.dropFirst(prioritizedCount).enumerated()), id: \.element.id) { offset, action in
            actionRow(action, at: prioritizedCount + offset)
        }

        if !viewModel.nodeCreationResults.isEmpty {
            sectionHeader("CREATE NODE")

            ForEach(Array(viewModel.nodeCreationResults.enumerated()), id: \.element.id) { index, option in
                NodeCreationOptionRow(
                    option: option,
                    isSelected: viewModel.selectionIndex(forNodeCreationResultAt: index) == viewModel.selectedIndex
                ) {
                    viewModel.createNode(option)
                }
                .id("create-\(option.id.rawValue)")
            }
        }

        if viewModel.canSubmitPrompt {
            CoCaptainPromptRow(
                prompt: viewModel.query,
                isSelected: viewModel.selectedIndex == viewModel.promptSelectionIndex
            ) {
                viewModel.submitPromptIfNeeded()
            }
            .id("cocaptain-prompt")
        }
    }

    private func actionRow(_ action: AppActionDefinition, at index: Int) -> some View {
        AppActionRow(
            item: action,
            isSelected: viewModel.selectionIndex(forActionAt: index) == viewModel.selectedIndex,
            onSelect: { viewModel.executeAction(action) }
        )
        .id(action.id.rawValue)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .opacity(0.4)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    static func scrollToSelection(
        newIndex: Int,
        viewModel: CommandPaletteViewModel,
        proxy: ScrollViewProxy
    ) {
        let nodeResults = viewModel.nodeResults
        let nodeCreationResults = viewModel.nodeCreationResults
        let actions = viewModel.filteredActions
        let prioritizedCount = viewModel.prioritizedNavigationActionCount
        let previewCount = viewModel.previewToolCount
        let nodeStartIndex = previewCount + prioritizedCount
        let remainingActionsStartIndex = previewCount + prioritizedCount + nodeResults.count
        let nodeCreationStartIndex = previewCount + nodeResults.count + actions.count

        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            if newIndex >= 0 && newIndex < previewCount {
                proxy.scrollTo("preview-tool-\(viewModel.filteredPreviewTools[newIndex].id)", anchor: .center)
            } else if newIndex >= previewCount && newIndex < previewCount + prioritizedCount {
                proxy.scrollTo(actions[newIndex - previewCount].id.rawValue, anchor: .center)
            } else if newIndex >= nodeStartIndex && newIndex < remainingActionsStartIndex {
                proxy.scrollTo(nodeResults[newIndex - nodeStartIndex].id.uuidString, anchor: .center)
            } else if newIndex >= remainingActionsStartIndex && newIndex < nodeCreationStartIndex {
                let actionIndex = prioritizedCount + newIndex - remainingActionsStartIndex
                let action = actions[actionIndex]
                proxy.scrollTo(action.id.rawValue, anchor: .center)
            } else if newIndex >= nodeCreationStartIndex
                        && newIndex < (nodeCreationStartIndex + nodeCreationResults.count) {
                let option = nodeCreationResults[newIndex - nodeCreationStartIndex]
                proxy.scrollTo("create-\(option.id.rawValue)", anchor: .center)
            } else if viewModel.canSubmitPrompt && newIndex == viewModel.promptSelectionIndex {
                proxy.scrollTo("cocaptain-prompt", anchor: .center)
            }
        }
    }
}

// MARK: - Row Component Views

private struct MiniAppPreviewToolRow: View {
    let tool: MiniAppPreviewTool
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: tool.icon)
                    .font(.system(size: 16))
                    .frame(width: 24)

                Text(tool.title)
                    .font(.system(size: 16))

                Spacer()

                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 12))
                        .opacity(0.8)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .omniboxRowStyle(isSelected: isSelected)
    }
}

struct AppActionRow: View {
    let item: AppActionDefinition
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: item.icon)
                        .font(.system(size: 16))
                        .frame(width: 24)
                    
                    Text(item.localizedTitle)
                        .font(.system(size: 16))
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "return")
                            .font(.system(size: 12))
                            .opacity(0.8)
                            .foregroundColor(.blue)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        }
        .omniboxRowStyle(isSelected: isSelected)
    }
}

struct CoCaptainPromptRow: View {
    let prompt: String
    let isSelected: Bool
    let onSelect: () -> Void

    private var currentCopilot: CopilotPersona {
        UserProfileStore().loadSelectedCopilot()
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(currentCopilot.avatarImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask \(currentCopilot.displayName)")
                        .font(.system(size: 16, weight: .medium))

                    Text(trimmedPrompt)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(0.65)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 12))
                        .opacity(0.8)
                        .foregroundColor(Color(hex: currentCopilot.accentHex))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .omniboxRowStyle(isSelected: isSelected)
    }
}

struct NodeCreationOptionRow: View {
    let option: NodeCreationOption
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: option.icon)
                    .font(.system(size: 16))
                    .frame(width: 24)
                    .foregroundColor(.blue)

                Text(option.title)
                    .font(.system(size: 16, weight: .medium))

                Spacer()

                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 12))
                        .opacity(0.8)
                        .foregroundColor(.blue)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .omniboxRowStyle(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct NodeSearchResultRow: View {
    let result: NodeSearchResult
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: result.role.icon)
                    .font(.system(size: 16))
                    .frame(width: 24)
                    .foregroundColor(result.role.themeColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.system(size: 16, weight: .medium))
                    
                    if !result.snippet.isEmpty {
                        Text(result.snippet)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .opacity(0.6)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 12))
                        .opacity(0.8)
                        .foregroundColor(.blue)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .omniboxRowStyle(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
