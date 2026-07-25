import SwiftUI

/// Pinch-to-zoom + pan container for full-screen media.
///
/// Designed to sit inside a paging `TabView`: the pan gesture is only armed
/// while actually zoomed in, so at 1× a horizontal swipe still pages to the
/// next clip. Pinching back below 1× snaps to fit. Taps pass through to the
/// content (the players use them for play/pause) because the pan gesture keeps
/// the default 10 pt activation distance.
struct Zoomable<Content: View>: View {
    /// False while this page is off-screen — resets the zoom so returning to a
    /// clip never shows it still magnified from last time.
    var isActive: Bool = true

    @ViewBuilder var content: Content

    private let maxScale: CGFloat = 6

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            content
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .highPriorityGesture(pan(in: geo.size), including: scale > 1 ? .all : .none)
                .simultaneousGesture(magnify(in: geo.size))
                .onChange(of: isActive) { _, active in
                    if !active { reset() }
                }
        }
        .clipped()
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(baseScale * value.magnification, 0.5), maxScale)
                // Re-clamp as we zoom out so the content can't stay pushed off screen.
                offset = clamped(baseOffset, in: size)
            }
            .onEnded { _ in
                if scale <= 1 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { reset() }
                } else {
                    baseScale = scale
                    offset = clamped(offset, in: size)
                    baseOffset = offset
                }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clamped(
                    CGSize(width:  baseOffset.width  + value.translation.width,
                           height: baseOffset.height + value.translation.height),
                    in: size
                )
            }
            .onEnded { _ in baseOffset = offset }
    }

    /// Stops the magnified content from being dragged past its own edges.
    private func clamped(_ o: CGSize, in size: CGSize) -> CGSize {
        let limitX = max(0, (size.width  * scale - size.width)  / 2)
        let limitY = max(0, (size.height * scale - size.height) / 2)
        return CGSize(width:  min(max(o.width,  -limitX), limitX),
                      height: min(max(o.height, -limitY), limitY))
    }

    private func reset() {
        scale = 1
        baseScale = 1
        offset = .zero
        baseOffset = .zero
    }
}
