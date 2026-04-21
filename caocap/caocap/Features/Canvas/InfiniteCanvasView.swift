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
                MagnificationGesture()
                    .onChanged { 
                        viewport.handleMagnificationChanged($0)
                        currentScale = viewport.scale
                    }
                    .onEnded { _ in 
                        viewport.handleMagnificationEnded()
                        currentScale = viewport.scale
                        // Update the store's zoom level so it stays in place during the session.
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

/// Renders smooth, curved arrows between connected nodes.
struct ConnectionLayer: View {
    let nodes: [SpatialNode]
    let dragOffsets: [UUID: CGSize]
    let viewport: ViewportState
    let center: CGPoint
    
    var body: some View {
        Canvas { context, size in
            for node in nodes {
                if let nextId = node.nextNodeId,
                   let nextNode = nodes.first(where: { $0.id == nextId }) {
                    
                    let nodeOffset = dragOffsets[node.id] ?? .zero
                    let nextNodeOffset = dragOffsets[nextNode.id] ?? .zero
                    
                    // Manually calculate screen-space coordinates to avoid clipping.
                    // Positions are offsets from the 'center' point.
                    let start = CGPoint(
                        x: center.x + (node.position.x + nodeOffset.width) * viewport.scale + viewport.offset.width,
                        y: center.y + (node.position.y + nodeOffset.height) * viewport.scale + viewport.offset.height
                    )
                    
                    let end = CGPoint(
                        x: center.x + (nextNode.position.x + nextNodeOffset.width) * viewport.scale + viewport.offset.width,
                        y: center.y + (nextNode.position.y + nextNodeOffset.height) * viewport.scale + viewport.offset.height
                    )
                    
                    drawArrow(context: context, from: start, to: end, themeColor: node.theme.color, scale: viewport.scale)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
    
    private func drawArrow(context: GraphicsContext, from: CGPoint, to: CGPoint, themeColor: Color, scale: CGFloat) {
        var path = Path()
        path.move(to: from)
        
        // Calculate control points for a smooth curve
        let midX = (from.x + to.x) / 2
        let cp1 = CGPoint(x: midX, y: from.y)
        let cp2 = CGPoint(x: midX, y: to.y)
        
        path.addCurve(to: to, control1: cp1, control2: cp2)
        
        let stroke = StrokeStyle(lineWidth: 3 * scale, lineCap: .round, lineJoin: .round, dash: [10 * scale, 10 * scale])
        context.stroke(path, with: .color(themeColor.opacity(0.4)), style: stroke)
        
        // Draw an arrowhead at the end
        drawArrowhead(context: context, at: to, direction: calculateDirection(from: cp2, to: to), color: themeColor.opacity(0.4), scale: scale)
    }
    
    private func drawArrowhead(context: GraphicsContext, at point: CGPoint, direction: CGFloat, color: Color, scale: CGFloat) {
        let size: CGFloat = 12 * scale
        var path = Path()
        path.move(to: CGPoint(x: -size, y: -size/1.5))
        path.addLine(to: .zero)
        path.addLine(to: CGPoint(x: -size, y: size/1.5))
        
        var arrowContext = context
        arrowContext.translateBy(x: point.x, y: point.y)
        arrowContext.rotate(by: Angle(radians: Double(direction)))
        arrowContext.fill(path, with: .color(color))
    }
    
    private func calculateDirection(from: CGPoint, to: CGPoint) -> CGFloat {
        atan2(to.y - from.y, to.x - from.x)
    }
}

/// A highly optimized canvas view that renders a procedural dotted grid.
struct DottedBackground: View {
    @Environment(\.colorScheme) var colorScheme
    let offset: CGSize
    let scale: CGFloat
    
    let dotSpacing: CGFloat = 30
    let dotSize: CGFloat = 2
    
    var body: some View {
        Canvas { context, size in
            let scaledSpacing = dotSpacing * scale
            let dotColor = colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5)
            
            let centerX = size.width / 2
            let centerY = size.height / 2
            
            // Calculate the starting position for the dot grid to ensure it loops infinitely.
            let startX = ((offset.width + centerX).truncatingRemainder(dividingBy: scaledSpacing)) - scaledSpacing
            let startY = ((offset.height + centerY).truncatingRemainder(dividingBy: scaledSpacing)) - scaledSpacing
            
            for x in stride(from: startX, through: size.width + scaledSpacing, by: scaledSpacing) {
                for y in stride(from: startY, through: size.height + scaledSpacing, by: scaledSpacing) {
                    let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                }
            }
        }
    }
}

#Preview {
    InfiniteCanvasView(store: ProjectStore(), currentScale: .constant(1.0), onNodeAction: nil)
}
