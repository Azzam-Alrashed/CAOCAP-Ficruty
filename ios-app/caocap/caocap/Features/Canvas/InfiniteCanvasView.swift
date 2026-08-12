import SwiftUI
import UIKit

/// Renders one spatial workspace and owns the transient gesture state needed to
/// pan, zoom, select, and drag nodes without changing the durable project model
/// until a gesture is committed.
struct InfiniteCanvasView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(OnboardingCoordinator.self) private var onboarding: OnboardingCoordinator?
    
    /// Tracks the current panning and zooming state of the canvas.
    @Binding var viewport: ViewportState
    
    /// Real-time scale feedback for external overlays.
    @Binding var currentScale: CGFloat

    /// Fullscreen mini-app preview — owned by the session so FAB dismiss can close it.
    @Binding var presentedMiniApp: SpatialNode?
    /// Non-mini-app node inspector sheet — also session-owned for FAB dismiss.
    @Binding var selectedNodeDetail: SpatialNode?
    
    /// The central store managing node data and persistence.
    var store: ProjectStore
    
    /// Node to pulse-highlight after fly-to navigation from CoCaptain or search.
    var canvasFocusNodeID: UUID?
    var commandPalette: CommandPaletteViewModel? = nil
    
    /// Callback triggered when a specialized action node is tapped. Its
    /// presence also marks the canvas as non-persistent onboarding mode.
    var onNodeAction: ((NodeAction) -> Void)? = nil
    
    var onNavigateToSubCanvas: ((String) -> Void)? = nil
    var onRecoverUnsupportedProject: (() -> Void)? = nil
    var onFlyToNode: ((UUID) -> Void)? = nil
    init(
        store: ProjectStore,
        viewport: Binding<ViewportState>,
        currentScale: Binding<CGFloat>,
        presentedMiniApp: Binding<SpatialNode?>,
        selectedNodeDetail: Binding<SpatialNode?>,
        canvasFocusNodeID: UUID? = nil,
        commandPalette: CommandPaletteViewModel? = nil,
        onNodeAction: ((NodeAction) -> Void)? = nil,
        onNavigateToSubCanvas: ((String) -> Void)? = nil,
        onRecoverUnsupportedProject: (() -> Void)? = nil,
        onFlyToNode: ((UUID) -> Void)? = nil
    ) {
        self.store = store
        self._viewport = viewport
        self._currentScale = currentScale
        self._presentedMiniApp = presentedMiniApp
        self._selectedNodeDetail = selectedNodeDetail
        self.canvasFocusNodeID = canvasFocusNodeID
        self.commandPalette = commandPalette
        self.onNodeAction = onNodeAction
        self.onNavigateToSubCanvas = onNavigateToSubCanvas
        self.onRecoverUnsupportedProject = onRecoverUnsupportedProject
        self.onFlyToNode = onFlyToNode
    }
    
    // Drag offsets stay local until the drag ends so links and nodes can track
    // the finger smoothly without writing every intermediate frame to ProjectStore.
    
    /// Temporary translation offsets applied to nodes currently being dragged.
    @State private var nodeDragOffsets: [UUID: CGSize] = [:]
    /// Flag indicating an active node drag, used to disable canvas panning during the gesture.
    @State private var isDraggingNode = false
    /// Prevents a multi-touch magnification gesture from being interpreted as a
    /// node drag by the card's single-finger `DragGesture`.
    @State private var isPinchingCanvas = false
    /// Caches intrinsic node dimensions for fly-to and onboarding geometry.
    @State private var nodeSizes: [UUID: CGSize] = [:]
    /// Touch-pan translation stays view-local until the gesture ends, avoiding a
    /// global observable viewport mutation for every touch event.
    @GestureState private var panTranslation: CGSize = .zero
    /// UIKit trackpad gestures cannot use `@GestureState`, but must follow the
    /// same transient-update rule as touch panning.
    @State private var trackpadPanTranslation: CGSize = .zero

    private var displayedOffset: CGSize {
        CGSize(
            width: viewport.offset.width + panTranslation.width + trackpadPanTranslation.width,
            height: viewport.offset.height + panTranslation.height + trackpadPanTranslation.height
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            // Node positions are stored as offsets from the visible center, so
            // the center point is the bridge between canvas-space and screen-space.
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            
            ZStack {
                // Layer 1: The Infinite Dotted Grid
                DottedBackground(offset: displayedOffset, scale: viewport.scale)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .updating($panTranslation) { value, state, _ in
                                state = value.translation
                            }
                            .onEnded { value in
                                viewport.handleDragTranslation(value.translation)
                                viewport.handleDragEnded()
                                persistViewportIfNeeded()
                                PerformanceSignposts.event(PerformanceSignposts.Name.canvasGesture)
                            }
                    )
                
                // Layer 2: Node Connections (Drawn in screen space to prevent clipping and layout bugs)
                ConnectionLayer(
                    nodes: store.nodes,
                    dragOffsets: nodeDragOffsets,
                    offset: displayedOffset,
                    scale: viewport.scale,
                    center: center,
                    activeAgentStates: store.activeAgentStates
                )
                
                // Layer 3: The Spatial Core (Scaled & Offset)
                ZStack {
                    // Layer 2.5: Spatial Centerpiece (Universal)
                    Color.clear
                        .frame(width: 0, height: 0)
                        .overlay(
                            Image("SpaceSketchBG")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 2000, height: 2000)
                                .opacity(colorScheme == .dark ? 0.40 : 0.25)
                                .blendMode(colorScheme == .dark ? .screen : .multiply)
                                .allowsHitTesting(false)
                        )
                    
                    CanvasNodeLayer(
                        nodes: store.nodes,
                        activeAgentStates: store.activeAgentStates,
                        nodeDragOffsets: nodeDragOffsets,
                        focusedNodeID: canvasFocusNodeID,
                        containerSize: geometry.size,
                        onTap: handleNodeTap,
                        onDoubleTap: handleNodeDoubleTap,
                        onDelete: handleNodeDelete,
                        onInspect: handleNodeInspect,
                        onDragChanged: handleNodeDragChanged,
                        onDragEnded: handleNodeDragEnded
                    )
                    .equatable()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(viewport.scale)
                .offset(displayedOffset)

                if let message = store.unsupportedProjectMessage {
                    UnsupportedProjectCard(
                        message: message,
                        onCreateFreshCanvas: { onRecoverUnsupportedProject?() }
                    )
                    .frame(maxWidth: 460)
                    .padding(24)
                }

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "canvas")
            .onboardingExplicitAnchorFrames(canvasExplicitAnchorFrames(canvasSize: geometry.size))
            .contentShape(Rectangle()) // Ensure the entire area is gesture-sensitive.
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                    viewport.fitTo(nodes: store.nodes, containerSize: geometry.size)
                }
                HapticsManager.shared.trigger(.medium)
            }
            .gesture(
                TrackpadPanGesture(
                    onChanged: { translation in
                        guard !isDraggingNode else { return }
                        trackpadPanTranslation = translation
                    },
                    onEnded: { translation in
                        guard !isDraggingNode else { return }
                        viewport.handleDragTranslation(translation)
                        viewport.handleDragEnded()
                        trackpadPanTranslation = .zero
                        persistViewportIfNeeded()
                    }
                )
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if !isPinchingCanvas {
                            isPinchingCanvas = true
                            nodeDragOffsets.removeAll()
                            isDraggingNode = false
                        }
                        let location = CGPoint(
                            x: value.startAnchor.x * geometry.size.width,
                            y: value.startAnchor.y * geometry.size.height
                        )
                        viewport.handleMagnificationChanged(value.magnification, at: location, in: geometry.size)
                        currentScale = viewport.scale
                    }
                    .onEnded { _ in 
                        viewport.handleMagnificationEnded()
                        currentScale = viewport.scale
                        persistViewportIfNeeded()
                        PerformanceSignposts.event(PerformanceSignposts.Name.canvasGesture)
                        DispatchQueue.main.async {
                            isPinchingCanvas = false
                        }
                    }
            )
            .onPreferenceChange(NodeSizePreferenceKey.self) { value in
                nodeSizes = value
            }
        }
        .background(backgroundColor)
        .onboardingTooltipOverlay(
            isCommandPalettePresented: commandPalette?.isPresented ?? false,
            rendersAnchor: { $0.isCanvasLocal }
        )
        .edgesIgnoringSafeArea(.all)
        .sheet(item: $selectedNodeDetail) { node in
            NodeDetailView(
                node: node,
                store: store,
                commandPalette: commandPalette,
                onFlyToNode: handleFlyToFromDetail
            )
        }
        .sheet(item: $presentedMiniApp) { node in
            NodeDetailView(
                node: node,
                store: store,
                commandPalette: commandPalette,
                onFlyToNode: handleFlyToFromDetail
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            currentScale = viewport.scale
        }
    }

    private func canvasExplicitAnchorFrames(canvasSize: CGSize) -> [OnboardingTooltipAnchor: CGRect] {
        var frames: [OnboardingTooltipAnchor: CGRect] = [:]

        return frames
    }

    private func handleNodeTap(_ node: SpatialNode) {
        if let action = node.action {
            onNodeAction?(action)
        } else if node.type == .subCanvas, let fileName = node.linkedCanvasFileName {
            onNavigateToSubCanvas?(fileName)
        } else if node.type == .miniApp {
            presentedMiniApp = node
        } else {
            selectedNodeDetail = node
        }
    }

    private func handleNodeDoubleTap(_ node: SpatialNode, containerSize: CGSize) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            let targetScale = computeTargetScale(for: node.id, containerSize: containerSize)
            viewport.flyTo(
                nodePosition: node.position,
                containerSize: containerSize,
                targetScale: targetScale
            )
        }
        HapticsManager.shared.trigger(.medium)
    }

    private func handleNodeDelete(_ node: SpatialNode) {
        HapticsManager.shared.notification(.warning)
        store.deleteNode(id: node.id, persist: true)
    }

    private func handleNodeInspect(_ node: SpatialNode) {
        selectedNodeDetail = node
    }

    private func handleNodeDragChanged(_ node: SpatialNode, translation: CGSize) {
        guard !isPinchingCanvas else { return }
        isDraggingNode = true
        nodeDragOffsets[node.id] = canvasTranslation(for: translation)
    }

    private func handleNodeDragEnded(_ node: SpatialNode, translation: CGSize) {
        guard !isPinchingCanvas else { return }
        let canvasTranslation = canvasTranslation(for: translation)
        let finalPosition = CGPoint(
            x: node.position.x + canvasTranslation.width,
            y: node.position.y + canvasTranslation.height
        )

        store.updateNodePosition(
            id: node.id,
            position: finalPosition,
            persist: true
        )

        nodeDragOffsets[node.id] = nil
        isDraggingNode = false
        HapticsManager.shared.selectionChanged()
        PerformanceSignposts.event(PerformanceSignposts.Name.canvasGesture)
    }
    
    /// Resolves the color of the infinite canvas background grid.
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.05) : Color(white: 0.95)
    }

    /// Flushes the transient gesture scale and offset to the `ProjectStore`.
    private func persistViewportIfNeeded() {
        store.updateViewport(
            offset: viewport.offset,
            scale: viewport.scale,
            persist: true
        )
    }

    /// Dismisses node detail chrome, then flies the workspace camera to the target node.
    private func handleFlyToFromDetail(_ nodeID: UUID) {
        selectedNodeDetail = nil
        presentedMiniApp = nil
        onFlyToNode?(nodeID)
    }

    /// Converts screen-space gesture movement into the unscaled coordinate
    /// system used by node positions and connection offsets.
    private func canvasTranslation(for translation: CGSize) -> CGSize {
        CGSize(
            width: translation.width / viewport.scale,
            height: translation.height / viewport.scale
        )
    }

    /// Computes the exact zoom level required to fit a specific node within the screen bounds.
    /// - Parameters:
    ///   - nodeId: The ID of the node to frame.
    ///   - containerSize: The physical screen dimensions available.
    /// - Returns: A zoom scale factor capped at 1.2x.
    private func computeTargetScale(for nodeId: UUID, containerSize: CGSize) -> CGFloat {
        guard let nodeSize = nodeSizes[nodeId], containerSize != .zero else {
            return 1.0
        }
        let paddingFactor: CGFloat = 0.8
        let scaleX = (containerSize.width * paddingFactor) / nodeSize.width
        let scaleY = (containerSize.height * paddingFactor) / nodeSize.height
        return min(min(scaleX, scaleY), 1.2)
    }

    private func screenFrame(for nodeId: UUID, canvasSize: CGSize) -> CGRect? {
        guard let node = store.nodes.first(where: { $0.id == nodeId }),
              let nodeSize = nodeSizes[nodeId] else {
            return nil
        }

        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let dragOffset = nodeDragOffsets[nodeId] ?? .zero
        let screenCenter = CGPoint(
            x: center.x + (node.position.x + dragOffset.width) * viewport.scale + displayedOffset.width,
            y: center.y + (node.position.y + dragOffset.height) * viewport.scale + displayedOffset.height
        )
        let scaledSize = CGSize(
            width: nodeSize.width * viewport.scale,
            height: nodeSize.height * viewport.scale
        )

        return CGRect(
            x: screenCenter.x - scaledSize.width / 2,
            y: screenCenter.y - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }
}

/// Renders every node and its interaction modifiers behind a single equality
/// boundary so viewport-only updates can reuse the complete node hierarchy.
private struct CanvasNodeLayer: View, Equatable {
    let nodes: [SpatialNode]
    let activeAgentStates: [UUID: AgentExecutionState]
    let nodeDragOffsets: [UUID: CGSize]
    let focusedNodeID: UUID?
    let containerSize: CGSize
    let onTap: (SpatialNode) -> Void
    let onDoubleTap: (SpatialNode, CGSize) -> Void
    let onDelete: (SpatialNode) -> Void
    let onInspect: (SpatialNode) -> Void
    let onDragChanged: (SpatialNode, CGSize) -> Void
    let onDragEnded: (SpatialNode, CGSize) -> Void

    static func == (lhs: CanvasNodeLayer, rhs: CanvasNodeLayer) -> Bool {
        lhs.nodes == rhs.nodes
            && lhs.activeAgentStates == rhs.activeAgentStates
            && lhs.nodeDragOffsets == rhs.nodeDragOffsets
            && lhs.focusedNodeID == rhs.focusedNodeID
            && lhs.containerSize == rhs.containerSize
    }

    var body: some View {
        ForEach(nodes) { node in
            spatialNode(node)
        }
    }

    private func spatialNode(_ node: SpatialNode) -> some View {
        let currentOffset = nodeDragOffsets[node.id] ?? .zero
        let isDragging = nodeDragOffsets[node.id] != nil

        return NodeView(
            node: node,
            isDragging: isDragging,
            agentState: activeAgentStates[node.id] ?? .idle,
            isTransientlyFocused: focusedNodeID == node.id
        )
        .equatable()
        .offset(
            x: node.position.x + currentOffset.width,
            y: node.position.y + currentOffset.height
        )
        .zIndex(isDragging ? 1 : 0)
        .onTapGesture(count: 2) {
            onDoubleTap(node, containerSize)
        }
        .onTapGesture {
            onTap(node)
        }
        .contextMenu(menuItems: {
            if !node.isProtected {
                Button(role: .destructive) {
                    onDelete(node)
                } label: {
                    Label("Delete Node", systemImage: "trash")
                }
            }

            Button {
                onInspect(node)
            } label: {
                Label("Inspect", systemImage: "info.circle")
            }
        }, preview: {
            NodeView(node: node, reportsSize: false)
                .environment(\.colorScheme, .dark)
                .frame(width: 280)
                .padding()
        })
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .named("canvas"))
                .onChanged { value in
                    onDragChanged(node, value.translation)
                }
                .onEnded { value in
                    onDragEnded(node, value.translation)
                }
        )
    }
}

/// A custom UIKit pan gesture wrapper specifically for two-finger trackpad panning on iPadOS/macOS.
private struct TrackpadPanGesture: UIGestureRecognizerRepresentable {
    var onChanged: (CGSize) -> Void
    var onEnded: (CGSize) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        // Keep direct touch panning with SwiftUI's DragGesture. Without this
        // restriction, this recognizer receives the same finger movement and
        // the two transient translations are added together.
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        recognizer.allowedScrollTypesMask = .continuous
        recognizer.delegate = context.coordinator
        recognizer.cancelsTouchesInView = false
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view)
        let canvasTranslation = CGSize(width: translation.x, height: translation.y)

        switch recognizer.state {
        case .began, .changed:
            onChanged(canvasTranslation)
        case .ended, .cancelled, .failed:
            onEnded(canvasTranslation)
        default:
            break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}



#Preview {
    InfiniteCanvasView(
        store: ProjectStore(),
        viewport: .constant(ViewportState()),
        currentScale: .constant(1.0),
        presentedMiniApp: .constant(nil),
        selectedNodeDetail: .constant(nil),
        onNodeAction: nil
    )
}

/// An overlay view displayed when the current project file contains schema elements
/// this version of CAOCAP does not understand, offering the user a safe escape hatch.
private struct UnsupportedProjectCard: View {
    let message: String
    let onCreateFreshCanvas: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Project format changed", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onCreateFreshCanvas) {
                Label("Create Fresh Mini-App Canvas", systemImage: "plus.square.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(22)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
    }
}
