import UIKit

/// Transparent overlay view for rendering strokes in real-time on top of PDF content.
/// This view is positioned on top of the PDF image and handles drawing/erasing touch events.
class DrawingOverlayView: UIView {

    // MARK: - Properties

    /// The drawing controller that manages stroke state and rendering
    weak var drawingController: DrawingController?

    /// The page index this overlay represents
    var pageIndex: Int = 0

    /// The content rect of the PDF (for coordinate conversion)
    var contentRect: CGRect = .zero

    /// Whether strokes are stored as normalized (0-1) coordinates
    var useNormalizedCoordinates: Bool = false

    /// Current zoom scale (used to adjust stroke width for consistent visual appearance)
    var zoomScale: CGFloat = 1.0

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isOpaque = false
        // Allow touches to pass through when not drawing
        isUserInteractionEnabled = true
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let controller = drawingController else { return }

        // Draw completed strokes for this page
        controller.drawStrokes(
            in: context,
            page: pageIndex,
            contentRect: contentRect,
            useNormalized: useNormalizedCoordinates,
            zoomScale: zoomScale
        )

        // Draw active stroke being drawn
        controller.drawActiveStroke(
            in: context,
            page: pageIndex,
            contentRect: contentRect,
            zoomScale: zoomScale
        )
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let controller = drawingController,
              controller.drawingMode != .view,
              let touch = touches.first else {
            super.touchesBegan(touches, with: event)
            return
        }

        let location = touch.location(in: self)
        controller.handleTouchBegan(location, page: pageIndex, contentRect: contentRect)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let controller = drawingController,
              controller.drawingMode != .view,
              let touch = touches.first else {
            super.touchesMoved(touches, with: event)
            return
        }

        let location = touch.location(in: self)
        controller.handleTouchMoved(location, page: pageIndex, contentRect: contentRect)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let controller = drawingController,
              controller.drawingMode != .view else {
            super.touchesEnded(touches, with: event)
            return
        }

        controller.handleTouchEnded(page: pageIndex)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let controller = drawingController,
              controller.drawingMode != .view else {
            super.touchesCancelled(touches, with: event)
            return
        }

        controller.handleTouchCancelled()
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let controller = drawingController else {
            return nil
        }

        // Only intercept touches when in drawing/erase/highlight mode
        if controller.drawingMode != .view {
            return super.hitTest(point, with: event)
        }

        // In view mode, let touches pass through to the underlying scroll view
        return nil
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let controller = drawingController else {
            return false
        }

        // Only claim touches when in drawing mode
        return controller.drawingMode != .view && super.point(inside: point, with: event)
    }
}
