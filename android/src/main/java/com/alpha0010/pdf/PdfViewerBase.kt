package com.alpha0010.pdf

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.util.LruCache
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.common.MapBuilder
import com.facebook.react.uimanager.events.RCTEventEmitter
import kotlinx.coroutines.*
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.locks.Lock
import kotlin.concurrent.withLock

// MARK: - Tap Zone Helper

enum class TapZone { LEFT, MIDDLE, RIGHT }

fun classifyTapZone(tapX: Float, viewWidth: Int, edgeTapZone: Float): TapZone {
    val edgeRatio = edgeTapZone / 100f
    val leftEdge = viewWidth * edgeRatio
    val rightEdge = viewWidth * (1f - edgeRatio)
    return when {
        tapX < leftEdge -> TapZone.LEFT
        tapX > rightEdge -> TapZone.RIGHT
        else -> TapZone.MIDDLE
    }
}

// MARK: - Shared Manager Constants

object PdfViewerConstants {
    const val COMMAND_RESET_ZOOM = 1
    const val COMMAND_SCROLL_TO_PAGE = 2
    const val COMMAND_CLEAR_STROKES = 3

    fun commandsMap(): Map<String, Int> = MapBuilder.of(
        "resetZoom", COMMAND_RESET_ZOOM,
        "scrollToPage", COMMAND_SCROLL_TO_PAGE,
        "clearStrokes", COMMAND_CLEAR_STROKES
    )

    fun bubblingEventTypes(): Map<String, Any> = MapBuilder.builder<String, Any>()
        .put("onPdfError", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onPdfError")))
        .put("onPdfLoadComplete", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onPdfLoadComplete")))
        .put("onPageChange", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onPageChange")))
        .put("onZoomChange", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onZoomChange")))
        .put("onTap", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onTap")))
        .put("onMiddleClick", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onMiddleClick")))
        .put("onDrawingStart", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onDrawingStart")))
        .put("onDrawingEnd", MapBuilder.of("phasedRegistrationNames", MapBuilder.of("bubbled", "onDrawingEnd")))
        .build()

    /** Shared findViewByTag + getAnnotations for Module classes */
    fun getAnnotationsForTag(context: ReactApplicationContext, viewTag: Int, promise: Promise) {
        context.runOnUiQueueThread {
            try {
                val view = context.currentActivity
                    ?.findViewById<View>(android.R.id.content)
                    ?.let { findViewByTag(it, viewTag) } as? PdfViewerBase

                if (view != null) {
                    promise.resolve(view.getAnnotations())
                } else {
                    promise.reject("E_VIEW_NOT_FOUND", "PDF view not found for tag $viewTag")
                }
            } catch (e: Exception) {
                promise.reject("E_UNKNOWN", e.message)
            }
        }
    }

    private fun findViewByTag(view: View, tag: Int): View? {
        if (view.id == tag) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val result = findViewByTag(view.getChildAt(i), tag)
                if (result != null) return result
            }
        }
        return null
    }
}

// MARK: - PdfViewerBase

/**
 * Base class for PagingPdfView and ZoomablePdfScrollView.
 * Contains shared props, PDF loading, annotation parsing, drawing controller, stroke management,
 * RN event emission, and DrawingControllerDelegate implementation.
 */
@SuppressLint("ViewConstructor")
abstract class PdfViewerBase(context: Context, protected val pdfMutex: Lock) : FrameLayout(context), DrawingControllerDelegate {

    // MARK: - Props

    protected var mSource = ""
    protected var mAnnotations = ""
    protected var mParsedAnnotations: List<AnnotationPage> = emptyList()
    protected var mMinScale = 1f
    protected var mMaxScale = 3f
    protected var mEdgeTapZone = 15f
    protected var mBackgroundColor = Color.DKGRAY

    // MARK: - Drawing

    protected val drawingController = DrawingController()
    protected val textAnnotationHandler: TextAnnotationHandler

    // MARK: - PDF State

    protected var mPdfRenderer: PdfRenderer? = null
    protected var mFileDescriptor: ParcelFileDescriptor? = null
    protected var mPdfPageWidth = 0
    protected var mPdfPageHeight = 0
    protected var mActualPageCount = 0

    // MARK: - Cache & Coroutines

    protected val mImageCache: LruCache<Int, Bitmap>
    protected val renderScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // MARK: - Page Tracking

    protected var mCurrentPage = 0
    protected var mPreviousWidth = 0

    init {
        drawingController.delegate = this
        textAnnotationHandler = TextAnnotationHandler(context)

        val maxMemory = (Runtime.getRuntime().maxMemory() / 1024).toInt()
        val cacheSize = maxMemory / 8
        mImageCache = object : LruCache<Int, Bitmap>(cacheSize) {
            override fun sizeOf(key: Int, bitmap: Bitmap): Int = bitmap.byteCount / 1024
        }
    }

    // MARK: - Override Points

    /** Called after PDF loaded successfully. Subclass should notify adapter and update UI. */
    protected abstract fun onPdfLoaded()

    /** Called after annotations changed. Subclass should refresh visible pages. */
    protected abstract fun onAnnotationsChanged()

    /** Called after drawing mode changed. Subclass should update gestures/input. */
    protected abstract fun onDrawingModeChanged(mode: DrawingMode)

    /** Called when drawing overlay needs redraw. */
    protected abstract fun redrawOverlay()

    // MARK: - Setters

    open fun setSource(source: String) {
        if (mSource != source) {
            mSource = source
            onSourceChanged()
        }
    }

    /** Override for deferred loading (e.g. PagingPdfView waits for valid dimensions). */
    protected open fun onSourceChanged() {
        reloadPdf()
    }

    fun setAnnotations(annotations: String?) {
        val newAnnotations = annotations ?: ""
        if (newAnnotations == mAnnotations) return
        mAnnotations = newAnnotations
        mParsedAnnotations = parseAnnotations(mAnnotations)
        mImageCache.evictAll()
        onAnnotationsChanged()
    }

    open fun setMinZoom(minZoom: Float) {
        mMinScale = minZoom.coerceAtLeast(0.5f)
    }

    open fun setMaxZoom(maxZoom: Float) {
        mMaxScale = maxZoom.coerceAtLeast(1f)
    }

    fun setEdgeTapZone(zone: Float) {
        mEdgeTapZone = zone.coerceIn(0f, 50f)
    }

    open fun setPdfBackgroundColor(color: Int) {
        if (color == mBackgroundColor) return
        mBackgroundColor = color
        onBackgroundColorChanged()
    }

    protected open fun onBackgroundColorChanged() {
        setBackgroundColor(mBackgroundColor)
    }

    fun setDrawingMode(mode: String) {
        val newMode = DrawingMode.fromString(mode)
        if (newMode == drawingController.drawingMode) return
        if (newMode != DrawingMode.TEXT) {
            textAnnotationHandler.commitTextInput()
        }
        drawingController.drawingMode = newMode
        onDrawingModeChanged(newMode)
    }

    fun setStrokeColor(color: String) {
        drawingController.strokeColor = color
    }

    fun setStrokeWidth(width: Float) {
        drawingController.strokeWidth = width
    }

    fun setStrokeOpacity(opacity: Float) {
        drawingController.strokeOpacity = opacity
    }

    fun setTextColor(color: String) {
        drawingController.textColor = color
        textAnnotationHandler.textColor = color
    }

    fun setTextFontSize(size: Float) {
        drawingController.textFontSize = size
        textAnnotationHandler.textFontSize = size
    }

    // MARK: - Public Commands

    abstract fun resetZoom()

    abstract fun scrollToPage(page: Int, animated: Boolean)

    fun clearStrokes(page: Int) {
        if (page < 0) {
            drawingController.clearAllStrokes()
            drawingController.clearAllTexts()
        } else {
            drawingController.clearStrokes(page)
            drawingController.clearTexts(page)
        }
        redrawOverlay()
    }

    fun getAnnotations(): WritableMap {
        return drawingController.getAnnotationsForExport()
    }

    // MARK: - PDF Loading

    protected fun reloadPdf() {
        if (mSource.isEmpty()) return

        closePdf()
        mImageCache.evictAll()

        val file = File(mSource)
        try {
            mFileDescriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            mPdfRenderer = PdfRenderer(mFileDescriptor!!)

            mPdfRenderer?.let { renderer ->
                if (renderer.pageCount > 0) {
                    val page = renderer.openPage(0)
                    mPdfPageWidth = page.width
                    mPdfPageHeight = page.height
                    page.close()
                }
                mActualPageCount = renderer.pageCount
            }

            onPdfLoaded()
            onLoadComplete()

        } catch (e: FileNotFoundException) {
            onError("File '$mSource' not found.")
        } catch (e: Exception) {
            onError("Failed to open PDF: ${e.message}")
        }
    }

    protected fun closePdf() {
        pdfMutex.withLock {
            try {
                mPdfRenderer?.close()
            } catch (_: Exception) {}
            mPdfRenderer = null
        }
        try {
            mFileDescriptor?.close()
        } catch (_: Exception) {}
        mFileDescriptor = null
    }

    protected fun getPageHeight(): Int {
        if (mPdfPageWidth <= 0 || mPdfPageHeight <= 0) return height
        return (width.toFloat() * mPdfPageHeight / mPdfPageWidth).toInt()
    }

    // MARK: - Cleanup

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        renderScope.cancel()
        closePdf()
        mImageCache.evictAll()
    }

    // MARK: - RN Event Emission

    protected fun emitEvent(eventName: String, event: WritableMap = Arguments.createMap()) {
        val reactContext = context as ReactContext
        reactContext.getJSModule(RCTEventEmitter::class.java).receiveEvent(id, eventName, event)
    }

    protected fun onError(message: String) {
        emitEvent("onPdfError", Arguments.createMap().apply { putString("message", message) })
    }

    protected fun onLoadComplete() {
        emitEvent("onPdfLoadComplete", Arguments.createMap().apply {
            putInt("width", mPdfPageWidth)
            putInt("height", mPdfPageHeight)
            putInt("pageCount", mActualPageCount)
        })
    }

    protected fun onPageChange() {
        emitEvent("onPageChange", Arguments.createMap().apply { putInt("page", mCurrentPage) })
    }

    protected fun onZoomChange(scale: Float) {
        emitEvent("onZoomChange", Arguments.createMap().apply { putDouble("scale", scale.toDouble()) })
    }

    protected fun onTap(position: String) {
        emitEvent("onTap", Arguments.createMap().apply { putString("position", position) })
    }

    protected fun onMiddleClick() {
        emitEvent("onMiddleClick")
    }

    // MARK: - DrawingControllerDelegate

    override fun onDrawingStart() {
        emitEvent("onDrawingStart")
    }

    override fun onDrawingEnd() {
        emitEvent("onDrawingEnd")
    }

    override fun onStrokeAdded(stroke: DrawingStroke, page: Int) {}

    override fun onStrokeRemoved(strokeId: String, page: Int) {}

    override fun onStrokesCleared(page: Int) {}

    override fun onNeedsRedraw() {
        post { redrawOverlay() }
    }
}
