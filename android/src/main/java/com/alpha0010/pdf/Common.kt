package com.alpha0010.pdf

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.RectF
import android.graphics.pdf.PdfRenderer
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableArray
import com.facebook.react.bridge.WritableMap
import org.json.JSONArray
import java.util.UUID
import java.util.concurrent.locks.Lock
import kotlin.concurrent.withLock
import kotlin.math.hypot
import androidx.core.graphics.createBitmap

const val SLICES = 4

enum class ResizeMode(val jsName: String) {
  CONTAIN("contain"),
  FIT_WIDTH("fitWidth")
}

// --- Drawing Mode ---

enum class DrawingMode(val jsName: String) {
    VIEW("view"),
    DRAW("draw"),
    ERASE("erase"),
    HIGHLIGHT("highlight"),
    TEXT("text");

    companion object {
        fun fromString(value: String): DrawingMode {
            return entries.find { it.jsName == value } ?: VIEW
        }
    }
}

// --- Drawing Stroke ---

data class DrawingStroke(
    val id: String,
    val color: String,
    val width: Float,
    val opacity: Float,
    val path: MutableList<PointF>
) {
    fun toWritableMap(): WritableMap {
        val map = Arguments.createMap()
        map.putString("id", id)
        map.putString("color", color)
        map.putDouble("width", width.toDouble())
        map.putDouble("opacity", opacity.toDouble())

        val pathArray = Arguments.createArray()
        for (point in path) {
            val pointArray = Arguments.createArray()
            pointArray.pushDouble(point.x.toDouble())
            pointArray.pushDouble(point.y.toDouble())
            pathArray.pushArray(pointArray)
        }
        map.putArray("path", pathArray)

        return map
    }
}

// --- Drawing Text ---

data class DrawingText(
    val id: String,
    val color: String,
    val fontSize: Float,
    val point: List<Float>,  // [normalizedX, normalizedY]
    val str: String
)

// --- Page Texts Storage ---

class PageTexts {
    private val texts = mutableMapOf<Int, MutableList<DrawingText>>()

    fun getTexts(forPage: Int): List<DrawingText> {
        return texts[forPage] ?: emptyList()
    }

    fun addText(text: DrawingText, toPage: Int) {
        val pageList = texts.getOrPut(toPage) { mutableListOf() }
        pageList.add(text)
    }

    fun removeText(withId: String, fromPage: Int): Boolean {
        val pageList = texts[fromPage] ?: return false
        return pageList.removeAll { it.id == withId }
    }

    fun clearTexts(forPage: Int) {
        texts.remove(forPage)
    }

    fun clearAllTexts() {
        texts.clear()
    }

    fun getAllTexts(): Map<Int, List<DrawingText>> {
        return texts.toMap()
    }
}

// --- Page Strokes Storage ---

class PageStrokes {
    private val strokes = mutableMapOf<Int, MutableList<DrawingStroke>>()

    fun setStrokes(pageStrokes: List<DrawingStroke>, forPage: Int) {
        strokes[forPage] = pageStrokes.toMutableList()
    }

    fun getStrokes(forPage: Int): List<DrawingStroke> {
        return strokes[forPage] ?: emptyList()
    }

    fun addStroke(stroke: DrawingStroke, toPage: Int) {
        val pageList = strokes.getOrPut(toPage) { mutableListOf() }
        pageList.add(stroke)
    }

    fun removeStroke(withId: String, fromPage: Int): Boolean {
        val pageList = strokes[fromPage] ?: return false
        return pageList.removeAll { it.id == withId }
    }

    fun clearStrokes(forPage: Int) {
        strokes.remove(forPage)
    }

    fun clearAllStrokes() {
        strokes.clear()
    }

    fun getAllStrokes(): Map<Int, List<DrawingStroke>> {
        return strokes.toMap()
    }
}

// --- Drawing Controller ---

// --- Undo Action ---

sealed class UndoAction {
    data class AddStroke(val page: Int, val stroke: DrawingStroke) : UndoAction()
    data class RemoveStroke(val page: Int, val stroke: DrawingStroke) : UndoAction()
    data class AddText(val page: Int, val text: DrawingText) : UndoAction()
    data class RemoveText(val page: Int, val text: DrawingText) : UndoAction()
    data class MoveText(val page: Int, val textId: String, val fromPoint: List<Float>, val toPoint: List<Float>) : UndoAction()
}

interface DrawingControllerDelegate {
    fun onDrawingStart()
    fun onDrawingEnd()
    fun onStrokeAdded(stroke: DrawingStroke, page: Int)
    fun onStrokeRemoved(strokeId: String, page: Int)
    fun onStrokesCleared(page: Int)
    fun onNeedsRedraw()
    fun onUndoStateChanged(canUndo: Boolean, canRedo: Boolean)
}

class DrawingController {
    var delegate: DrawingControllerDelegate? = null

    var drawingMode: DrawingMode = DrawingMode.VIEW
    var strokeColor: String = "#000000"
    var strokeWidth: Float = 3f
    var strokeOpacity: Float = 1f

    private val pageStrokes = PageStrokes()
    private val pageTexts = PageTexts()
    private var activeStroke: Pair<Int, MutableList<PointF>>? = null
    var isDrawing: Boolean = false
        private set

    // Undo/redo
    private val undoStack = mutableListOf<UndoAction>()
    private val redoStack = mutableListOf<UndoAction>()
    private val maxUndoStackSize = 50
    val canUndo: Boolean get() = undoStack.isNotEmpty()
    val canRedo: Boolean get() = redoStack.isNotEmpty()

    // Text props
    var textColor: String = "#0000FF"
    var textFontSize: Float = 16f

    // Stroke management

    fun setStrokes(strokes: List<DrawingStroke>, forPage: Int) {
        pageStrokes.setStrokes(strokes, forPage)
    }

    fun getStrokes(forPage: Int): List<DrawingStroke> {
        return pageStrokes.getStrokes(forPage)
    }

    fun clearStrokes(forPage: Int) {
        pageStrokes.clearStrokes(forPage)
        clearUndoStack()
        delegate?.onStrokesCleared(forPage)
    }

    fun clearAllStrokes() {
        pageStrokes.clearAllStrokes()
        clearUndoStack()
    }

    // Text management

    fun addText(text: DrawingText, toPage: Int) {
        pageTexts.addText(text, toPage)
    }

    fun getTexts(forPage: Int): List<DrawingText> {
        return pageTexts.getTexts(forPage)
    }

    fun removeText(withId: String, fromPage: Int): Boolean {
        return pageTexts.removeText(withId, fromPage)
    }

    fun clearTexts(forPage: Int) {
        pageTexts.clearTexts(forPage)
    }

    fun clearAllTexts() {
        pageTexts.clearAllTexts()
    }

    // Undoable text operations

    fun addTextWithUndo(text: DrawingText, toPage: Int) {
        pageTexts.addText(text, toPage)
        pushUndoAction(UndoAction.AddText(toPage, text))
    }

    fun removeTextWithUndo(withId: String, fromPage: Int) {
        val text = pageTexts.getTexts(fromPage).firstOrNull { it.id == withId } ?: return
        pageTexts.removeText(withId, fromPage)
        pushUndoAction(UndoAction.RemoveText(fromPage, text))
    }

    fun moveTextWithUndo(withId: String, fromPoint: List<Float>, toPoint: List<Float>, onPage: Int) {
        // Update text position in pageTexts
        val texts = pageTexts.getTexts(onPage).toMutableList()
        val index = texts.indexOfFirst { it.id == withId }
        if (index >= 0) {
            texts[index] = texts[index].copy(point = toPoint)
            pageTexts.clearTexts(onPage)
            texts.forEach { pageTexts.addText(it, onPage) }
        }
        pushUndoAction(UndoAction.MoveText(onPage, withId, fromPoint, toPoint))
    }

    // Undo/Redo

    fun undo() {
        val action = undoStack.removeLastOrNull() ?: return
        when (action) {
            is UndoAction.AddStroke -> pageStrokes.removeStroke(action.stroke.id, action.page)
            is UndoAction.RemoveStroke -> pageStrokes.addStroke(action.stroke, action.page)
            is UndoAction.AddText -> pageTexts.removeText(action.text.id, action.page)
            is UndoAction.RemoveText -> pageTexts.addText(action.text, action.page)
            is UndoAction.MoveText -> moveTextInternal(action.textId, action.fromPoint, action.page)
        }
        redoStack.add(action)
        notifyUndoStateChanged()
        delegate?.onNeedsRedraw()
    }

    fun redo() {
        val action = redoStack.removeLastOrNull() ?: return
        when (action) {
            is UndoAction.AddStroke -> pageStrokes.addStroke(action.stroke, action.page)
            is UndoAction.RemoveStroke -> pageStrokes.removeStroke(action.stroke.id, action.page)
            is UndoAction.AddText -> pageTexts.addText(action.text, action.page)
            is UndoAction.RemoveText -> pageTexts.removeText(action.text.id, action.page)
            is UndoAction.MoveText -> moveTextInternal(action.textId, action.toPoint, action.page)
        }
        undoStack.add(action)
        notifyUndoStateChanged()
        delegate?.onNeedsRedraw()
    }

    private fun moveTextInternal(textId: String, toPoint: List<Float>, page: Int) {
        val texts = pageTexts.getTexts(page).toMutableList()
        val index = texts.indexOfFirst { it.id == textId }
        if (index >= 0) {
            texts[index] = texts[index].copy(point = toPoint)
            pageTexts.clearTexts(page)
            texts.forEach { pageTexts.addText(it, page) }
        }
    }

    private fun pushUndoAction(action: UndoAction) {
        undoStack.add(action)
        if (undoStack.size > maxUndoStackSize) {
            undoStack.removeFirst()
        }
        redoStack.clear()
        notifyUndoStateChanged()
    }

    fun clearUndoStack() {
        undoStack.clear()
        redoStack.clear()
        notifyUndoStateChanged()
    }

    private fun notifyUndoStateChanged() {
        delegate?.onUndoStateChanged(canUndo, canRedo)
    }

    // Touch handling

    fun handleTouchBegan(point: PointF, page: Int, contentRect: RectF) {
        if (drawingMode == DrawingMode.VIEW) return

        if (drawingMode == DrawingMode.ERASE) {
            eraseStroke(point, page, contentRect)
        } else {
            // Don't redraw yet — wait for first move to avoid
            // visual flash when a second finger arrives and pinch cancels
            isDrawing = true
            activeStroke = Pair(page, mutableListOf(point))
            delegate?.onDrawingStart()
        }
    }

    fun handleTouchMoved(point: PointF, page: Int, contentRect: RectF) {
        if (drawingMode == DrawingMode.VIEW) return

        if (drawingMode == DrawingMode.ERASE) {
            eraseStroke(point, page, contentRect)
        } else if (isDrawing) {
            activeStroke?.let { (strokePage, path) ->
                if (strokePage == page) {
                    path.add(point)
                    delegate?.onNeedsRedraw()
                }
            }
        }
    }

    fun handleTouchEnded(page: Int) {
        if (drawingMode == DrawingMode.VIEW) return

        activeStroke?.let { (strokePage, path) ->
            if (path.isNotEmpty() && strokePage == page) {
                finishStroke(page)
            }
        }

        isDrawing = false
        activeStroke = null
        delegate?.onDrawingEnd()
        delegate?.onNeedsRedraw()
    }

    fun handleTouchCancelled() {
        isDrawing = false
        activeStroke = null
        delegate?.onDrawingEnd()
        delegate?.onNeedsRedraw()
    }

    private fun finishStroke(page: Int) {
        val (_, path) = activeStroke ?: return

        val width = if (drawingMode == DrawingMode.HIGHLIGHT) 20f else strokeWidth
        val opacity = if (drawingMode == DrawingMode.HIGHLIGHT) 0.3f else strokeOpacity

        val newStroke = DrawingStroke(
            id = UUID.randomUUID().toString(),
            color = strokeColor,
            width = width,
            opacity = opacity,
            path = path.toMutableList()
        )

        pageStrokes.addStroke(newStroke, page)
        pushUndoAction(UndoAction.AddStroke(page, newStroke))
        delegate?.onStrokeAdded(newStroke, page)
    }

    private fun eraseStroke(point: PointF, page: Int, contentRect: RectF) {
        val threshold = 0.03f // 3% of content size
        val strokes = pageStrokes.getStrokes(page)

        for (stroke in strokes.reversed()) {
            for (strokePoint in stroke.path) {
                val dist = hypot(point.x - strokePoint.x, point.y - strokePoint.y)
                if (dist < threshold) {
                    if (pageStrokes.removeStroke(stroke.id, page)) {
                        pushUndoAction(UndoAction.RemoveStroke(page, stroke))
                        delegate?.onStrokeRemoved(stroke.id, page)
                        delegate?.onNeedsRedraw()
                    }
                    return
                }
            }
        }

        // Check text annotations
        val texts = pageTexts.getTexts(page)
        for (text in texts.reversed()) {
            if (text.point.size < 2) continue

            val textX = text.point[0]
            val textY = text.point[1]

            val paint = Paint().apply {
                textSize = text.fontSize
                isAntiAlias = true
            }
            val textWidth = paint.measureText(text.str)
            val normalizedWidth = if (contentRect.width() > 0) textWidth / contentRect.width() else 0f
            val normalizedHeight = if (contentRect.height() > 0) text.fontSize / contentRect.height() else 0f

            val padding = 0.02f
            val hitRect = RectF(
                textX - padding,
                textY - padding,
                textX + normalizedWidth + padding * 2,
                textY + normalizedHeight + padding * 2
            )

            if (hitRect.contains(point.x, point.y)) {
                pageTexts.removeText(text.id, page)
                pushUndoAction(UndoAction.RemoveText(page, text))
                delegate?.onNeedsRedraw()
                return
            }
        }
    }

    // Get active stroke for drawing

    fun getActiveStroke(): Pair<Int, List<PointF>>? {
        return activeStroke?.let { Pair(it.first, it.second.toList()) }
    }

    // Export

    fun getAnnotationsForExport(): WritableMap {
        val result = Arguments.createMap()
        val allStrokes = pageStrokes.getAllStrokes()
        val allTexts = pageTexts.getAllTexts()
        val allPages = allStrokes.keys + allTexts.keys

        for (page in allPages) {
            val pageMap = Arguments.createMap()

            // Strokes
            val strokesArray = Arguments.createArray()
            val strokes = allStrokes[page] ?: emptyList()
            for (stroke in strokes) {
                val strokeMap = Arguments.createMap()
                strokeMap.putString("id", stroke.id)
                strokeMap.putString("color", stroke.color)
                strokeMap.putDouble("width", stroke.width.toDouble())
                strokeMap.putDouble("opacity", stroke.opacity.toDouble())

                val simplifiedPath = simplifyPath(stroke.path)
                val pathArray = Arguments.createArray()
                for (point in simplifiedPath) {
                    val pointArray = Arguments.createArray()
                    pointArray.pushDouble(point.x.toDouble())
                    pointArray.pushDouble(point.y.toDouble())
                    pathArray.pushArray(pointArray)
                }
                strokeMap.putArray("path", pathArray)
                strokesArray.pushMap(strokeMap)
            }
            pageMap.putArray("strokes", strokesArray)

            // Texts
            val textsArray = Arguments.createArray()
            val texts = allTexts[page] ?: emptyList()
            for (text in texts) {
                val textMap = Arguments.createMap()
                textMap.putString("color", text.color)
                textMap.putDouble("fontSize", text.fontSize.toDouble())
                textMap.putString("str", text.str)
                val pointArray = Arguments.createArray()
                pointArray.pushDouble(text.point[0].toDouble())
                pointArray.pushDouble(text.point[1].toDouble())
                textMap.putArray("point", pointArray)
                textsArray.pushMap(textMap)
            }
            pageMap.putArray("text", textsArray)

            result.putMap(page.toString(), pageMap)
        }

        return result
    }

    // Path simplification using Ramer-Douglas-Peucker algorithm

    private fun simplifyPath(path: List<PointF>, epsilon: Float = 0.002f): List<PointF> {
        if (path.size <= 2) return path
        return rdpSimplify(path, epsilon)
    }

    private fun rdpSimplify(points: List<PointF>, epsilon: Float): List<PointF> {
        if (points.size <= 2) return points

        var maxDistance = 0f
        var maxIndex = 0

        val first = points.first()
        val last = points.last()

        for (i in 1 until points.size - 1) {
            val distance = perpendicularDistance(points[i], first, last)
            if (distance > maxDistance) {
                maxDistance = distance
                maxIndex = i
            }
        }

        return if (maxDistance > epsilon) {
            val left = rdpSimplify(points.subList(0, maxIndex + 1), epsilon)
            val right = rdpSimplify(points.subList(maxIndex, points.size), epsilon)
            left.dropLast(1) + right
        } else {
            listOf(first, last)
        }
    }

    private fun perpendicularDistance(point: PointF, lineStart: PointF, lineEnd: PointF): Float {
        val dx = lineEnd.x - lineStart.x
        val dy = lineEnd.y - lineStart.y

        val lengthSquared = dx * dx + dy * dy
        if (lengthSquared == 0f) {
            return hypot(point.x - lineStart.x, point.y - lineStart.y)
        }

        val numerator = kotlin.math.abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x)
        val denominator = kotlin.math.sqrt(lengthSquared)

        return numerator / denominator
    }
}

// --- Annotation Data Classes ---



/**
 * Parses annotations JSON string to list of AnnotationPage.
 */
fun parseAnnotations(json: String?): List<AnnotationPage> {
    if (json.isNullOrEmpty()) return emptyList()

    return try {
        val jsonArray = JSONArray(json)
        val result = mutableListOf<AnnotationPage>()

        for (i in 0 until jsonArray.length()) {
            val pageObj = jsonArray.getJSONObject(i)

            val strokesArray = pageObj.getJSONArray("strokes")
            val strokes = mutableListOf<Stroke>()
            for (j in 0 until strokesArray.length()) {
                val strokeObj = strokesArray.getJSONObject(j)
                val pathArray = strokeObj.getJSONArray("path")
                val path = mutableListOf<List<Float>>()
                for (k in 0 until pathArray.length()) {
                    val pointArray = pathArray.getJSONArray(k)
                    path.add(listOf(
                        pointArray.getDouble(0).toFloat(),
                        pointArray.getDouble(1).toFloat()
                    ))
                }
                strokes.add(Stroke(
                    color = strokeObj.getString("color"),
                    width = strokeObj.getDouble("width").toFloat(),
                    path = path
                ))
            }

            val textArray = pageObj.getJSONArray("text")
            val texts = mutableListOf<PositionedText>()
            for (j in 0 until textArray.length()) {
                val textObj = textArray.getJSONObject(j)
                val pointArray = textObj.getJSONArray("point")
                texts.add(PositionedText(
                    color = textObj.getString("color"),
                    fontSize = textObj.getDouble("fontSize").toFloat(),
                    point = listOf(
                        pointArray.getDouble(0).toFloat(),
                        pointArray.getDouble(1).toFloat()
                    ),
                    str = textObj.getString("str")
                ))
            }

            result.add(AnnotationPage(strokes, texts))
        }
        result
    } catch (e: Exception) {
        emptyList()
    }
}

/**
 * Parses hex color string to Android Color int.
 */
fun parseColor(hexColor: String): Int {
    return try {
        Color.parseColor(hexColor)
    } catch (e: Exception) {
        Color.BLACK
    }
}

/**
 * Shared PDF page rendering utility.
 */
object PdfPageRenderer {

    /**
     * Renders a PDF page to a Bitmap.
     * Must be called from a background thread.
     *
     * @param renderer The PdfRenderer instance
     * @param pdfMutex Lock for thread-safe PDF access
     * @param pageIndex Zero-based page index
     * @param viewWidth Width to render into
     * @param pageHeight Height to render into
     * @param annotation Optional annotation for this page
     * @return Rendered bitmap or null on failure
     */
    fun renderPage(
        renderer: PdfRenderer,
        pdfMutex: Lock,
        pageIndex: Int,
        viewWidth: Int,
        pageHeight: Int,
        annotation: AnnotationPage? = null
    ): Bitmap? {
        if (viewWidth <= 0 || pageHeight <= 0) return null

        return pdfMutex.withLock {
            try {
                val page = renderer.openPage(pageIndex)
                val bitmap = createBitmap(viewWidth, pageHeight)
                bitmap.eraseColor(Color.WHITE)

                val matrix = Matrix()
                matrix.setScale(
                    viewWidth.toFloat() / page.width,
                    pageHeight.toFloat() / page.height
                )

                page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                page.close()

                // Draw annotations if present
                if (annotation != null) {
                    val canvas = Canvas(bitmap)

                    // Draw strokes
                    for (stroke in annotation.strokes) {
                        if (stroke.path.size < 2) continue

                        val paint = Paint().apply {
                            color = parseColor(stroke.color)
                            strokeWidth = stroke.width * 2 // Scale for density
                            style = Paint.Style.STROKE
                            strokeCap = Paint.Cap.ROUND
                            strokeJoin = Paint.Join.ROUND
                            isAntiAlias = true
                        }

                        val path = Path()
                        stroke.path.forEachIndexed { index, point ->
                            if (point.size >= 2) {
                                val x = point[0] * viewWidth
                                val y = point[1] * pageHeight
                                if (index == 0) {
                                    path.moveTo(x, y)
                                } else {
                                    path.lineTo(x, y)
                                }
                            }
                        }
                        canvas.drawPath(path, paint)
                    }

                    // Draw text annotations
                    for (text in annotation.text) {
                        if (text.point.size < 2) continue

                        val paint = Paint().apply {
                            color = parseColor(text.color)
                            textSize = text.fontSize * 2 // Scale for density
                            isAntiAlias = true
                        }

                        val x = text.point[0] * viewWidth
                        val y = text.point[1] * pageHeight + paint.textSize // Adjust for baseline
                        canvas.drawText(text.str, x, y, paint)
                    }
                }

                bitmap
            } catch (e: Exception) {
                null
            }
        }
    }
}
