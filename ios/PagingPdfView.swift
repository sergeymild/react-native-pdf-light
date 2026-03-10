import UIKit

// MARK: - PagingPdfView (paged PDF viewer with per-page zoom using UIPageViewController)

class PagingPdfView: PdfViewerBase {

    // MARK: - Private State

    private var pageViewController: UIPageViewController!
    private var needsInitialPage = false

    // MARK: - Setup

    override func setupViews() {
        imageCache.countLimit = 5

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

    // MARK: - Override Points

    override func onPdfLoaded() {
        currentPage = 0

        if bounds.width > 0 && bounds.height > 0 {
            showPage(0, animated: false)
        } else {
            needsInitialPage = true
        }
    }

    override func onAnnotationsChanged() {
        if let currentVC = pageViewController?.viewControllers?.first as? PdfPageViewController {
            renderPage(at: currentVC.pageIndex) { [weak self, weak currentVC] image in
                guard let self = self, let image = image else { return }
                self.imageCache.setObject(image, forKey: NSNumber(value: currentVC?.pageIndex ?? 0))
                currentVC?.setImage(image)
            }
        }
    }

    override func updateZoomLimits() {
        if let currentVC = pageViewController.viewControllers?.first as? PdfPageViewController {
            currentVC.minZoom = minZoom
            currentVC.maxZoom = maxZoom
        }
    }

    override func updateBackgroundColor() {
        super.updateBackgroundColor()
        if let currentVC = pageViewController.viewControllers?.first as? PdfPageViewController {
            currentVC.view.backgroundColor = pdfBackgroundColor
        }
    }

    override func onDrawingModeChanged(_ mode: DrawingMode) {
        // Disable page swiping in drawing modes
        let isViewMode = mode == .view
        for view in pageViewController?.view.subviews ?? [] {
            if let scrollView = view as? UIScrollView {
                scrollView.isScrollEnabled = isViewMode
            }
        }

        if let currentVC = pageViewController?.viewControllers?.first as? PdfPageViewController {
            currentVC.updateDrawingMode(mode)
        }
    }

    override func redrawCurrentOverlay() {
        if let currentVC = pageViewController?.viewControllers?.first as? PdfPageViewController {
            currentVC.redrawOverlay()
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        pageViewController.view.frame = bounds

        if needsInitialPage && bounds.width > 0 && bounds.height > 0 {
            needsInitialPage = false
            showPage(0, animated: false)
        }

        // Clear cache and re-render on rotation
        if bounds.width != previousBoundsWidth && previousBoundsWidth > 0 && actualPageCount > 0 {
            imageCache.removeAllObjects()
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

    // MARK: - Page Navigation

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
        pageVC.textAnnotationHandler = textAnnotationHandler
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

    // MARK: - Public Commands

    override func resetZoom() {
        if let currentVC = pageViewController.viewControllers?.first as? PdfPageViewController {
            currentVC.resetZoom()
        }
    }

    override func scrollToPage(_ page: Int, animated: Bool) {
        guard page >= 0, page < actualPageCount else { return }
        showPage(page, animated: animated)
        onPageChange?(["page": page])
    }
}

// MARK: - UIPageViewControllerDataSource

extension PagingPdfView: UIPageViewControllerDataSource {

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let pageVC = viewController as? PdfPageViewController else { return nil }
        let previousIndex = pageVC.pageIndex - 1
        guard previousIndex >= 0 else { return nil }

        if !pageVC.isAtMinZoom { return nil }

        return createPageViewController(for: previousIndex)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let pageVC = viewController as? PdfPageViewController else { return nil }
        let nextIndex = pageVC.pageIndex + 1
        guard nextIndex < actualPageCount else { return nil }

        if !pageVC.isAtMinZoom { return nil }

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

class PdfPageViewController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate, TextAnnotationHandlerDelegate {

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
    weak var textAnnotationHandler: TextAnnotationHandler?
    private var currentDrawingMode: DrawingMode = .view
    private let drawingOverlay = DrawingOverlayView()

    var isAtMinZoom: Bool {
        return scrollView.zoomScale <= minZoom + 0.01
    }

    private let scrollView = UIScrollView()
    private let contentContainer = UIView()
    private let imageView = UIImageView()

    private var doubleTapGesture: UITapGestureRecognizer?
    private var edgeTapGesture: UITapGestureRecognizer?
    private var middleTapGesture: UITapGestureRecognizer?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = pageBackgroundColor

        scrollView.delegate = self
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = maxZoom
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        view.addSubview(scrollView)

        contentContainer.backgroundColor = .clear
        scrollView.addSubview(contentContainer)

        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        contentContainer.addSubview(imageView)

        drawingOverlay.pageIndex = pageIndex
        drawingOverlay.drawingController = drawingController
        drawingOverlay.textAnnotationHandler = textAnnotationHandler
        drawingOverlay.useNormalizedCoordinates = true
        contentContainer.addSubview(drawingOverlay)

        textAnnotationHandler?.delegate = self

        // Double tap to zoom (only works in middle zone)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        scrollView.addGestureRecognizer(doubleTap)
        doubleTapGesture = doubleTap

        // Edge tap - no delay
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

        // Don't update layout during zoom — UIScrollView manages contentContainer's transform
        if scrollView.zoomScale != 1.0 {
            scrollView.contentInset = centeredContentInset(for: scrollView)
            return
        }

        let viewSize = view.bounds.size
        let imageSize = image.size

        let scale = viewSize.width / imageSize.width
        let scaledHeight = imageSize.height * scale

        let contentSize = CGSize(width: viewSize.width, height: scaledHeight)

        // Use bounds + center instead of frame (safe with transforms)
        contentContainer.bounds = CGRect(origin: .zero, size: contentSize)
        contentContainer.center = CGPoint(x: contentSize.width / 2, y: contentSize.height / 2)
        imageView.frame = contentContainer.bounds
        drawingOverlay.frame = contentContainer.bounds
        drawingOverlay.contentRect = contentContainer.bounds

        scrollView.contentSize = contentSize

        scrollView.contentInset = centeredContentInset(for: scrollView)
    }

    func updateDrawingMode(_ mode: DrawingMode) {
        currentDrawingMode = mode

        guard isViewLoaded else { return }

        let isViewMode = mode == .view
        scrollView.isScrollEnabled = isViewMode
        scrollView.pinchGestureRecognizer?.isEnabled = isViewMode
        doubleTapGesture?.isEnabled = isViewMode
    }

    func redrawOverlay() {
        drawingOverlay.setNeedsDisplay()
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
        guard drawingController?.drawingMode == .view else { return }

        let tapLocation = gesture.location(in: view)

        let viewportHeight = view.bounds.height
        let contentHeight = scrollView.contentSize.height * scrollView.zoomScale
        let currentOffset = scrollView.contentOffset.y
        let maxOffset = contentHeight - viewportHeight

        let isLandscape = view.bounds.width > view.bounds.height
        let zone = classifyTapZone(point: tapLocation, in: view.bounds, edgeTapZone: edgeTapZone)

        switch zone {
        case .left:
            if currentOffset <= 0 {
                onPreviousPage?(isLandscape)
            } else {
                let newOffset = max(0, currentOffset - viewportHeight)
                UIView.animate(withDuration: 0.3) {
                    self.scrollView.contentOffset = CGPoint(x: 0, y: newOffset)
                }
            }
            onTap?("left")
        case .right, .middle:
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
        scrollView.contentInset = centeredContentInset(for: scrollView)
        drawingOverlay.zoomScale = scrollView.zoomScale
        drawingOverlay.setNeedsDisplay()
        onZoomChange?(scrollView.zoomScale)
    }

    // MARK: - TextAnnotationHandlerDelegate

    var textHandlerDrawingController: DrawingController {
        return drawingController!
    }

    var textHandlerContentContainer: UIView {
        return contentContainer
    }

    var textHandlerHostView: UIView {
        return view
    }

    var textHandlerZoomScale: CGFloat {
        return scrollView.zoomScale
    }

    func textHandlerContentRectForPage(_ page: Int) -> CGRect {
        return contentContainer.bounds
    }

    func textHandlerPageForPoint(_ pointInContent: CGPoint) -> Int {
        return pageIndex
    }

    func textHandlerRedrawOverlay() {
        drawingOverlay.setNeedsDisplay()
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let tapLocation = gestureRecognizer.location(in: view)
        let zone = classifyTapZone(point: tapLocation, in: view.bounds, edgeTapZone: edgeTapZone)

        if gestureRecognizer === edgeTapGesture {
            return zone != .middle && isAtMinZoom && drawingController?.drawingMode == .view
        }

        if gestureRecognizer === middleTapGesture || gestureRecognizer === doubleTapGesture {
            return zone == .middle
        }

        return true
    }
}
