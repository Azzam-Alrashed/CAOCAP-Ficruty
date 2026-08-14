import SwiftUI

enum SettingsPresentation {
    case tab
    case sheet
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedCopilot: CopilotPersona
    var presentation: SettingsPresentation = .sheet
    var onOpenAccount: () -> Void = {}
    var onOpenAppIcon: () -> Void = {}
    var onEraseEverything: () async throws -> Void = {}
    
    @AppStorage("app_language") private var selectedLanguage = "English"
    @AppStorage("app_theme") private var selectedTheme = "System"
    @AppStorage("haptics_enabled") private var hapticsEnabled = true
    @AppStorage("haptics_intensity") private var hapticsIntensity = "Medium"
    @AppStorage("grid_opacity") private var gridOpacity: Double = 0.1
    @AppStorage("connection_style") private var connectionStyle = "Dashed"
    @AppStorage("cocaptain.modelName") private var modelName = CoCaptainModelSelectionPolicy.cloudModelName

    @State private var localModelManager = LocalGemmaModelManager.shared
    @State private var showingEraseConfirmation = false
    @State private var isErasingEverything = false
    @State private var eraseErrorMessage: String?

    let languages = LocalizationManager.supportedLanguages
    let themes = ["System", "Light", "Dark"]
    let intensities = ["Subtle", "Medium", "Sharp"]
    let styles = ["Solid", "Dashed", "Neon"]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // MARK: - Background
                Color(uiColor: .systemBackground).ignoresSafeArea()
                
                // Subtle Glow
                Circle()
                    .fill(Color.orange.opacity(0.16))
                    .frame(width: 400, height: 400)
                    .blur(radius: 60)
                    .offset(x: 150, y: -200)
                
                ScrollView {
                    VStack(spacing: 32) {
                        
                        VStack(spacing: 24) {
                            // MARK: - Account
                            SettingsSection("Account") {
                                SettingsRow(
                                    icon: "person.crop.circle.fill",
                                    title: "Account",
                                    subtitle: "Profile, subscription, and account management",
                                    color: .blue,
                                    action: onOpenAccount
                                )
                            }

                            // MARK: - Copilot
                            SettingsSection(LocalizedStringKey("settings.copilot.title")) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(LocalizedStringKey("settings.copilot.subtitle"))
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 14)

                                    CopilotPersonaPicker(selection: selectedCopilot) { persona in
                                        selectedCopilot = persona
                                    }
                                        .padding(.horizontal, 12)
                                        .padding(.bottom, 14)
                                }
                            }

                            GemmaModelSettingsSection(
                                modelName: $modelName,
                                localModelManager: localModelManager,
                                eligibility: .current
                            )

                            // MARK: - Appearance
                            SettingsSection("Appearance") {
                                SettingsPickerRow(icon: "paintbrush.fill", title: "Theme", selection: $selectedTheme, options: themes, color: .purple)
                                
                                Divider().padding(.leading, 56).opacity(0.3)
                                
                                SettingsLanguagePickerRow(selection: $selectedLanguage)

                                Divider().padding(.leading, 56).opacity(0.3)

                                SettingsRow(
                                    icon: "app.dashed",
                                    title: "App Icon",
                                    subtitle: "Choose how CAOCAP appears on your Home Screen",
                                    color: .indigo,
                                    action: onOpenAppIcon
                                )
                            }
                            
                            // MARK: - Canvas
                            SettingsSection("Canvas") {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Label("Grid Visibility", systemImage: "grid")
                                            .font(.system(size: 16, weight: .medium))
                                        Spacer()
                                        Text("\(Int(gridOpacity * 100))%")
                                            .font(.system(size: 14, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Slider(value: $gridOpacity, in: 0.05...0.4, step: 0.05)
                                        .tint(.orange)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                
                                Divider().padding(.leading, 56).opacity(0.3)
                                
                                SettingsPickerRow(icon: "waveform.path", title: "Connection Style", selection: $connectionStyle, options: styles, color: .orange)
                            }

                            // MARK: - Interaction
                            SettingsSection("Interaction") {
                                Toggle(isOn: $hapticsEnabled) {
                                    Label("Tactile Feedback", systemImage: "sensor.touch.fill")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .tint(.green)
                                
                                if hapticsEnabled {
                                    Divider().padding(.leading, 56).opacity(0.3)
                                    
                                    SettingsPickerRow(icon: "shredder.fill", title: "Intensity", selection: $hapticsIntensity, options: intensities, color: .green)
                                }
                            }

                            SettingsSection("Danger Zone") {
                                SettingsRow(
                                    icon: "trash.fill",
                                    title: "Erase Everything",
                                    subtitle: "Delete all local data and start like a fresh install",
                                    color: .red,
                                    action: {
                                        guard !isErasingEverything else { return }
                                        showingEraseConfirmation = true
                                    }
                                )
                                .confirmationDialog(
                                    "Erase Everything?",
                                    isPresented: $showingEraseConfirmation,
                                    titleVisibility: .visible
                                ) {
                                    Button("Erase Everything", role: .destructive) {
                                        isErasingEverything = true
                                        Task { @MainActor in
                                            do {
                                                try await onEraseEverything()
                                                dismissIfNeeded()
                                            } catch {
                                                isErasingEverything = false
                                                eraseErrorMessage = error.localizedDescription
                                            }
                                        }
                                    }
                                    Button("Cancel", role: .cancel) {}
                                } message: {
                                    Text("This permanently deletes all local app data, preferences, onboarding answers, and downloaded models, then signs you out. Your cloud account and App Store purchases are not deleted.")
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // MARK: - Footer
                        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                            Text("Version \(version) (\(build))")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 40)
                        }
                    }
                }
            }
            .navigationTitle(presentation == .tab ? "Settings" : "")
            .navigationBarTitleDisplayMode(presentation == .tab ? .large : .inline)
            .toolbar {
                if presentation == .sheet {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("Settings")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.primary.opacity(0.6))
                                .padding(8)
                                .background(.primary.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Close Settings")
                    }
                }
            }
            .onAppear {
                modelName = CoCaptainModelSelectionPolicy.resolvedModelName(
                    modelName,
                    eligibility: .current
                )
                localModelManager.refreshCacheSize()
            }
            .preferredColorScheme(currentColorScheme)
            .alert(
                "Couldn’t Erase Everything",
                isPresented: Binding(
                    get: { eraseErrorMessage != nil },
                    set: { if !$0 { eraseErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(eraseErrorMessage ?? "Please try again.")
            }
        }
    }
    
    private var currentColorScheme: ColorScheme? {
        switch selectedTheme {
        case "Light": return .light
        case "Dark": return .dark
        default: return nil
        }
    }

    private func dismissIfNeeded() {
        guard presentation == .sheet else { return }
        dismiss()
    }
}

// MARK: - Helper View
struct SettingsPickerRow: View {
    let icon: String
    let title: LocalizedStringKey
    @Binding var selection: String
    let options: [String]
    let color: Color
    
    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .medium))
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(LocalizedStringKey(option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct SettingsLanguagePickerRow: View {
    @Binding var selection: String
    
    var body: some View {
        HStack {
            Label("Language", systemImage: "globe")
                .font(.system(size: 16, weight: .medium))
            Spacer()
            Menu {
                Button {
                    selection = "English"
                } label: {
                    HStack {
                        Text("English")
                        if selection == "English" {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Button {} label: {
                    Text("Arabic (Coming Soon)")
                        .foregroundStyle(.secondary)
                }
                .disabled(true)
            } label: {
                HStack(spacing: 4) {
                    Text("English")
                        .font(.system(size: 15, weight: .regular))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    @Previewable @State var selectedCopilot: CopilotPersona = .cocaptain
    SettingsView(selectedCopilot: $selectedCopilot)
}
