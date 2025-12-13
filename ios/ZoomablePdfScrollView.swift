import UIKit

// MARK: - ZoomablePdfScrollView (scrollable PDF viewer with global zoom using UICollectionView)

class ZoomablePdfScrollView: UIView, UIScrollViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    // MARK: - React Props

    @objc var source = "" { didSet { reloadPdf() } }

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

        // Setup double tap gesture for zoom toggle
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapGesture)

        // Setup single tap gesture for tap-to-scroll
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.require(toFail: doubleTapGesture) // Wait for double tap to fail
        addGestureRecognizer(tapGesture)
    }

    // MARK: - Tap Handling

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        let tapLocation = gesture.location(in: self)

        // Calculate scroll amount (one viewport height)
        let viewportHeight = bounds.height
        let currentOffset = scrollView.contentOffset.y
        let maxOffset = scrollView.contentSize.height * scrollView.zoomScale - viewportHeight

      // Use edgeTapZone percentage for left/right scroll zones
      let edgeRatio = edgeTapZone / 100.0
      let leftEdge = bounds.width * edgeRatio
      let rightEdge = bounds.width * (1.0 - edgeRatio)

      if tapLocation.x < leftEdge {
          // Left 15% - scroll up
          let newOffset = max(0, currentOffset - viewportHeight)
          onTap?(["position": "left"])
          UIView.animate(withDuration: 0.3) {
              self.scrollView.contentOffset = CGPoint(x: 0, y: newOffset)
          }
      } else if tapLocation.x > rightEdge {
          // Right 15% - scroll down
          let newOffset = min(maxOffset, currentOffset + viewportHeight)
          onTap?(["position": "right"])
          UIView.animate(withDuration: 0.3) {
              self.scrollView.contentOffset = CGPoint(x: 0, y: newOffset)
          }
      } else {
          // Middle 70% - call onMiddleClick
          onMiddleClick?([:])
      }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let tapLocation = gesture.location(in: self)

        // Only handle double tap in middle zone
        let edgeRatio = edgeTapZone / 100.0
        let leftEdge = bounds.width * edgeRatio
        let rightEdge = bounds.width * (1.0 - edgeRatio)

        guard tapLocation.x >= leftEdge && tapLocation.x <= rightEdge else {
            return
        }

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

    // MARK: - PDF Rendering

    private func renderPage(at index: Int, completion: @escaping (UIImage?) -> Void) {
        guard let document = pdfDocument else {
            completion(nil)
            return
        }

        let viewWidth = bounds.width
        let pageHeight = viewWidth * (pdfPageHeight / pdfPageWidth)

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

            UIGraphicsBeginImageContextWithOptions(renderSize, true, 1.0)
            guard let context = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Fill with white
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: renderSize))

            // Scale and flip for PDF rendering
            context.translateBy(x: 0, y: renderSize.height)
            context.scaleBy(x: renderSize.width / pdfWidth, y: -renderSize.height / pdfHeight)

            context.concatenate(pdfPage.getDrawingTransform(
                .cropBox,
                rect: CGRect(x: 0, y: 0, width: pdfWidth, height: pdfHeight),
                rotate: 0,
                preserveAspectRatio: false
            ))

            context.interpolationQuality = .high
            context.setRenderingIntent(.defaultIntent)
            context.drawPDFPage(pdfPage)

            let rendered = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            DispatchQueue.main.async {
                completion(rendered)
            }
        }
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
