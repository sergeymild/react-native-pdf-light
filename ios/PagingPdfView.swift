import UIKit

// MARK: - PagingPdfView (paged PDF viewer with per-page zoom using UIPageViewController)

class PagingPdfView: UIView {

    // MARK: - React Props

    @objc var source = "" { didSet { reloadPdf() } }

    @objc var minZoom: CGFloat = 1.0 { didSet { updateZoomLimits() } }
    @objc var maxZoom: CGFloat = 3.0 { didSet { updateZoomLimits() } }
    @objc var edgeTapZone: CGFloat = 15.0

    @objc var pdfBackgroundColor: UIColor = UIColor(white: 0.2, alpha: 1.0) {
        didSet { updateBackgroundColor() }
    }

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

    // MARK: - PDF Rendering

    private func renderPage(at index: Int, completion: @escaping (UIImage?) -> Void) {
        guard let document = pdfDocument else {
            completion(nil)
            return
        }

        let viewWidth = bounds.width
        let pageHeight = viewWidth * (pdfPageHeight / pdfPageWidth)

        // Guard against zero size
        guard viewWidth > 0, pageHeight > 0 else {
            completion(nil)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let pdfPage = document.page(at: index + 1) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let pageBounds = pdfPage.getBoxRect(.cropBox)
            let pdfWidth: CGFloat
            let pdfHeight: CGFloat

            if pdfPage.rotationAngle % 180 == 90 {
                pdfWidth = pageBounds.height
                pdfHeight = pageBounds.width
            } else {
                pdfWidth = pageBounds.width
                pdfHeight = pageBounds.height
            }

            // Render at 2x for retina
            let scale: CGFloat = 2.0
            let renderSize = CGSize(width: viewWidth * scale, height: pageHeight * scale)

            // Use UIGraphicsImageRenderer instead of deprecated UIGraphicsBeginImageContext
            let renderer = UIGraphicsImageRenderer(size: renderSize)
            let rendered = renderer.image { context in
                let ctx = context.cgContext

                // Fill with white
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: renderSize))

                // Scale and flip for PDF rendering
                ctx.translateBy(x: 0, y: renderSize.height)
                ctx.scaleBy(x: renderSize.width / pdfWidth, y: -renderSize.height / pdfHeight)

                ctx.concatenate(pdfPage.getDrawingTransform(
                    .cropBox,
                    rect: CGRect(x: 0, y: 0, width: pdfWidth, height: pdfHeight),
                    rotate: 0,
                    preserveAspectRatio: false
                ))

                ctx.interpolationQuality = .high
                ctx.setRenderingIntent(.defaultIntent)
                ctx.drawPDFPage(pdfPage)
            }

            DispatchQueue.main.async {
                completion(rendered)
            }
        }
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

    var isAtMinZoom: Bool {
        return scrollView.zoomScale <= minZoom + 0.01
    }

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()

    private var doubleTapGesture: UITapGestureRecognizer!
    private var edgeTapGesture: UITapGestureRecognizer!
    private var middleTapGesture: UITapGestureRecognizer!

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

        // Setup image view
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        scrollView.addSubview(imageView)

        // Double tap to zoom (only works in middle zone)
        doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.delegate = self
        scrollView.addGestureRecognizer(doubleTapGesture)

        // Edge tap - no delay (doesn't wait for double tap to fail)
        edgeTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleEdgeTap(_:)))
        edgeTapGesture.numberOfTapsRequired = 1
        edgeTapGesture.delegate = self
        scrollView.addGestureRecognizer(edgeTapGesture)

        // Middle tap - waits for double tap to fail
        middleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMiddleTap(_:)))
        middleTapGesture.numberOfTapsRequired = 1
        middleTapGesture.require(toFail: doubleTapGesture)
        middleTapGesture.delegate = self
        scrollView.addGestureRecognizer(middleTapGesture)
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

        imageView.frame = CGRect(x: 0, y: 0, width: viewSize.width, height: scaledHeight)
        scrollView.contentSize = imageView.frame.size

        updateContentInset()
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
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentInset()
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

        // Edge tap only in edge zones AND when not zoomed
        if gestureRecognizer === edgeTapGesture {
            return isInEdgeZone && isAtMinZoom
        }

        // Middle tap and double tap only in middle zone
        if gestureRecognizer === middleTapGesture || gestureRecognizer === doubleTapGesture {
            return isInMiddleZone
        }

        return true
    }
}
