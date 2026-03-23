import UIKit

// MARK: - ZoomablePdfScrollView (scrollable PDF viewer with global zoom using UICollectionView)

class ZoomablePdfScrollView: PdfViewerBase, UIScrollViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate, TextAnnotationHandlerDelegate {

    // MARK: - Additional Props (Zoomable-only)

    @objc var pdfPaddingTop: CGFloat = 0.0 { didSet { updateContentInset() } }
    @objc var pdfPaddingBottom: CGFloat = 0.0 { didSet { updateContentInset() } }

    // MARK: - Computed Helpers

    private var unscaledPageHeight: CGFloat {
        guard pdfPageWidth > 0 else { return 0 }
        return bounds.width * (pdfPageHeight / pdfPageWidth)
    }

    // MARK: - Private State

    private let scrollView = UIScrollView()
    private let contentContainer = UIView()
    private var collectionView: UICollectionView!
    private let drawingOverlay = DrawingOverlayView()

    // Gesture recognizers
    private var doubleTapGesture: UITapGestureRecognizer!
    private var edgeTapGesture: UITapGestureRecognizer!
    private var middleTapGesture: UITapGestureRecognizer!
    private var drawingPinchGesture: UIPinchGestureRecognizer!
    private var drawingPanGesture: UIPanGestureRecognizer!

    // MARK: - Setup

    override func setupViews() {
        imageCache.countLimit = 10

        // Setup text annotation handler
        textAnnotationHandler.delegate = self

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

        // Setup drawing overlay on top of collection view
        drawingOverlay.drawingController = drawingController
        drawingOverlay.useNormalizedCoordinates = true
        drawingOverlay.multiPageMode = true
        contentContainer.addSubview(drawingOverlay)

        // Double tap to zoom (only works in middle zone)
        doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.delegate = self
        addGestureRecognizer(doubleTapGesture)

        // Edge tap - no delay
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

        // Pinch gesture for zooming while in drawing mode
        drawingPinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handleDrawingPinch(_:)))
        drawingPinchGesture.delegate = self
        drawingPinchGesture.delaysTouchesBegan = false
        drawingPinchGesture.isEnabled = false
        addGestureRecognizer(drawingPinchGesture)

        // 2-finger pan for scrolling while in drawing mode
        drawingPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDrawingPan(_:)))
        drawingPanGesture.minimumNumberOfTouches = 2
        drawingPanGesture.maximumNumberOfTouches = 2
        drawingPanGesture.delegate = self
        drawingPanGesture.delaysTouchesBegan = false
        drawingPanGesture.isEnabled = false
        addGestureRecognizer(drawingPanGesture)
    }

    // MARK: - Override Points

    override func onPdfLoaded() {
        collectionView.reloadData()
        updateCollectionViewSize()
    }

    override func onAnnotationsChanged() {
        collectionView?.reloadData()
    }

    override func updateZoomLimits() {
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = maxZoom
    }

    override func onDrawingModeChanged(_ mode: DrawingMode) {
        let isViewMode = mode == .view
        scrollView.isScrollEnabled = isViewMode
        scrollView.pinchGestureRecognizer?.isEnabled = isViewMode
        doubleTapGesture.isEnabled = isViewMode
        drawingPinchGesture.isEnabled = !isViewMode
        drawingPanGesture.isEnabled = !isViewMode

        // Full redraw to fix any stale CATiledLayer tiles
        drawingOverlay.setNeedsDisplay()
    }

    override func redrawCurrentOverlay() {
        drawingOverlay.setNeedsDisplay()
    }

    // MARK: - Tap Handling

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > minZoom {
            UIView.animate(withDuration: 0.3) {
                self.scrollView.zoomScale = self.minZoom
            }
        } else {
            let zoomRect = zoomRectForScale(maxZoom, center: gesture.location(in: contentContainer))
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }

    @objc private func handleEdgeTap(_ gesture: UITapGestureRecognizer) {
        guard drawingController.drawingMode == .view else { return }

        let tapLocation = gesture.location(in: self)

        let viewportHeight = bounds.height
        let scale = scrollView.zoomScale

        let inset = scrollView.contentInset
        let minOffset = -inset.top
        let maxOffset = scrollView.contentSize.height * scale - viewportHeight + inset.bottom

        guard pdfPageWidth > 0, pdfPageHeight > 0 else { return }
        let pageHeight = unscaledPageHeight * scale

        let isPortraitMode = bounds.height > bounds.width
        let currentOffset = scrollView.contentOffset.y
        let zone = classifyTapZone(point: tapLocation, in: bounds, edgeTapZone: edgeTapZone)

        if isPortraitMode {
            let centerY = (currentOffset + inset.top) + viewportHeight / 2
            let currentCenteredPage = Int(centerY / pageHeight)

            switch zone {
            case .left:
                let targetPage = max(0, currentCenteredPage - 1)
                let targetOffset = offsetToCenterPage(targetPage, pageHeight: pageHeight, viewportHeight: viewportHeight, insetTop: inset.top)
                let clampedOffset = max(minOffset, min(maxOffset, targetOffset))
                UIView.animate(withDuration: 0.3) {
                    self.scrollView.contentOffset = CGPoint(x: 0, y: clampedOffset)
                }
            case .right, .middle:
                let targetPage = min(actualPageCount - 1, currentCenteredPage + 1)
                let targetOffset = offsetToCenterPage(targetPage, pageHeight: pageHeight, viewportHeight: viewportHeight, insetTop: inset.top - pdfPaddingTop)
                let clampedOffset = max(minOffset, min(maxOffset, targetOffset))
                UIView.animate(withDuration: 0.3) {
                    self.scrollView.contentOffset = CGPoint(x: 0, y: clampedOffset)
                }
            }
        } else {
            switch zone {
            case .left:
                let newOffset = max(minOffset, currentOffset - viewportHeight)
                UIView.animate(withDuration: 0.3) {
                    self.scrollView.contentOffset = CGPoint(x: 0, y: newOffset)
                }
            case .right, .middle:
                let newOffset = min(maxOffset, currentOffset + viewportHeight)
                UIView.animate(withDuration: 0.3) {
                    self.scrollView.contentOffset = CGPoint(x: 0, y: newOffset)
                }
            }
        }

        onTap?(["position": zone == .left ? "left" : "right"])
    }

    private func offsetToCenterPage(_ page: Int, pageHeight: CGFloat, viewportHeight: CGFloat, insetTop: CGFloat) -> CGFloat {
        let pageCenterY = CGFloat(page) * pageHeight + pageHeight / 2
        return pageCenterY - viewportHeight / 2 - insetTop
    }

    @objc private func handleMiddleTap(_ gesture: UITapGestureRecognizer) {
        onMiddleClick?([:])
    }

    @objc private func handleDrawingPinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            drawingController.handleTouchCancelled()
        case .changed:
            let scale = gesture.scale
            gesture.scale = 1.0

            let currentScale = scrollView.zoomScale
            let newScale = min(max(currentScale * scale, minZoom), maxZoom)
            guard newScale != currentScale else { return }

            // Pinch center in visible area coordinates
            let pinchInView = gesture.location(in: self)

            // Content point under pinch (unzoomed)
            let contentX = (scrollView.contentOffset.x + pinchInView.x) / currentScale
            let contentY = (scrollView.contentOffset.y + pinchInView.y) / currentScale

            scrollView.zoomScale = newScale

            // Keep same content point under pinch center
            scrollView.contentOffset = CGPoint(
                x: contentX * newScale - pinchInView.x,
                y: contentY * newScale - pinchInView.y
            )
        default:
            break
        }
    }

    @objc private func handleDrawingPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            drawingController.handleTouchCancelled()
        case .changed:
            let translation = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)

            var offset = scrollView.contentOffset
            offset.x -= translation.x
            offset.y -= translation.y

            // Clamp to content bounds
            let maxX = max(0, scrollView.contentSize.width * scrollView.zoomScale - scrollView.bounds.width + scrollView.contentInset.right)
            let maxY = max(0, scrollView.contentSize.height * scrollView.zoomScale - scrollView.bounds.height + scrollView.contentInset.bottom)
            offset.x = max(-scrollView.contentInset.left, min(maxX, offset.x))
            offset.y = max(-scrollView.contentInset.top, min(maxY, offset.y))

            scrollView.contentOffset = offset
        default:
            break
        }
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

    override func layoutSubviews() {
        super.layoutSubviews()

        scrollView.frame = bounds

        // Clear cache and reset zoom if width changed (rotation)
        if bounds.width != previousBoundsWidth && previousBoundsWidth > 0 {
            imageCache.removeAllObjects()
            scrollView.zoomScale = 1.0
            collectionView.reloadData()
        }
        previousBoundsWidth = bounds.width

        updateCollectionViewSize()
    }

    private func updateCollectionViewSize() {
        guard bounds.width > 0, pdfPageWidth > 0, pdfPageHeight > 0 else { return }

        // Don't update layout during zoom
        if scrollView.zoomScale != 1.0 {
            updateContentInset()
            return
        }

        let viewWidth = bounds.width
        let pageHeight = unscaledPageHeight
        let totalHeight = pageHeight * CGFloat(actualPageCount)

        contentContainer.bounds = CGRect(x: 0, y: 0, width: viewWidth, height: totalHeight)
        contentContainer.center = CGPoint(x: viewWidth / 2, y: totalHeight / 2)

        collectionView.frame = contentContainer.bounds
        scrollView.contentSize = CGSize(width: viewWidth, height: totalHeight)

        drawingOverlay.frame = contentContainer.bounds
        drawingOverlay.pageCount = actualPageCount
        drawingOverlay.pageWidth = viewWidth
        drawingOverlay.pageHeight = pageHeight
        drawingOverlay.setNeedsDisplay()

        collectionView.collectionViewLayout.invalidateLayout()

        updateContentInset()
    }

    private func updateContentInset() {
        scrollView.contentInset = centeredContentInset(
            for: scrollView,
            extraTop: pdfPaddingTop,
            extraBottom: pdfPaddingBottom
        )
    }

    // MARK: - Page Detection

    private func pageIndexForPoint(_ point: CGPoint) -> Int {
        guard pdfPageWidth > 0, pdfPageHeight > 0, actualPageCount > 0 else { return 0 }

        let pageHeight = unscaledPageHeight
        let pageIndex = Int(point.y / pageHeight)
        return max(0, min(pageIndex, actualPageCount - 1))
    }

    private func contentRectForPage(_ page: Int) -> CGRect {
        guard pdfPageWidth > 0, pdfPageHeight > 0 else { return .zero }

        let pageHeight = unscaledPageHeight
        return CGRect(
            x: 0,
            y: CGFloat(page) * pageHeight,
            width: bounds.width,
            height: pageHeight
        )
    }

    // MARK: - TextAnnotationHandlerDelegate

    var textHandlerDrawingController: DrawingController { drawingController }
    var textHandlerContentContainer: UIView { contentContainer }
    var textHandlerHostView: UIView { self }
    var textHandlerZoomScale: CGFloat { scrollView.zoomScale }

    func textHandlerContentRectForPage(_ page: Int) -> CGRect {
        return contentRectForPage(page)
    }

    func textHandlerPageForPoint(_ pointInContent: CGPoint) -> Int {
        return pageIndexForPoint(pointInContent)
    }

    func textHandlerRedrawOverlay() {
        drawingOverlay.setNeedsDisplay()
    }

    // MARK: - UICollectionViewDataSource

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return actualPageCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PdfPageCell.reuseId, for: indexPath) as! PdfPageCell

        if let cachedImage = imageCache.object(forKey: NSNumber(value: indexPath.item)) {
            cell.setImage(cachedImage)
        } else {
            cell.setImage(nil)
            renderPage(at: indexPath.item) { [weak self] image in
                guard let self, let image else { return }
                self.imageCache.setObject(image, forKey: NSNumber(value: indexPath.item))
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
        return CGSize(width: viewWidth, height: unscaledPageHeight)
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return contentContainer
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentInset()
        drawingOverlay.zoomScale = scrollView.zoomScale
        drawingOverlay.setNeedsDisplay()
        onZoomChange?(["scale": scrollView.zoomScale])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateCurrentPage()
    }

    private func updateCurrentPage() {
        guard bounds.width > 0, pdfPageWidth > 0, pdfPageHeight > 0, actualPageCount > 0 else { return }

        let pageHeight = unscaledPageHeight
        let scale = scrollView.zoomScale

        let centerY = (scrollView.contentOffset.y + scrollView.bounds.height / 2) / scale
        let newPage = Int(centerY / pageHeight)
        let clampedPage = max(0, min(newPage, actualPageCount - 1))

        if clampedPage != currentPage {
            currentPage = clampedPage
            onPageChange?(["page": currentPage])
        }
    }

    // MARK: - Public Commands

    override func resetZoom() {
        UIView.animate(withDuration: 0.3) {
            self.scrollView.zoomScale = 1.0
        }
    }

    override func scrollToPage(_ page: Int, animated: Bool) {
        guard page >= 0, page < actualPageCount else { return }

        let pageHeight = unscaledPageHeight
        let yOffset = CGFloat(page) * pageHeight

        scrollView.setContentOffset(CGPoint(x: 0, y: yOffset * scrollView.zoomScale), animated: animated)
    }

    // MARK: - Touch Handling for Drawing

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard realDrawingMode != .view else {
            return super.hitTest(point, with: event)
        }

        guard bounds.contains(point) else { return nil }

        for subview in subviews.reversed() {
            if subview == scrollView { continue }
            let pointInSubview = convert(point, to: subview)
            if let hitView = subview.hitTest(pointInSubview, with: event) {
                return hitView
            }
        }

        return self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard realDrawingMode != .view, let touch = touches.first else {
            super.touchesBegan(touches, with: event)
            return
        }

        // Multiple fingers — cancel drawing, don't start new
        if let allTouches = event?.allTouches, allTouches.count > 1 {
            if drawingController.isDrawing {
                drawingController.handleTouchCancelled()
            }
            textAnnotationHandler.handleMultiTouchDetected()
            return
        }

        if realDrawingMode == .text {
            if textAnnotationHandler.handleTouchBegan(touch) { return }
        }

        let location = touch.location(in: contentContainer)
        let page = pageIndexForPoint(location)
        let pageRect = contentRectForPage(page)

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

        // Multiple fingers — cancel any active drawing
        if let allTouches = event?.allTouches, allTouches.count > 1 {
            if drawingController.isDrawing {
                drawingController.handleTouchCancelled()
            }
            textAnnotationHandler.handleMultiTouchDetected()
            return
        }

        if textAnnotationHandler.isDraggingText || textAnnotationHandler.hasPendingText {
            textAnnotationHandler.handleTouchMoved(touch)
            return
        }

        let location = touch.location(in: contentContainer)
        let page = pageIndexForPoint(location)
        let pageRect = contentRectForPage(page)

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

        if textAnnotationHandler.isDraggingText || textAnnotationHandler.hasPendingText {
            textAnnotationHandler.handleTouchEnded(touch)
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

        if textAnnotationHandler.isDraggingText || textAnnotationHandler.hasPendingText {
            textAnnotationHandler.handleTouchCancelled()
            return
        }

        drawingController.handleTouchCancelled()
    }

    // MARK: - UIGestureRecognizerDelegate

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === drawingPinchGesture || gestureRecognizer === drawingPanGesture {
            return realDrawingMode != .view
        }

        if realDrawingMode != .view {
            if gestureRecognizer === edgeTapGesture ||
               gestureRecognizer === middleTapGesture ||
               gestureRecognizer === doubleTapGesture {
                return false
            }
        }

        let tapLocation = gestureRecognizer.location(in: self)
        let zone = classifyTapZone(point: tapLocation, in: bounds, edgeTapZone: edgeTapZone)

        if gestureRecognizer === edgeTapGesture {
            return zone != .middle && scrollView.zoomScale <= minZoom + 0.01 && drawingController.drawingMode == .view
        }

        if gestureRecognizer === middleTapGesture || gestureRecognizer === doubleTapGesture {
            return zone == .middle
        }

        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow drawing pinch and pan to work simultaneously with each other and raw touches
        let drawingGestures: [UIGestureRecognizer] = [drawingPinchGesture, drawingPanGesture]
        if drawingGestures.contains(where: { $0 === gestureRecognizer || $0 === otherGestureRecognizer }) {
            return true
        }
        return false
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
