import SwiftUI

struct InfiniteCanvasView: View {
    @Environment(\.colorScheme) var colorScheme
    
    /// Tracks the current panning and zooming state of the canvas.
    @State private var viewport: ViewportState
    
    /// Real-time scale feedback for external overlays.
    @Binding var currentScale: CGFloat
    
    /// The central store managing node data and persistence.
    var store: ProjectStore
    
    /// Callback triggered when a specialized action node is tapped.
    var onNodeAction: ((String) -> Void)? = nil
    
    init(store: ProjectStore, currentScale: Binding<CGFloat>, onNodeAction: ((String) -> Void)? = nil) {
        self.store = store
        self._currentScale = currentScale
        self.onNodeAction = onNodeAction
        
        // Onboarding always starts fresh; active projects load saved state.
        if onNodeAction != nil && store.fileName.contains("onboarding") {
            self._viewport = State(initialValue: ViewportState(offset: .zero, scale: 1.0))
        } else {
            self._viewport = State(initialValue: ViewportState(
                offset: store.viewportOffset,
                scale: store.viewportScale
            ))
        }
    }
    
    // Selection and Dragging State
    @State private var selectedNode: SpatialNode?
    @State private var nodeDragOffsets: [UUID: CGSize] = [:]
    @State private var isDraggingNode = false
    
    var body: some View {
        GeometryReader { geometry in
            // Calculate the screen center to serve as the canvas origin.
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            
            ZStack {
                // Layer 1: The Infinite Dotted Grid
                DottedBackground(offset: viewport.offset, scale: viewport.scale)
                
                // Layer 2: Node Connections (Drawn in screen space to prevent clipping)
                ConnectionLayer(nodes: store.nodes, dragOffsets: nodeDragOffsets, viewport: viewport, center: center)
                
                // Layer 3: The Spatial Nodes
                ZStack {
                    ForEach(store.nodes) { node in
                        let currentOffset = nodeDragOffsets[node.id] ?? .zero
                        let isDraggingThisNode = nodeDragOffsets[node.id] != nil
                        
                        NodeView(node: node, isDragging: isDraggingThisNode)
                            .offset(
                                x: node.position.x + currentOffset.width,
                                y: node.position.y + currentOffset.height
                            )
                            .onTapGesture {
                                if node.title == "Go to the Home workspace" || node.title == "Retry Onboarding" {
                                    onNodeAction?(node.title)
                                } else {
                                    selectedNode = node
                                }
                            }
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 5)
                                    .onChanged { value in
                                        // Block canvas panning while a node is being moved.
                                        isDraggingNode = true
                                        nodeDragOffsets[node.id] = value.translation
                                    }
                                    .onEnded { value in
                                        // Finalize the node position with a smooth spring animation.
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                            let finalX = node.position.x + value.translation.width
                                            let finalY = node.position.y + value.translation.height
                                            
                                            // Update the store so the node stays in place during the session.
                                            // Only persist to disk for active projects.
                                            store.updateNodePosition(
                                                id: node.id,
                                                position: CGPoint(x: finalX, y: finalY),
                                                persist: onNodeAction == nil
                                            )
                                            
                                            nodeDragOffsets[node.id] = nil
                                            isDraggingNode = false
                                        }
                                    }
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(viewport.scale)
                .offset(viewport.offset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle()) // Ensure the entire area is gesture-sensitive.
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        // Only pan the background if no node is currently being dragged.
                        if !isDraggingNode {
                            viewport.handleDragChanged(value)
                        }
                    }
                    .onEnded { _ in 
                        if !isDraggingNode {
                            viewport.handleDragEnded()
                            // Update the store's viewport so it stays in place during the session.
                            // Only persist to disk for active projects.
                            store.updateViewport(
                                offset: viewport.offset,
                                scale: viewport.scale,
                                persist: onNodeAction == nil
                            )
                        }
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
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
                        // Update the store's viewport so it stays in place during the session.
                        // Only persist to disk for active projects.
                        store.updateViewport(
                            offset: viewport.offset,
                            scale: viewport.scale,
                            persist: onNodeAction == nil
                        )
                    }
            )
        }
        .background(backgroundColor)
        .edgesIgnoringSafeArea(.all)
        .sheet(item: $selectedNode) { node in
            NodeDetailView(node: node)
        }
        .onAppear {
            currentScale = viewport.scale
        }
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.05) : Color(white: 0.95)
    }
}



#Preview {
    InfiniteCanvasView(store: ProjectStore(), currentScale: .constant(1.0), onNodeAction: nil)
}
