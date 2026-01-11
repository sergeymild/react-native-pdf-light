import UIKit

// MARK: - ZoomablePdfScrollView (scrollable PDF viewer with global zoom using UICollectionView)

class ZoomablePdfScrollView: UIView, UIScrollViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate, DrawingControllerDelegate {

    // MARK: - React Props

    @objc var source = "" { didSet { reloadPdf() } }

    @objc var annotations = "" {
        didSet {
            parseAnnotations()
            imageCache.removeAllObjects()
            collectionView?.reloadData()
        }
    }

    @objc var minZoom: CGFloat = 1.0 { didSet { updateZoomLimits() } }
    @objc var maxZoom: CGFloat = 3.0 { didSet { updateZoomLimits() } }
    @objc var edgeTapZone: CGFloat = 15.0
    @objc var pdfPaddingTop: CGFloat = 0.0 { didSet { updateContentInset() } }
    @objc var pdfPaddingBottom: CGFloat = 0.0 { didSet { updateContentInset() } }

    @objc var pdfBackgroundColor: UIColor = UIColor(white: 0.2, alpha: 1.0) {
        didSet { updateBackgroundColor() }
    }

    // MARK: - Drawing Props

    @objc var drawingMode = "view" { didSet { updateDrawingMode() } }
    @objc var strokeColor = "#000000" { didSet { drawingController.strokeColor = strokeColor } }
    @objc var strokeWidth: CGFloat = 3.0 { didSet { drawingController.strokeWidth = strokeWidth } }
    @objc var strokeOpacity: CGFloat = 1.0 { didSet { drawingController.strokeOpacity = strokeOpacity } }
    @objc var strokes = "" { didSet { loadStrokes() } }

    // MARK: - React Events

    @objc var onPdfError: RCTDirectEventBlock?
    @objc var onPdfLoadComplete: RCTDirectEventBlock? {
        didSet {
            // Send pending load complete event if PDF was loaded before callback was set
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

    // Drawing events
    @objc var onDrawingStart: RCTDirectEventBlock?
    @objc var onDrawingEnd: RCTDirectEventBlock?

    // Store load complete event if callback not yet set
    private var pendingLoadCompleteEvent: [String: Any]?

    // MARK: - Private State

    private let scrollView = UIScrollView()
    private let contentContainer = UIView() // Container for both collectionView and drawingOverlay
    private var collectionView: UICollectionView!
    private var pdfDocument: CGPDFDocument?
    private var currentPage: Int = 0
    private var isReloading = false
    private var actualPageCount: Int = 0

    // PDF dimensions (from first page)
    private var pdfPageWidth: CGFloat = 0
    private var pdfPageHeight: CGFloat = 0

    // Image cache
    private var imageCache = NSCache<NSNumber, UIImage>()

    // Parsed annotations
    private var parsedAnnotations: [AnnotationPage] = []

    // Gesture recognizers
    private var doubleTapGesture: UITapGestureRecognizer!
    private var edgeTapGesture: UITapGestureRecognizer!
    private var middleTapGesture: UITapGestureRecognizer!

    // Drawing controller
    private let drawingController = DrawingController()
    private var realDrawingMode = DrawingMode.view
    private let drawingOverlay = DrawingOverlayView()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        backgroundColor = pdfBackgroundColor
        imageCache.countLimit = 10 // Cache up to 10 rendered pages

        // Setup drawing controller
        drawingController.delegate = self

        // Setup outer scroll view (for zooming)
        scrollView.delegate = self
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = maxZoom
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        addSubview(scrollView)

        // Setup collection view layout
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0

        // Setup content container (this is what gets zoomed)
        contentContainer.backgroundColor = .clear
        scrollView.addSubview(contentContainer)

        // Setup collection view inside container
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.register(PdfPageCell.self, forCellWithReuseIdentifier: PdfPageCell.reuseId)
        contentContainer.addSubview(collectionView)

        // Setup drawing overlay on top of collection view (inside same container so it zooms together)
        drawingOverlay.drawingController = drawingController
        drawingOverlay.useNormalizedCoordinates = true
        drawingOverlay.multiPageMode = true
        contentContainer.addSubview(drawingOverlay)

        // Double tap to zoom (only works in middle zone)
        doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.delegate = self
        addGestureRecognizer(doubleTapGesture)

        // Edge tap - no delay (doesn't wait for double tap to fail)
        edgeTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleEdgeTap(_:)))
        edgeTapGesture.numberOfTapsRequired = 1
        edgeTapGesture.delegate = self
        addGestureRecognizer(edgeTapGesture)

        // Middle tap - waits for double tap to fail
        middleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMiddleTap(_:)))
        middleTapGesture.numberOfTapsRequired = 1
        middleTapGesture.require(toFail: doubleTapGesture)
        middleTapGesture.delegate = self
        addGestureRecognizer(middleTapGesture)
    }

    // MARK: - Tap Handling

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        // Toggle zoom: if zoomed in, reset to 1.0; otherwise zoom to maxZoom
        if scrollView.zoomScale > minZoom {
            UIView.animate(withDuration: 0.3) {
                self.scrollView.zoomScale = self.minZoom
            }
        } else {
            // Zoom to point
            let zoomRect = zoomRectForScale(maxZoom, center: gesture.location(in: contentContainer))
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }

    @objc private func handleEdgeTap(_ gesture: UITapGestureRecognizer) {
        // Ignore edge taps in drawing modes
        guard drawingController.drawingMode == .view else { return }

        let tapLocation = gesture.location(in: self)

        let viewportHeight = bounds.height
        let scale = scrollView.zoomScale

        // Account for content insets (including pdfPaddingTop/Bottom)
        let inset = scrollView.contentInset
        let minOffset = -inset.top
        let maxOffset = scrollView.contentSize.height * scale - viewportHeight + inset.bottom

        let edgeRatio = edgeTapZone / 100.0
        let leftEdge = bounds.width * edgeRatio

        // Calculate page height
        guard pdfPageWidth > 0, pdfPageHeight > 0 else { return }
        let pageHeight = bounds.width * (pdfPageHeight / pdfPageWidth) * scale

        // Check device orientation: portrait (height > width) or landscape (width >= height)
        let isPortraitMode = bounds.height > bounds.width

        let currentOffset = scrollView.contentOffset.y

        if isPortraitMode {
            // Portrait mode: scroll page by page, centering each page
            let centerY = (currentOffset + inset.top) + viewportHeight / 2
            let currentCenteredPage = Int(centerY / pageHeight)

            if tapLocation.x < leftEdge {
                // Left zone - go to previous page
                let targetPage = max(0, currentCenteredPage - 1)
                let targetOffset = offsetToCenterPage(targetPage, pageHeight: pageHeight, viewportHeight: viewportHeight, insetTop: inset.top)
                let clampedOffset = max(minOffset, min(maxOffset, targetOffset))
                UIView.animate(withDuration: 0.3) {
                    self.scrollView.contentOffset = CGPoint(x: 0, y: clampedOffset)
                }
            } else {
                // Right zone - go to next page
                let targetPage = min(actualPageCount - 1, currentCenteredPage + 1)
                let targetOffset = offsetToCenterPage(targetPage, pageHeight: pageHeight, viewportHeight: viewportHeight, insetTop: inset.top - pdfPaddingTop)
                let clampedOffset = max(minOffset, min(maxOffset, targetOffset))
                UIView.animate(withDuration: 0.3) {
                    self.scrollView.contentOffset = CGPoint(x: 0, y: clampedOffset)
                }
            }
        } else {
            // Landscape mode: scroll by viewport height
            if tapLocation.x < leftEdge {
                // Left zone - scroll up by viewport
                let newOffset = max(minOffset, currentOffset - viewportHeight)
                UIView.animate(withDuration: 0.3) {
                    self.scrollView.contentOffset = CGPoint(x: 0, y: newOffset)
                }
            } else {
                // Right zone - scroll down by viewport
                let newOffset = min(maxOffset, currentOffset + viewportHeight)
                UIView.animate(withDuration: 0.3) {
                    self.scrollView.contentOffset = CGPoint(x: 0, y: newOffset)
                }
            }
        }

        onTap?(["position": tapLocation.x < leftEdge ? "left" : "right"])
    }

    private func offsetToCenterPage(_ page: Int, pageHeight: CGFloat, viewportHeight: CGFloat, insetTop: CGFloat) -> CGFloat {
        // Center of page N is at: page * pageHeight + pageHeight / 2
        // To center it in viewport: centerOfPage - viewportHeight / 2 - insetTop
        let pageCenterY = CGFloat(page) * pageHeight + pageHeight / 2
        return pageCenterY - viewportHeight / 2 - insetTop
    }

    @objc private func handleMiddleTap(_ gesture: UITapGestureRecognizer) {
        onMiddleClick?([:])
    }

    private func zoomRectForScale(_ scale: CGFloat, center: CGPoint) -> CGRect {
        let size = CGSize(
            width: scrollView.bounds.width / scale,
            height: scrollView.bounds.height / scale
        )
        let origin = CGPoint(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2
        )
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Layout

    private var previousBoundsWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()

        scrollView.frame = bounds

        // Clear cache if width changed (rotation)
        if bounds.width != previousBoundsWidth && previousBoundsWidth > 0 {
            imageCache.removeAllObjects()
            collectionView.reloadData()
        }
        previousBoundsWidth = bounds.width

        updateCollectionViewSize()
    }

    private func updateCollectionViewSize() {
        guard bounds.width > 0, pdfPageWidth > 0, pdfPageHeight > 0 else { return }

        let viewWidth = bounds.width
        let pageHeight = viewWidth * (pdfPageHeight / pdfPageWidth)
        let totalHeight = (pageHeight) * CGFloat(actualPageCount)

        // Update container frame
        contentContainer.frame = CGRect(x: 0, y: 0, width: viewWidth, height: totalHeight)

        // Collection view fills the container
        collectionView.frame = contentContainer.bounds
        scrollView.contentSize = CGSize(width: viewWidth, height: totalHeight)

        // Update drawing overlay to match container
        drawingOverlay.frame = contentContainer.bounds
        drawingOverlay.pageCount = actualPageCount
        drawingOverlay.pageHeight = pageHeight
        drawingOverlay.setNeedsDisplay()

        // Invalidate layout to recalculate cell sizes
        collectionView.collectionViewLayout.invalidateLayout()

        updateContentInset()
    }

    private func updateLayout() {
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.minimumLineSpacing = 0
        }
        updateCollectionViewSize()
    }

    private func updateContentInset() {
        let scrollViewSize = scrollView.bounds.size
        let contentSize = scrollView.contentSize
        let scale = scrollView.zoomScale

        let scaledContentWidth = contentSize.width * scale
        let scaledContentHeight = contentSize.height * scale

        let horizontalInset = max(0, (scrollViewSize.width - scaledContentWidth) / 2)
        let verticalInset = max(0, (scrollViewSize.height - scaledContentHeight) / 2)

        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset + pdfPaddingTop,
            left: horizontalInset,
            bottom: verticalInset + pdfPaddingBottom,
            right: horizontalInset
        )
    }

    private func updateZoomLimits() {
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = maxZoom
    }

    private func updateBackgroundColor() {
        backgroundColor = pdfBackgroundColor
    }

    // MARK: - Drawing Mode

    private func updateDrawingMode() {
        guard let mode = DrawingMode(rawValue: drawingMode) else {
            realDrawingMode = .view
            drawingController.drawingMode = .view
            return
        }
        realDrawingMode = mode
        drawingController.drawingMode = mode

        // Disable all scroll/zoom gestures in drawing modes (draw, erase, highlight)
        let isViewMode = mode == .view
        scrollView.isScrollEnabled = isViewMode
        scrollView.pinchGestureRecognizer?.isEnabled = isViewMode
        doubleTapGesture.isEnabled = isViewMode
    }

    private func loadStrokes() {
        guard !strokes.isEmpty else {
            drawingController.clearAllStrokes()
            drawingOverlay.setNeedsDisplay()
            return
        }

        do {
            let data = strokes.data(using: .utf8)!
            let pageStrokes = try JSONDecoder().decode(PageStrokes.self, from: data)
            drawingController.setAllStrokes(pageStrokes)
            drawingOverlay.setNeedsDisplay()
        } catch {
            onPdfError?(["message": "Failed to parse strokes: \(error.localizedDescription)"])
        }
    }

    // MARK: - Page Detection for Drawing

    /// Determine which page a point in the collection view belongs to
    private func pageIndexForPoint(_ point: CGPoint) -> Int {
        guard pdfPageWidth > 0, pdfPageHeight > 0, actualPageCount > 0 else { return 0 }

        let pageHeight = bounds.width * (pdfPageHeight / pdfPageWidth)
        let pageIndex = Int(point.y / pageHeight)
        return max(0, min(pageIndex, actualPageCount - 1))
    }

    /// Get the content rect for a specific page (in collection view coordinates)
    private func contentRectForPage(_ page: Int) -> CGRect {
        guard pdfPageWidth > 0, pdfPageHeight > 0 else { return .zero }

        let pageHeight = bounds.width * (pdfPageHeight / pdfPageWidth)
        return CGRect(
            x: 0,
            y: CGFloat(page) * pageHeight,
            width: bounds.width,
            height: pageHeight
        )
    }

    // MARK: - DrawingControllerDelegate

    func drawingController(_ controller: DrawingController, didAddStroke stroke: DrawingStroke, onPage page: Int) {
        // Strokes are stored natively, no sync needed
    }

    func drawingController(_ controller: DrawingController, didRemoveStroke strokeId: String, onPage page: Int) {
        // Strokes are stored natively, no sync needed
    }

    func drawingController(_ controller: DrawingController, strokesCleared onPage: Int) {
        // Strokes are stored natively, no sync needed
    }

    func drawingControllerDidStartDrawing(_ controller: DrawingController) {
        onDrawingStart?([:])
    }

    func drawingControllerDidEndDrawing(_ controller: DrawingController) {
        onDrawingEnd?([:])
    }

    func drawingControllerNeedsRedraw(_ controller: DrawingController) {
        // For CATiledLayer, we need to invalidate the visible tiles
        let visibleRect = CGRect(
            x: 0,
            y: scrollView.contentOffset.y / scrollView.zoomScale,
            width: bounds.width,
            height: bounds.height / scrollView.zoomScale
        )
        drawingOverlay.layer.setNeedsDisplay(visibleRect)
    }

    // MARK: - PDF Loading

    private func reloadPdf() {
        guard !source.isEmpty, !isReloading else { return }
        isReloading = true

        // Clear cache
        imageCache.removeAllObjects()
        pdfDocument = nil

        // Load PDF document
        let url = URL(fileURLWithPath: source)
        guard let document = CGPDFDocument(url as CFURL) else {
            onPdfError?(["message": "Failed to open PDF: \(source)"])
            isReloading = false
            return
        }

        pdfDocument = document

        // Get dimensions from first page
        if let firstPage = document.page(at: 1) {
            let pageBounds = firstPage.getBoxRect(.cropBox)
            if firstPage.rotationAngle % 180 == 90 {
                pdfPageWidth = pageBounds.height
                pdfPageHeight = pageBounds.width
            } else {
                pdfPageWidth = pageBounds.width
                pdfPageHeight = pageBounds.height
            }
        }

        actualPageCount = document.numberOfPages

        isReloading = false
        collectionView.reloadData()
        updateCollectionViewSize()

        // Notify load complete
        let loadCompleteEvent: [String: Any] = [
            "width": pdfPageWidth,
            "height": pdfPageHeight,
            "pageCount": actualPageCount
        ]
        if let callback = onPdfLoadComplete {
            callback(loadCompleteEvent)
        } else {
            // Store for later when callback is set (race condition workaround)
            pendingLoadCompleteEvent = loadCompleteEvent
        }
    }

    // MARK: - UICollectionViewDataSource

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return actualPageCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PdfPageCell.reuseId, for: indexPath) as! PdfPageCell

        // Check cache first
        if let cachedImage = imageCache.object(forKey: NSNumber(value: indexPath.item)) {
            cell.setImage(cachedImage)
        } else {
            cell.setImage(nil) // Clear while loading
            renderPage(at: indexPath.item) { [weak self] image in
                guard let self, let image else { return }
                self.imageCache.setObject(image, forKey: NSNumber(value: indexPath.item))
                // Only update if cell is still visible for this index
                if let currentCell = self.collectionView.cellForItem(at: indexPath) as? PdfPageCell {
                    currentCell.setImage(image)
                }
            }
        }

        return cell
    }

    // MARK: - UICollectionViewDelegateFlowLayout

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard pdfPageWidth > 0, pdfPageHeight > 0 else {
            return CGSize(width: bounds.width, height: bounds.height)
        }

        let viewWidth = bounds.width
        let pageHeight = viewWidth * (pdfPageHeight / pdfPageWidth)
        return CGSize(width: viewWidth, height: pageHeight)
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return contentContainer
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentInset()
        // Update drawing overlay zoom scale for consistent stroke width
        drawingOverlay.zoomScale = scrollView.zoomScale
        drawingOverlay.setNeedsDisplay()
        onZoomChange?(["scale": scrollView.zoomScale])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateCurrentPage()
    }

    private func updateCurrentPage() {
        guard bounds.width > 0, pdfPageWidth > 0, pdfPageHeight > 0, actualPageCount > 0 else { return }

        let pageHeight = bounds.width * (pdfPageHeight / pdfPageWidth)
        let pageWithSpacing = pageHeight
        let scale = scrollView.zoomScale

        // Calculate center point in content coordinates
        let centerY = (scrollView.contentOffset.y + scrollView.bounds.height / 2) / scale
        let newPage = Int(centerY / pageWithSpacing)
        let clampedPage = max(0, min(newPage, actualPageCount - 1))

        if clampedPage != currentPage {
            currentPage = clampedPage
            onPageChange?(["page": currentPage])
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

    private func renderPage(at index: Int, completion: @escaping (UIImage?) -> Void) {
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

    // MARK: - Public Commands

    func resetZoom() {
        UIView.animate(withDuration: 0.3) {
            self.scrollView.zoomScale = 1.0
        }
    }

    func scrollToPage(_ page: Int, animated: Bool) {
        guard page >= 0, page < actualPageCount else { return }

        let pageHeight = bounds.width * (pdfPageHeight / pdfPageWidth)
        let pageWithSpacing = pageHeight
        let yOffset = CGFloat(page) * pageWithSpacing

        scrollView.setContentOffset(CGPoint(x: 0, y: yOffset * scrollView.zoomScale), animated: animated)
    }

    func clearStrokes(page: Int) {
        if page >= 0 {
            drawingController.clearStrokes(forPage: page)
        } else {
            // Clear all pages
            drawingController.clearAllStrokes()
        }
        drawingOverlay.setNeedsDisplay()
    }

    /// Get all annotations (strokes) from all pages
    func getAnnotations() -> [String: Any] {
        return drawingController.getAnnotationsForExport()
    }

    // MARK: - Cleanup

    func clearCache() {
        imageCache.removeAllObjects()
    }

    // MARK: - Touch Handling for Drawing

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // In view mode, use default behavior
        guard realDrawingMode != .view else {
            return super.hitTest(point, with: event)
        }

        // In drawing mode, only intercept if point is within bounds
        guard bounds.contains(point) else {
            return nil
        }

        // Check if any subview wants this touch (could be a button or other control)
        // We only intercept touches on the scrollView/content area, not on any overlay controls
        for subview in subviews.reversed() {
            if subview == scrollView { continue } // We'll handle scrollView specially
            let pointInSubview = convert(point, to: subview)
            if let hitView = subview.hitTest(pointInSubview, with: event) {
                return hitView // Let the subview handle it
            }
        }

        // Touch is in our bounds and no subview claimed it - intercept for drawing
        return self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard realDrawingMode != .view, let touch = touches.first else {
            super.touchesBegan(touches, with: event)
            return
        }

        let location = touch.location(in: contentContainer)
        let page = pageIndexForPoint(location)
        let pageRect = contentRectForPage(page)

        // Convert to page-local coordinates then normalize to 0-1
        let localX = location.x / pageRect.width
        let localY = (location.y - pageRect.minY) / pageRect.height
        let normalizedPoint = CGPoint(x: localX, y: localY)

        drawingOverlay.pageIndex = page
        drawingOverlay.contentRect = pageRect

        drawingController.handleTouchBegan(normalizedPoint, page: page, contentRect: pageRect)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard realDrawingMode != .view, let touch = touches.first else {
            super.touchesMoved(touches, with: event)
            return
        }

        let location = touch.location(in: contentContainer)
        let page = pageIndexForPoint(location)
        let pageRect = contentRectForPage(page)

        // Convert to page-local coordinates then normalize to 0-1
        let localX = location.x / pageRect.width
        let localY = (location.y - pageRect.minY) / pageRect.height
        let normalizedPoint = CGPoint(x: localX, y: localY)

        drawingController.handleTouchMoved(normalizedPoint, page: page, contentRect: pageRect)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard realDrawingMode != .view, let touch = touches.first else {
            super.touchesEnded(touches, with: event)
            return
        }

        let location = touch.location(in: contentContainer)
        let page = pageIndexForPoint(location)

        drawingController.handleTouchEnded(page: page)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard realDrawingMode != .view else {
            super.touchesCancelled(touches, with: event)
            return
        }

        drawingController.handleTouchCancelled()
    }

    // MARK: - UIGestureRecognizerDelegate

  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Disable all tap gestures in drawing mode
        if realDrawingMode != .view {
            if gestureRecognizer === edgeTapGesture ||
               gestureRecognizer === middleTapGesture ||
               gestureRecognizer === doubleTapGesture {
                return false
            }
        }

        let tapLocation = gestureRecognizer.location(in: self)
        let edgeRatio = edgeTapZone / 100.0
        let leftEdge = bounds.width * edgeRatio
        let rightEdge = bounds.width * (1.0 - edgeRatio)

        let isInEdgeZone = tapLocation.x < leftEdge || tapLocation.x > rightEdge
        let isInMiddleZone = tapLocation.x >= leftEdge && tapLocation.x <= rightEdge

        // Edge tap only in edge zones AND when not zoomed AND in view mode
        if gestureRecognizer === edgeTapGesture {
            return isInEdgeZone && scrollView.zoomScale <= minZoom + 0.01 && drawingController.drawingMode == .view
        }

        // Middle tap and double tap only in middle zone
        if gestureRecognizer === middleTapGesture || gestureRecognizer === doubleTapGesture {
            return isInMiddleZone
        }

        return true
    }
}

// MARK: - PdfPageCell

private class PdfPageCell: UICollectionViewCell {
    static let reuseId = "PdfPageCell"

    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        contentView.backgroundColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)
    }

    func setImage(_ image: UIImage?) {
        imageView.image = image
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
    }
}
