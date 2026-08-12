import SwiftUI

/// Compact CoCaptain / CoStar picker for Settings and the Command Line change-copilot sheet.
struct CopilotPersonaPicker: View {
    let selection: CopilotPersona
    var onSelect: (CopilotPersona) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(CopilotPersona.allCases) { persona in
                personaRow(persona)
            }
        }
    }

    private func personaRow(_ persona: CopilotPersona) -> some View {
        let isSelected = selection == persona

        return Button {
            onSelect(persona)
        } label: {
            HStack(spacing: 14) {
                Image(persona.avatarImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                Color(hex: persona.accentHex).opacity(isSelected ? 0.95 : 0.25),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(persona.nameKey))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(LocalizedStringKey(persona.roleKey))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(hex: persona.accentHex) : .secondary.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground).opacity(isSelected ? 1 : 0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        Color(hex: persona.accentHex).opacity(isSelected ? 0.45 : 0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(persona.nameKey)))
        .accessibilityValue(Text(isSelected ? "Selected" : "Not selected"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Lightweight sheet wrapper used by the Command Line `changeCopilot` action.
struct CopilotPersonaPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selection: CopilotPersona
    var onSelect: (CopilotPersona) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(LocalizedStringKey("settings.copilot.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    CopilotPersonaPicker(selection: selection) { persona in
                        onSelect(persona)
                        dismiss()
                    }
                }
                .padding(20)
            }
            .navigationTitle(Text(LocalizedStringKey("settings.copilot.title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
