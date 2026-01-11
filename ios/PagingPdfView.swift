import UIKit

// MARK: - PagingPdfView (paged PDF viewer with per-page zoom using UIPageViewController)

class PagingPdfView: UIView, DrawingControllerDelegate {

    // MARK: - React Props

    @objc var source = "" { didSet { reloadPdf() } }

    @objc var annotations = "" {
        didSet {
            parseAnnotations()
            imageCache.removeAllObjects()
            if let currentVC = pageViewController?.viewControllers?.first as? PdfPageViewController {
                renderPage(at: currentVC.pageIndex) { [weak self, weak currentVC] image in
                    guard let self = self, let image = image else { return }
                    self.imageCache.setObject(image, forKey: NSNumber(value: currentVC?.pageIndex ?? 0))
                    currentVC?.setImage(image)
                }
            }
        }
    }

    @objc var minZoom: CGFloat = 1.0 { didSet { updateZoomLimits() } }
    @objc var maxZoom: CGFloat = 3.0 { didSet { updateZoomLimits() } }
    @objc var edgeTapZone: CGFloat = 15.0

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

    private var pageViewController: UIPageViewController!
    private var pdfDocument: CGPDFDocument?
    private var currentPage: Int = 0
    private var isReloading = false
    private var actualPageCount: Int = 0
    private var needsInitialPage = false
    private var previousBoundsWidth: CGFloat = 0

    // PDF dimensions (from first page)
    private var pdfPageWidth: CGFloat = 0
    private var pdfPageHeight: CGFloat = 0

    // Image cache
    private var imageCache = NSCache<NSNumber, UIImage>()

    // Parsed annotations
    private var parsedAnnotations: [AnnotationPage] = []

    // Drawing controller
    private let drawingController = DrawingController()
    private var realDrawingMode = DrawingMode.view

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
        imageCache.countLimit = 5 // Cache up to 5 rendered pages

        // Setup drawing controller
        drawingController.delegate = self

        // Setup page view controller
      let options: [UIPageViewController.OptionsKey: Any] = [:]
        pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: options
        )
        pageViewController.dataSource = self
        pageViewController.delegate = self
        pageViewController.view.backgroundColor = .clear

        addSubview(pageViewController.view)
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

        // Disable page swiping in drawing modes
        let isViewMode = mode == .view
        for view in pageViewController?.view.subviews ?? [] {
            if let scrollView = view as? UIScrollView {
                scrollView.isScrollEnabled = isViewMode
            }
        }

        // Update current page view controller
        if let currentVC = pageViewController?.viewControllers?.first as? PdfPageViewController {
            currentVC.updateDrawingMode(mode)
        }
    }

    private func loadStrokes() {
        guard !strokes.isEmpty else {
            drawingController.clearAllStrokes()
            return
        }

        do {
            let data = strokes.data(using: .utf8)!
            let pageStrokes = try JSONDecoder().decode(PageStrokes.self, from: data)
            drawingController.setAllStrokes(pageStrokes)

            // Redraw current page
            if let currentVC = pageViewController?.viewControllers?.first as? PdfPageViewController {
                currentVC.redrawOverlay()
            }
        } catch {
            onPdfError?(["message": "Failed to parse strokes: \(error.localizedDescription)"])
        }
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
        if let currentVC = pageViewController?.viewControllers?.first as? PdfPageViewController {
            currentVC.redrawOverlay()
        }
    }

    private func updateBackgroundColor() {
        backgroundColor = pdfBackgroundColor
        // Update current page background
        if let currentVC = pageViewController.viewControllers?.first as? PdfPageViewController {
            currentVC.view.backgroundColor = pdfBackgroundColor
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        pageViewController.view.frame = bounds

        // Show initial page when we have valid bounds
        if needsInitialPage && bounds.width > 0 && bounds.height > 0 {
            needsInitialPage = false
            showPage(0, animated: false)
        }

        // Clear cache and re-render on rotation
        if bounds.width != previousBoundsWidth && previousBoundsWidth > 0 && actualPageCount > 0 {
            imageCache.removeAllObjects()
            // Re-render current page
            if let currentVC = pageViewController.viewControllers?.first as? PdfPageViewController {
                renderPage(at: currentVC.pageIndex) { [weak self, weak currentVC] image in
                    guard let self = self, let image = image else { return }
                    self.imageCache.setObject(image, forKey: NSNumber(value: currentVC?.pageIndex ?? 0))
                    currentVC?.setImage(image)
                }
            }
        }
        previousBoundsWidth = bounds.width
    }

    private func updateSpacing() {
        // UIPageViewController spacing can only be set at init time
        // So we need to recreate it
        let currentPageIndex = currentPage

        pageViewController.view.removeFromSuperview()

      let options: [UIPageViewController.OptionsKey: Any] = [:]
        pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: options
        )
        pageViewController.dataSource = self
        pageViewController.delegate = self
        pageViewController.view.backgroundColor = .clear
        pageViewController.view.frame = bounds

        addSubview(pageViewController.view)

        // Restore current page
        if actualPageCount > 0 {
            showPage(currentPageIndex, animated: false)
        }
    }

    private func updateZoomLimits() {
        // Update zoom limits for current page
        if let currentVC = pageViewController.viewControllers?.first as? PdfPageViewController {
            currentVC.minZoom = minZoom
            currentVC.maxZoom = maxZoom
        }
    }

    // MARK: - PDF Loading

    private func reloadPdf() {
        guard !source.isEmpty, !isReloading else { return }
        isReloading = true

        // Clear cache
        imageCache.removeAllObjects()
        pdfDocument = nil
        currentPage = 0

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

        // Show first page (defer if bounds are zero)
        if bounds.width > 0 && bounds.height > 0 {
            showPage(0, animated: false)
        } else {
            needsInitialPage = true
        }

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

    private func showPage(_ pageIndex: Int, animated: Bool, scrollToBottom: Bool = false) {
        guard pageIndex >= 0, pageIndex < actualPageCount else { return }

        let pageVC = createPageViewController(for: pageIndex, scrollToBottom: scrollToBottom)
        let direction: UIPageViewController.NavigationDirection = pageIndex >= currentPage ? .forward : .reverse

        pageViewController.setViewControllers(
            [pageVC],
            direction: direction,
            animated: animated,
            completion: nil
        )

        currentPage = pageIndex
    }

    private func createPageViewController(for pageIndex: Int, scrollToBottom: Bool = false) -> PdfPageViewController {
        let pageVC = PdfPageViewController()
        pageVC.pageIndex = pageIndex
        pageVC.minZoom = minZoom
        pageVC.maxZoom = maxZoom
        pageVC.edgeTapZone = edgeTapZone
        pageVC.pageBackgroundColor = pdfBackgroundColor
        pageVC.shouldScrollToBottomOnLoad = scrollToBottom
        pageVC.drawingController = drawingController
        pageVC.updateDrawingMode(realDrawingMode)
        pageVC.onZoomChange = { [weak self] scale in
            self?.onZoomChange?(["scale": scale])
        }
        pageVC.onTap = { [weak self] position in
            self?.onTap?(["position": position])
        }
        pageVC.onMiddleClick = { [weak self] in
            self?.onMiddleClick?([:])
        }
        pageVC.onPreviousPage = { [weak self] scrollToBottom in
            guard let self = self, pageIndex > 0 else { return }
            self.showPage(pageIndex - 1, animated: true, scrollToBottom: scrollToBottom)
            self.onPageChange?(["page": pageIndex - 1])
        }
        pageVC.onNextPage = { [weak self] in
            guard let self = self, pageIndex < self.actualPageCount - 1 else { return }
            self.scrollToPage(pageIndex + 1, animated: true)
        }

        // Load image from cache or render
        if let cachedImage = imageCache.object(forKey: NSNumber(value: pageIndex)) {
            pageVC.setImage(cachedImage)
        } else {
            renderPage(at: pageIndex) { [weak self, weak pageVC] image in
                guard let self = self, let image = image else { return }
                self.imageCache.setObject(image, forKey: NSNumber(value: pageIndex))
                pageVC?.setImage(image)
            }
        }

        return pageVC
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
        if let currentVC = pageViewController.viewControllers?.first as? PdfPageViewController {
            currentVC.resetZoom()
        }
    }

    func scrollToPage(_ page: Int, animated: Bool) {
        guard page >= 0, page < actualPageCount else { return }
        showPage(page, animated: animated)
        onPageChange?(["page": page])
    }

    func clearStrokes(page: Int) {
        if page >= 0 {
            drawingController.clearStrokes(forPage: page)
        } else {
            // Clear all pages
            drawingController.clearAllStrokes()
        }
        if let currentVC = pageViewController?.viewControllers?.first as? PdfPageViewController {
            currentVC.redrawOverlay()
        }
    }

    /// Get all annotations (strokes) from all pages
    func getAnnotations() -> [String: Any] {
        return drawingController.getAnnotationsForExport()
    }

    // MARK: - Cleanup

    func clearCache() {
        imageCache.removeAllObjects()
    }
}

// MARK: - UIPageViewControllerDataSource

extension PagingPdfView: UIPageViewControllerDataSource {

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let pageVC = viewController as? PdfPageViewController else { return nil }
        let previousIndex = pageVC.pageIndex - 1
        guard previousIndex >= 0 else { return nil }

        // Only allow page change when zoom is at minimum
        if !pageVC.isAtMinZoom {
            return nil
        }

        return createPageViewController(for: previousIndex)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let pageVC = viewController as? PdfPageViewController else { return nil }
        let nextIndex = pageVC.pageIndex + 1
        guard nextIndex < actualPageCount else { return nil }

        // Only allow page change when zoom is at minimum
        if !pageVC.isAtMinZoom {
            return nil
        }

        return createPageViewController(for: nextIndex)
    }
}

// MARK: - UIPageViewControllerDelegate

extension PagingPdfView: UIPageViewControllerDelegate {

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed,
              let currentVC = pageViewController.viewControllers?.first as? PdfPageViewController else { return }

        currentPage = currentVC.pageIndex
        onPageChange?(["page": currentPage])
    }
}

// MARK: - PdfPageViewController (single page with zoom)

class PdfPageViewController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {

    var pageIndex: Int = 0
    var minZoom: CGFloat = 1.0 {
        didSet { scrollView.minimumZoomScale = minZoom }
    }
    var maxZoom: CGFloat = 3.0 {
        didSet { scrollView.maximumZoomScale = maxZoom }
    }
    var edgeTapZone: CGFloat = 15.0
    var pageBackgroundColor: UIColor = UIColor(white: 0.2, alpha: 1.0)

    var onZoomChange: ((CGFloat) -> Void)?
    var onTap: ((String) -> Void)?
    var onMiddleClick: (() -> Void)?
    var onPreviousPage: ((_ scrollToBottom: Bool) -> Void)?
    var onNextPage: (() -> Void)?

    var shouldScrollToBottomOnLoad = false

    // Drawing support
    weak var drawingController: DrawingController?
    private var currentDrawingMode: DrawingMode = .view
    private let drawingOverlay = DrawingOverlayView()

    var isAtMinZoom: Bool {
        return scrollView.zoomScale <= minZoom + 0.01
    }

    private let scrollView = UIScrollView()
    private let contentContainer = UIView() // Container for imageView + drawingOverlay (zooms together)
    private let imageView = UIImageView()

    private var doubleTapGesture: UITapGestureRecognizer?
    private var edgeTapGesture: UITapGestureRecognizer?
    private var middleTapGesture: UITapGestureRecognizer?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = pageBackgroundColor

        // Setup scroll view for zooming
        scrollView.delegate = self
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = maxZoom
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        view.addSubview(scrollView)

        // Setup content container (this is what gets zoomed)
        contentContainer.backgroundColor = .clear
        scrollView.addSubview(contentContainer)

        // Setup image view inside container
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        contentContainer.addSubview(imageView)

        // Setup drawing overlay on top of image view (inside same container so it zooms together)
        drawingOverlay.pageIndex = pageIndex
        drawingOverlay.drawingController = drawingController
        contentContainer.addSubview(drawingOverlay)

        // Double tap to zoom (only works in middle zone)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        scrollView.addGestureRecognizer(doubleTap)
        doubleTapGesture = doubleTap

        // Edge tap - no delay (doesn't wait for double tap to fail)
        let edgeTap = UITapGestureRecognizer(target: self, action: #selector(handleEdgeTap(_:)))
        edgeTap.numberOfTapsRequired = 1
        edgeTap.delegate = self
        scrollView.addGestureRecognizer(edgeTap)
        edgeTapGesture = edgeTap

        // Middle tap - waits for double tap to fail
        let middleTap = UITapGestureRecognizer(target: self, action: #selector(handleMiddleTap(_:)))
        middleTap.numberOfTapsRequired = 1
        middleTap.require(toFail: doubleTap)
        middleTap.delegate = self
        scrollView.addGestureRecognizer(middleTap)
        middleTapGesture = middleTap

        // Apply drawing mode that may have been set before view loaded
        updateDrawingMode(currentDrawingMode)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        updateImageViewFrame()
    }

    func setImage(_ image: UIImage?) {
        imageView.image = image
        updateImageViewFrame()

        // Scroll to bottom if requested (for landscape back navigation)
        if shouldScrollToBottomOnLoad {
            shouldScrollToBottomOnLoad = false
            scrollToBottom()
        }
    }

    func scrollToBottom() {
        let contentHeight = scrollView.contentSize.height
        let viewportHeight = scrollView.bounds.height
        let maxOffset = max(0, contentHeight - viewportHeight)
        scrollView.contentOffset = CGPoint(x: 0, y: maxOffset)
    }

    private func updateImageViewFrame() {
        guard let image = imageView.image else { return }

        let viewSize = view.bounds.size
        let imageSize = image.size

        // Calculate size to fit width
        let scale = viewSize.width / imageSize.width
        let scaledHeight = imageSize.height * scale

        let contentFrame = CGRect(x: 0, y: 0, width: viewSize.width, height: scaledHeight)

        // Update container, image view, and drawing overlay frames
        contentContainer.frame = contentFrame
        imageView.frame = contentContainer.bounds
        drawingOverlay.frame = contentContainer.bounds
        drawingOverlay.contentRect = contentContainer.bounds

        scrollView.contentSize = contentFrame.size

        updateContentInset()
    }

    func updateDrawingMode(_ mode: DrawingMode) {
        currentDrawingMode = mode

        // Only update gestures if view is loaded
        guard isViewLoaded else { return }

        // Disable all scroll/zoom gestures in drawing modes (draw, erase, highlight)
        let isViewMode = mode == .view
        scrollView.isScrollEnabled = isViewMode
        scrollView.pinchGestureRecognizer?.isEnabled = isViewMode
        doubleTapGesture?.isEnabled = isViewMode
    }

    func redrawOverlay() {
        drawingOverlay.setNeedsDisplay()
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
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > minZoom {
            scrollView.setZoomScale(minZoom, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let zoomRect = CGRect(
                x: point.x - 50,
                y: point.y - 50,
                width: 100,
                height: 100
            )
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }

    @objc private func handleEdgeTap(_ gesture: UITapGestureRecognizer) {
        // Ignore edge taps in drawing modes
        guard drawingController?.drawingMode == .view else { return }

        let tapLocation = gesture.location(in: view)

        let viewportHeight = view.bounds.height
        let contentHeight = scrollView.contentSize.height * scrollView.zoomScale
        let currentOffset = scrollView.contentOffset.y
        let maxOffset = contentHeight - viewportHeight

        let edgeRatio = edgeTapZone / 100.0
        let leftEdge = view.bounds.width * edgeRatio

        // Check if landscape mode
        let isLandscape = view.bounds.width > view.bounds.height

        if tapLocation.x < leftEdge {
            // Left zone - scroll up or previous page
            if currentOffset <= 0 {
                // In landscape mode, go to previous page scrolled to bottom
                onPreviousPage?(isLandscape)
            } else {
                let newOffset = max(0, currentOffset - viewportHeight)
                UIView.animate(withDuration: 0.3) {
                    self.scrollView.contentOffset = CGPoint(x: 0, y: newOffset)
                }
            }
            onTap?("left")
        } else {
            // Right zone - scroll down or next page
            if currentOffset >= maxOffset - 1 {
                onNextPage?()
            } else {
                let newOffset = min(maxOffset, currentOffset + viewportHeight)
                UIView.animate(withDuration: 0.3) {
                    self.scrollView.contentOffset = CGPoint(x: 0, y: newOffset)
                }
            }
            onTap?("right")
        }
    }

    @objc private func handleMiddleTap(_ gesture: UITapGestureRecognizer) {
        onMiddleClick?()
    }

    func resetZoom() {
        scrollView.setZoomScale(minZoom, animated: true)
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
        onZoomChange?(scrollView.zoomScale)
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let tapLocation = gestureRecognizer.location(in: view)
        let edgeRatio = edgeTapZone / 100.0
        let leftEdge = view.bounds.width * edgeRatio
        let rightEdge = view.bounds.width * (1.0 - edgeRatio)

        let isInEdgeZone = tapLocation.x < leftEdge || tapLocation.x > rightEdge
        let isInMiddleZone = tapLocation.x >= leftEdge && tapLocation.x <= rightEdge

        // Edge tap only in edge zones AND when not zoomed AND in view mode
        if gestureRecognizer === edgeTapGesture {
            return isInEdgeZone && isAtMinZoom && drawingController?.drawingMode == .view
        }

        // Middle tap and double tap only in middle zone
        if gestureRecognizer === middleTapGesture || gestureRecognizer === doubleTapGesture {
            return isInMiddleZone
        }

        return true
    }
}
