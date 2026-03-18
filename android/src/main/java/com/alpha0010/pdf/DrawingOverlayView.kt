package com.alpha0010.pdf

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.RectF
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
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

    // Horizontal offset for zoom panning (in screen coordinates)
    var offsetX: Float = 0f

    // RecyclerView paddingTop (needed to align overlay with RV content in multi-page mode)
    var recyclerPaddingTop: Float = 0f

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

    private val textPaint = TextPaint().apply {
        isAntiAlias = true
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

        // Draw text annotations
        drawTexts(canvas, controller, pageIndex, contentRect)
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
        val scaledPaddingTop = recyclerPaddingTop * zoomScale

        // Calculate which pages are visible (using unscaled values for calculation)
        val viewHeight = height.toFloat()
        val firstVisiblePage = ((scrollOffset / pageHeight).toInt()).coerceAtLeast(0)
        val lastVisiblePage = (((scrollOffset + viewHeight / zoomScale) / pageHeight).toInt() + 1).coerceAtMost(pageCount - 1)

        Log.d("DRAW_DEBUG", "=== RENDER ===")
        Log.d("DRAW_DEBUG", "zoomScale=$zoomScale, scrollOffset=$scrollOffset, scaledScrollOffset=$scaledScrollOffset, offsetX=$offsetX")
        Log.d("DRAW_DEBUG", "pageHeight=$pageHeight, scaledPageHeight=$scaledPageHeight, scaledWidth=$scaledWidth")
        Log.d("DRAW_DEBUG", "viewWidth=$width, viewHeight=$height")

        // Draw strokes for each visible page
        for (page in firstVisiblePage..lastVisiblePage) {
            // Page position in scaled coordinates
            // scaledPaddingTop accounts for RecyclerView padding that shifts content down
            // offsetX is the horizontal pan offset - we add it to pageRect so strokes align with PDF content
            val pageTop = scaledPaddingTop + page * scaledPageHeight - scaledScrollOffset
            val pageRect = RectF(offsetX, pageTop, offsetX + scaledWidth, pageTop + scaledPageHeight)

            // Draw completed strokes
            val strokes = controller.getStrokes(page)
            if (strokes.isNotEmpty()) {
                Log.d("DRAW_DEBUG", "Page $page: pageTop=$pageTop, pageRect=$pageRect, strokes=${strokes.size}")
                // Log first stroke's first point conversion
                val firstStroke = strokes.first()
                if (firstStroke.path.isNotEmpty()) {
                    val pt = firstStroke.path.first()
                    val screenX = pageRect.left + pt.x * pageRect.width()
                    val screenY = pageRect.top + pt.y * pageRect.height()
                    Log.d("DRAW_DEBUG", "First stroke point: normalized=(${pt.x}, ${pt.y}) -> screen=($screenX, $screenY)")
                }
            }
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

            // Draw text annotations
            drawTexts(canvas, controller, page, pageRect)
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

    private fun drawTexts(canvas: Canvas, controller: DrawingController, page: Int, rect: RectF) {
        val texts = controller.getTexts(page)
        if (texts.isEmpty() || rect.isEmpty) return

        for (text in texts) {
            if (text.point.size < 2) continue

            val color = try { Color.parseColor(text.color) } catch (e: Exception) { Color.BLUE }
            textPaint.color = color
            // In single-page mode parent scales, in multi-page mode we scale manually
            val scale = if (multiPageMode) zoomScale else 1f
            textPaint.textSize = text.fontSize * resources.displayMetrics.density * scale

            val x = rect.left + text.point[0] * rect.width()
            val y = rect.top + text.point[1] * rect.height()
            // Large width prevents word-wrap; \n still creates line breaks
            val largeWidth = 100000

            canvas.save()
            canvas.translate(x, y)
            val layout = StaticLayout.Builder.obtain(text.str, 0, text.str.length, textPaint, largeWidth)
                .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .setLineSpacing(0f, 1f)
                .setIncludePad(false)
                .build()
            layout.draw(canvas)
            canvas.restore()
        }
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
