import SwiftUI

/// A terminal-like command surface for local app commands and CoPilot requests.
struct CommandPaletteView: View {
    @Bindable var viewModel: CommandPaletteViewModel
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("app.dictationLocale") private var dictationLocaleRawValue = DictationLocaleOption.auto.rawValue
    @State private var dictation = DictationController()

    private var dictationLocaleOption: DictationLocaleOption {
        DictationLocaleOption(rawValue: dictationLocaleRawValue) ?? .auto
    }

    var body: some View {
        ZStack {
            if viewModel.isPresented {
                Rectangle()
                    .fill(Color.black.opacity(0.2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.all, edges: .all)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isFocused = false
                        viewModel.setPresented(false)
                    }
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
                    .zIndex(0)

                VStack(spacing: 8) {
                    Spacer()

                    HStack(spacing: 12) {
                        Image(systemName: "command")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        TextField("Type a command...", text: $viewModel.query)
                            .textFieldStyle(.plain)
                            .focused($isFocused)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .frame(height: 24)
                            .submitLabel(.done)
                            .onSubmit {
                                viewModel.submit()
                            }

                        if dictation.isRecording || viewModel.query.isEmpty {
                            commandLineMicButton
                        } else {
                            clearQueryButton
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
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
                .frame(maxWidth: 500)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.asymmetric(
                    insertion: .offset(y: 12).combined(with: .opacity),
                    removal: .offset(y: 6).combined(with: .opacity)
                ))
                .zIndex(1)
                .onAppear {
                    GlobalFloatingChromeController.makeMainAppWindowKey()
                    Task { @MainActor in
                        await Task.yield()
                        isFocused = true
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.16), value: viewModel.isPresented)
        .animation(.easeInOut(duration: 0.2), value: dictation.errorMessage)
        .onChange(of: dictation.transcript) { _, transcript in
            viewModel.query = transcript
        }
        .onChange(of: viewModel.isPresented) { _, isPresented in
            if !isPresented {
                isFocused = false
                dictation.stop()
            }
        }
        .onDisappear {
            dictation.stop()
        }
    }

    private var clearQueryButton: some View {
        Button {
            viewModel.query = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear Command Line")
    }

    private var commandLineMicButton: some View {
        Button {
            if dictation.isRecording {
                dictation.stop()
            } else {
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
                .foregroundStyle(dictation.isRecording ? .red : .secondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Start dictation")
        .contextMenu {
            dictationLocaleMenu
        }
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
