package com.alpha0010.pdf

import android.content.Context
import android.graphics.Color
import android.graphics.PointF
import android.graphics.RectF
import android.text.InputType
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.TextView
import java.util.UUID
import kotlin.math.hypot

/**
 * Delegate interface for TextAnnotationHandler.
 * Provides view-specific operations.
 */
interface TextAnnotationHandlerDelegate {
    val textHandlerDrawingController: DrawingController
    val textHandlerContentContainer: View
    val textHandlerHostView: ViewGroup
    val textHandlerZoomScale: Float
    fun textHandlerContentRectForPage(page: Int): RectF
    fun textHandlerPageForPoint(pointInContent: PointF): Int
    fun textHandlerRedrawOverlay()
}

/**
 * Reusable handler for text annotation input and dragging.
 * Used by both ZoomablePdfScrollView and PagingPdfView.
 */
class TextAnnotationHandler(private val context: Context) {

    var delegate: TextAnnotationHandlerDelegate? = null
    var textColor: String = "#0000FF"
    var textFontSize: Float = 16f

    // Text input state
    private var textInputView: EditText? = null
    private var textInputPage: Int = 0
    private var textInputNormalizedPoint: PointF = PointF()

    // Text drag state
    var isDraggingText: Boolean = false
        private set
    private var draggingTextPage: Int = 0
    private var draggingLabel: TextView? = null
    private var draggingTouchOffsetX: Float = 0f
    private var draggingTouchOffsetY: Float = 0f
    private var draggingText: DrawingText? = null

    // Pending touch: tap vs drag detection
    private var pendingText: DrawingText? = null       // existing text hit
    private var pendingNewTextPoint: PointF? = null     // new text tap (no hit)
    private var pendingNewTextEvent: MotionEvent? = null
    private var pendingTextPage: Int = 0
    private var pendingTouchStartX: Float = 0f
    private var pendingTouchStartY: Float = 0f
    private val dragThreshold: Float = 24f  // pixels
    private var pendingWasMultiTouch = false

    // Editing existing text
    private var editingTextId: String? = null
    private var editingTextColor: String? = null
    private var editingTextFontSize: Float? = null

    val hasActiveTextInput: Boolean get() = textInputView != null
    val hasPendingText: Boolean get() = pendingText != null || pendingNewTextPoint != null

    // Convert screen touch coordinates to content coordinates
    var screenToContentConverter: ((MotionEvent) -> PointF)? = null
    // Convert content coordinates back to screen (hostView) coordinates
    var contentToScreenConverter: ((PointF) -> PointF)? = null

    private fun screenToContent(event: MotionEvent): PointF {
        return screenToContentConverter?.invoke(event) ?: PointF(event.x, event.y)
    }

    private fun contentToScreen(contentPoint: PointF): PointF {
        return contentToScreenConverter?.invoke(contentPoint) ?: contentPoint
    }

    /**
     * Handle touch in text mode. Returns true if touch was consumed.
     */
    fun handleTouchDown(event: MotionEvent): Boolean {
        val delegate = delegate ?: return false

        // Clear any stale pending state from previous gesture
        if (hasPendingText) clearPending()

        // If there's a text input view, check if touch is outside it
        val existingInput = textInputView
        if (existingInput != null) {
            val loc = IntArray(2)
            existingInput.getLocationOnScreen(loc)
            val inputRect = RectF(
                loc[0].toFloat(), loc[1].toFloat(),
                (loc[0] + existingInput.width).toFloat(),
                (loc[1] + existingInput.height).toFloat()
            )
            val screenLoc = IntArray(2)
            delegate.textHandlerHostView.getLocationOnScreen(screenLoc)
            val touchScreenX = event.x + screenLoc[0]
            val touchScreenY = event.y + screenLoc[1]

            if (!inputRect.contains(touchScreenX, touchScreenY)) {
                commitTextInput()
                return true
            }
            return false
        }

        // Convert touch to content coordinates
        val contentPoint = screenToContent(event)
        val page = delegate.textHandlerPageForPoint(contentPoint)
        val pageRect = delegate.textHandlerContentRectForPage(page)
        if (pageRect.isEmpty) return false

        // Normalize
        val normalizedX = (contentPoint.x - pageRect.left) / pageRect.width()
        val normalizedY = (contentPoint.y - pageRect.top) / pageRect.height()
        val normalizedPoint = PointF(normalizedX, normalizedY)

        // Check if touching existing text — defer to detect tap vs drag
        val hitResult = hitTestTextAnnotation(normalizedPoint, page)
        if (hitResult != null) {
            val (_, textAnnotation) = hitResult
            pendingText = textAnnotation
            pendingTextPage = page
            pendingTouchStartX = event.x
            pendingTouchStartY = event.y
            return true
        }

        // No existing text — defer until touchUp to avoid opening on multi-finger
        pendingNewTextPoint = normalizedPoint
        pendingNewTextEvent = MotionEvent.obtain(event)
        pendingTextPage = page
        pendingTouchStartX = event.x
        pendingTouchStartY = event.y
        return true
    }

    fun handleTouchMove(event: MotionEvent): Boolean {
        val delegate = delegate ?: return false

        // Pending new text — cancel if finger moves (scroll/zoom gesture)
        if (pendingNewTextPoint != null) {
            val dist = hypot(event.x - pendingTouchStartX, event.y - pendingTouchStartY)
            if (dist >= dragThreshold) {
                pendingWasMultiTouch = true
                clearPending()
            }
            return true
        }

        // Pending existing text — check if finger moved enough to start drag
        val text = pendingText
        if (text != null) {
            val dist = hypot(event.x - pendingTouchStartX, event.y - pendingTouchStartY)
            if (dist >= dragThreshold) {
                startDraggingText(text, pendingTextPage, event)
                clearPending()
            }
            return true
        }

        if (!isDraggingText) return false
        val label = draggingLabel ?: return false

        val newX = (event.x - draggingTouchOffsetX).toInt()
        val newY = (event.y - draggingTouchOffsetY).toInt()
        label.layout(newX, newY, newX + label.width, newY + label.height)
        return true
    }

    fun handleTouchUp(event: MotionEvent): Boolean {
        // Pending existing text, no drag → tap to edit
        val text = pendingText
        if (text != null) {
            editExistingText(text, pendingTextPage)
            clearPending()
            return true
        }

        // Pending new text → tap to create
        val point = pendingNewTextPoint
        val ev = pendingNewTextEvent
        if (point != null && ev != null) {
            showTextInput(point, pendingTextPage, ev)
            clearPending()
            return true
        }

        if (!isDraggingText) return false
        finishDraggingText(event)
        return true
    }

    fun handleTouchCancel() {
        // Pending existing text cancelled (single finger) → treat as tap to edit
        val text = pendingText
        if (text != null && !pendingWasMultiTouch) {
            editExistingText(text, pendingTextPage)
            clearPending()
            return
        }

        // Pending new text cancelled — only open if not multi-touch
        val point = pendingNewTextPoint
        val ev = pendingNewTextEvent
        if (point != null && ev != null && !pendingWasMultiTouch) {
            showTextInput(point, pendingTextPage, ev)
            clearPending()
            return
        }

        if (hasPendingText) {
            clearPending()
            return
        }

        if (!isDraggingText) return
        // Restore text at original position
        val dragText = draggingText
        val del = delegate
        if (dragText != null && del != null) {
            del.textHandlerDrawingController.addText(dragText, draggingTextPage)
            del.textHandlerRedrawOverlay()
        }
        cancelDraggingText()
    }

    fun handleMultiTouchDetected() {
        pendingWasMultiTouch = true
        clearPending()
    }

    private fun clearPending() {
        pendingText = null
        pendingNewTextEvent?.recycle()
        pendingNewTextEvent = null
        pendingNewTextPoint = null
        pendingWasMultiTouch = false
    }

    // MARK: - Edit Existing Text

    private fun editExistingText(text: DrawingText, page: Int) {
        val delegate = delegate ?: return

        // Remove text so it doesn't render while editing
        delegate.textHandlerDrawingController.removeText(text.id, page)
        delegate.textHandlerRedrawOverlay()

        val normalizedPoint = PointF(text.point[0], text.point[1])
        editingTextId = text.id
        editingTextColor = text.color
        editingTextFontSize = text.fontSize

        // Convert text position to screen coordinates for the EditText
        val pageRect = delegate.textHandlerContentRectForPage(page)
        val contentX = pageRect.left + text.point[0] * pageRect.width()
        val contentY = pageRect.top + text.point[1] * pageRect.height()
        val screenPos = contentToScreen(PointF(contentX, contentY))
        val fakeEvent = MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, screenPos.x, screenPos.y, 0)

        showTextInput(normalizedPoint, page, fakeEvent, text.str, text.color, text.fontSize)
        fakeEvent.recycle()
    }

    // MARK: - Text Input

    private fun showTextInput(normalizedPoint: PointF, page: Int, event: MotionEvent,
                              existingText: String? = null, color: String? = null, fontSize: Float? = null) {
        val delegate = delegate ?: return

        textInputPage = page
        textInputNormalizedPoint = normalizedPoint

        val hostView = delegate.textHandlerHostView
        val zoomScale = delegate.textHandlerZoomScale
        val useFontSize = fontSize ?: textFontSize
        val useColor = color ?: textColor

        val screenX = event.x
        val screenY = event.y

        val editText = EditText(context).apply {
            setBackgroundColor(Color.TRANSPARENT)
            textSize = useFontSize * zoomScale
            setTextColor(try { Color.parseColor(useColor) } catch (e: Exception) { Color.BLUE })
            setPadding(0, 0, 0, 0)
            gravity = Gravity.TOP or Gravity.START
            // Multi-line, no auto-suggestions, no word-wrap
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            // Allow horizontal scrolling (no word-wrap)
            setHorizontallyScrolling(true)
            maxLines = Int.MAX_VALUE
            isSingleLine = false
            if (existingText != null) {
                setText(existingText)
                setSelection(existingText.length)
            }
        }

        val maxWidthScreen = (hostView.width - screenX.toInt()).coerceAtLeast(120)
        val lp = FrameLayout.LayoutParams(maxWidthScreen, ViewGroup.LayoutParams.WRAP_CONTENT)
        lp.leftMargin = screenX.toInt()
        lp.topMargin = screenY.toInt()

        hostView.addView(editText, lp)
        editText.measure(
            View.MeasureSpec.makeMeasureSpec(maxWidthScreen, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        editText.layout(lp.leftMargin, lp.topMargin, lp.leftMargin + editText.measuredWidth, lp.topMargin + editText.measuredHeight)
        editText.bringToFront()
        editText.requestFocus()

        // Re-measure on text change so height grows with newlines
        editText.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: android.text.Editable?) {
                editText.post {
                    val lineHeight = editText.lineHeight
                    val lineCount = editText.lineCount.coerceAtLeast(1)
                    val newHeight = lineCount * lineHeight + editText.paddingTop + editText.paddingBottom
                    editText.layout(lp.leftMargin, lp.topMargin, lp.leftMargin + maxWidthScreen, lp.topMargin + newHeight)
                }
            }
        })

        // Show keyboard
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        editText.postDelayed({ imm.showSoftInput(editText, InputMethodManager.SHOW_IMPLICIT) }, 100)

        textInputView = editText
    }

    fun commitTextInput() {
        val editText = textInputView ?: return
        val delegate = delegate ?: return

        val text = editText.text?.toString()?.trim() ?: ""

        // Hide keyboard
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.hideSoftInputFromWindow(editText.windowToken, 0)

        (editText.parent as? ViewGroup)?.removeView(editText)
        textInputView = null

        val existingId = editingTextId
        val existingColor = editingTextColor ?: textColor
        val existingFontSize = editingTextFontSize
        editingTextId = null
        editingTextColor = null
        editingTextFontSize = null

        if (text.isEmpty()) return

        val useFontSize = existingFontSize ?: textFontSize
        val useColor = if (existingId != null) existingColor else textColor
        val drawingText = DrawingText(
            id = existingId ?: UUID.randomUUID().toString(),
            color = useColor,
            fontSize = useFontSize,
            point = listOf(textInputNormalizedPoint.x, textInputNormalizedPoint.y),
            str = text
        )
        delegate.textHandlerDrawingController.addTextWithUndo(drawingText, textInputPage)
        delegate.textHandlerRedrawOverlay()
    }

    // MARK: - Hit Test

    private fun hitTestTextAnnotation(normalizedPoint: PointF, page: Int): Pair<Int, DrawingText>? {
        val delegate = delegate ?: return null

        val texts = delegate.textHandlerDrawingController.getTexts(page)
        val pageRect = delegate.textHandlerContentRectForPage(page)
        if (pageRect.isEmpty) return null

        for ((index, text) in texts.withIndex()) {
            if (text.point.size < 2) continue

            val textX = text.point[0]
            val textY = text.point[1]

            val paint = android.text.TextPaint().apply {
                textSize = text.fontSize * context.resources.displayMetrics.density
                isAntiAlias = true
            }
            val layout = android.text.StaticLayout.Builder.obtain(text.str, 0, text.str.length, paint, 100000)
                .setAlignment(android.text.Layout.Alignment.ALIGN_NORMAL)
                .setIncludePad(false)
                .build()
            var maxLineWidth = 0f
            for (i in 0 until layout.lineCount) {
                maxLineWidth = maxOf(maxLineWidth, layout.getLineWidth(i))
            }
            val normalizedWidth = maxLineWidth / pageRect.width()
            val normalizedHeight = layout.height.toFloat() / pageRect.height()

            val padding = 0.02f
            val hitRect = RectF(
                textX - padding,
                textY - padding,
                textX + normalizedWidth + padding * 2,
                textY + normalizedHeight + padding * 2
            )

            if (hitRect.contains(normalizedPoint.x, normalizedPoint.y)) {
                return Pair(index, text)
            }
        }
        return null
    }

    // MARK: - Text Dragging

    private fun startDraggingText(textAnnotation: DrawingText, page: Int, event: MotionEvent) {
        val delegate = delegate ?: return

        isDraggingText = true
        draggingTextPage = page
        draggingText = textAnnotation

        // Remove text from controller so overlay doesn't draw it
        delegate.textHandlerDrawingController.removeText(textAnnotation.id, page)
        delegate.textHandlerRedrawOverlay()

        val zoomScale = delegate.textHandlerZoomScale
        val pageRect = delegate.textHandlerContentRectForPage(page)
        val hostView = delegate.textHandlerHostView

        // Create floating label (multi-line)
        val label = TextView(context).apply {
            text = textAnnotation.str
            textSize = textAnnotation.fontSize * zoomScale
            setTextColor(
                (try { Color.parseColor(textAnnotation.color) } catch (e: Exception) { Color.BLUE })
                    .let { Color.argb(180, Color.red(it), Color.green(it), Color.blue(it)) }
            )
            setBackgroundColor(Color.TRANSPARENT)
        }

        // Convert text position from content to screen coordinates
        val contentX = pageRect.left + textAnnotation.point[0] * pageRect.width()
        val contentY = pageRect.top + textAnnotation.point[1] * pageRect.height()
        val screenPos = contentToScreen(PointF(contentX, contentY))
        val screenX = screenPos.x
        val screenY = screenPos.y

        val widthSpec = View.MeasureSpec.makeMeasureSpec(hostView.width, View.MeasureSpec.AT_MOST)
        val heightSpec = View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        label.measure(widthSpec, heightSpec)
        val lw = label.measuredWidth
        val lh = label.measuredHeight
        val left = screenX.toInt()
        val top = screenY.toInt()

        val lp = FrameLayout.LayoutParams(lw, lh)
        hostView.addView(label, lp)
        label.layout(left, top, left + lw, top + lh)
        label.bringToFront()

        draggingTouchOffsetX = event.x - screenX
        draggingTouchOffsetY = event.y - screenY
        draggingLabel = label
    }

    private fun finishDraggingText(event: MotionEvent) {
        val text = draggingText ?: return
        val delegate = delegate ?: run { cancelDraggingText(); return }

        val labelX = event.x - draggingTouchOffsetX
        val labelY = event.y - draggingTouchOffsetY

        val contentPoint = screenToContentConverter?.invoke(
            MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, labelX, labelY, 0)
        ) ?: PointF(labelX, labelY)

        val pageRect = delegate.textHandlerContentRectForPage(draggingTextPage)
        val normalizedX = (contentPoint.x - pageRect.left) / pageRect.width()
        val normalizedY = (contentPoint.y - pageRect.top) / pageRect.height()

        val newPoint = listOf(normalizedX, normalizedY)
        // Re-add text at original position (it was removed during drag start)
        delegate.textHandlerDrawingController.addText(text, draggingTextPage)
        // Record the move as a single undoable action
        delegate.textHandlerDrawingController.moveTextWithUndo(text.id, text.point, newPoint, draggingTextPage)
        cancelDraggingText()
        delegate.textHandlerRedrawOverlay()
    }

    private fun cancelDraggingText() {
        draggingLabel?.let { (it.parent as? ViewGroup)?.removeView(it) }
        draggingLabel = null
        isDraggingText = false
        draggingText = null
    }
}
