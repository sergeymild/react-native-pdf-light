package com.alpha0010.pdf

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.RectF
import android.util.Log
import android.view.View
import kotlin.math.hypot

/**
 * Transparent overlay view for drawing strokes on top of PDF content.
 */
class DrawingOverlayView(context: Context) : View(context) {

    var drawingController: DrawingController? = null
    var pageIndex: Int = 0
    var contentRect: RectF = RectF()
    var zoomScale: Float = 1f

    // Multi-page mode for ZoomablePdfScrollView
    var multiPageMode: Boolean = false
    var pageCount: Int = 0
    var pageHeight: Float = 0f
    var scrollOffset: Float = 0f

    private val strokePaint = Paint().apply {
        isAntiAlias = true
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private val fillPaint = Paint().apply {
        isAntiAlias = true
        style = Paint.Style.FILL
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val controller = drawingController ?: return

        // Debug logging
        val activeStroke = controller.getActiveStroke()
        val strokeCount = controller.getStrokes(pageIndex).size
        Log.d("DrawingOverlay", "onDraw: multiPageMode=$multiPageMode, pageIndex=$pageIndex, " +
                "width=$width, height=$height, contentRect=$contentRect, zoomScale=$zoomScale, " +
                "strokes=$strokeCount, activeStroke=${activeStroke != null}")

        if (multiPageMode) {
            drawMultiPage(canvas, controller)
        } else {
            drawSinglePage(canvas, controller)
        }
    }

    private fun drawSinglePage(canvas: Canvas, controller: DrawingController) {
        if (contentRect.isEmpty) {
            Log.d("DrawingOverlay", "drawSinglePage: contentRect is empty!")
            return
        }

        // Draw completed strokes
        val strokes = controller.getStrokes(pageIndex)
        val activeStroke = controller.getActiveStroke()
        Log.d("DrawingOverlay", "drawSinglePage: pageIndex=$pageIndex, strokes=${strokes.size}, activeStroke=${activeStroke != null}, contentRect=$contentRect")

        for (stroke in strokes) {
            if (stroke.path.isEmpty()) continue

            if (stroke.path.size == 1) {
                drawDot(canvas, stroke, contentRect)
            } else {
                drawStroke(canvas, stroke, contentRect)
            }
        }

        // Draw active stroke
        activeStroke?.let { (strokePage, path) ->
            if (strokePage == pageIndex && path.isNotEmpty()) {
                Log.d("DrawingOverlay", "drawSinglePage: drawing active stroke with ${path.size} points")
                if (path.size == 1) {
                    drawActiveDot(canvas, path[0], controller, contentRect)
                } else {
                    drawActivePath(canvas, path, controller, contentRect)
                }
            }
        }
    }

    private fun drawMultiPage(canvas: Canvas, controller: DrawingController) {
        if (pageHeight <= 0 || pageCount <= 0) {
            Log.d("DrawingOverlay", "drawMultiPage: early return - pageHeight=$pageHeight, pageCount=$pageCount")
            return
        }

        // Calculate scaled dimensions for zoom
        val scaledPageHeight = pageHeight * zoomScale
        val scaledWidth = width * zoomScale
        val scaledScrollOffset = scrollOffset * zoomScale

        // Calculate which pages are visible (using unscaled values for calculation)
        val viewHeight = height.toFloat()
        val firstVisiblePage = ((scrollOffset / pageHeight).toInt()).coerceAtLeast(0)
        val lastVisiblePage = (((scrollOffset + viewHeight / zoomScale) / pageHeight).toInt() + 1).coerceAtMost(pageCount - 1)

        Log.d("DrawingOverlay", "drawMultiPage: firstVisiblePage=$firstVisiblePage, lastVisiblePage=$lastVisiblePage, zoomScale=$zoomScale")

        // Draw strokes for each visible page
        for (page in firstVisiblePage..lastVisiblePage) {
            // Page position in scaled coordinates
            val pageTop = page * scaledPageHeight - scaledScrollOffset
            val pageRect = RectF(0f, pageTop, scaledWidth, pageTop + scaledPageHeight)

            // Draw completed strokes
            val strokes = controller.getStrokes(page)
            for (stroke in strokes) {
                if (stroke.path.isEmpty()) continue

                if (stroke.path.size == 1) {
                    drawDot(canvas, stroke, pageRect)
                } else {
                    drawStroke(canvas, stroke, pageRect)
                }
            }

            // Draw active stroke
            controller.getActiveStroke()?.let { (strokePage, path) ->
                if (strokePage == page && path.isNotEmpty()) {
                    if (path.size == 1) {
                        drawActiveDot(canvas, path[0], controller, pageRect)
                    } else {
                        drawActivePath(canvas, path, controller, pageRect)
                    }
                }
            }
        }
    }

    private fun drawStroke(canvas: Canvas, stroke: DrawingStroke, rect: RectF) {
        val color = parseColorWithOpacity(stroke.color, stroke.opacity)
        strokePaint.color = color
        // In multiPageMode, overlay has no scale transform so we scale manually
        // In single page mode, overlay inherits scale from parent container
        val scale = if (multiPageMode) zoomScale else 1f
        strokePaint.strokeWidth = stroke.width * resources.displayMetrics.density * scale

        val path = buildPath(stroke.path, rect)
        canvas.drawPath(path, strokePaint)
    }

    private fun drawDot(canvas: Canvas, stroke: DrawingStroke, rect: RectF) {
        val point = stroke.path[0]
        val x = rect.left + point.x * rect.width()
        val y = rect.top + point.y * rect.height()

        val color = parseColorWithOpacity(stroke.color, stroke.opacity)
        fillPaint.color = color
        val scale = if (multiPageMode) zoomScale else 1f
        val radius = stroke.width * resources.displayMetrics.density * scale / 2

        canvas.drawCircle(x, y, radius, fillPaint)
    }

    private fun drawActivePath(canvas: Canvas, path: List<PointF>, controller: DrawingController, rect: RectF) {
        val color = parseColorWithOpacity(controller.strokeColor, controller.strokeOpacity)
        strokePaint.color = color
        val scale = if (multiPageMode) zoomScale else 1f
        strokePaint.strokeWidth = controller.strokeWidth * resources.displayMetrics.density * scale

        val drawPath = buildPath(path, rect)
        canvas.drawPath(drawPath, strokePaint)
    }

    private fun drawActiveDot(canvas: Canvas, point: PointF, controller: DrawingController, rect: RectF) {
        val x = rect.left + point.x * rect.width()
        val y = rect.top + point.y * rect.height()

        val color = parseColorWithOpacity(controller.strokeColor, controller.strokeOpacity)
        fillPaint.color = color
        val scale = if (multiPageMode) zoomScale else 1f
        val radius = controller.strokeWidth * resources.displayMetrics.density * scale / 2

        canvas.drawCircle(x, y, radius, fillPaint)
    }

    private fun buildPath(points: List<PointF>, rect: RectF): Path {
        val path = Path()
        if (points.isEmpty() || rect.isEmpty) return path

        val firstPoint = points.first()
        val firstX = rect.left + firstPoint.x * rect.width()
        val firstY = rect.top + firstPoint.y * rect.height()
        path.moveTo(firstX, firstY)

        // For 2-point strokes, just draw a straight line
        if (points.size == 2) {
            val lastPoint = points.last()
            val lastX = rect.left + lastPoint.x * rect.width()
            val lastY = rect.top + lastPoint.y * rect.height()
            path.lineTo(lastX, lastY)
            return path
        }

        var prevX = firstX
        var prevY = firstY
        for (i in 1 until points.size) {
            val point = points[i]
            val x = rect.left + point.x * rect.width()
            val y = rect.top + point.y * rect.height()

            val midX = (prevX + x) / 2
            val midY = (prevY + y) / 2
            path.quadTo(prevX, prevY, midX, midY)
            prevX = x
            prevY = y
        }

        val lastPoint = points.last()
        val lastX = rect.left + lastPoint.x * rect.width()
        val lastY = rect.top + lastPoint.y * rect.height()
        path.lineTo(lastX, lastY)

        return path
    }

    private fun parseColorWithOpacity(hexColor: String, opacity: Float): Int {
        val baseColor = try {
            Color.parseColor(hexColor)
        } catch (e: Exception) {
            Color.BLACK
        }
        val alpha = (opacity * 255).toInt().coerceIn(0, 255)
        return Color.argb(alpha, Color.red(baseColor), Color.green(baseColor), Color.blue(baseColor))
    }
}
