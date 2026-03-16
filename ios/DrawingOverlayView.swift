import UIKit

/// Transparent overlay view for rendering strokes in real-time on top of PDF content.
/// This view is positioned on top of the PDF image and handles drawing/erasing touch events.
/// Uses CATiledLayer for efficient rendering of large content.
class DrawingOverlayView: UIView {

    // MARK: - Layer Class Override

    override class var layerClass: AnyClass {
        return CATiledLayer.self
    }

    private var tiledLayer: CATiledLayer {
        return layer as! CATiledLayer
    }

    // MARK: - Properties

    /// The drawing controller that manages stroke state and rendering
    weak var drawingController: DrawingController?

    /// Text annotation handler for text mode touch interception (single-page mode only)
    weak var textAnnotationHandler: TextAnnotationHandler?

    /// The page index this overlay represents
    var pageIndex: Int = 0

    /// The content rect of the PDF (for coordinate conversion)
    var contentRect: CGRect = .zero

    /// Whether strokes are stored as normalized (0-1) coordinates
    var useNormalizedCoordinates: Bool = false

    /// Current zoom scale (used to adjust stroke width for consistent visual appearance)
    var zoomScale: CGFloat = 1.0

    // Multi-page mode (for ZoomablePdfScrollView)
    var multiPageMode: Bool = false
    var pageCount: Int = 0
    var pageWidth: CGFloat = 0
    var pageHeight: CGFloat = 0

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
        contentMode = .redraw
        isUserInteractionEnabled = true

        // Configure tiled layer for better performance
        tiledLayer.tileSize = CGSize(width: 512, height: 512)
        tiledLayer.levelsOfDetail = 1
        tiledLayer.levelsOfDetailBias = 0
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let controller = drawingController else { return }

        if multiPageMode && pageCount > 0 && pageHeight > 0 {
            // Only draw pages that intersect with the dirty rect for efficiency
            let firstPage = max(0, Int(rect.minY / pageHeight))
            let lastPage = min(pageCount - 1, Int(rect.maxY / pageHeight))

            for page in firstPage...lastPage {
                let pageRect = CGRect(
                    x: 0,
                    y: CGFloat(page) * pageHeight,
                    width: pageWidth,
                    height: pageHeight
                )

                controller.drawStrokes(
                    in: context,
                    page: page,
                    contentRect: pageRect,
                    useNormalized: useNormalizedCoordinates,
                    zoomScale: zoomScale
                )

                controller.drawActiveStroke(
                    in: context,
                    page: page,
                    contentRect: pageRect,
                    zoomScale: zoomScale,
                    useNormalized: useNormalizedCoordinates
                )

                controller.drawTexts(
                    in: context,
                    page: page,
                    contentRect: pageRect,
                    useNormalized: useNormalizedCoordinates,
                    zoomScale: zoomScale
                )
            }
        } else {
            // Single page mode
            controller.drawStrokes(
                in: context,
                page: pageIndex,
                contentRect: contentRect,
                useNormalized: useNormalizedCoordinates,
                zoomScale: zoomScale
            )

            controller.drawActiveStroke(
                in: context,
                page: pageIndex,
                contentRect: contentRect,
                zoomScale: zoomScale,
                useNormalized: useNormalizedCoordinates
            )

            controller.drawTexts(
                in: context,
                page: pageIndex,
                contentRect: contentRect,
                useNormalized: useNormalizedCoordinates,
                zoomScale: zoomScale
            )
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let controller = drawingController,
              controller.drawingMode != .view,
              let touch = touches.first else {
            super.touchesBegan(touches, with: event)
            return
        }

        // Multiple fingers — cancel drawing, let scroll view handle pinch
        if let allTouches = event?.allTouches, allTouches.count > 1 {
            if controller.isDrawing {
                controller.handleTouchCancelled()
            }
            return
        }

        // In text mode, delegate to text annotation handler
        if controller.drawingMode == .text, let handler = textAnnotationHandler {
            if handler.handleTouchBegan(touch) { return }
        }

        let location = touch.location(in: self)
        let point: CGPoint
        if useNormalizedCoordinates && !contentRect.isEmpty {
            point = CGPoint(x: location.x / contentRect.width, y: location.y / contentRect.height)
        } else {
            point = location
        }
        controller.handleTouchBegan(point, page: pageIndex, contentRect: contentRect)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let controller = drawingController,
              controller.drawingMode != .view,
              let touch = touches.first else {
            super.touchesMoved(touches, with: event)
            return
        }

        // Multiple fingers — cancel any active drawing
        if let allTouches = event?.allTouches, allTouches.count > 1 {
            if controller.isDrawing {
                controller.handleTouchCancelled()
            }
            return
        }

        // Handle text dragging
        if let handler = textAnnotationHandler, handler.isDraggingText {
            handler.handleTouchMoved(touch)
            return
        }

        let location = touch.location(in: self)
        let point: CGPoint
        if useNormalizedCoordinates && !contentRect.isEmpty {
            point = CGPoint(x: location.x / contentRect.width, y: location.y / contentRect.height)
        } else {
            point = location
        }
        controller.handleTouchMoved(point, page: pageIndex, contentRect: contentRect)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let controller = drawingController,
              controller.drawingMode != .view,
              let touch = touches.first else {
            super.touchesEnded(touches, with: event)
            return
        }

        if let handler = textAnnotationHandler, handler.isDraggingText {
            handler.handleTouchEnded(touch)
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

        if let handler = textAnnotationHandler, handler.isDraggingText {
            handler.handleTouchCancelled()
            return
        }

        controller.handleTouchCancelled()
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let controller = drawingController else {
            return nil
        }

        // In multi-page mode, let parent view handle touches
        if multiPageMode {
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

        // In multi-page mode, let parent view handle touches
        if multiPageMode {
            return false
        }

        // Only claim touches when in drawing mode
        return controller.drawingMode != .view && super.point(inside: point, with: event)
    }
}
