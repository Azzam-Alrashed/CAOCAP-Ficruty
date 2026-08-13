import SwiftUI

/// Read-only rendering of the active canvas for Home's latest-session card.
/// It observes viewport values but never changes or persists them.
struct SessionCanvasPreview: View {
    @Environment(\.colorScheme) private var colorScheme

    let viewport: ViewportState

    var body: some View {
        DottedBackground(offset: viewport.offset, scale: viewport.scale)
            .overlay {
                Image("SpaceSketchBG")
                    .resizable()
                    .scaledToFill()
                    .frame(width: ViewportState.spaceSketchSize.width, height: ViewportState.spaceSketchSize.height)
                    .opacity(colorScheme == .dark ? 0.40 : 0.25)
                    .blendMode(colorScheme == .dark ? .screen : .multiply)
                    .scaleEffect(viewport.scale)
                    .offset(viewport.offset)
            }
            .background(colorScheme == .dark ? Color(white: 0.05) : Color(white: 0.95))
            .clipped()
            .allowsHitTesting(false)
    }
}
