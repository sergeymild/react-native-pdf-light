import UIKit

// MARK: - Tap Zone Helper

enum TapZone {
    case left, middle, right
}

func classifyTapZone(point: CGPoint, in bounds: CGRect, edgeTapZone: CGFloat) -> TapZone {
    let edgeRatio = edgeTapZone / 100.0
    let leftEdge = bounds.width * edgeRatio
    let rightEdge = bounds.width * (1.0 - edgeRatio)
    if point.x < leftEdge { return .left }
    if point.x > rightEdge { return .right }
    return .middle
}

// MARK: - Content Inset Helper

func centeredContentInset(for scrollView: UIScrollView, extraTop: CGFloat = 0, extraBottom: CGFloat = 0) -> UIEdgeInsets {
    let scrollViewSize = scrollView.bounds.size
    let contentSize = scrollView.contentSize
    let scale = scrollView.zoomScale

    let scaledContentWidth = contentSize.width * scale
    let scaledContentHeight = contentSize.height * scale

    let horizontalInset = max(0, (scrollViewSize.width - scaledContentWidth) / 2)
    let verticalInset = max(0, (scrollViewSize.height - scaledContentHeight) / 2)

    return UIEdgeInsets(
        top: verticalInset + extraTop,
        left: horizontalInset,
        bottom: verticalInset + extraBottom,
        right: horizontalInset
    )
}

// MARK: - PdfViewerBase

/// Base class for PagingPdfView and ZoomablePdfScrollView.
/// Contains shared React props, PDF loading, annotation parsing, drawing controller, and stroke management.
@objc(PdfViewerBase) @objcMembers
class PdfViewerBase: UIView, DrawingControllerDelegate {

    // MARK: - React Props

    @objc var source = "" { didSet { reloadPdf() } }

    @objc var annotations = "" {
        didSet {
            parseAnnotations()
            imageCache.removeAllObjects()
            onAnnotationsChanged()
        }
    }

    @objc var minZoom: CGFloat = 1.0 { didSet { updateZoomLimits() } }
    @objc var maxZoom: CGFloat = 3.0 { didSet { updateZoomLimits() } }
    @objc var edgeTapZone: CGFloat = 15.0

    @objc var pdfBackgroundColor: UIColor = UIColor(white: 0.2, alpha: 1.0) {
        didSet { updateBackgroundColor() }
    }

    // MARK: - Drawing Props

    @objc var drawingMode = "view" { didSet { applyDrawingMode() } }
    @objc var strokeColor = "#000000" { didSet { drawingController.strokeColor = strokeColor } }
    @objc var strokeWidth: CGFloat = 3.0 { didSet { drawingController.strokeWidth = strokeWidth } }
    @objc var strokeOpacity: CGFloat = 1.0 { didSet { drawingController.strokeOpacity = strokeOpacity } }
    @objc var strokes = "" { didSet { loadStrokes() } }

    // MARK: - React Events

    @objc var onPdfError: RCTDirectEventBlock?
    @objc var onPdfLoadComplete: RCTDirectEventBlock? {
        didSet {
            if let pending = pendingLoadCompleteEvent {
                onPdfLoadComplete?(pending)
                pendingLoadCompleteEvent = nil
            }
        }
    }
    @objc var onPageChange: RCTDirectEventBlock?
    @objc var onZoomChange: RCTDirectEventBlock?
    @objc var onTap: RCTDirectEventBlock?
    @objc var onMiddleClick: RCTDirectEventBlock?
    @objc var onDrawingStart: RCTDirectEventBlock?
    @objc var onDrawingEnd: RCTDirectEventBlock?
    @objc var onUndoStateChange: RCTDirectEventBlock?

    // MARK: - Text Annotation Props

    @objc var textColor = "#0000FF" { didSet { textAnnotationHandler.textColor = textColor } }
    @objc var textFontSize: CGFloat = 16.0 { didSet { textAnnotationHandler.textFontSize = textFontSize } }

    // MARK: - Internal State (accessible to subclasses)

    private var pendingLoadCompleteEvent: [String: Any]?
    private(set) var pdfDocument: CGPDFDocument?
    var currentPage: Int = 0
    private var isReloading = false
    private(set) var actualPageCount: Int = 0

    private(set) var pdfPageWidth: CGFloat = 0
    private(set) var pdfPageHeight: CGFloat = 0

    let imageCache = NSCache<NSNumber, UIImage>()
    private(set) var parsedAnnotations: [AnnotationPage] = []

    let drawingController = DrawingController()
    var realDrawingMode = DrawingMode.view
    let textAnnotationHandler = TextAnnotationHandler()

    var previousBoundsWidth: CGFloat = 0

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = pdfBackgroundColor
        drawingController.delegate = self
        setupViews()
    }

    // MARK: - Override Points (subclasses must call super where noted)

    /// Setup viewer-specific views. Called once during init.
    /// Subclasses should set imageCache.countLimit here.
    func setupViews() {
        // Override in subclass
    }

    /// Called after PDF document loaded and dimensions extracted.
    func onPdfLoaded() {
        // Override in subclass
    }

    /// Called after annotations prop changed and parsed.
    func onAnnotationsChanged() {
        // Override in subclass
    }

    /// Called when minZoom/maxZoom changes.
    func updateZoomLimits() {
        // Override in subclass
    }

    /// Called when pdfBackgroundColor changes.
    func updateBackgroundColor() {
        backgroundColor = pdfBackgroundColor
    }

    /// Called after common drawing mode logic (realDrawingMode set, drawingController updated,
    /// text input dismissed). Subclass should update gestures/scroll here.
    func onDrawingModeChanged(_ mode: DrawingMode) {
        // Override in subclass
    }

    /// Called when the drawing overlay needs a redraw.
    func redrawCurrentOverlay() {
        // Override in subclass
    }

    // MARK: - PDF Loading

    func reloadPdf() {
        guard !source.isEmpty, !isReloading else { return }
        isReloading = true

        imageCache.removeAllObjects()
        pdfDocument = nil

        let url = URL(fileURLWithPath: source)
        guard let document = CGPDFDocument(url as CFURL) else {
            onPdfError?(["message": "Failed to open PDF: \(source)"])
            isReloading = false
            return
        }

        pdfDocument = document

        if let firstPage = document.page(at: 1) {
            let dims = firstPage.effectiveDimensions
            pdfPageWidth = dims.width
            pdfPageHeight = dims.height
        }

        actualPageCount = document.numberOfPages
        isReloading = false

        onPdfLoaded()

        let loadCompleteEvent: [String: Any] = [
            "width": pdfPageWidth,
            "height": pdfPageHeight,
            "pageCount": actualPageCount
        ]
        if let callback = onPdfLoadComplete {
            callback(loadCompleteEvent)
        } else {
            pendingLoadCompleteEvent = loadCompleteEvent
        }
    }

    // MARK: - Annotations

    private func parseAnnotations() {
        guard !annotations.isEmpty,
              let data = annotations.data(using: .utf8) else {
            parsedAnnotations = []
            return
        }

        do {
            parsedAnnotations = try JSONDecoder().decode([AnnotationPage].self, from: data)
        } catch {
            parsedAnnotations = []
        }
    }

    // MARK: - PDF Rendering

    func renderPage(at index: Int, completion: @escaping (UIImage?) -> Void) {
        guard let document = pdfDocument else {
            completion(nil)
            return
        }

        let annotation = index < parsedAnnotations.count ? parsedAnnotations[index] : nil

        PdfPageRenderer.renderPage(
            document: document,
            pageIndex: index,
            viewWidth: bounds.width,
            pdfPageWidth: pdfPageWidth,
            pdfPageHeight: pdfPageHeight,
            annotation: annotation,
            completion: completion
        )
    }

    // MARK: - Drawing Mode

    private func applyDrawingMode() {
        guard let mode = DrawingMode(rawValue: drawingMode) else {
            realDrawingMode = .view
            drawingController.drawingMode = .view
            return
        }
        realDrawingMode = mode
        drawingController.drawingMode = mode

        if mode != .text {
            textAnnotationHandler.commitTextInput()
        }

        onDrawingModeChanged(mode)
    }

    // MARK: - Strokes

    private func loadStrokes() {
        guard !strokes.isEmpty else {
            drawingController.clearAllStrokes()
            redrawCurrentOverlay()
            return
        }

        do {
            let data = strokes.data(using: .utf8)!
            let pageStrokes = try JSONDecoder().decode(PageStrokes.self, from: data)
            drawingController.setAllStrokes(pageStrokes)
            redrawCurrentOverlay()
        } catch {
            onPdfError?(["message": "Failed to parse strokes: \(error.localizedDescription)"])
        }
    }

    // MARK: - Public Commands

    func resetZoom() {
        // Override in subclass
    }

    func scrollToPage(_ page: Int, animated: Bool) {
        // Override in subclass
    }

    func undo() {
        drawingController.undo()
    }

    func redo() {
        drawingController.redo()
    }

    func clearStrokes(page: Int) {
        if page >= 0 {
            drawingController.clearStrokes(forPage: page)
            drawingController.clearTexts(forPage: page)
        } else {
            drawingController.clearAllStrokes()
            drawingController.clearAllTexts()
        }
        redrawCurrentOverlay()
    }

    func getAnnotations() -> [String: Any] {
        return drawingController.getAnnotationsForExport()
    }

    func loadAnnotations(_ json: String) {
        guard !json.isEmpty,
              let data = json.data(using: .utf8) else {
            print("[loadAnnotations] Empty or invalid JSON")
            return
        }

        do {
            let pages = try JSONDecoder().decode([AnnotationPage].self, from: data)
            print("[loadAnnotations] Parsed \(pages.count) pages")
            drawingController.clearAllStrokes()
            drawingController.clearAllTexts()

            for (pageIndex, page) in pages.enumerated() {
                let drawingStrokes = page.strokes.map { stroke in
                    DrawingStroke(
                        id: UUID().uuidString,
                        color: stroke.color,
                        width: stroke.width,
                        opacity: stroke.opacity ?? 1.0,
                        path: stroke.path
                    )
                }
                drawingController.setStrokes(drawingStrokes, forPage: pageIndex)

                for text in page.text {
                    guard text.point.count >= 2 else { continue }
                    let drawingText = DrawingText(
                        id: UUID().uuidString,
                        color: text.color,
                        fontSize: text.fontSize,
                        point: text.point,
                        str: text.str
                    )
                    drawingController.addText(drawingText, toPage: pageIndex)
                }

                if !page.strokes.isEmpty || !page.text.isEmpty {
                    print("[loadAnnotations] Page \(pageIndex): \(drawingStrokes.count) strokes, \(page.text.count) texts")
                    if let first = drawingStrokes.first, let firstPoint = first.path.first {
                        print("[loadAnnotations]   first stroke path[0]=\(firstPoint)")
                    }
                }
            }
            drawingController.clearUndoStack()
            redrawCurrentOverlay()
            print("[loadAnnotations] Done, overlay redrawn")
        } catch {
            print("[loadAnnotations] Parse error: \(error)")
            onPdfError?(["message": "Failed to parse loadAnnotations: \(error.localizedDescription)"])
        }
    }

    func clearCache() {
        imageCache.removeAllObjects()
    }

    // MARK: - DrawingControllerDelegate

    func drawingController(_ controller: DrawingController, didAddStroke stroke: DrawingStroke, onPage page: Int) {}

    func drawingController(_ controller: DrawingController, didRemoveStroke strokeId: String, onPage page: Int) {}

    func drawingController(_ controller: DrawingController, strokesCleared onPage: Int) {}

    func drawingControllerDidStartDrawing(_ controller: DrawingController) {
        onDrawingStart?([:])
    }

    func drawingControllerDidEndDrawing(_ controller: DrawingController) {
        onDrawingEnd?([:])
    }

    func drawingControllerNeedsRedraw(_ controller: DrawingController) {
        redrawCurrentOverlay()
    }

    func drawingController(_ controller: DrawingController, didRequestTextInputAt normalizedPoint: CGPoint, onPage page: Int) {
        // Handled by TextAnnotationHandler via touch interception
    }

    func drawingController(_ controller: DrawingController, undoStateChanged canUndo: Bool, canRedo: Bool) {
        onUndoStateChange?(["canUndo": canUndo, "canRedo": canRedo])
    }
}
