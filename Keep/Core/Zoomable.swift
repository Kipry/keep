import SwiftUI
import UIKit

/// Pinch-to-zoom, pan and double-tap container for full-screen media.
///
/// Built on a real `UIScrollView` rather than SwiftUI gestures. The previous
/// version composed `MagnifyGesture` with a `DragGesture`, and the drag never
/// arrived: these views live inside a paging `TabView`, which is a
/// `UIPageViewController` underneath, and its scroll view's pan recognizer wins
/// against a SwiftUI gesture attached to a descendant. Zooming worked, panning
/// silently did nothing, so the magnified image could only ever be viewed
/// centred.
///
/// A nested `UIScrollView` is arbitrated by UIKit instead of fighting it, and
/// brings the behaviour people already know from Photos: rubber-banding at the
/// edges, momentum, and double-tap to zoom to a point. At 1× the inner scroll
/// view has nothing to scroll, so it yields and the pager still swipes between
/// clips.
struct Zoomable<Content: View>: UIViewControllerRepresentable {
    /// False while this page is off-screen — resets the zoom so returning to a
    /// clip never shows it still magnified from last time.
    var isActive: Bool = true
    /// Single tap, delivered only once a double tap has been ruled out. The
    /// players use it for play/pause; passing it in rather than attaching an
    /// `onTapGesture` inside `content` is what keeps a double-tap-to-zoom from
    /// also toggling playback.
    var onSingleTap: (() -> Void)?

    @ViewBuilder var content: Content

    func makeUIViewController(context: Context) -> ZoomableController<Content> {
        ZoomableController(rootView: content, onSingleTap: onSingleTap)
    }

    func updateUIViewController(_ controller: ZoomableController<Content>, context: Context) {
        controller.update(rootView: content, isActive: isActive, onSingleTap: onSingleTap)
    }
}

final class ZoomableController<Content: View>: UIViewController, UIScrollViewDelegate {

    private let scrollView = UIScrollView()
    private let host: UIHostingController<Content>
    private var onSingleTap: (() -> Void)?

    private let maxScale: CGFloat = 6
    /// Where a double tap lands, matching Photos' single intermediate step.
    private let doubleTapScale: CGFloat = 3

    init(rootView: Content, onSingleTap: (() -> Void)?) {
        self.host = UIHostingController(rootView: rootView)
        self.onSingleTap = onSingleTap
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = maxScale
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        // Nothing to bounce against at 1×; without this the page would wobble
        // under a drag that is meant to reach the pager.
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrollView)

        addChild(host)
        host.view.backgroundColor = .clear
        // The zooming view carries a transform, so it must not also be driven
        // by autoresizing — its frame is set explicitly in viewDidLayoutSubviews.
        host.view.autoresizingMask = []
        host.safeAreaRegions = []
        scrollView.addSubview(host.view)
        host.didMove(toParent: self)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = scrollView.bounds.size
        guard size.width > 0, size.height > 0, host.view.bounds.size != size else { return }
        // A bounds change (rotation, first layout) invalidates any transform,
        // so drop back to fit rather than leaving the content off-centre.
        scrollView.setZoomScale(1, animated: false)
        host.view.frame = CGRect(origin: .zero, size: size)
        scrollView.contentSize = size
    }

    func update(rootView: Content, isActive: Bool, onSingleTap: (() -> Void)?) {
        host.rootView = rootView
        self.onSingleTap = onSingleTap
        if !isActive && scrollView.zoomScale != scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
        }
    }

    // MARK: Gestures

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        // Zoom to the tapped point rather than the centre, so double-tapping a
        // face puts that face on screen.
        let point = recognizer.location(in: host.view)
        let size = CGSize(width: scrollView.bounds.width / doubleTapScale,
                          height: scrollView.bounds.height / doubleTapScale)
        scrollView.zoom(to: CGRect(x: point.x - size.width / 2,
                                   y: point.y - size.height / 2,
                                   width: size.width,
                                   height: size.height),
                        animated: true)
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }
}
