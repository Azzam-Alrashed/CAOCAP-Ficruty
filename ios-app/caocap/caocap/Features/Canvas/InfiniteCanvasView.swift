import SwiftUI

/// Blank spatial workspace retained for the upcoming orchestration workflow editor.
/// Legacy nodes remain persisted by `ProjectStore`, but are intentionally not rendered.
struct InfiniteCanvasView: View {
    @Environment(\.colorScheme) private var colorScheme

    let store: ProjectStore
    @Binding var viewport: ViewportState
    @Binding var currentScale: CGFloat

    @GestureState private var panTranslation: CGSize = .zero

    private var displayedOffset: CGSize {
        CGSize(
            width: viewport.offset.width + panTranslation.width,
            height: viewport.offset.height + panTranslation.height
        )
    }

    var body: some View {
        GeometryReader { geometry in
            DottedBackground(offset: displayedOffset, scale: viewport.scale)
                .overlay {
                    Image("SpaceSketchBG")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 2000, height: 2000)
                        .opacity(colorScheme == .dark ? 0.40 : 0.25)
                        .blendMode(colorScheme == .dark ? .screen : .multiply)
                        .scaleEffect(viewport.scale)
                        .offset(displayedOffset)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .updating($panTranslation) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            viewport.handleDragTranslation(value.translation)
                            viewport.handleDragEnded()
                            persistViewport()
                            PerformanceSignposts.event(PerformanceSignposts.Name.canvasGesture)
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let location = CGPoint(
                                x: value.startAnchor.x * geometry.size.width,
                                y: value.startAnchor.y * geometry.size.height
                            )
                            viewport.handleMagnificationChanged(
                                value.magnification,
                                at: location,
                                in: geometry.size
                            )
                            currentScale = viewport.scale
                        }
                        .onEnded { _ in
                            viewport.handleMagnificationEnded()
                            currentScale = viewport.scale
                            persistViewport()
                            PerformanceSignposts.event(PerformanceSignposts.Name.canvasGesture)
                        }
                )
                .onAppear {
                    if viewport.offset == .zero, viewport.scale == 1.0 {
                        let fitScale = viewport.scaleToFitSpaceSketch(in: geometry.size)
                        viewport.flyTo(
                            nodePosition: .zero,
                            containerSize: geometry.size,
                            targetScale: fitScale
                        )
                        persistViewport()
                    }
                    currentScale = viewport.scale
                }
        }
        .background(colorScheme == .dark ? Color(white: 0.05) : Color(white: 0.95))
        .ignoresSafeArea()
    }

    private func persistViewport() {
        store.updateViewport(offset: viewport.offset, scale: viewport.scale)
    }
}

#Preview {
    InfiniteCanvasView(
        store: ProjectStore(),
        viewport: .constant(ViewportState()),
        currentScale: .constant(1)
    )
}
