package com.alpha0010.pdf

import android.content.Context
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PointF
import android.graphics.RectF
import android.text.InputType
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.TextView
import java.util.UUID

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

    val hasActiveTextInput: Boolean get() = textInputView != null

    /**
     * Handle touch in text mode. Returns true if touch was consumed.
     */
    fun handleTouchDown(event: MotionEvent): Boolean {
        val delegate = delegate ?: run {
            android.util.Log.d("PDFText", "handleTouchDown: no delegate!")
            return false
        }
        val contentContainer = delegate.textHandlerContentContainer
        android.util.Log.d("PDFText", "handleTouchDown: eventXY=(${event.x}, ${event.y}), hasInput=${textInputView != null}")

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

        // Check if touching existing text (start drag)
        val hitResult = hitTestTextAnnotation(normalizedPoint, page)
        if (hitResult != null) {
            val (_, textAnnotation) = hitResult
            startDraggingText(textAnnotation, page, event)
            return true
        }

        // Show text input at the touch position
        android.util.Log.d("PDFText", "showing text input: normalized=($normalizedX, $normalizedY), page=$page, eventXY=(${event.x}, ${event.y})")
        showTextInput(normalizedPoint, page, event)
        return true
    }

    fun handleTouchMove(event: MotionEvent): Boolean {
        if (!isDraggingText) return false
        val label = draggingLabel ?: return false

        val newX = (event.x - draggingTouchOffsetX).toInt()
        val newY = (event.y - draggingTouchOffsetY).toInt()
        label.layout(newX, newY, newX + label.width, newY + label.height)
        return true
    }

    fun handleTouchUp(event: MotionEvent): Boolean {
        if (!isDraggingText) return false
        finishDraggingText(event)
        return true
    }

    fun handleTouchCancel() {
        if (!isDraggingText) return
        // Restore text at original position
        val text = draggingText
        val delegate = delegate
        if (text != null && delegate != null) {
            delegate.textHandlerDrawingController.addText(text, draggingTextPage)
            delegate.textHandlerRedrawOverlay()
        }
        cancelDraggingText()
    }

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

    // MARK: - Text Input

    private fun showTextInput(normalizedPoint: PointF, page: Int, event: MotionEvent) {
        val delegate = delegate ?: return

        textInputPage = page
        textInputNormalizedPoint = normalizedPoint

        val pageRect = delegate.textHandlerContentRectForPage(page)
        val hostView = delegate.textHandlerHostView
        val zoomScale = delegate.textHandlerZoomScale

        // Use the touch event position directly — it's already in the hostView coordinate space
        val screenX = event.x
        val screenY = event.y

        val density = context.resources.displayMetrics.density
        val editText = EditText(context).apply {
            setBackgroundColor(Color.TRANSPARENT)
            textSize = textFontSize * zoomScale
            setTextColor(try { Color.parseColor(textColor) } catch (e: Exception) { Color.BLUE })
            setPadding(0, 0, 0, 0)
            gravity = Gravity.TOP or Gravity.START
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            imeOptions = EditorInfo.IME_ACTION_DONE
            maxLines = 10

            setOnEditorActionListener { _, actionId, _ ->
                if (actionId == EditorInfo.IME_ACTION_DONE) {
                    commitTextInput()
                    true
                } else false
            }
        }

        val maxWidthScreen = (hostView.width - screenX.toInt()).coerceAtLeast(120)
        val lp = FrameLayout.LayoutParams(maxWidthScreen, ViewGroup.LayoutParams.WRAP_CONTENT)
        lp.leftMargin = screenX.toInt()
        lp.topMargin = screenY.toInt()

        hostView.addView(editText, lp)
        // Manually measure and layout for RN views (Yoga doesn't handle dynamic children)
        editText.measure(
            View.MeasureSpec.makeMeasureSpec(maxWidthScreen, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        editText.layout(lp.leftMargin, lp.topMargin, lp.leftMargin + editText.measuredWidth, lp.topMargin + editText.measuredHeight)
        editText.bringToFront()
        editText.requestFocus()
        android.util.Log.d("PDFText", "showTextInput: screenXY=($screenX, $screenY), maxWidth=$maxWidthScreen, measuredW=${editText.measuredWidth}, measuredH=${editText.measuredHeight}, hostView=${hostView.javaClass.simpleName}")

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

        if (text.isEmpty()) return

        val drawingText = DrawingText(
            id = UUID.randomUUID().toString(),
            color = textColor,
            fontSize = textFontSize,
            point = listOf(textInputNormalizedPoint.x, textInputNormalizedPoint.y),
            str = text
        )
        delegate.textHandlerDrawingController.addText(drawingText, textInputPage)
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

            val paint = Paint().apply {
                textSize = text.fontSize * context.resources.displayMetrics.density
                isAntiAlias = true
            }
            val textWidth = paint.measureText(text.str)
            val normalizedWidth = textWidth / pageRect.width()
            val normalizedHeight = (text.fontSize * context.resources.displayMetrics.density) / pageRect.height()

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
        android.util.Log.d("PDFText", "startDraggingText: text='${textAnnotation.str}', page=$page, eventXY=(${event.x}, ${event.y})")

        isDraggingText = true
        draggingTextPage = page
        draggingText = textAnnotation

        // Remove text from controller so overlay doesn't draw it
        delegate.textHandlerDrawingController.removeText(textAnnotation.id, page)
        delegate.textHandlerRedrawOverlay()

        val zoomScale = delegate.textHandlerZoomScale
        val pageRect = delegate.textHandlerContentRectForPage(page)
        val hostView = delegate.textHandlerHostView
        val contentContainer = delegate.textHandlerContentContainer
        val density = context.resources.displayMetrics.density

        // Create floating label
        val label = TextView(context).apply {
            text = textAnnotation.str
            textSize = textAnnotation.fontSize * zoomScale
            setTextColor(
                (try { Color.parseColor(textAnnotation.color) } catch (e: Exception) { Color.BLUE })
                    .let { Color.argb(180, Color.red(it), Color.green(it), Color.blue(it)) }
            )
            setBackgroundColor(Color.argb(50, 255, 0, 0)) // DEBUG: red tint to verify visibility
        }

        // Convert text position from content to screen (hostView) coordinates
        val contentX = pageRect.left + textAnnotation.point[0] * pageRect.width()
        val contentY = pageRect.top + textAnnotation.point[1] * pageRect.height()
        val screenPos = contentToScreen(PointF(contentX, contentY))
        val screenX = screenPos.x
        val screenY = screenPos.y

        // PagingPdfView is a RN view (Yoga layout) — dynamic children don't get measured.
        // Manually measure and layout the label.
        val widthSpec = android.view.View.MeasureSpec.makeMeasureSpec(hostView.width, android.view.View.MeasureSpec.AT_MOST)
        val heightSpec = android.view.View.MeasureSpec.makeMeasureSpec(0, android.view.View.MeasureSpec.UNSPECIFIED)
        label.measure(widthSpec, heightSpec)
        val lw = label.measuredWidth
        val lh = label.measuredHeight
        val left = screenX.toInt()
        val top = screenY.toInt()

        val lp = FrameLayout.LayoutParams(lw, lh)
        hostView.addView(label, lp)
        label.layout(left, top, left + lw, top + lh)
        label.bringToFront()
        android.util.Log.d("PDFText", "startDraggingText: screenXY=($screenX, $screenY), contentXY=($contentX, $contentY), zoomScale=$zoomScale, labelSize=${lw}x${lh}, hostViewSize=(${hostView.width}x${hostView.height})")

        draggingTouchOffsetX = event.x - screenX
        draggingTouchOffsetY = event.y - screenY
        draggingLabel = label

        label.post {
            android.util.Log.d("PDFText", "label post-layout: width=${label.width}, height=${label.height}, visibility=${label.visibility}, alpha=${label.alpha}, attached=${label.isAttachedToWindow}, parent=${label.parent?.javaClass?.simpleName}, parentChildCount=${(label.parent as? ViewGroup)?.childCount}, indexInParent=${(label.parent as? ViewGroup)?.indexOfChild(label)}")
        }
    }

    private fun finishDraggingText(event: MotionEvent) {
        val text = draggingText ?: return
        val delegate = delegate ?: run { cancelDraggingText(); return }

        // Convert final screen position back to content coordinates using the converter
        val labelX = event.x - draggingTouchOffsetX
        val labelY = event.y - draggingTouchOffsetY

        // Create a fake MotionEvent at the label position to reuse screenToContentConverter
        val contentPoint = screenToContentConverter?.invoke(
            MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, labelX, labelY, 0)
        ) ?: PointF(labelX, labelY)

        val pageRect = delegate.textHandlerContentRectForPage(draggingTextPage)
        val normalizedX = (contentPoint.x - pageRect.left) / pageRect.width()
        val normalizedY = (contentPoint.y - pageRect.top) / pageRect.height()

        val movedText = DrawingText(
            id = text.id,
            color = text.color,
            fontSize = text.fontSize,
            point = listOf(normalizedX, normalizedY),
            str = text.str
        )
        delegate.textHandlerDrawingController.addText(movedText, draggingTextPage)
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
