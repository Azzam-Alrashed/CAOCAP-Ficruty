import SwiftUI

/// Opens a canvas node. Mini-App nodes enter a large-sheet shell with Agent /
/// Settings tools available through the shared omnibox.
struct NodeDetailView: View {
    /// The canvas node whose detail is being shown. Used as the initial value;
    /// the live version is always read from `store.nodes`.
    let node: SpatialNode
    /// The owning project store, passed through to child sheets.
    let store: ProjectStore
    var commandPalette: CommandPaletteViewModel? = nil
    var onFlyToNode: ((UUID) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    /// Always reads the node from the store so that any edits made inside a
    /// child sheet (e.g. title change in settings) are reflected here without
    /// needing to re-open the detail view.
    private var currentNode: SpatialNode {
        store.nodes.first(where: { $0.id == node.id }) ?? node
    }

    var body: some View {
        if currentNode.type == .miniApp {
            MiniAppDetailShell(
                node: currentNode,
                store: store,
                commandPalette: commandPalette,
                onFlyToNode: onFlyToNode
            )
        } else {
            MiniAppSettingsView(node: currentNode, store: store) {
                dismiss()
            }
        }
    }
}

/// Identifies which tool sheet should be presented over the Mini-App detail shell.
private enum MiniAppTool: String, Identifiable {
    /// CoCaptain agent chat panel.
    case agent
    /// Node identity and agent profile settings form.
    case settings

    var id: String { rawValue }

    init?(_ previewTool: MiniAppPreviewTool) {
        switch previewTool {
        case .agent: self = .agent
        case .settings: self = .settings
        case .backToCanvas: return nil
        }
    }
}

/// Large-sheet shell for Mini-App nodes. Surfaces Agent / Settings / Back through
/// the shared omnibox (opened via the global FAB above sheets).
private struct MiniAppDetailShell: View {
    let node: SpatialNode
    let store: ProjectStore
    var commandPalette: CommandPaletteViewModel?
    var onFlyToNode: ((UUID) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    /// Drives which tool sheet is currently presented.
    @State private var activeTool: MiniAppTool?

    private var currentNode: SpatialNode {
        store.nodes.first(where: { $0.id == node.id }) ?? node
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: currentNode.icon ?? "square.stack.3d.up.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(currentNode.theme.color)
                Text(currentNode.displayTitle)
                    .font(.title2.weight(.semibold))
                if let subtitle = currentNode.displaySubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()

            if let commandPalette {
                CommandPaletteView(viewModel: commandPalette)
            }
        }
        .onAppear {
            guard let commandPalette else { return }
            commandPalette.miniAppPreviewContext = MiniAppPreviewPaletteContext(
                nodeID: currentNode.id,
                onSelectTool: handlePreviewToolSelection
            )
        }
        .onDisappear {
            commandPalette?.miniAppPreviewContext = nil
            commandPalette?.setPresented(false)
        }
        .sheet(item: $activeTool) { tool in
            switch tool {
            case .agent:
                NavigationStack {
                    NodeAgentChatView(
                        nodeID: currentNode.id,
                        store: store,
                        actionDispatcher: nil,
                        onFlyToNode: { nodeID in
                            activeTool = nil
                            onFlyToNode?(nodeID)
                        }
                    )
                }
            case .settings:
                MiniAppSettingsView(node: currentNode, store: store) {
                    dismiss()
                }
            }
        }
    }

    private func handlePreviewToolSelection(_ tool: MiniAppPreviewTool) {
        switch tool {
        case .backToCanvas:
            dismiss()
        default:
            if let miniAppTool = MiniAppTool(tool) {
                activeTool = miniAppTool
            }
        }
    }
}

/// A navigation-wrapped `Form` for editing a node's identity (name, subtitle, icon,
/// theme), agent profile (role, system prompt, auto-trigger flag), and — for
/// non-protected nodes — a destructive delete action.
private struct MiniAppSettingsView: View {
    let node: SpatialNode
    let store: ProjectStore
    /// Invoked after the user confirms node deletion so the caller (e.g.,
    /// `InfiniteCanvasView`) can dismiss the sheet that was showing this detail.
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var currentNode: SpatialNode {
        store.nodes.first(where: { $0.id == node.id }) ?? node
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: Binding(
                        get: { currentNode.title },
                        set: { store.updateNodeTitle(id: node.id, title: $0) }
                    ))

                    TextField("Subtitle", text: Binding(
                        get: { currentNode.subtitle ?? "" },
                        set: { store.updateNodeSubtitle(id: node.id, subtitle: $0.isEmpty ? nil : $0) }
                    ))

                    TextField("SF Symbol", text: Binding(
                        get: { currentNode.icon ?? "" },
                        set: { store.updateNodeIcon(id: node.id, icon: $0.isEmpty ? nil : $0) }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Picker("Theme", selection: Binding(
                        get: { currentNode.theme },
                        set: { store.updateNodeTheme(id: node.id, theme: $0) }
                    )) {
                        ForEach(NodeTheme.allCases, id: \.self) { theme in
                            Text(theme.rawValue.capitalized).tag(theme)
                        }
                    }
                }

                Section("Agent Profile") {
                    TextField("Role Name", text: Binding(
                        get: { currentNode.agentProfile.roleName },
                        set: {
                            store.updateNodeAgentProfile(
                                id: node.id,
                                profile: AgentProfile(
                                    systemPrompt: currentNode.agentProfile.systemPrompt,
                                    roleName: $0,
                                    isAutoTriggerEnabled: currentNode.agentProfile.isAutoTriggerEnabled
                                )
                            )
                        }
                    ))

                    TextEditor(text: Binding(
                        get: { currentNode.agentProfile.systemPrompt ?? "" },
                        set: {
                            store.updateNodeAgentProfile(
                                id: node.id,
                                profile: AgentProfile(
                                    systemPrompt: $0.isEmpty ? nil : $0,
                                    roleName: currentNode.agentProfile.roleName,
                                    isAutoTriggerEnabled: currentNode.agentProfile.isAutoTriggerEnabled
                                )
                            )
                        }
                    ))
                    .frame(minHeight: 120)

                    Toggle("Auto-Trigger Downstream", isOn: Binding(
                        get: { currentNode.agentProfile.isAutoTriggerEnabled },
                        set: {
                            store.updateNodeAgentProfile(
                                id: node.id,
                                profile: AgentProfile(
                                    systemPrompt: currentNode.agentProfile.systemPrompt,
                                    roleName: currentNode.agentProfile.roleName,
                                    isAutoTriggerEnabled: $0
                                )
                            )
                        }
                    ))
                }

                if !currentNode.isProtected {
                    Section {
                        Button("Delete Node", role: .destructive) {
                            HapticsManager.shared.notification(.warning)
                            store.deleteNode(id: node.id)
                            dismiss()
                            onDelete()
                        }
                    }
                }
            }
            .navigationTitle(currentNode.type == .miniApp ? "Mini-App Settings" : "Node Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
