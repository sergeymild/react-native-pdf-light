import UIKit

// MARK: - DrawingControllerDelegate

protocol DrawingControllerDelegate: AnyObject {
    /// Called when a stroke is completed and should be added to state
    func drawingController(_ controller: DrawingController, didAddStroke stroke: DrawingStroke, onPage page: Int)

    /// Called when a stroke is erased
    func drawingController(_ controller: DrawingController, didRemoveStroke strokeId: String, onPage page: Int)

    /// Called when strokes are cleared for a page
    func drawingController(_ controller: DrawingController, strokesCleared onPage: Int)

    /// Called when drawing gesture starts
    func drawingControllerDidStartDrawing(_ controller: DrawingController)

    /// Called when drawing gesture ends
    func drawingControllerDidEndDrawing(_ controller: DrawingController)

    /// Called when the view needs to redraw (during active drawing)
    func drawingControllerNeedsRedraw(_ controller: DrawingController)
}

// MARK: - DrawingController

/// Shared controller for handling drawing logic across different PDF views.
/// Manages touch handling, stroke storage, coordinate conversion, and rendering.
class DrawingController {

    // MARK: - Properties

    weak var delegate: DrawingControllerDelegate?

    /// Current drawing mode
    var drawingMode: DrawingMode = .view

    /// Current stroke color (hex string)
    var strokeColor: String = "#000000"

    /// Current stroke width
    var strokeWidth: CGFloat = 3.0

    /// Current stroke opacity
    var strokeOpacity: CGFloat = 1.0

    /// Strokes organized by page
    private(set) var pageStrokes = PageStrokes()

    /// Active stroke being drawn (page index and path points in content coordinates)
    private var activeStroke: (page: Int, path: [CGPoint])?

    /// Whether a drawing gesture is in progress
    private(set) var isDrawing: Bool = false

    // MARK: - Stroke Management

    /// Set strokes for a specific page (called when props change from React)
    func setStrokes(_ strokes: [DrawingStroke], forPage page: Int) {
        pageStrokes.setStrokes(strokes, forPage: page)
    }

    /// Set all page strokes at once (from JSON prop)
    func setAllStrokes(_ allStrokes: PageStrokes) {
        pageStrokes = allStrokes
    }

    /// Get strokes for a specific page
    func getStrokes(forPage page: Int) -> [DrawingStroke] {
        return pageStrokes.getStrokes(forPage: page)
    }

    /// Clear strokes for a specific page
    func clearStrokes(forPage page: Int) {
        pageStrokes.clearStrokes(forPage: page)
        delegate?.drawingController(self, strokesCleared: page)
    }

    /// Clear all strokes
    func clearAllStrokes() {
        pageStrokes.clearAllStrokes()
    }

    // MARK: - Touch Handling

    /// Handle touch began event
    /// - Parameters:
    ///   - point: Touch point in content coordinates (already adjusted for zoom/pan)
    ///   - page: Page index
    ///   - contentRect: The rect of the PDF content area (for coordinate normalization)
    func handleTouchBegan(_ point: CGPoint, page: Int, contentRect: CGRect) {
        guard drawingMode != .view else { return }

        if drawingMode == .erase {
            // Try to erase at this point
            eraseStroke(at: point, page: page, contentRect: contentRect)
        } else {
            // Start drawing
            isDrawing = true
            activeStroke = (page: page, path: [point])
            delegate?.drawingControllerDidStartDrawing(self)
            delegate?.drawingControllerNeedsRedraw(self)
        }
    }

    /// Handle touch moved event
    /// - Parameters:
    ///   - point: Touch point in content coordinates
    ///   - page: Page index
    ///   - contentRect: The rect of the PDF content area
    func handleTouchMoved(_ point: CGPoint, page: Int, contentRect: CGRect) {
        guard drawingMode != .view else { return }

        if drawingMode == .erase {
            eraseStroke(at: point, page: page, contentRect: contentRect)
        } else if isDrawing, var stroke = activeStroke, stroke.page == page {
            stroke.path.append(point)
            activeStroke = stroke
            delegate?.drawingControllerNeedsRedraw(self)
        }
    }

    /// Handle touch ended event
    /// - Parameter page: Page index
    func handleTouchEnded(page: Int) {
        guard drawingMode != .view else { return }

        if isDrawing, let stroke = activeStroke, !stroke.path.isEmpty, stroke.page == page {
            finishStroke(page: page)
        }

        isDrawing = false
        activeStroke = nil
        delegate?.drawingControllerDidEndDrawing(self)
        delegate?.drawingControllerNeedsRedraw(self)
    }

    /// Handle touch cancelled event
    func handleTouchCancelled() {
        isDrawing = false
        activeStroke = nil
        delegate?.drawingControllerDidEndDrawing(self)
        delegate?.drawingControllerNeedsRedraw(self)
    }

    // MARK: - Private Methods

    private func finishStroke(page: Int) {
        guard let stroke = activeStroke, stroke.page == page else { return }

        // Get contentRect from the first point's context (we need to store this differently)
        // For now, we'll rely on the delegate to provide proper context
        // The path is already in content coordinates, we need to normalize it

        let strokeId = UUID().uuidString
        let newStroke = DrawingStroke(
            id: strokeId,
            color: strokeColor,
            width: strokeWidth,
            opacity: strokeOpacity,
            path: stroke.path.map { [$0.x, $0.y] } // Store as content coordinates for now
        )

        pageStrokes.addStroke(newStroke, toPage: page)
        delegate?.drawingController(self, didAddStroke: newStroke, onPage: page)
    }

    private func eraseStroke(at point: CGPoint, page: Int, contentRect: CGRect) {
        let threshold: CGFloat = 20.0
        let strokes = pageStrokes.getStrokes(forPage: page)

        for stroke in strokes.reversed() {
            for pathPoint in stroke.path {
                guard pathPoint.count >= 2 else { continue }
                let strokePoint = CGPoint(x: pathPoint[0], y: pathPoint[1])
                let dist = hypot(point.x - strokePoint.x, point.y - strokePoint.y)
                if dist < threshold {
                    if pageStrokes.removeStroke(withId: stroke.id, fromPage: page) {
                        delegate?.drawingController(self, didRemoveStroke: stroke.id, onPage: page)
                        delegate?.drawingControllerNeedsRedraw(self)
                    }
                    return
                }
            }
        }
    }

    // MARK: - Coordinate Conversion

    /// Convert content coordinates to normalized (0-1) coordinates
    func contentToNormalized(_ point: CGPoint, contentRect: CGRect) -> [CGFloat] {
        guard !contentRect.isEmpty else {
            return [0, 0]
        }
        let normalizedX = (point.x - contentRect.minX) / contentRect.width
        let normalizedY = (point.y - contentRect.minY) / contentRect.height
        return [normalizedX, normalizedY]
    }

    /// Convert normalized (0-1) coordinates to content coordinates
    func normalizedToContent(_ normalized: [CGFloat], contentRect: CGRect) -> CGPoint {
        guard normalized.count >= 2, !contentRect.isEmpty else {
            return .zero
        }
        let x = contentRect.minX + normalized[0] * contentRect.width
        let y = contentRect.minY + normalized[1] * contentRect.height
        return CGPoint(x: x, y: y)
    }

    // MARK: - Rendering

    /// Draw all strokes for a page
    /// - Parameters:
    ///   - context: Graphics context
    ///   - page: Page index
    ///   - contentRect: Content rect for coordinate conversion (pass .zero if strokes are in content coords)
    ///   - useNormalized: Whether strokes are stored as normalized coordinates
    ///   - zoomScale: Current zoom scale (stroke width is divided by this for consistent visual thickness)
    func drawStrokes(in context: CGContext, page: Int, contentRect: CGRect, useNormalized: Bool = false, zoomScale: CGFloat = 1.0) {
        let strokes = pageStrokes.getStrokes(forPage: page)

        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in strokes {
            guard !stroke.path.isEmpty else { continue }
            if stroke.path.count == 1 {
                // Draw a dot for single-point strokes
                drawDot(context: context, stroke: stroke, contentRect: contentRect, useNormalized: useNormalized, zoomScale: zoomScale)
            } else {
                drawSingleStroke(context: context, stroke: stroke, contentRect: contentRect, useNormalized: useNormalized, zoomScale: zoomScale)
            }
        }
    }

    /// Draw the active stroke being drawn
    func drawActiveStroke(in context: CGContext, page: Int, contentRect: CGRect, zoomScale: CGFloat = 1.0) {
        guard let stroke = activeStroke, stroke.page == page, !stroke.path.isEmpty else { return }

        // Single point - draw a dot
        if stroke.path.count == 1 {
            let point = stroke.path[0]
            let color = parseColor(strokeColor).withAlphaComponent(strokeOpacity)
            let radius = strokeWidth / zoomScale / 2
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            return
        }

        let color = parseColor(strokeColor).withAlphaComponent(strokeOpacity)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(strokeWidth / zoomScale)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.beginPath()
        context.move(to: stroke.path[0])

        // For small strokes, don't skip any points
        let minSkipDist: CGFloat = stroke.path.count < 10 ? 0 : 4

        var prevPoint = stroke.path[0]
        for i in 1..<stroke.path.count {
            let point = stroke.path[i]
            let dist = hypot(point.x - prevPoint.x, point.y - prevPoint.y)
            if dist < minSkipDist { continue }

            let midPoint = CGPoint(x: (prevPoint.x + point.x) / 2, y: (prevPoint.y + point.y) / 2)
            context.addQuadCurve(to: midPoint, control: prevPoint)
            prevPoint = point
        }

        context.addLine(to: stroke.path.last!)
        context.strokePath()
    }

    private func drawDot(context: CGContext, stroke: DrawingStroke, contentRect: CGRect, useNormalized: Bool, zoomScale: CGFloat = 1.0) {
        guard let firstPath = stroke.path.first, firstPath.count >= 2 else { return }

        let point: CGPoint
        if useNormalized {
            point = normalizedToContent(firstPath, contentRect: contentRect)
        } else {
            point = CGPoint(x: firstPath[0], y: firstPath[1])
        }

        let color = parseColor(stroke.color).withAlphaComponent(stroke.opacity)
        let radius = stroke.width / zoomScale / 2
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }

    private func drawSingleStroke(context: CGContext, stroke: DrawingStroke, contentRect: CGRect, useNormalized: Bool, zoomScale: CGFloat = 1.0) {
        let color = parseColor(stroke.color).withAlphaComponent(stroke.opacity)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(stroke.width / zoomScale)

        context.beginPath()

        let firstPoint: CGPoint
        if useNormalized {
            firstPoint = normalizedToContent(stroke.path[0], contentRect: contentRect)
        } else {
            firstPoint = CGPoint(x: stroke.path[0][0], y: stroke.path[0][1])
        }
        var prevPoint = firstPoint
        context.move(to: prevPoint)

        // For small strokes, don't skip any points
        let minSkipDist: CGFloat = stroke.path.count < 10 ? 0 : 8

        for i in 1..<stroke.path.count {
            let point: CGPoint
            if useNormalized {
                point = normalizedToContent(stroke.path[i], contentRect: contentRect)
            } else {
                guard stroke.path[i].count >= 2 else { continue }
                point = CGPoint(x: stroke.path[i][0], y: stroke.path[i][1])
            }

            let dist = hypot(point.x - prevPoint.x, point.y - prevPoint.y)
            if dist < minSkipDist { continue }

            let midPoint = CGPoint(x: (prevPoint.x + point.x) / 2, y: (prevPoint.y + point.y) / 2)
            context.addQuadCurve(to: midPoint, control: prevPoint)
            prevPoint = point
        }

        let lastPoint: CGPoint
        if useNormalized {
            lastPoint = normalizedToContent(stroke.path.last!, contentRect: contentRect)
        } else {
            let last = stroke.path.last!
            lastPoint = CGPoint(x: last[0], y: last[1])
        }
        context.addLine(to: lastPoint)
        context.strokePath()
    }

    // MARK: - Export

    /// Get all annotations as a dictionary suitable for sending to React Native
    func getAnnotationsForExport() -> [String: [[String: Any]]] {
        var result: [String: [[String: Any]]] = [:]
        let allStrokes = pageStrokes.getAllStrokes()

        for (page, strokes) in allStrokes {
            var strokesArray: [[String: Any]] = []
            for stroke in strokes {
                let strokeDict: [String: Any] = [
                    "id": stroke.id,
                    "color": stroke.color,
                    "width": stroke.width,
                    "opacity": stroke.opacity,
                    "path": simplifyPath(stroke.path)
                ]
                strokesArray.append(strokeDict)
            }
            result[String(page)] = strokesArray
        }

        return result
    }

    /// Simplify path using Ramer-Douglas-Peucker algorithm
    /// Removes points that don't contribute significantly to the shape
    private func simplifyPath(_ path: [[CGFloat]], epsilon: CGFloat = 1.5) -> [[CGFloat]] {
        guard path.count > 2 else { return path }

        // Convert to points for easier processing
        let points = path.compactMap { arr -> CGPoint? in
            guard arr.count >= 2 else { return nil }
            return CGPoint(x: arr[0], y: arr[1])
        }

        guard points.count > 2 else { return path }

        // Apply RDP algorithm
        let simplified = rdpSimplify(points: points, epsilon: epsilon)

        // Convert back to array format
        return simplified.map { [$0.x, $0.y] }
    }

    /// Ramer-Douglas-Peucker line simplification algorithm
    private func rdpSimplify(points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }

        // Find the point with maximum distance from line between first and last
        var maxDistance: CGFloat = 0
        var maxIndex = 0

        let first = points.first!
        let last = points.last!

        for i in 1..<points.count - 1 {
            let distance = perpendicularDistance(point: points[i], lineStart: first, lineEnd: last)
            if distance > maxDistance {
                maxDistance = distance
                maxIndex = i
            }
        }

        // If max distance is greater than epsilon, recursively simplify
        if maxDistance > epsilon {
            let left = rdpSimplify(points: Array(points[0...maxIndex]), epsilon: epsilon)
            let right = rdpSimplify(points: Array(points[maxIndex...]), epsilon: epsilon)

            // Combine results (removing duplicate point at maxIndex)
            return Array(left.dropLast()) + right
        } else {
            // All points between first and last can be removed
            return [first, last]
        }
    }

    /// Calculate perpendicular distance from point to line
    private func perpendicularDistance(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y

        // If line is a point, return distance to that point
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 {
            return hypot(point.x - lineStart.x, point.y - lineStart.y)
        }

        // Calculate perpendicular distance using cross product
        let numerator = abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x)
        let denominator = sqrt(lengthSquared)

        return numerator / denominator
    }

    // MARK: - Helpers

    private func parseColor(_ hex: String) -> UIColor {
        return UIColor(hexString: hex) ?? .black
    }
}
