import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @AppStorage("app_language") private var selectedLanguage = "English"
    @AppStorage("app_theme") private var selectedTheme = "System"
    @AppStorage("haptics_enabled") private var hapticsEnabled = true
    
    let languages = ["English", "Arabic", "French", "German", "Spanish"]
    let themes = ["System", "Light", "Dark"]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // MARK: - Background
                Color(uiColor: .systemBackground).ignoresSafeArea()
                
                // Subtle Glow (Orange/Red for Settings)
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 400, height: 400)
                    .blur(radius: 60)
                    .offset(x: 150, y: -200)
                
                ScrollView {
                    VStack(spacing: 32) {
                        
                        VStack(spacing: 24) {
                            // Interface Section
                            SettingsSection(title: "Interface") {
                                
                                HStack {
                                    Label("Theme", systemImage: "paintbrush.fill")
                                        .font(.system(size: 16, weight: .medium))
                                    Spacer()
                                    Picker("Theme", selection: $selectedTheme) {
                                        ForEach(themes, id: \.self) { theme in
                                            Text(theme).tag(theme)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.orange)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                
                                Divider().padding(.leading, 50).opacity(0.3)
                                
                                HStack {
                                    Label("Language", systemImage: "globe")
                                        .font(.system(size: 16, weight: .medium))
                                    Spacer()
                                    Picker("Language", selection: $selectedLanguage) {
                                        ForEach(languages, id: \.self) { lang in
                                            Text(lang).tag(lang)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.orange)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            
                            // App Settings
                            SettingsSection(title: "System") {
                                Toggle(isOn: $hapticsEnabled) {
                                    Label("Haptic Feedback", systemImage: "waveform.path")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .tint(.orange)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // MARK: - Footer
                        VStack(spacing: 8) {
                            Text("APP CONFIGURATION")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text("Changes apply in real-time.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 40)
                    }
                }
            }
            .toolbar {
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
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
