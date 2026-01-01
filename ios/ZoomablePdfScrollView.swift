import UIKit

// MARK: - ZoomablePdfScrollView (scrollable PDF viewer with global zoom using UICollectionView)

class ZoomablePdfScrollView: UIView, UIScrollViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {

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

    private let scrollView = UIScrollView()
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

        // Setup collection view
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.register(PdfPageCell.self, forCellWithReuseIdentifier: PdfPageCell.reuseId)
        scrollView.addSubview(collectionView)

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
            let zoomRect = zoomRectForScale(maxZoom, center: gesture.location(in: collectionView))
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }

    @objc private func handleEdgeTap(_ gesture: UITapGestureRecognizer) {
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

        collectionView.frame = CGRect(x: 0, y: 0, width: viewWidth, height: totalHeight)
        scrollView.contentSize = CGSize(width: viewWidth, height: totalHeight)

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
        return collectionView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentInset()
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

    // MARK: - Cleanup

    func clearCache() {
        imageCache.removeAllObjects()
    }

    // MARK: - UIGestureRecognizerDelegate

  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let tapLocation = gestureRecognizer.location(in: self)
        let edgeRatio = edgeTapZone / 100.0
        let leftEdge = bounds.width * edgeRatio
        let rightEdge = bounds.width * (1.0 - edgeRatio)

        let isInEdgeZone = tapLocation.x < leftEdge || tapLocation.x > rightEdge
        let isInMiddleZone = tapLocation.x >= leftEdge && tapLocation.x <= rightEdge

        // Edge tap only in edge zones AND when not zoomed
        if gestureRecognizer === edgeTapGesture {
            return isInEdgeZone && scrollView.zoomScale <= minZoom + 0.01
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
