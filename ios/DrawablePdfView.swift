import UIKit

// MARK: - Drawing Types

enum DrawingMode: String {
    case view = "view"
    case draw = "draw"
    case erase = "erase"
    case highlight = "highlight"
}

struct DrawingStroke: Codable {
    let id: String
    let color: String
    let width: CGFloat
    let opacity: CGFloat
    let path: [[CGFloat]]
}

// MARK: - DrawablePdfView

class DrawablePdfView: UIView, UIGestureRecognizerDelegate {

    // MARK: - React Props

    @objc var source = "" { didSet { markDirty() } }
    @objc var page: NSNumber = 0 { didSet { markDirty() } }
    @objc var resizeMode = ResizeMode.CONTAIN.rawValue { didSet { validateResizeMode() } }
    @objc var annotationStr = "" { didSet { loadAnnotation(file: false) } }
    @objc var annotation = "" { didSet { loadAnnotation(file: true) } }

    @objc var drawingMode = DrawingMode.view.rawValue { didSet { updateDrawingMode() } }
    @objc var strokeColor = "#000000"
    @objc var strokeWidth: CGFloat = 3.0
    @objc var strokeOpacity: CGFloat = 1.0
    @objc var strokes = "" { didSet { loadStrokes() } }

    @objc var minZoom: CGFloat = 1.0
    @objc var maxZoom: CGFloat = 3.0
    @objc var zoomEnabled = true

    // MARK: - React Events

    @objc var onPdfError: RCTDirectEventBlock?
    @objc var onPdfLoadComplete: RCTDirectEventBlock?
    @objc var onDrawingStart: RCTDirectEventBlock?
    @objc var onDrawingEnd: RCTDirectEventBlock?
    @objc var onStrokeEnd: RCTDirectEventBlock?
    @objc var onStrokeRemoved: RCTDirectEventBlock?
    @objc var onStrokesCleared: RCTDirectEventBlock?
    @objc var onZoomChange: RCTDirectEventBlock?
    @objc var onZoomPanStart: RCTDirectEventBlock?
    @objc var onZoomPanEnd: RCTDirectEventBlock?
    @objc var onSingleTap: RCTDirectEventBlock?

    // MARK: - Private State

    private var annotationData = [AnnotationPage]()
    private var currentStrokes = [DrawingStroke]()
    private var activeStrokePath = [CGPoint]()
    private var isDrawing = false

    private var realResizeMode = ResizeMode.CONTAIN
    private var realDrawingMode = DrawingMode.view

    // PDF rendering
    private var pdfImage: UIImage?
    private var pdfPageWidth: CGFloat = 0
    private var pdfPageHeight: CGFloat = 0
    private var pdfContentRect = CGRect.zero
    private var isDirty = true
    private var renderGeneration = 0

    // Zoom state
    private var scale: CGFloat = 1.0
    private var offsetX: CGFloat = 0.0
    private var offsetY: CGFloat = 0.0
    private var isScaling = false
    private var lastPinchScale: CGFloat = 1.0

    // Gesture recognizers
    private var pinchGesture: UIPinchGestureRecognizer!
    private var panGesture: UIPanGestureRecognizer!
    private var doubleTapGesture: UITapGestureRecognizer!
    private var singleTapGesture: UITapGestureRecognizer!

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestures()
        backgroundColor = .white
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
        backgroundColor = .white
    }

    private func setupGestures() {
        // Pinch to zoom
        pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGesture.delegate = self
        addGestureRecognizer(pinchGesture)

        // Pan (for zoomed state)
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(panGesture)

        // Double tap to zoom
        doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.delegate = self
        addGestureRecognizer(doubleTapGesture)

        // Single tap (for tap-to-scroll in view mode)
        singleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTapGesture.numberOfTapsRequired = 1
        singleTapGesture.delegate = self
        singleTapGesture.require(toFail: doubleTapGesture)
        addGestureRecognizer(singleTapGesture)
    }

    // MARK: - Layout

    private var previousBounds: CGRect = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds != previousBounds {
            previousBounds = bounds
            markDirty()
            renderPdf()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            renderPdf()
        }
    }

    // MARK: - Render Control

    private func markDirty() {
        isDirty = true
    }

    func renderPdf() {
        guard !frame.isEmpty && !source.isEmpty && isDirty else {
            return
        }
        isDirty = false
        renderGeneration += 1
        let currentGeneration = renderGeneration
        let currentFrame = frame

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let url = URL(fileURLWithPath: self.source)
            guard let pdf = CGPDFDocument(url as CFURL) else {
                self.dispatchOnError(message: "Failed to open '\(self.source)' for reading.")
                return
            }
            guard let pdfPage = pdf.page(at: self.page.intValue + 1) else {
                self.dispatchOnError(message: "Failed to open page '\(self.page)' of '\(self.source)' for reading.")
                return
            }

            let pageBounds = pdfPage.getBoxRect(.cropBox)
            let pageHeight: CGFloat
            let pageWidth: CGFloat
            if pdfPage.rotationAngle % 180 == 90 {
                pageHeight = pageBounds.width
                pageWidth = pageBounds.height
            } else {
                pageHeight = pageBounds.height
                pageWidth = pageBounds.width
            }

            UIGraphicsBeginImageContextWithOptions(currentFrame.size, true, 0.0)
            guard let context = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                self.dispatchOnError(message: "Failed to open graphics context for rendering '\(self.source)'.")
                return
            }
            context.saveGState()

            // Fill with white
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: currentFrame.size))

            // Calculate target dimensions and content rect
            let targetHeight = currentFrame.width * pageHeight / pageWidth
            var contentRect = CGRect.zero

            if self.realResizeMode == .CONTAIN {
                if targetHeight > currentFrame.height {
                    let targetWidth = currentFrame.height * pageWidth / pageHeight
                    let offsetX = (currentFrame.width - targetWidth) / 2
                    context.translateBy(x: offsetX, y: 0.0)
                    let scaleFactor = currentFrame.height / targetHeight
                    context.scaleBy(x: scaleFactor, y: scaleFactor)
                    contentRect = CGRect(x: offsetX, y: 0, width: targetWidth, height: currentFrame.height)
                } else {
                    let offsetY = (currentFrame.height - targetHeight) / 2
                    context.translateBy(x: 0.0, y: offsetY)
                    contentRect = CGRect(x: 0, y: offsetY, width: currentFrame.width, height: targetHeight)
                }
            } else {
                contentRect = CGRect(x: 0, y: 0, width: currentFrame.width, height: targetHeight)
            }

            context.translateBy(x: 0.0, y: targetHeight)
            context.scaleBy(x: currentFrame.width / pageWidth, y: -targetHeight / pageHeight)
            context.concatenate(pdfPage.getDrawingTransform(
                .cropBox,
                rect: CGRect(x: 0.0, y: 0.0, width: pageWidth, height: pageHeight),
                rotate: 0,
                preserveAspectRatio: false
            ))

            context.interpolationQuality = .high
            context.setRenderingIntent(.defaultIntent)
            context.drawPDFPage(pdfPage)
            context.restoreGState()

            // Render static annotations
            context.saveGState()
            self.renderAnnotation(context, scaleX: currentFrame.width, scaleY: currentFrame.height)
            context.restoreGState()

            let rendered = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            DispatchQueue.main.async { [weak self] in
                guard let self = self, currentGeneration == self.renderGeneration else { return }
                self.pdfImage = rendered
                self.pdfPageWidth = pageWidth
                self.pdfPageHeight = pageHeight
                self.pdfContentRect = contentRect
                self.setNeedsDisplay()
                self.dispatchOnLoadComplete(pageWidth: pageWidth, pageHeight: pageHeight)
            }
        }
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.saveGState()

        // Apply zoom transform
        context.translateBy(x: offsetX, y: offsetY)
        context.scaleBy(x: scale, y: scale)

        // Draw PDF
        if let pdfImage = pdfImage {
            pdfImage.draw(in: CGRect(origin: .zero, size: bounds.size))
        }

        // Draw strokes
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in currentStrokes {
            guard stroke.path.count > 1 else { continue }
            drawStroke(context: context, stroke: stroke)
        }

        // Draw active stroke
        if !activeStrokePath.isEmpty {
            drawActiveStroke(context: context)
        }

        context.restoreGState()
    }

    private func drawStroke(context: CGContext, stroke: DrawingStroke) {
        let color = parseColor(stroke.color).withAlphaComponent(stroke.opacity)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(stroke.width)

        context.beginPath()

        var prevPoint = normalizedToContent(stroke.path[0])
        context.move(to: prevPoint)

        for i in 1..<stroke.path.count {
            let point = normalizedToContent(stroke.path[i])
            let dist = hypot(point.x - prevPoint.x, point.y - prevPoint.y)
            if dist < 8 { continue }

            let midPoint = CGPoint(x: (prevPoint.x + point.x) / 2, y: (prevPoint.y + point.y) / 2)
            context.addQuadCurve(to: midPoint, control: prevPoint)
            prevPoint = point
        }

        let lastPoint = normalizedToContent(stroke.path.last!)
        context.addLine(to: lastPoint)
        context.strokePath()
    }

    private func drawActiveStroke(context: CGContext) {
        guard activeStrokePath.count > 1 else { return }

        let color = parseColor(strokeColor).withAlphaComponent(strokeOpacity)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(strokeWidth)

        context.beginPath()
        context.move(to: activeStrokePath[0])

        var prevPoint = activeStrokePath[0]
        for i in 1..<activeStrokePath.count {
            let point = activeStrokePath[i]
            let dist = hypot(point.x - prevPoint.x, point.y - prevPoint.y)
            if dist < 8 { continue }

            let midPoint = CGPoint(x: (prevPoint.x + point.x) / 2, y: (prevPoint.y + point.y) / 2)
            context.addQuadCurve(to: midPoint, control: prevPoint)
            prevPoint = point
        }

        context.addLine(to: activeStrokePath.last!)
        context.strokePath()
    }

    // MARK: - Coordinate Conversion

    /// Convert content coordinates (zoom-adjusted) to normalized (0-1 relative to PDF)
    private func contentToNormalized(_ point: CGPoint) -> [CGFloat] {
        guard !pdfContentRect.isEmpty else {
            return [point.x / bounds.width, point.y / bounds.height]
        }

        let normalizedX = (point.x - pdfContentRect.minX) / pdfContentRect.width
        let normalizedY = (point.y - pdfContentRect.minY) / pdfContentRect.height
        return [normalizedX, normalizedY]
    }

    /// Convert normalized coordinates to content coordinates (for drawing with zoom context)
    private func normalizedToContent(_ normalized: [CGFloat]) -> CGPoint {
        guard !pdfContentRect.isEmpty else {
            return CGPoint(x: normalized[0] * bounds.width, y: normalized[1] * bounds.height)
        }

        let x = pdfContentRect.minX + normalized[0] * pdfContentRect.width
        let y = pdfContentRect.minY + normalized[1] * pdfContentRect.height
        return CGPoint(x: x, y: y)
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard realDrawingMode != .view, let touch = touches.first else {
            super.touchesBegan(touches, with: event)
            return
        }

        let location = touch.location(in: self)
        let contentLocation = CGPoint(
            x: (location.x - offsetX) / scale,
            y: (location.y - offsetY) / scale
        )

        if realDrawingMode == .erase {
            eraseStrokeAt(contentLocation)
        } else {
            isDrawing = true
            activeStrokePath = [contentLocation]
            onDrawingStart?([:])
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard realDrawingMode != .view, let touch = touches.first else {
            super.touchesMoved(touches, with: event)
            return
        }

        let location = touch.location(in: self)
        let contentLocation = CGPoint(
            x: (location.x - offsetX) / scale,
            y: (location.y - offsetY) / scale
        )

        if realDrawingMode == .erase {
            eraseStrokeAt(contentLocation)
        } else if isDrawing {
            activeStrokePath.append(contentLocation)
            setNeedsDisplay()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard realDrawingMode != .view else {
            super.touchesEnded(touches, with: event)
            return
        }

        if isDrawing && activeStrokePath.count > 1 {
            finishStroke()
        }

        isDrawing = false
        activeStrokePath.removeAll()
        onDrawingEnd?([:])
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDrawing = false
        activeStrokePath.removeAll()
        onDrawingEnd?([:])
        setNeedsDisplay()
        super.touchesCancelled(touches, with: event)
    }

    private func finishStroke() {
        let path = activeStrokePath.map { contentToNormalized($0) }
        let strokeId = UUID().uuidString

        let newStroke = DrawingStroke(
            id: strokeId,
            color: strokeColor,
            width: strokeWidth,
            opacity: strokeOpacity,
            path: path
        )

        currentStrokes.append(newStroke)

        onStrokeEnd?([
            "id": strokeId,
            "color": strokeColor,
            "width": strokeWidth,
            "opacity": strokeOpacity,
            "path": path
        ])
    }

    private func eraseStrokeAt(_ point: CGPoint) {
        let threshold: CGFloat = 20.0

        for (index, stroke) in currentStrokes.enumerated().reversed() {
            for pathPoint in stroke.path {
                let contentPoint = normalizedToContent(pathPoint)
                let dist = hypot(point.x - contentPoint.x, point.y - contentPoint.y)
                if dist < threshold {
                    let removedId = stroke.id
                    currentStrokes.remove(at: index)
                    onStrokeRemoved?(["id": removedId])
                    setNeedsDisplay()
                    return
                }
            }
        }
    }

    // MARK: - Zoom Gestures

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard realDrawingMode == .view && zoomEnabled else { return }

        switch gesture.state {
        case .began:
            isScaling = true
            lastPinchScale = scale
        case .changed:
            let newScale = lastPinchScale * gesture.scale
            let clampedScale = min(max(newScale, minZoom), maxZoom)

            let center = gesture.location(in: self)
            let oldScale = scale
            scale = clampedScale

            // Adjust offset to zoom toward pinch center
            offsetX = center.x - (center.x - offsetX) * (scale / oldScale)
            offsetY = center.y - (center.y - offsetY) * (scale / oldScale)

            constrainOffset()
            setNeedsDisplay()
            dispatchZoomChange()
        case .ended, .cancelled:
            isScaling = false
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard realDrawingMode == .view && zoomEnabled && scale > 1.0 else { return }

        switch gesture.state {
        case .began:
            onZoomPanStart?([:])
        case .changed:
            let translation = gesture.translation(in: self)
            offsetX += translation.x
            offsetY += translation.y
            gesture.setTranslation(.zero, in: self)

            constrainOffset()
            setNeedsDisplay()
            dispatchZoomChange()
        case .ended, .cancelled:
            onZoomPanEnd?([:])
        default:
            break
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard realDrawingMode == .view && zoomEnabled else { return }

        if scale > 1.0 {
            // Reset zoom
            UIView.animate(withDuration: 0.3, animations: {
                self.scale = 1.0
                self.offsetX = 0
                self.offsetY = 0
                self.setNeedsDisplay()
            }, completion: { _ in
                self.dispatchZoomChange()
            })
        } else {
            // Zoom in to 2x at tap location
            let center = gesture.location(in: self)
            UIView.animate(withDuration: 0.3, animations: {
                let newScale: CGFloat = 2.0
                self.offsetX = center.x - (center.x - self.offsetX) * (newScale / self.scale)
                self.offsetY = center.y - (center.y - self.offsetY) * (newScale / self.scale)
                self.scale = newScale
                self.constrainOffset()
                self.setNeedsDisplay()
            }, completion: { _ in
                self.dispatchZoomChange()
            })
        }
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        // Only fire single tap in view mode when not zoomed
        guard realDrawingMode == .view && scale <= 1.01 else { return }
        onSingleTap?([:])
    }

    private func constrainOffset() {
        // At scale > 1, content is larger than view
        // offsetX = 0 means left edge of content at left edge of screen
        // offsetX = bounds.width * (1 - scale) means right edge of content at right edge of screen
        let minOffsetX = min(0, bounds.width * (1 - scale))
        let maxOffsetX: CGFloat = 0
        let minOffsetY = min(0, bounds.height * (1 - scale))
        let maxOffsetY: CGFloat = 0

        offsetX = min(max(offsetX, minOffsetX), maxOffsetX)
        offsetY = min(max(offsetY, minOffsetY), maxOffsetY)
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    // MARK: - Public Commands

    func clearStrokes() {
        currentStrokes.removeAll()
        onStrokesCleared?([:])
        setNeedsDisplay()
    }

    func resetZoom() {
        UIView.animate(withDuration: 0.3) {
            self.scale = 1.0
            self.offsetX = 0
            self.offsetY = 0
            self.setNeedsDisplay()
        }
        dispatchZoomChange()
    }

    // MARK: - Private Helpers

    private func validateResizeMode() {
        guard let mode = ResizeMode(rawValue: resizeMode) else {
            dispatchOnError(message: "Unknown resizeMode '\(resizeMode)'.")
            return
        }
        realResizeMode = mode
        markDirty()
    }

    private func updateDrawingMode() {
        guard let mode = DrawingMode(rawValue: drawingMode) else {
            realDrawingMode = .view
            return
        }
        realDrawingMode = mode

        // Enable/disable zoom gestures based on mode
        pinchGesture.isEnabled = mode == .view
        panGesture.isEnabled = mode == .view && scale > 1.0
        doubleTapGesture.isEnabled = mode == .view
    }

    private func loadStrokes() {
        guard !strokes.isEmpty else {
            if !currentStrokes.isEmpty {
                currentStrokes.removeAll()
                setNeedsDisplay()
            }
            return
        }

        do {
            let data = strokes.data(using: .utf8)!
            currentStrokes = try JSONDecoder().decode([DrawingStroke].self, from: data)
            setNeedsDisplay()
        } catch {
            dispatchOnError(message: "Failed to parse strokes: \(error.localizedDescription)")
        }
    }

    private func loadAnnotation(file: Bool) {
        guard !annotation.isEmpty || !annotationStr.isEmpty else {
            if !annotationData.isEmpty {
                annotationData.removeAll()
                markDirty()
            }
            return
        }

        do {
            let data: Data
            if file {
                data = try Data(contentsOf: URL(fileURLWithPath: annotation))
            } else {
                data = annotationStr.data(using: .utf8)!
            }
            annotationData = try JSONDecoder().decode([AnnotationPage].self, from: data)
        } catch {
            dispatchOnError(message: "Failed to load annotation: \(error.localizedDescription)")
            return
        }
        markDirty()
    }

    private func renderAnnotation(_ context: CGContext, scaleX: CGFloat, scaleY: CGFloat) {
        guard page.intValue < annotationData.count else { return }
        let annotationPage = annotationData[page.intValue]

        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in annotationPage.strokes {
            guard stroke.path.count > 1 else { continue }
            context.setStrokeColor(parseColor(stroke.color).cgColor)
            context.setLineWidth(stroke.width)

            context.beginPath()
            computePath(context, stroke.path, scaleX: scaleX, scaleY: scaleY)
            context.strokePath()
        }

        for msg in annotationPage.text {
            let scaledFont = 9 + (msg.fontSize * scaleX) / 1000
            msg.str.draw(
                at: CGPoint(x: scaleX * msg.point[0], y: scaleY * msg.point[1]),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: scaledFont),
                    .foregroundColor: parseColor(msg.color)
                ]
            )
        }
    }

    private func computePath(_ context: CGContext, _ coordinates: [[CGFloat]], scaleX: CGFloat, scaleY: CGFloat) {
        var prevPoint = coordinates[0]
        context.move(to: CGPoint(x: scaleX * prevPoint[0], y: scaleY * prevPoint[1]))

        for point in coordinates.dropFirst() {
            let dist = hypot(scaleX * (prevPoint[0] - point[0]), scaleY * (prevPoint[1] - point[1]))
            guard dist > 3 else { continue }

            let midX = (prevPoint[0] + point[0]) / 2
            let midY = (prevPoint[1] + point[1]) / 2
            context.addQuadCurve(
                to: CGPoint(x: scaleX * midX, y: scaleY * midY),
                control: CGPoint(x: scaleX * prevPoint[0], y: scaleY * prevPoint[1])
            )
            prevPoint = point
        }

        let lastPoint = coordinates.last!
        context.addLine(to: CGPoint(x: scaleX * lastPoint[0], y: scaleY * lastPoint[1]))
    }

    private func parseColor(_ hex: String) -> UIColor {
        guard let colorInt = UInt64(hex.dropFirst().prefix(6), radix: 16) else {
            return UIColor.black
        }
        var alpha = CGFloat(1.0)
        if hex.count == 9, let alphaInt = UInt64(hex.suffix(2), radix: 16) {
            alpha = CGFloat(alphaInt) / 255.0
        }
        return UIColor(
            red: CGFloat((colorInt & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((colorInt & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(colorInt & 0x0000FF) / 255.0,
            alpha: alpha
        )
    }

    // MARK: - Event Dispatch

    private func dispatchOnError(message: String) {
        onPdfError?(["message": message])
    }

    private func dispatchOnLoadComplete(pageWidth: CGFloat, pageHeight: CGFloat) {
        onPdfLoadComplete?(["width": pageWidth, "height": pageHeight])
    }

    private func dispatchZoomChange() {
        onZoomChange?([
            "scale": scale,
            "offsetX": offsetX,
            "offsetY": offsetY
        ])
        // Update pan gesture enabled state based on current zoom
        updatePanGestureState()
    }

    private func updatePanGestureState() {
        panGesture.isEnabled = realDrawingMode == .view && scale > 1.0
    }
}
